# FIXME: put this in a namespace
class Change
  class Invalid < Exception; end
  
  attr_reader   :created_at
  attr_accessor :attribute
  attr_accessor :old_value
  attr_accessor :new_value  
  
  def initialize(args={})
    args.each do |attr, value|
      raise ArgumentError.new("Unknown attribute #{attr}") unless self.respond_to?(attr)
      
      case attr.to_sym
      when :created_at
        value = Time.parse(value) unless value.is_a?(Time)
      when :attribute
        value = value.to_sym
      end
      
      instance_variable_set("@#{attr.to_s}", value)
    end
    
    @created_at = Time.parse(@created_at) if @created_at.is_a?(String)
    @created_at = timescrub(@created_at || Time.now)
    
    self
  end  
  
  def self.from_json(the_json)
    begin
      hash = JSON.parse(the_json)
    rescue JSON::ParserError => e
      raise Change::Invalid.new(e.to_s)
    end

    Change.new(hash)      
  end
  
  def valid?(opts={})
    # old_value is optional!
    #
    valid = created_at && attribute && new_value
    raise Invalid if opts[:raise] && !valid
    valid
  end
  
  def to_json(state=nil)
    valid? :raise => true
    hash = { :created_at => created_at, :attribute => attribute, :old_value => old_value, :new_value => new_value }
    JSON.pretty_generate(hash)
  end
  
  def to_s(opts={})
    if opts[:simple]
      "#{attribute} : #{old_value} => #{new_value}"
    else
      fields = [ date(created_at), attribute, old_value || '[nil]', new_value ]        
      "%10s : %12s : %s => %s" % fields        
    end
  end
end