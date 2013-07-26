#!/bin/env ruby

require 'json'
require 'digest'
require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'time'

def timescrub(t)
  # Time objects have sub-second precision.  Unfortunately, this precision is lost when we serialize.  What this means
  # is that the following code will fail, most unexpectedly:
  #
  #  i0 = Issue.new some_attributes
  #  i1 = Issue.from_json(i0.to_json)
  #  i0.created_at == i1.created_at  # this will be false!
  #      
  Time.new t.year, t.mon, t.day, t.hour, t.min, t.sec, t.utc_offset
end

# it's rude to pollute the global namespace, but here we go.
#
def date(t)
  t.strftime "%Y/%m/%d %H:%M:%S"
end

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


class Issue  
  include Comparable
    
  attr_reader :changelog
  
  SCHEMA_ATTRIBUTES = {
    :id             => { :class => String,    :required => true,    :settable => false },
    :created_at     => { :class => Time,      :required => true,    :settable => false },
    :updated_at     => { :class => Time,      :required => true,    :settable => false },
    
    :summary        => { :class => String,    :required => true,    :settable => true },
    :kind           => { :class => String,    :required => true,    :settable => true },
    :status         => { :class => String,    :required => true,    :settable => true },
    :owner          => { :class => String,    :required => true,    :settable => true },
    
    :priority       => { :class => Fixnum,    :required => true,    :settable => true },
    
    :description    => { :class => String,    :required => true,    :settable => true },
  }
  
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
  
  def initialize(issue={}, changelog=[])
    issue = Hash[issue.map { |k, v| [ k.to_sym, v ] }]
    
    @new = issue[:created_at].nil? && issue[:id].nil?      
    
    issue[:created_at] = Time.now unless issue.include?(:created_at) # intentionally not using ||=
    issue[:updated_at] = Time.now unless issue.include?(:updated_at) # intentionally not using ||=
    issue[:id] = SecureRandom.uuid.gsub('-', '') unless issue.include?(:id) # intentionally not using ||=

    @changelog = []
    @issue = {}
    
    self.issue = Issue::format_attributes issue
    
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
  
  def method_missing(method, *args, &block)
    method_str = method.to_s
    attr = method_str.gsub(/=$/, '').to_sym

    if data = SCHEMA_ATTRIBUTES[attr]
      if method_str[-1] == '='
        raise NoMethodError unless data[:settable]
        self.issue = Issue::format_attributes(@issue.merge( { attr => args.first } ) )
        @issue[:updated_at] = timescrub Time.now        
      else
        @issue[attr]
      end
    else
      super
    end
  end
  
  def respond_to?(method)
    method_str = method.to_s
    attr = method_str.gsub(/=$/, '').to_sym

    if data = SCHEMA_ATTRIBUTES[attr]
      return method_str[-1] != '=' || data[:settable]
    end
    
    super
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
  
  def valid?(opts={})
    begin
      raise Issue::Invalid.new("id is nil") unless id

      SCHEMA_ATTRIBUTES.each do |attr, cfg| 
        raise Issue::Invalid.new("Missing required attribute: #{attr}") if cfg[:required] && @issue[attr].nil?
      end

      @issue.each do |attr, value|
        unless @issue[attr].is_a?(SCHEMA_ATTRIBUTES[attr][:class])
          raise Issue::Invalid.new("Wrong type: #{attr} (expected #{SCHEMA_ATTRIBUTES[attr][:class]}, got #{@issue[attr.class]})")
        end

        if allowed_values = SCHEMA_ATTRIBUTES[attr][:allowed_values]
          unless allowed_values.include? @issue[attr]
            raise Issue::Invalid.new("#{@issue[attr]} is not an allowed value for #{attr.capitalize}")
          end
        end
      
        if SCHEMA_ATTRIBUTES[attr][:class] == String && @issue[attr] =~ /\A\s*\Z/
          raise Issue::Invalid.new("Empty string is not allowed for #{attr}")
        end
      end
    rescue Issue::Invalid => e
      return false unless opts[:raise]
      raise e
    end
    
    true
  end
  
  private
    def issue=(new_issue)
      new_issue.each do |attr, value|        
        if SCHEMA_ATTRIBUTES[attr][:settable] && @issue[attr] != new_issue[attr]
          @changelog << Change.new(:attribute => attr, :old_value => @issue[attr], :new_value => new_issue[attr])
        end
      end
      
      @issue = new_issue
    end
end

class Taco
  HOME_DIR = '.taco'

  attr_accessor :home
  
  class NotFound < Exception; end
  class Ambiguous < Exception; end
  
  def initialize(root_path=nil)    
    @home = File.join(root_path || Dir.getwd, HOME_DIR)
  end 
  
  def init!
    raise IOError.new("Could not create #{@home}\nDirectory already exists.") if File.exists?(@home)

    FileUtils.mkdir_p(@home)
  
    "Initialized #{@home}"
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

      raise NotFound.new("Issue not found.") unless entries.size > 0
      unless entries.size == 1
        issue_list = entries.map do |entry|
          issue = read(File.basename(entry))
          "#{issue.id} : #{issue.summary}"
        end
        raise Ambiguous.new("Found several matching issues:\n%s" % issue_list.join("\n")) 
      end

      issue_path = entries[0]
      issue_id = File.basename entries[0]
    end
     
    the_json = open(issue_path) { |f| f.read }

    issue = Issue.from_json the_json
    
    raise Issue::Invalid.new("Issue ID does not match filename: #{issue.id} != #{issue_id}") unless issue.id == issue_id
    
    issue
  end

  def list(opts={})
    filter_match = if opts.fetch(:filters, []).size > 0
      conditions = opts[:filters].map do |filter|
        attr, val = filter.split(':')
        %Q|i.send("#{attr}") == "#{val}"|
      end.join ' && '
      
      # FIXME: eval-ing user input? madness!
      eval "Proc.new { |i| #{conditions} }"
    else
      nil
    end
    
    ids = Dir.glob("#{@home}/*")
    
    ids.map do |name|
      id = File.basename name
      issue = Issue.from_json(open(name) { |f| f.read })

      next unless filter_match.nil? || filter_match.call(issue)
      
      raise Issue::Invalid.new("Issue ID does not match filename: #{issue.id} != #{id}") unless issue.id == id
      
      short_id = 8.upto(id.size).each do |n|
        short_id = id[0...n]
        break short_id unless ids.count { |i| i.include? short_id } > 1
      end
      
      if opts[:short_ids]
        [ issue, short_id ]
      else
        issue
      end
    end.reject(&:nil?).sort_by { |thing| opts[:short_ids] ? thing[0] : thing}
  end
end

class IssueEditor
  def initialize(taco, retry_path)    
    @taco, @retry_path = taco, retry_path
  end
  
  def new_issue!(opts={})
    if opts[:from_file]
      text = open(opts[:from_file]) { |f| f.read }
    else
      raise ArgumentError.new("Please define $EDITOR in your environment.") unless ENV['EDITOR']
      text = invoke_editor(opts[:template])
    end

    write_issue!(Issue.from_template(text), text) if text
  end
  
  def edit_issue!(issue, opts={})
    if text = invoke_editor(opts[:template] || issue.to_template)
      write_issue!(issue.update_from_template!(text), text)
    end
  end
  
  private
    def write_issue!(issue, text)
      begin
        @taco.write! issue
      rescue Exception => e
        open(@retry_path, 'w') { |f| f.write(text) } if text
        raise e
      end
      
      File.unlink @retry_path rescue nil
      issue      
    end
      
    def invoke_editor(template)
      text = nil
      file = Tempfile.new('taco')    

      begin
        file.write(template)
        file.close

        cmd = "$EDITOR #{file.path}"
        system(cmd)

        open(file.path) do |f| 
          text = f.read
        end
      ensure
        File.unlink(file.path) rescue nil
      end

      text == template ? nil : text
    end
end

class TacoCLI
  RC_NAME = '.tacorc'
  RC_TEXT =<<-EOT.strip
# Empty lines and lines beginning with # will be ignored.
#
# comma separated list of valid values for Issue fields
#
Kind = Defect, Feature Request
Status = Open, Closed
Priority = 1, 2, 3, 4, 5

# Default values for Issue fields
#
DefaultKind = Defect
DefaultStatus = Open
DefaultPriority = 3
EOT
  RETRY_NAME = '.taco_retry.txt'

  class ParseError < Exception; end
  
  def initialize(taco=nil)
    @taco = taco || Taco.new
    
    @retry_path = File.join(@taco.home, RETRY_NAME)
    
    @rc_path = File.join(@taco.home, RC_NAME)
    @config = parse_rc
    
    Issue.set_allowed_values! @config[:allowed]
  end
  
  def init!
    out = @taco.init!
    open(@rc_path, 'w') { |f| f.write(RC_TEXT) }
    out + "\nPlease edit the config file at #{@rc_path}"
  end

  def list(args)
    the_list = @taco.list(:short_ids => true, :filters => args).map do |issue, short_id| 
      "#{short_id} : #{issue.priority} : #{issue.summary}"
    end
    return "Found no issues." unless the_list.size > 0
    the_list.join("\n")
  end
  
  def new!(args, opts)
    editor_opts = if opts[:retry]
      raise ArgumentError.new("No previous Issue edit session was found.") unless File.exist?(@retry_path)      
      { :template => open(@retry_path) { |f| f.read } }
    elsif args.size == 0
      { :template => (Issue.new.to_template % @config[:defaults]) }
    elsif args.size == 1
      { :from_file => args[0] }
    end

    if issue = IssueEditor.new(@taco, @retry_path).new_issue!(editor_opts)
      "Created Issue #{issue.id}"
    else
      "Aborted."
    end
  end
  
  def show(args, opts)
    if opts[:all]
      filters = args.select { |arg| arg.include? ':' }
      args = @taco.list(:filters => filters).map(&:id)
    end
    
    args.map { |id| @taco.read(id).to_s(opts) }.join("\n\n")
  end
  
  def edit!(args, opts)
    ie = IssueEditor.new @taco, @retry_path
    
    if opts[:retry]
      raise ArgumentError.new("No previous Issue edit session was found.") unless File.exist?(@retry_path)      
      template = open(@retry_path) { |f| f.read }
    end
    
    if issue = ie.edit_issue!(@taco.read(args[0]), :template => template)
      "Updated Issue #{issue.id}"
    else
      "Aborted."
    end
  end
  
  def template(opts)
    if opts[:defaults]
      (Issue::TEMPLATE % @config[:defaults]).strip
    else
      Issue::TEMPLATE.gsub(/%{.*?}/, '').strip
    end
  end
  
  def push(opts)
    opts[:message] ||= 'turn and face the strange'
    cmd = "git add . && git commit -am '#{opts[:message]}' && git push"
    system(cmd)
  end
      
  private  
    def parse_rc
      defaults = Hash[Issue::SCHEMA_ATTRIBUTES.select { |attr, data| data[:settable] }.map { |attr, data| [ attr, nil ] } ] 
      config = { :defaults => defaults, :allowed => {} }
      
      def set_attr(hash, what, attr, value, line)
        if data = Issue::SCHEMA_ATTRIBUTES[attr]
          if data[:settable]
            hash[attr] = value
          else
            raise ParseError.new("Cannot set #{what} for write-protected Issue attribute '#{attr}' on line #{line}")
          end
        else
          raise ParseError.new("Unknown Issue attribute '#{attr}' on line #{line}")
        end
      end
      
      if File.exist? @rc_path
        open(@rc_path) do |f|
          f.readlines.each_with_index do |line, index|
            next if line =~ /^#/ || line =~ /^\s*$/            
            
            if line =~ /^Default(\w+)\s+=\s+(\w+)/
              attr, value = $1.strip.downcase.to_sym, $2.strip
              set_attr(config[:defaults], 'default', attr, value, index+1)
            elsif line =~ /^(\w+)\s*=\s*(.*)$/
              attr, values = $1.strip.downcase.to_sym, $2.split(',').map(&:strip)
              set_attr(config[:allowed], 'allowed values', attr, values, index+1)
            else
              raise ParseError.new("Unparseable stuff on line #{index+1}")
            end
          end
        end
      end

      config
    end 
end

# ########
# main
# ########

begin
  cli = TacoCLI.new(Taco.new)
rescue TacoCLI::ParseError => e
  puts "Parse error while reading .tacorc: #{e}"
  exit 1
end

require 'commander/import'

program :name, 'taco'
program :version, '1.2.1'
program :description, 'simple command line issue tracking'

command :init do |c|
  c.syntax = 'taco init'
  c.summary = 'initialize a taco repo in the current directory'
  c.description = 'Initialize a taco Issue repository in the current working directory'
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}") unless args.size == 0
      puts cli.init!
    rescue Exception => e
      puts "Error: #{e}"
      exit 1
    end
  end
end

command :list do |c|
  c.syntax = 'taco list'
  c.summary = 'list all issues in the repository'
  c.description = 'List all taco Issues in the current repository'
  
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      unless args.all? { |arg| arg =~ /\w+:\w+/ }
        raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}")
      end
      puts cli.list args
    rescue Exception => e
      puts "Error: #{e}"
      exit 1
    end
  end
end
  
command :new do |c|
  c.syntax = 'taco new [path_to_issue_template]'
  c.summary = 'create a new Issue'
  c.description = "Create a new Issue, interactively or from a template file.\n    Interactive mode launches $EDITOR with an Issue template."
  c.example 'interactive Issue creation', 'taco new'
  c.example 'Issue creation from a file', 'taco new /path/to/template'    
  
  c.option '--retry', nil, 'retry a failed Issue creation'
  
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}") if args.size > 1
      
      begin
        puts cli.new! args, { :retry => options.retry }
      rescue Issue::Invalid => e
        raise Issue::Invalid.new("#{e.to_s}.\nYou can use the --retry option to correct this error.")      
      end
    rescue Exception => e
      puts "Error: #{e}"        
      exit 1
    end
  end  
end

command :show do |c|
  c.syntax = 'taco show <issue id0..issue idN>'
  c.summary = 'display details for one or more Issues'
  c.description = 'Display details for one or more Issues'
  c.example 'show Issue by id', 'taco show 9f9c52ce1ced4ace878155c3a98cced0'
  c.example 'show Issue by unique id fragment', 'taco show ce1ced'
  c.example 'show two Issues by unique id fragment', 'taco show ce1ced bc2de4'
  c.example 'show Issue with changelog', 'taco show --changelog 9f9c52'
  c.example "show all Issues with 'kind' value 'kind2'", 'taco show --all kind:kind2'
  c.example "show all Issues with 'kind' value 'kind2' and 'owner' value 'mike'", 'taco show --all kind:kind2 owner:mike'
  
  c.option '--changelog', nil, 'shows the changelog'
  c.option '--all', nil, 'show all Issues'
  
  c.action do |args, options|
    begin
      puts cli.show args, { :changelog => options.changelog, :all => options.all }
    rescue Exception => e
      puts "Error: #{e}"
      exit 1
    end
  end  
end

command :edit do |c|
  c.syntax = 'taco edit <issue_id>'
  c.summary = 'edit an Issue'
  c.description = 'Edit details for an Issue'
  
  c.option '--retry', nil, 'retry a failed Issue edit'
  
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}") unless args.size == 1
      
      begin
        puts cli.edit! args, { :retry => options.retry }
      rescue Issue::Invalid => e
        raise Issue::Invalid.new("#{e.to_s}.\nYou can use the --retry option to correct this error.")      
      end        
    rescue Exception => e
      puts "Error: #{e}"
      exit 1
    end
  end  
end

command :template do |c|
  c.syntax = 'taco template'
  c.summary = 'print the Issue template on stdout'
  c.description = 'Print the Issue template on stdout'
  
  c.option '--defaults', nil, 'Print the Issue template with default values'
  
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}") unless args.size == 0
      
      puts cli.template({ :defaults => options.defaults })
    rescue Exception => e
      puts "Error: #{e}"
      exit 1
    end
  end  
end

command :push do |c|
  c.syntax = 'taco push'
  c.summary = 'Add, commit, and push all changes to git remote.'
  c.description = 'Shortcut for: git add . && git commit -a && git push'
  
  c.option '--message STRING', String, 'Override the default commit message.'
  
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}") unless args.size == 0
      
      puts cli.push({ :message => options.message })
    rescue Exception => e
      puts "Error: #{e}"
      exit 1
    end
  end  
end
