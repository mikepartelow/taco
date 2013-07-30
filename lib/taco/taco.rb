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
        %Q|i.send("#{attr}").to_s == "#{val}"|
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