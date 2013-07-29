require 'schema'
require 'change'
require 'securerandom'

class Issue  
  include Comparable
  include Schema
  
  alias_method :schema_valid?, :valid?
  
  attr_reader :changelog

  schema_attr :id,          class: String,      settable: false
  schema_attr :created_at,  class: Time,        settable: false
  schema_attr :updated_at,  class: Time,        settable: false
  
  schema_attr :summary,     class: String,      settable: true
  schema_attr :kind,        class: String,      settable: true
  schema_attr :status,      class: String,      settable: true
  schema_attr :owner,       class: String,      settable: true
  schema_attr :priority,    class: Fixnum,      settable: true
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

    @new = attributes[:created_at].nil? && attributes[:id].nil?      

    @changelog = []
            
    attributes.each do |attr, value|
      schema_attr = self.class.schema_attributes[attr]
      raise ArgumentError.new("unknown attribute: #{attr}") unless schema_attr
      if schema_attr[:settable]
        self.send "#{attr}=", attributes[attr]
      end
    end
    
    self.id = attributes[:id] || SecureRandom.uuid.gsub('-', '')
    self.created_at = attributes[:created_at] || Time.now
    self.updated_at = attributes[:updated_at] || Time.now
    
    if changelog.size > 0
      @changelog = changelog.map do |thing|
        if thing.is_a? Change
          thing
        else
          Change.new thing
        end
      end
    end
    
    self
  end
  
  def schema_attribute_change(attribute, old_value, new_value)
    if self.class.schema_attributes[attribute][:settable]
      self.updated_at = Time.now
      @changelog << Change.new(:attribute => attribute, :old_value => old_value, :new_value => new_value)
    end
  end   
  
  def new?
    @new
  end
  
  def <=>(other)
    if self.class.schema_attributes.all? { |attr, opts| self.send(attr) == other.send(attr) }
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
    fields = self.class.schema_attributes.map do |attr, opts|
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
  
  def valid?(opts={})
    valid = schema_valid?
    error = schema_errors.first
    raise Invalid.new("attribute #{error.first}: #{error[1].inspect} is not a valid value") if !valid && opts[:raise]
    valid
  end
  
  def to_json(state=nil)
    valid? :raise => true
    hash = { :issue => self.to_hash, :changelog => changelog }
    JSON.pretty_generate(hash)
  end
  
  def to_template
    if new?
      header = "# New Issue\n#"
      body = TEMPLATE % self.to_hash
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
      body = TEMPLATE % self.to_hash
      
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
        
        if schema_attributes.include?(key) && schema_attributes[key][:settable]
          issue[key] = value
        else
          raise ArgumentError.new("Unknown Issue attribute: #{key} on line #{index+1}") unless schema_attributes.include?(key)
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
    
    attrs = self.class.schema_attributes.map do |attr, opts|
      if opts[:settable] && self.send(attr) != (new_value = new_issue.send(attr))
        self.send("#{attr}=", new_value)
      end
    end

    self
  end  
  
  private
    def date(t)
      t.strftime "%Y/%m/%d %H:%M:%S"
    end
  
    def dup
      raise NoMethodError.new
    end
    
    def clone
      raise NoMethodError.new
    end
end
