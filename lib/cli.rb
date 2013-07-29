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
    
    # Issue.set_allowed_values! @config[:allowed]
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
      defaults = Hash[Issue.schema_attributes.select { |attr, opts| opts[:settable] }.map { |attr, opts| [ attr, nil ] } ] 
      config = { :defaults => defaults, :allowed => {} }
      
      def set_attr(hash, what, attr, value, line)
        if data = Issue.schema_attributes[attr]
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
