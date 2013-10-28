require 'tempfile'
require 'fileutils'
require 'time'

require 'taco/issue'

class Taco
  HOME_DIR = '.taco'

  attr_accessor :home

  class NotFound < Exception; end
  class Ambiguous < Exception; end

  def initialize(root_path=nil)
    @home = File.join(root_path || Dir.getwd, HOME_DIR)
    @index_path = File.join(@home, '.index')
    @cache_path = File.join(@home, '.cache')
  end

  def init!
    raise IOError.new("Could not create #{@home}\nDirectory already exists.") if File.exists?(@home)

    FileUtils.mkdir_p(@home)

    index!

    "Initialized #{@home}"
  end

  def write!(issue_or_issues)
    issues = issue_or_issues.is_a?(Array) ? issue_or_issues : [ issue_or_issues ]

    issues.each do |issue|
      the_json = issue.to_json # do this first so we don't bother the filesystem if the issue is invalid
      open(File.join(@home, issue.id), 'w') { |f| f.write(the_json) }
    end

    # FIXME: this is a pretty slow thing to do.
    #
    index!

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
    if opts.fetch(:filters, []).size > 0
      # FIXME: find a *fast* way to tell if the index is stale.  a slow way: the index is older than the youngest issue
      #         this is extremely important since we can "git pull" and end up with new issues, and thus a stale index
      #
      #
      # FIXME: Index class
      #
      # FIXME: make sure @index_path isn't committed, it should be kept local
      #      

      # NOTE: it seems that splitting the_index and the_cache into separate files is actually slower than
      #       using one big file.
      #
      the_index = JSON.parse(open(@index_path) { |f| f.read })

      groups = opts[:filters].map do |filter|
        attr, val = filter.split(':', 2)
        attr = Issue.schema_attr_expand(attr)
        the_index[attr.to_s][val.downcase] || []
      end

      ids = groups.inject { |common, group| common & group } || []
    else
      ids = if Dir.exists? @home
        Dir.entries(@home).reject { |e| e.start_with? '.' }
      else
        []
      end
    end

    if opts[:thin_issue] && File.exists?(@cache_path)
      the_cache = JSON.parse(open(@cache_path) { |f| f.read })
    else
      the_cache = {}
    end

    ids.map do |id|
      issue = if opts[:thin_issue]
        Issue.new the_cache[id]
      else
        Issue.from_json(open(File.join(@home, id)) { |f| f.read })
      end

      raise Issue::Invalid.new("Issue ID does not match filename: #{issue.id} != #{id}") unless issue.id == id

      # FIXME: this could be done when we generate the_cache 
      #
      the_short_id = 8.upto(id.size).each do |n|
        the_short_id = id[0...n]
        break the_short_id unless ids.count { |i| i.include? the_short_id } > 1
      end

      # because the length of the short_id is determinable only within the context of a group of issues
      # (because it must long enough to be unique), we can only define it on Issue in the context of a group
      #
      issue.instance_eval "def short_id; #{the_short_id.inspect}; end"

      issue
    end.reject(&:nil?).sort
  end

  def index!
    the_index = {}
    the_cache = {}

    list.each do |issue|      
      the_hash = issue.to_hash

      the_hash.each do |k, v|
        k, v = k.downcase, v.to_s.downcase
        the_index[k] ||= {}
        the_index[k][v] ||= []
        the_index[k][v] << issue.id
      end

      the_cache[issue.id] = the_hash
    end

    open(@index_path, 'w') { |f| f.write(the_index.to_json) }
    open(@cache_path, 'w') { |f| f.write(the_cache.to_json) }
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