#!/bin/env ruby

require 'json'
require 'digest'
require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'time'

require 'change'
require 'schema'

# it's rude to pollute the global namespace, but here we go.
#
def date(t)
  t.strftime "%Y/%m/%d %H:%M:%S"
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
  INDEX_ERB_NAME = '.index.html.erb'
  INDEX_ERB_SRC_PATH = File.realpath(File.join(File.dirname(__FILE__), '../lib/taco/defaults/index.html.erb'))  

  class ParseError < Exception; end
  
  def initialize(taco=nil)
    @taco = taco || Taco.new
    
    @retry_path = File.join(@taco.home, RETRY_NAME)
    
    @rc_path = File.join(@taco.home, RC_NAME)
    @config = parse_rc
    
    @index_erb_path = File.join(@taco.home, INDEX_ERB_NAME)
    
    Issue.set_allowed_values! @config[:allowed]
  end
  
  def init!
    out = @taco.init!
    open(@rc_path, 'w') { |f| f.write(RC_TEXT) }
    
    FileUtils.copy(INDEX_ERB_SRC_PATH, @index_erb_path)
    
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
  
  def html
    require 'erb'
    
    issues = @taco.list
    ERB.new(open(@index_erb_path) { |f| f.read }).result(binding)    
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
program :version, '1.3.1'
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

command :html do |c|
  c.syntax = 'taco html'
  c.summary = 'Generate an HTML buglist'
  c.description = 'Generate an HTML buglist from index.html.erb'
  
  c.action do |args, options|
    begin
      # FIXME: merge this kind of thing into commander: tell it how many arguments we expect.
      raise ArgumentError.new("Unexpected arguments: #{args.join(', ')}") unless args.size == 0
      
      puts cli.html
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
