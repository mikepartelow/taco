#!/bin/env ruby

require 'json'
require 'digest'
require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'time'

# TODO:
#  - store schema version in each issue
#  - query by status
#  - editing: full (editor) or quick (commandline updates, like new arguments)
#  - arguments to 'new': taco new component:foo kind:bar summary:'ick thud wank'
#  - simplified editing: taco edit 123abc summary:'change only this one field'
#  - arg parsing: https://github.com/visionmedia/commander (check out their other stuff, too)
#  - should taco config and issues go into different directories?
#  - activities (or a better name): timestamped, attributed log of changes to an issue

#  - fully interactive mode (shell)

#  - don't bypass commander's exception handler, fix it and use it.
#    - fix problems with commander and send patch to owner (clone to taco until gem suffices)
#  - interactive_new can use say_editor

#  - dsl for attributes: attr :id, :class => String, :required => true, :settable => false
#                        => creates setter/getter and validators
#                        perhaps a different dsl for taco vs user attrs: id vs kind

#  PATH TO 1.0
#  ---
#
#  - status
#  - owner
#  - comments
#  - changelog

class Issue  
  include Comparable
  
  SCHEMA_ATTRIBUTES = {
    :id             => { :class => String,    :required => true,   :settable => false },
    :created_at     => { :class => Time,      :required => true,   :settable => false },
    :updated_at     => { :class => Time,      :required => true,   :settable => false },
    
    :summary        => { :class => String,    :required => true,   :settable => true },
    :kind           => { :class => String,    :required => true,   :settable => true },
    :description    => { :class => String,    :required => true,   :settable => true },
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
    
    @new = @issue[:created_at].nil? && @issue[:id].nil?
    
    @issue[:created_at] = Time.now unless @issue.include?(:created_at) # intentionally not using ||=
    @issue[:updated_at] = Time.now unless @issue.include?(:updated_at) # intentionally not using ||=
    @issue[:id] = SecureRandom.uuid.gsub('-', '') unless @issue.include?(:id) # intentionally not using ||=
    
    @issue = Issue::validate_attributes @issue
    
    self
  end
  
  def new?
    @new
  end
  
  def self.set_allowed_values(attrs)
    attrs.each do |attr, values|
      raise ArgumentError.new("Unknown Issue attributes: #{attr}") unless SCHEMA_ATTRIBUTES.include? attr      
      
      SCHEMA_ATTRIBUTES[attr][:allowed_values] = values
    end
  end
  
  # self.validate_attributes does known-attr checking, type checking, and value-massaging.
  # FIXME: since we have a valid? function which actually does "Validation", this should be renamed.
  #
  def self.validate_attributes(issue_attrs)
    attrs = issue_attrs.dup
    
    attrs.keys.each { |attr| raise ArgumentError.new("Unknown Issue attribute: #{attr}") unless SCHEMA_ATTRIBUTES.include? attr }
    
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
  
  def method_missing(method, *args, &block)
    method_str = method.to_s
    attr = method_str.gsub(/=$/, '').to_sym

    if data = SCHEMA_ATTRIBUTES[attr]
      if method_str[-1] == '='
        raise NoMethodError unless data[:settable]
        @issue = Issue::validate_attributes(@issue.merge( { attr => args.first } ) )
        @issue[:updated_at] = Time.now        
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
  
  def to_s
    # FIXME: this should not use TEMPLATE.
    #    
    header =<<-EOT.strip
ID          : #{id}
Created At  : #{created_at}
EOT
    
    body = TEMPLATE % @issue
    body = body.lines.reject { |l| l.start_with?('#') }.join
    
    header + "\n" + body
  end
  
  def to_json
    valid? :raise => true
    JSON.pretty_generate(@issue)
  end
  
  def to_template
    if new?
      header = "# New Issue\n#"
      body = TEMPLATE
    else
      header =<<-EOT.strip
# Edit Issue
#
# ID          : #{id}
# Created At  : #{created_at}
#
EOT
      body = TEMPLATE % @issue
    end
    header + "\n" + body
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
          raise ArgumentError.new("Unknown Issue attribute: #{key}") unless SCHEMA_ATTRIBUTES.include?(key)
          raise ArgumentError.new("Cannot set write-protected Issue attribute: #{key}")
        end
      else
        issue[:description] += line
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

    @issue = Issue::validate_attributes(Hash[attrs])
    @issue[:updated_at] = Time.now
    
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
    rescue Issue::Invalid
      return false unless opts[:raise]
      raise
    end
    
    true
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
  RC_NAME = '.tacorc'
  RC_TEXT =<<-EOT.strip
# Empty lines and lines beginning with # will be ignored.
#
# A comma separated list of valid values for Issue.kind.
#
Kind = Defect, Feature Request

# Comment out to have no default.
DefaultKind = Defect
EOT

  class ParseError < Exception; end
  
  def initialize(taco=nil)
    @taco = taco || Taco.new
    
    @rc_path = File.join(@taco.home, RC_NAME)
    @config = parse_rc
    
    Issue.set_allowed_values @config[:allowed]
  end
  
  def init!
    out = @taco.init!
    open(@rc_path, 'w') { |f| f.write(RC_TEXT) }
    out + "\nPlease edit the config file at #{@rc_path}"
  end

  def list
    the_list = @taco.list(:short_ids => true).map { |issue, short_id| "#{short_id} : #{issue.summary}" }
    return "Found no issues." unless the_list.size > 0
    the_list.join("\n")
  end
  
  def new!(args)
    if args.size > 0
      the_template = open(args[0]) { |f| f.read }
      issue = @taco.write!(Issue.from_template(the_template))
      
      "Created Issue #{issue.id}"
    elsif args.size == 0
      if issue = interactive_edit!
        "Created Issue #{issue.id}"
      else
        "Aborted."
      end
    end
  end
  
  def show(args)
    args.map { |id| @taco.read(id).to_s }.join("\n\n")        
  end
  
  def edit!(args)
    if args.size == 1
      issue = @taco.read args[0]
      if issue = interactive_edit!(issue)
        "Updated Issue #{issue.id}"
      else
        "Aborted."
      end
    end
  end
      
  private  
    def interactive_edit!(issue=Issue.new)    
      raise ArgumentError.new("Please define $EDITOR in your environment.") unless ENV['EDITOR']

      template = format_template(issue.to_template)
      new_issue = nil      

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
            
            if issue.new?
              new_issue = Issue.from_template(text)
            else
              issue.update_from_template!(text)
              new_issue = issue
            end
          end      
        rescue Errno::ENOENT
          new_issue = nil
        end
      ensure
        File.unlink(path) rescue nil
      end

      if new_issue
        @taco.write! new_issue
      else
        nil
      end
    end
  
    def format_template(text)
      text % @config[:defaults]
    end
    
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

if __FILE__ == $PROGRAM_NAME
  begin
    cli = TacoCLI.new(Taco.new)
  rescue TacoCLI::ParseError => e
    puts "Parse error while reading .tacorc: #{e}"
    exit 1
  end

  require 'commander/import'
  
  program :name, 'taco'
  program :version, '0.9.0'
  program :description, 'simple command line issue tracking'

  command :init do |c|
    c.syntax = 'taco init'
    c.summary = 'initialize a taco repo in the current directory'
    c.description = 'Initialize a taco Issue repository in the current working directory'
    c.action do |args, options|
      begin
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
        puts cli.list
      rescue Exception => e
        puts "Error: #{e}"
        exit 1
      end
    end
  end
    
  command :new do |c|
    c.syntax = 'taco new [path_to_issue_template]'
    c.summary = 'create a new issue'
    c.description = "Create a new issue, interactively or from a template file.\n    Interactive mode launches $EDITOR with an Issue template."
    c.example 'interactive issue creation', 'taco new'
    c.example 'issue creation from a file', 'taco new /path/to/template'    
    c.action do |args, options|
      begin
        puts cli.new! args
      rescue Exception => e
        puts "Error: #{e}"
        exit 1
      end
    end  
  end
  
  command :show do |c|
    c.syntax = 'taco show <issue id0..issue idN>'
    c.summary = 'display details for one or more issues'
    c.description = 'Display details for one or more issues'
    c.example 'show issue by id', 'taco show 9f9c52ce1ced4ace878155c3a98cced0'
    c.example 'show issue by unique id fragment', 'taco show ce1ced'
    c.example 'show two issues by unique id fragment', 'taco show ce1ced bc2de4'
    c.action do |args, options|
      begin
        puts cli.show args
      rescue Exception => e
        puts "Error: #{e}"
        exit 1
      end
    end  
  end

  command :edit do |c|
    c.syntax = 'taco edit <issue_id>'
    c.summary = 'edit an issue'
    c.description = 'Edit details for an issue'
    c.action do |args, options|
      begin
        puts cli.edit! args
      rescue Exception => e
        puts "Error: #{e}"
        exit 1
      end
    end  
  end

  
end
