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
    if opts.fetch(:filters, []).size > 0
      # FIXME: find a *fast* way to tell if the index is stale.  a slow way: the index is older than the youngest issue
      #
      # FIXME: update the index when writing an issue
      #
      # FIXME: faster index update
      #
      # FIXME: Index class
      #
      the_index = JSON.parse(open(@index_path) { |f| f.read })

      groups = opts[:filters].map do |filter|
        attr, val = filter.split(':', 2)
        attr = Issue.schema_attr_expand(attr)
        the_index[attr.to_s][val]
      end

      ids = groups.inject { |common, group| common & group }.map { |id| File.join(@home, id) }
    else
      ids = Dir.glob("#{@home}/*")
    end

    ids.map do |name|
      id = File.basename name
      issue = Issue.from_json(open(name) { |f| f.read })

      raise Issue::Invalid.new("Issue ID does not match filename: #{issue.id} != #{id}") unless issue.id == id

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
    attrmap = {}

    list.each do |issue|
      # FIXME: since we're stripping these attributes, we should explicitly disallow filtering/searching on them.
      #
      fields_to_ignore = [ :id, :created_at, :updated_at, :description, ]
      the_hash = issue.to_hash.delete_if { |k,v| fields_to_ignore.include? k }

      the_hash.each do |k, v|
        k, v = k.downcase, v.to_s.downcase
        attrmap[k] ||= {}
        attrmap[k][v] ||= []
        attrmap[k][v] << issue.id
      end

      the_hash
    end

    the_json = attrmap.to_json

    open(@index_path, 'w') { |f| f.write(the_json) }
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