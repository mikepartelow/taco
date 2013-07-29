require 'issue'
require 'taco'
require 'tacorc'

class TacoCLI
  RETRY_NAME = '.taco_retry.txt'

  TACORC_NAME = '.tacorc'
  INDEX_ERB_NAME = '.index.html.erb'
  
  DEFAULT_TACORC_NAME = 'tacorc'
  DEFAULT_INDEX_ERB_NAME = 'index.html.erb'
  DEFAULTS_HOME = File.realpath(File.join(File.dirname(__FILE__), '../lib/taco/defaults/'))
  
  def initialize
    @taco = Taco.new
    
    @retry_path = File.join(@taco.home, RETRY_NAME)

    @tacorc_path = File.join(@taco.home, TACORC_NAME)
    @index_erb_path = File.join(@taco.home, INDEX_ERB_NAME)
    
    if File.exist? @tacorc_path
      rc = TacoRc.new @tacorc_path
      rc.update_schema! Issue
      p Issue.schema_attributes[:kind]
    end
  end
  
  def init!
    out = @taco.init!

    FileUtils.copy(File.join(DEFAULTS_HOME, DEFAULT_TACORC_NAME), @tacorc_path)    
    FileUtils.copy(File.join(DEFAULTS_HOME, DEFAULT_INDEX_ERB_NAME), @index_erb_path)
    
    out + "\nPlease edit the config file at #{@tacorc_path}"
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
      { :template => Issue.new.to_template }
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
      (Issue::TEMPLATE % Issue.new.to_hash).strip
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
end