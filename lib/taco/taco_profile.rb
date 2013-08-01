# ~/.taco_profile configures per-user interactions with taco
# a default .taco_profile exists at .taco/.taco_profile
# contrast with .taco/.tacorc

class TacoProfile
  attr_reader :sort_order, :filters, :columns
  
  def initialize(text)
    text ||= ''
    
    # FIXME: this is way too coupled to Issue
    #
    @sort_order = [ :created_at, :id ]
    @columns = [ :short_id, :priority, :summary ]
    @filters = []
    
    text.lines.each_with_index do |line, index|
      next if line =~ /^#/ || line =~ /^\s*$/
      
      key, value = line.split(':', 2).map(&:strip)
      case key
      when 'sort'
        @sort_order = value.split(',').map(&:to_sym)
      when 'filters'
        @filters = value.split(/\s/)
      when 'columns'
        @columns = value.split(',').map(&:to_sym)
      else
        raise ArgumentError.new("Parse error on line #{index+1}")
      end
    end
  end
end