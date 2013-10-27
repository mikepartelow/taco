require 'taco/issue'
require 'taco/taco'
require 'taco/tacorc'
require 'taco/taco_profile'

# FIXME: this file should be named taco_cli.rb

class TacoCLI
  RETRY_NAME = '.taco_retry.txt'

  TACORC_NAME = '.tacorc'
  TACO_PROFILE_NAME = '.taco_profile'
  INDEX_ERB_NAME = '.index.html.erb'

  DEFAULT_TACORC_NAME = 'tacorc'
  DEFAULT_TACO_PROFILE_NAME = 'taco_profile'
  DEFAULT_INDEX_ERB_NAME = 'index.html.erb'

  DEFAULTS_HOME = File.realpath(File.join(File.dirname(__FILE__), 'defaults/'))

  def initialize
    @taco = Taco.new

    @retry_path = File.join(@taco.home, RETRY_NAME)

    @tacorc_path = File.join(@taco.home, TACORC_NAME)
    @taco_profile_path = File.join(@taco.home, TACO_PROFILE_NAME)
    @index_erb_path = File.join(@taco.home, INDEX_ERB_NAME)

    # FIXME: do this elsewhere.  pass in an initialized TacoRc object
    #
    if File.exist? @tacorc_path
      rc = TacoRc.new @tacorc_path
      rc.update_schema! Issue
    end

    # FIXME: do this elsewhere.  pass in an initialized TacoProfile object
    #
    if File.exist? @taco_profile_path
      profile_text = open(@taco_profile_path) { |f| f.read }
    end

    @profile = TacoProfile.new profile_text
  end

  def init!
    out = @taco.init!

    FileUtils.copy(File.join(DEFAULTS_HOME, DEFAULT_TACORC_NAME), @tacorc_path)
    FileUtils.copy(File.join(DEFAULTS_HOME, DEFAULT_TACO_PROFILE_NAME), @taco_profile_path)

    FileUtils.copy(File.join(DEFAULTS_HOME, DEFAULT_INDEX_ERB_NAME), @index_erb_path)

    out + "\nPlease edit the config files at:\n #{@tacorc_path}\n #{@taco_profile_path}"
  end

  def list(args, opts)
    filters = args.size > 0 ? args : @profile.filters

    the_list = @taco.list :filters => filters

    if opts[:sort]
      attrs = opts[:sort].split(',').map(&:to_sym)
      attrs.each do |attr|
        # FIXME: don't hardcode :short_id
        raise ArgumentError.new("Unknown Issue attribute for sort: #{attr}") unless attr == :short_id || Issue.schema_attributes.include?(attr)
      end
    else
      attrs = @profile.sort_order
    end

    the_list.sort! do |issue_a, issue_b|
      order = 0

      attrs.take_while do |attr|
        order = issue_a.send(attr) <=> issue_b.send(attr)
        order == 0
      end

      order
    end

    the_list.map! do |issue|
      @profile.columns.map { |col| issue.send(col) }.join(' : ')
    end

    return "Found no issues." unless the_list.size > 0
    the_list.join("\n")
  end

  def new!(args, opts)
    editor_opts = if opts[:retry]
      raise ArgumentError.new("No previous Issue edit session was found.") unless File.exist?(@retry_path)
      { :template => open(@retry_path) { |f| f.read } }
    else
      file, defaults = nil, {}

      args.each do |arg|
        if arg.include? ':'
          k, v = arg.split(':', 2)
          defaults[k.to_sym] = v
        elsif file
          raise ArgumentError.new("Multiple filenames given.")
        else
          file = arg
        end
      end

      if file && defaults.size > 0
        raise ArgumentError.new("Cannot set defaults when creating Issue from file.")
      elsif file
        { :from_file => file, :defaults => defaults }
      else
        { :template => Issue.new.to_template(:defaults => defaults) }
      end
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