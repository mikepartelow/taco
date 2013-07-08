#!/bin/env ruby

require 'json'
require 'digest'
require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'time'

# TODO:
#  - store schema version in each issue
#  - config files (user, project)
#  - query by status
#  - editing: full (editor) or quick (commandline updates, like new arguments)
#  - arguments to 'new': component:foo kind:bar summary:'ick thud wank'
#  - arg parsing: https://github.com/visionmedia/commander (check out their other stuff, too)
#  - unified error handler that prints messages to stderr
#  - method_missing (http://technicalpickles.com/posts/using-method_missing-and-respond_to-to-create-dynamic-methods/)
#  - should taco config and issues go into different directories?
#  - whenever we read an Issue from a file, raise if the filename doesn't match Issue.id
#  - validate_attributes Issue fields versus list of acceptable values (kind: Defect, Feature Request, etc.)

class Issue  
  include Comparable
  
  SCHEMA_ATTRIBUTES = {
    :id             => { :class => String,    :required => true,   :settable => false },
    :summary        => { :class => String,    :required => true,   :settable => true },
    :kind           => { :class => String,    :required => true,   :settable => true },
    :description    => { :class => String,    :required => true,   :settable => true },
    :created_at     => { :class => Time,      :required => true,   :settable => false },
  }
  TEMPLATE =<<-EOT.strip
# Lines beginning with # will be ignored.
Summary     : %{summary}
Kind        : %{kind}
# Everything past this line is Issue Description
%{description}
EOT

  class Invalid < Exception; end
  class NotFound < Exception; end
  
  def initialize(issue={})
    @issue = Hash[issue.map { |k, v| [ k.to_sym, v ] }]
    @issue[:created_at] = Time.now unless @issue.include?(:created_at) # intentionally not using ||=
    @issue[:id] = SecureRandom.uuid.gsub('-', '') unless @issue.include?(:id) # intentionally not using ||=
    
    @issue = Issue::validate_attributes @issue
    
    self
  end
  
  def self.set_allowed_values(attrs)
    attrs.each do |attr, values|
      raise ArgumentError.new("Unknown attributes: #{attr}") unless SCHEMA_ATTRIBUTES.include? attr      
      
      SCHEMA_ATTRIBUTES[attr][:allowed_values] = values
    end
  end
  
  # self.validate_attributes does known-attr checking, type checking, and value-massaging.
  # FIXME: since we have a valid? function which actually does "Validation", this should be renamed.
  #
  def self.validate_attributes(issue_attrs)
    attrs = issue_attrs.dup
    
    attrs.keys.each { |attr| raise ArgumentError.new("Unknown attribute: #{attr}") unless SCHEMA_ATTRIBUTES.include? attr }
    
    SCHEMA_ATTRIBUTES.each do |attr, cfg|
      next unless attrs.include? attr

      case cfg[:class].to_s # can't case on cfg[:class], because class of cfg[:class] is always Class :-)
      when 'Time'
        unless attrs[attr].is_a?(String) || attrs[attr].is_a?(Time)
          raise ArgumentError.new("#{attr} : expected type #{cfg[:class]}, got type #{attrs[attr].class}")
        end
        
        t = attrs[attr].is_a?(String) ? Time.parse(attrs[attr]) : attrs[attr]
        # Time objects have sub-second precision.  Unfortunately, this precision is lost when we serialize.  What this means
        # is that the following code will fail, most unexpectedly:
        #
        #  i0 = Issue.new some_attributes
        #  i1 = Issue.from_json(i0.to_json)
        #  i0.created_at == i1.created_at  # this will be false!
        #      
        attrs[attr] = Time.new t.year, t.mon, t.day, t.hour, t.min, t.sec, t.utc_offset
      when 'String'
        unless attrs[attr].is_a?(String)
          raise ArgumentError.new("#{attr} : expected type #{cfg[:class]}, got type #{attrs[attr].class}")
        end
         
        attrs[attr] && attrs[attr].strip!
      end
    end 
    
    attrs   
  end
  
  def <=>(other)
    return 0 if SCHEMA_ATTRIBUTES.all? { |attr, cfg| self.send(attr) == other.send(attr) }        
    return self.id <=> other.id if self.created_at == other.created_at
    return self.created_at <=> other.created_at
  end

  def inspect
    fields = SCHEMA_ATTRIBUTES.map do |attr, cfg|
      "@#{attr}=#{self.send(attr).inspect}"
    end.join ', '
    
    "#<#{self.class}:0x%016x %s>" % [ object_id, fields ]
  end
  
  def id
    @issue[:id]
  end
  
  def created_at
    @issue[:created_at]
  end
  
  def description
    @issue[:description]
  end

  def description=(description)
    @issue = Issue::validate_attributes(@issue.merge({ :description => description }))
    description
  end
  
  def kind
    @issue[:kind]
  end

  def kind=(kind)
    @issue = Issue::validate_attributes(@issue.merge({ :kind => kind }))
    kind
  end
  
  def summary
    @issue[:summary]
  end
  
  def summary=(summary)
    @issue = Issue::validate_attributes(@issue.merge({ :summary => summary }))
    summary
  end
  
  def to_s    
    header =<<-EOT.strip
ID          : #{id}"
Created At  : #{created_at}
EOT
    
    body = TEMPLATE % @issue
    body = body.lines.reject { |l| l.start_with?('#') }.join
    
    header + "\n\n" + body
  end
  
  def to_json
    raise Invalid unless valid?
    JSON.pretty_generate(@issue)
  end
  
  def self.from_json(the_json)
    begin
      Issue.new(JSON.parse(the_json))
    rescue JSON::ParserError => e
      raise Issue::Invalid.new(e.to_s)
    end
  end    
  
  def self.from_template(text)
    issue = { :description => '' }
    
    text.lines.each do |line|
      next if line =~ /^#/
      
      if line =~ /^(\w+)\s*:\s*(.*)$/
        key, value = $1.downcase.to_sym, $2.strip
        
        if SCHEMA_ATTRIBUTES.include?(key) && SCHEMA_ATTRIBUTES[key][:settable]
          issue[key] = value
        else
          raise ArgumentError.new("Unknown Attribute: #{key}") unless SCHEMA_ATTRIBUTES.include?(key)
          raise ArgumentError.new("Cannot Set Write-Protected Attribute: #{key}")
        end
      else
        issue[:description] += line
      end
    end
    
    Issue.new(issue)
  end
  
  def valid?
    return false unless id

    SCHEMA_ATTRIBUTES.each { |attr, cfg| return false if cfg[:required] && @issue[attr].nil? }

    @issue.each do |attr, value|
      return false unless @issue[attr].is_a?(SCHEMA_ATTRIBUTES[attr][:class])

      if allowed_values = SCHEMA_ATTRIBUTES[attr][:allowed_values]
        return false unless allowed_values.include? @issue[attr]
      end
      
      # we don't have to check empty-string variants (whitespace) because all fields have been .strip()ed when being set
      #
      return false if SCHEMA_ATTRIBUTES[attr][:class] == String && @issue[attr] =~ /^$/
    end
    
    true
  end
end

class Taco
  HOME_DIR = '.taco'
  RC_NAME = '.tacorc'
  RC_TEXT =<<-EOT.strip
# Empty lines and lines beginning with # will be ignored.
#
# A comma separated list of valid Issue Kinds.
#
Kinds = Defect, Feature Request

# A comma separated list of valid Issue States.
States = Open, Closed

# A comma seprated list of valid Components.
Components = Widget, Doohickey, Dingus

# Comment these out to have no default.
DefaultKind = Defect
DefaultState = Open
# DefaultComponent = Widget 
EOT

  attr_accessor :home
  
  class NotFound < Exception; end
  class Ambiguous < Exception; end
  
  def initialize(root_path=nil)    
    @home = File.join(root_path || Dir.getwd, HOME_DIR)
    # @rc_path = File.join(@home, RC_NAME)
    # 
    # @config = {}
    # parse_rc! if File.exists?(@rc_path)
  end 
  
  # def parse_rc!
  #   text = open(@rc_path) { |f| f.read }
  #   
  #   text.lines.each do |line|
  #     next if line =~ /^#/ || line =~ /^\s+$/
  #     
  #     key, values = line.split(/=/, 2).map(&:strip)
  #     if key.start_with?('Default')
  #       @config[key] = values
  #     else
  #       @config[key] = values.split(',').map(&:strip)
  #     end
  #   end
  # end
  # 
  # def set_defaults(text)
  #   # FIXME: why does Taco know so much about Issue?
  #   #
  #   text.lines.map do |line|      
  #     if line =~ /%{(\w+)}/
  #       key = $1
  #       default = "Default#{key.capitalize}"
  # 
  #       line % { key.to_sym => @config[default] }
  #     else
  #       line
  #     end
  #   end.join
  # end
  
  def init!
    raise IOError.new("Could not create #{@home}, directory already exists.") if File.exists?(@home)

    FileUtils.mkdir_p(@home)
  
    rc_path = File.join(@home, RC_NAME)  
    open(rc_path, 'w') { |f| f.write(RC_TEXT) }  
  
    "Initialized #{@home}\nPlease edit #{rc_path} as needed."
  end
  
  def write!(issue_or_issues)
    issues = issue_or_issues.is_a?(Array) ? issue_or_issues : [ issue_or_issues ]
    
    issues.each do |issue|
      the_json = issue.to_json # do this first so we don't bother the filesystem if the issue is invalid    
      open(File.join(@home, issue.id), 'w') { |f| f.write(the_json) }
    end
    
    issue_or_issues
  end  
  
  def read(issue_id)
    issue_path = File.join(@home, issue_id)

    unless File.exist? issue_path
      entries = Dir[File.join(@home, "*#{issue_id}*")]

      raise NotFound.new unless entries.size > 0
      raise Ambiguous.new("Found several matching issues: %s" % entries.join(' ')) unless entries.size == 1

      issue_path = entries[0]
      issue_id = File.basename entries[0]
    end
     
    the_json = open(issue_path) { |f| f.read }

    issue = Issue.from_json the_json
    
    raise Issue::Invalid.new("Issue ID does not match filename: #{issue.id} != #{issue_id}") unless issue.id == issue_id
    
    issue
  end

  def list(opts={})
    ids = Dir.glob("#{@home}/*")
    
    ids.map do |name|
      id = File.basename name
      issue = Issue.from_json(open(name) { |f| f.read })
      
      raise Issue::Invalid.new("Issue ID does not match filename: #{issue.id} != #{id}") unless issue.id == id
      
      short_id = (8...id.size).each do |n|
        short_id = id[0...n]
        break short_id unless ids.count { |i| i.include? short_id } > 1
      end
      
      if opts[:short_ids]
        [ issue, short_id ]
      else
        issue
      end
    end.sort_by { |thing| opts[:short_ids] ? thing[0] : thing}
  end
end

class TacoCLI
  def initialize(taco=nil)
    @taco = taco || Taco.new
  end
    
  def execute!(cmd, *args)
    case cmd
    when 'init'
      @taco.init!      
    when 'list'
      @taco.list(:short_ids => true).map { |issue, short_id| "#{short_id} : #{issue.summary}" }.join("\n")
    when 'show'
      args.map { |id| @taco.read(id).to_s }.join("\n\n")        
    when 'template'
      Issue::TEMPLATE
    when 'new'
      if args.size > 0
        the_template = open(args[0]) { |f| f.read }
        issue = @taco.write!(Issue.from_template(the_template))
        
        "Created Issue #{issue.id}"
      elsif args.size == 0
        issue = interactive_new!
        "Created Issue #{issue.id}"
      end
    end          
  end
  
  def interactive_new!
    def set_defaults(str)
      str
    end
    
    template = set_defaults(Issue::TEMPLATE)
    issue = nil      
    
    file = Tempfile.new('taco')    
    begin
      path = file.path
      file.write(template)
      file.close
    
      # FIXME: we should probably consult the exit code here
      #
      cmd = "$EDITOR #{path}"
      system(cmd)
  
      begin
        open(path) do |f| 
          text = f.read
          raise Errno::ENOENT if text == template
          issue = Issue.from_template(text)
        end      
      rescue Errno::ENOENT
        issue = nil
      end
    ensure
      File.unlink(path) rescue nil
    end
  
    @taco.write! issue
  end
end

if __FILE__ == $PROGRAM_NAME
  cli = TacoCLI.new(Taco.new)
  puts cli.execute! ARGV[0], *ARGV[1..-1]
end