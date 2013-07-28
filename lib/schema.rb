module Schema
  def self.included(base)
    base.extend(ClassMethods)
  end
  
  def valid?
    self.class.instance_variable_get("@schema_attrs").each do |attr, opts|
      if opts[:values]
        value = eval(attr.to_s)
        if opts[:values].is_a?(Array)
          return false unless opts[:values].include? value
        elsif opts[:values].is_a?(Proc)
          return false unless opts[:values].call(value)
        end
      end
    end
    
    true
  end
    
  module ClassMethods
    def schema_attr(name, opts)      
      @schema_attrs ||= {}

      raise TypeError.new("attribute #{name}: missing or invalid :class") unless opts[:class].is_a?(Class)
      raise TypeError.new("attribute #{name}: missing or invalid :default") unless opts[:default].is_a?(opts[:class])

      if opts[:values]
        unless opts[:values].is_a?(Array) || opts[:values].is_a?(Proc)
          raise ArgumentError.new("attribute #{name}: expecting Array or Proc for :values")
        end
        
        if opts[:values].is_a?(Array)
          raise TypeError.new("attribute #{name}: wrong type in :values Array") unless opts[:values].all? { |v| v.is_a?(opts[:class]) }
        end
      end

      raise ArgumentError.new("attribute #{name}: already exists") if @schema_attrs[name]
      
      @schema_attrs[name] = opts

      method = %Q(def #{name}; @#{name} ||= #{opts[:default].inspect}; end)
      module_eval method

      if opts[:settable]
        
        unless opts[:coerce] == false
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
        
        unless opts[:transform] == false
          case opts[:class].to_s # can't case on opts[:class], because class of opts[:class] is always Class :-)
          when 'String'
            unless opts[:transform].is_a? Proc
              # the default transform for String
              opts[:transform] = lambda { |s| s.strip }
            end
          end
          
          transform = 'value = opts[:transform].call(value)' if opts[:transform]
        end
        
        method = %Q(
          def #{name}=(value)
            opts = self.class.instance_variable_get("@schema_attrs")[:#{name}]
            #{coerce}
            raise TypeError.new("attribute #{name}: expected type #{opts[:class]}, received \#{value.class}") unless opts[:class] == value.class            
            #{transform}            
            @#{name} = value
          end
        )
        module_eval method
      end
    end
  end
end
