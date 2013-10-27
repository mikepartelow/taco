require 'time'

# Schema characteristics
#
# attributes have default validations, coercions, and transformations
#
#  FIXME: document

module Schema
  def self.included(base)
    base.extend(ClassMethods)
  end

  def to_hash
    Hash[self.class.schema_attributes.map do |attr, opts|
      [ attr, send(attr) ]
    end]
  end

  def schema_errors
    @errors || []
  end

  def valid?
    @errors = nil

    self.class.schema_attributes.each do |attr, opts|
      if opts[:validate].nil?
        case opts[:class].to_s # can't case on opts[:class], because class of opts[:class] is always Class :-)
        when 'String'
          opts[:validate] = lambda { |v| v !~ /\A\s*\Z/ }
        end
      end

      if opts[:validate]
        value = eval(attr.to_s)

        valid = if opts[:validate].is_a?(Array)
          opts[:validate].include? value
        elsif opts[:validate].is_a?(Proc)
          opts[:validate].call(value)
        end

        unless valid
          @errors = [ [ attr, value ] ]
          return false
        end
      end
    end

    true
  end

  module ClassMethods
    def schema_attributes
      @schema_attrs
    end

    def schema_attr_expand(prefix)
      candidates = @schema_attrs.keys.select { |a| a.to_s.start_with? prefix }
      raise KeyError.new("no attribute is prefixed with #{prefix}") if candidates.size == 0
      raise KeyError.new("prefix #{prefix} is not unique") if candidates.size > 1
      candidates[0]
    end

    def schema_attr_remove(name)
      raise KeyError.new("attribute #{name}: does not exist in class #{self.name}") unless @schema_attrs.include? name
      @schema_attrs.delete(name)
      self.send(:remove_method, name)
      self.send(:remove_method, "#{name}=".to_s)
    end

    def schema_attr_replace(name, opts)
      raise KeyError.new("attribute #{name}: does not exist in class #{self.name}") unless @schema_attrs.include? name
      schema_attr_remove(name)
      schema_attr(name, opts)
    end

    def schema_attr_update(name, opts)
      raise KeyError.new("attribute #{name}: does not exist in class #{self.name}") unless @schema_attrs.include? name
      raise KeyError.new("attribute #{name}: cannot update non-settable attribute") unless @schema_attrs[name][:settable]
      schema_attr_replace(name, @schema_attrs[name].merge(opts))
    end

    def schema_attr(name, opts)
      @schema_attrs ||= {}

      raise TypeError.new("attribute #{name}: missing or invalid :class") unless opts[:class].is_a?(Class)

      if opts[:default].nil?
        opts[:default] = case opts[:class].to_s # can't case on opts[:class], because class of opts[:class] is always Class :-)
        when 'String'
          ''
        when 'Fixnum'
          0
        when 'Time'
          lambda { Time.new }
        else
          raise ArgumentError.new("Sorry, no default default exists for #{opts[:class]}")
        end
      end

      unless opts[:default].is_a?(opts[:class]) || opts[:default].is_a?(Proc)
        raise TypeError.new("attribute #{name}: invalid :default")
      end

      if opts[:validate]
        unless opts[:validate].is_a?(Array) || opts[:validate].is_a?(Proc)
          raise ArgumentError.new("attribute #{name}: expecting Array or Proc for :validate")
        end

        if opts[:validate].is_a?(Array)
          raise TypeError.new("attribute #{name}: wrong type in :validate Array") unless opts[:validate].all? { |v| v.is_a?(opts[:class]) }
        end
      end

      raise ArgumentError.new("attribute #{name}: already exists") if @schema_attrs[name]

      @schema_attrs[name] = opts

      value_getter = if opts[:default].is_a?(Proc)
        %Q(
            opts = self.class.schema_attributes[:#{name}]
            value = opts[:default].call
            raise TypeError.new("attribute #{name}: expected type #{opts[:class]}, received \#{value.class}") unless opts[:class] == value.class
        )
      else
        %Q(value = #{opts[:default].inspect})
      end
      module_eval %Q(
                      def #{name}
                        if @#{name}.nil?
                          #{value_getter}
                          self.#{name}= value
                        end
                        @#{name}
                      end
                    )

      unless opts[:coerce] == false # possible values are false=no-coerce, nil=default-coerce, Proc=custom-coerce
        case opts[:class].to_s # can't case on opts[:class], because class of opts[:class] is always Class :-)
        when 'Fixnum'
          unless opts[:coerce].is_a? Proc
            # the default coercion for Fixnum
            opts[:coerce] = lambda do |value|
              unless value.is_a?(Fixnum) # FIXME: this "unless value.is_a?(same class as 'when')" is copy-pasta.  fix it.
                raise TypeError.new("attribute #{name}: cannot coerce from \#{value.class}") unless value.is_a?(String)
                i = value.to_i
                raise TypeError.new("attribute #{name}: failed to coerce from \#{value}") unless i.to_s == value
                value = i
              end
              value
            end
          end
        when 'Time'
          unless opts[:coerce].is_a? Proc
            # the default coercion for Time
            opts[:coerce] = lambda do |value|
              unless value.is_a?(Time) # FIXME: this "unless value.is_a?(same class as 'when')" is copy-pasta.  fix it.
                raise TypeError.new("attribute #{name}: cannot coerce from \#{value.class}") unless value.is_a?(String)
                begin
                  value = Time.parse(value)
                rescue ArgumentError
                  raise TypeError.new("attribute #{name}: cannot coerce from \#{value.class}")
                end
              end
              value
            end
          end
        end

        coerce = 'value = opts[:coerce].call(value)' if opts[:coerce]
      end

      unless opts[:transform] == false # possible values are false=no-transform, nil=default-transform, Proc=custom-transform
        case opts[:class].to_s # can't case on opts[:class], because class of opts[:class] is always Class :-)
        when 'String'
          unless opts[:transform].is_a? Proc
            # the default transform for String: remove excess whitespace
            opts[:transform] = lambda { |s| s.strip }
          end
        when 'Time'
          unless opts[:transform].is_a? Proc
            # the default transform for Time: remove subsecond precision.  subsec precision is not recorded in to_s, so unless
            #                                 we scrub it out, the following happens:
            #                                 foo.a_time = Time.new
            #                                 Time.parse(foo.a_time.to_s) == foo.a_time # returns false most of the time!
            opts[:transform] = lambda { |t| Time.new t.year, t.mon, t.day, t.hour, t.min, t.sec, t.utc_offset }
          end
        end

        transform = 'value = opts[:transform].call(value)' if opts[:transform]
      end

      callback = %Q(
        if self.respond_to? :schema_attribute_change
          self.schema_attribute_change(:#{name}, @#{name}, value)
        end
      )

      setter_method = %Q(
        def #{name}=(value)
          opts = self.class.schema_attributes[:#{name}]
          #{coerce}
          raise TypeError.new("attribute #{name}: expected type #{opts[:class]}, received \#{value.class}") unless opts[:class] == value.class
          #{transform}
          #{callback}
          @#{name} = value
        end
      )
      module_eval setter_method
      module_eval "private :#{name}=" unless opts[:settable]
    end
  end
end
