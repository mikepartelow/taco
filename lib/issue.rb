require 'schema'

class Issue  
  include Comparable
  include Schema
   
  attr_reader :changelog

  schema_attr :id,          class: String,      settable: false
  schema_attr :created_at,  class: Time,        settable: false
  schema_attr :updated_at,  class: Time,        settable: false
  
  schema_attr :summary,     class: String,      settable: true
  schema_attr :kind,        class: String,      settable: true
  schema_attr :status,      class: String,      settable: true
  schema_attr :owner,       class: String,      settable: true
  schema_attr :priority,    class: Fixnum,      settable: true,   validate: [ 1, 2, 3, 4, 5 ]
  schema_attr :description, class: String,      settable: true
    
  TEMPLATE =<<-EOT.strip
# Lines beginning with # will be ignored.
Summary     : %{summary}
Kind        : %{kind}
Status      : %{status}
Priority    : %{priority}
Owner       : %{owner}

# Everything between the --- lines is Issue Description
---
%{description}
---
EOT

  class Invalid < Exception; end
  class NotFound < Exception; end
  
  def initialize(attributes={}, changelog=[])
    attributes = Hash[attributes.map { |k, v| [ k.to_sym, v ] }]
    
    # @new = issue[:created_at].nil? && issue[:id].nil?      
    # 
    # issue[:created_at] = Time.now unless issue.include?(:created_at) # intentionally not using ||=
    # issue[:updated_at] = Time.now unless issue.include?(:updated_at) # intentionally not using ||=
    # issue[:id] = SecureRandom.uuid.gsub('-', '') unless issue.include?(:id) # intentionally not using ||=
    # 
    # self.issue = Issue::format_attributes issue
    # 
    # if changelog.size > 0
    #   @changelog = changelog.map do |thing|
    #     if thing.is_a? Change
    #       thing
    #     else
    #       Change.new thing
    #     end
    #   end
    # end
    
    self
  end
  
  def new?
    @new
  end
  
  def self.set_allowed_values!(attrs=nil)
    if attrs.nil?
      SCHEMA_ATTRIBUTES.each { |attr, data| data.delete(:allowed_values) }
    else
      attrs.each do |attr, values|
        raise ArgumentError.new("Unknown Issue attributes: #{attr}") unless SCHEMA_ATTRIBUTES.include? attr      
      
        if SCHEMA_ATTRIBUTES[attr][:class] == Fixnum
          values.map!(&:to_i)
        end
        
        SCHEMA_ATTRIBUTES[attr][:allowed_values] = values
      end
    end
  end
  
  def self.format_attributes(issue_attrs)
    attrs = issue_attrs.dup
    
    attrs.keys.each { |attr| raise ArgumentError.new("Unknown Issue attribute: #{attr}") unless SCHEMA_ATTRIBUTES.include? attr }
    
    SCHEMA_ATTRIBUTES.each do |attr, cfg|
      next unless attrs.include? attr

      case cfg[:class].to_s # can't case on cfg[:class], because class of cfg[:class] is always Class :-)
      when 'Time'
        unless attrs[attr].is_a?(String) || attrs[attr].is_a?(Time)
          raise TypeError.new("#{attr} : expected type #{cfg[:class]}, got type #{attrs[attr].class}")
        end
        
        t = if attrs[attr].is_a?(String)
          begin
            Time.parse(attrs[attr])
          rescue ArgumentError => e
            raise TypeError.new(e.to_s)
          end
        else
          attrs[attr]
        end
        attrs[attr] = timescrub(t)
      when 'String'
        unless attrs[attr].is_a?(String)
          raise TypeError.new("#{attr} : expected type #{cfg[:class]}, got type #{attrs[attr].class}")
        end
         
        attrs[attr] && attrs[attr].strip!
      when 'Fixnum'
        unless attrs[attr].is_a?(Fixnum) || attrs[attr].is_a?(String)
          raise TypeError.new("#{attr} : expected type #{cfg[:class]}, got type #{attrs[attr].class}")
        end          
        
        if attrs[attr].is_a?(String)
          i = attrs[attr].to_i
          raise TypeError.new("#{attr} : expected type #{cfg[:class]}, got type #{attrs[attr].class}") unless i.to_s == attrs[attr]
          attrs[attr] = i
        end
      end      
    end 
        
    attrs   
  end
  
  def <=>(other)
    if SCHEMA_ATTRIBUTES.all? { |attr, cfg| self.send(attr) == other.send(attr) }
      r = 0
    else
      if self.created_at == other.created_at
        r = self.id <=> other.id
      else
        r = self.created_at <=> other.created_at
      end

      # this clause should not return 0, we've already established inequality
      #      
      r = -1 if r == 0
    end
    
    r
  end

  def inspect
    fields = SCHEMA_ATTRIBUTES.map do |attr, cfg|
      "@#{attr}=#{self.send(attr).inspect}"
    end.join ', '
    
    "#<#{self.class}:0x%016x %s>" % [ object_id, fields ]
  end
      
  def to_s(opts={})
    text = <<-EOT.strip
ID          : #{id}
Created At  : #{date(created_at)}
Updated At  : #{date(updated_at)}

Summary     : #{summary}
Kind        : #{kind}
Status      : #{status}
Priority    : #{priority}
Owner       : #{owner}

---
#{description}
EOT

    if opts[:changelog]
      changelog_str = changelog.map { |c| %Q|# #{c.to_s.strip.gsub(/\n/, "\n# ")}| }.join("\n")      
      text << %Q|\n---\n\n#{changelog_str}|
    end
    
    text
  end
  
  def to_json(state=nil)
    valid? :raise => true
    hash = { :issue => @issue, :changelog => changelog }
    JSON.pretty_generate(hash)
  end
  
  def to_template
    if new?
      header = "# New Issue\n#"
      body = TEMPLATE
      footer = ""
    else
      header =<<-EOT
# Edit Issue
#
# ID          : #{id}
# Created At  : #{created_at}
# Updated At  : #{updated_at}
#
EOT
      body = TEMPLATE % @issue
      
      footer =<<-EOT      
# ChangeLog
#
#{changelog.map { |c| %Q|# #{c.to_s.strip.gsub(/\n/, "\n# ")}| }.join("\n")}      
EOT
    end
    
    (header + "\n" + body + "\n\n" + footer).strip
  end
  
  def self.from_json(the_json)
    begin
      hash = JSON.parse(the_json)
    rescue JSON::ParserError => e
      raise Issue::Invalid.new(e.to_s)
    end
    
    Issue.new(hash['issue'], hash['changelog'])    
  end    
  
  def self.from_template(text)
    issue = { :description => '' }
    reading_description = false
    
    text.lines.each_with_index do |line, index|
      next if line =~ /^#/ || (!reading_description && line =~ /^\s*$/)
      
      if line =~ /^---$/
        # FIXME: this means that there can be multiple description blocks in the template!
        #
        reading_description = !reading_description
        next
      end
      
      if !reading_description && line =~ /^(\w+)\s*:\s*(.*)$/
        key, value = $1.downcase.to_sym, $2.strip
        
        if SCHEMA_ATTRIBUTES.include?(key) && SCHEMA_ATTRIBUTES[key][:settable]
          issue[key] = value
        else
          raise ArgumentError.new("Unknown Issue attribute: #{key} on line #{index+1}") unless SCHEMA_ATTRIBUTES.include?(key)
          raise ArgumentError.new("Cannot set write-protected Issue attribute: #{key} on line #{index+1}")
        end
      elsif reading_description
        issue[:description] += line
      else
        raise ArgumentError.new("Cannot parse line #{index+1}")
      end
    end
    
    Issue.new(issue)
  end
  
  def update_from_template!(text)
    new_issue = Issue.from_template(text)
    
    attrs = SCHEMA_ATTRIBUTES.map do |attr, data|
      if data[:settable]
        [ attr, new_issue.send(attr) ]
      else
        [ attr, @issue[attr] ]
      end
    end

    self.issue = Issue::format_attributes(Hash[attrs])
    @issue[:updated_at] = timescrub Time.now
    
    self
  end
  
  # def valid?(opts={})
  #   begin
  #     raise Issue::Invalid.new("id is nil") unless id
  # 
  #     SCHEMA_ATTRIBUTES.each do |attr, cfg| 
  #       raise Issue::Invalid.new("Missing required attribute: #{attr}") if cfg[:required] && @issue[attr].nil?
  #     end
  # 
  #     @issue.each do |attr, value|
  #       unless @issue[attr].is_a?(SCHEMA_ATTRIBUTES[attr][:class])
  #         raise Issue::Invalid.new("Wrong type: #{attr} (expected #{SCHEMA_ATTRIBUTES[attr][:class]}, got #{@issue[attr.class]})")
  #       end
  # 
  #       if allowed_values = SCHEMA_ATTRIBUTES[attr][:allowed_values]
  #         unless allowed_values.include? @issue[attr]
  #           raise Issue::Invalid.new("#{@issue[attr]} is not an allowed value for #{attr.capitalize}")
  #         end
  #       end
  #     
  #       if SCHEMA_ATTRIBUTES[attr][:class] == String && @issue[attr] =~ /\A\s*\Z/
  #         raise Issue::Invalid.new("Empty string is not allowed for #{attr}")
  #       end
  #     end
  #   rescue Issue::Invalid => e
  #     return false unless opts[:raise]
  #     raise e
  #   end
  #   
  #   true
  # end
  
  private
    def issue=(new_issue)
      @issue ||= {}
      @changelog ||= []
      
      SCHEMA_ATTRIBUTES.each do |attr, data|
        if new_issue.include? attr
          if new_issue[attr] != @issue[attr] && data[:settable]
            @changelog << Change.new(:attribute => attr, :old_value => @issue[attr], :new_value => new_issue[attr])
          end

          @issue[attr] = new_issue[attr]          
        else
          @issue[attr] ||= data[:default]
        end
      end

      @issue
    end
    
    def dup
      # FIXME: make it work.
      #        have to do a deep copy of @issue, for one thing.
      raise NoMethodError.new
    end
    
    def clone
      raise NoMethodError.new
    end
end
