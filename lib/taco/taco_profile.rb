# ~/.taco_profile configures per-user interactions with taco
# a default .taco_profile exists at .taco/.taco_profile
# contrast with .taco/.tacorc

class TacoProfile
  attr_reader :sort_order, :filters, :columns

  def initialize(text)
    text ||= ''

    @sort_order, @columns, @filters = nil, nil, nil

    text.lines.each_with_index do |line, index|
      next if line =~ /^#/ || line =~ /^\s*$/

      key, value = line.split(':', 2).map(&:strip)
      case key
      when 'sort'
        raise ArgumentError.new("sort defined more than once on line #{index+1}") if @sort_order
        @sort_order = value.split(',').map(&:to_sym)
        raise ArgumentError.new("Unknown Issue attribute in sort on line #{index+1}") unless @sort_order.all? { |attr| Issue.schema_attributes.include?(attr) }
      when 'filters'
        raise ArgumentError.new("filters defined more than once on line #{index+1}") if @filters
        @filters = value.split(/\s/)
        raise ArgumentError.new("Unknown Issue attribute in filters on line #{index+1}") unless @filters.all? { |token| attr, value = token.split(':'); Issue.schema_attributes.include?(attr.to_sym) }
      when 'columns'
        raise ArgumentError.new("columns defined more than once on line #{index+1}") if @columns
        @columns = value.split(',').map(&:to_sym)
        raise ArgumentError.new("Unknown Issue attribute in columns on line #{index+1}") unless @columns.all? do |attr|
          # FIXME: really?  hard-code :short_id? there's got to be a better way.
          #
          attr == :short_id || Issue.schema_attributes.include?(attr)
        end
      else
        raise ArgumentError.new("Parse error on line #{index+1}")
      end
    end

    @sort_order ||= [ :created_at, :id ]
    @columns ||= [ :short_id, :priority, :summary ]
    @filters ||= []
  end
end