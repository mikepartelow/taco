module Schema
  def self.included(base)
    base.extend(ClassMethods)
  end
  
  def valid?
    self.class.instance_variable_get("@schema_attrs").each do |attr, opts|
      if opts[:validate]
        value = eval(attr.to_s)
        if opts[:validate].is_a?(Array)
          return false unless opts[:validate].include? value
        elsif opts[:validate].is_a?(Proc)
          return false unless opts[:validate].call(value)
        end
      end
    end
    
    true
  end
    
  module ClassMethods
    def schema_attr(name, opts)      
      @schema_attrs ||= {}

      raise TypeError.new("attribute #{name}: missing or invalid :class") unless opts[:class].is_a?(Class)
      unless opts[:default].is_a?(opts[:class]) || opts[:default].is_a?(Proc)
        raise TypeError.new("attribute #{name}: missing or invalid :default")
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
            opts = self.class.instance_variable_get("@schema_attrs")[:#{name}]
            value = opts[:default].call
            raise TypeError.new("attribute #{name}: expected type #{opts[:class]}, received \#{value.class}") unless opts[:class] == value.class            
        )        
      else
        %Q(value = #{opts[:default].inspect})
      end
      module_eval "def #{name}; #{value_getter}; @#{name} ||= value; end"

      if opts[:settable]
        
        unless opts[:coerce] == false # possible values are false=no-coerce, nil=default-coerce, Proc=custom-coerce
          case opts[:class].to_s # can't case on opts[:class], because class of opts[:class] is always Class :-)
          when 'Fixnum'
            unless opts[:coerce].is_a? Proc
              # the default coercion for Fixnum
              opts[:coerce] = lambda do |value|
                  unless value.is_a?(Fixnum)
                    raise TypeError.new("attribute #{name}: cannot coerce from \#{value.class}") unless value.is_a?(String)
                    i = value.to_i
                    raise TypeError.new("attribute #{name}: failed to coerce from \#{value}") unless i.to_s == value
                    value = i
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
              # the default transform for String
              opts[:transform] = lambda { |s| s.strip }
            end
          end
          
          transform = 'value = opts[:transform].call(value)' if opts[:transform]
        end
        
        setter_method = %Q(
          def #{name}=(value)
            opts = self.class.instance_variable_get("@schema_attrs")[:#{name}]
            #{coerce}
            raise TypeError.new("attribute #{name}: expected type #{opts[:class]}, received \#{value.class}") unless opts[:class] == value.class            
            #{transform}            
            @#{name} = value
          end
        )
        module_eval setter_method
      end
    end
  end
end
