require 'taco'
require 'fileutils'

TACO_PATH = File.realdirpath "./taco.rb"
TMP_PATH = File.realdirpath "./spec/tmp"
TACORC_PATH = File.join(TMP_PATH, '.taco', '.tacorc')
EDITOR_PATH = File.realdirpath "./spec/editor.rb"
EDITOR_WRITE_PATH = File.join(TMP_PATH, 'editor_output.txt')

def ex(args, opts={:env => {}, :stderr => false})
  opts[:env] ||= {}
  opts[:stderr] ||= false
  
  r, w = IO.pipe

  cmd = "cd #{TMP_PATH} && #{TACO_PATH} #{args}"
  cmd += " 2>&1" if opts[:stderr]

  Process.wait(Process.spawn(opts[:env], cmd, :out => w))
  w.close

  [ $?.to_i, r.read.strip ]
end

describe "Command Line Interface" do
  let(:taco) { Taco.new TMP_PATH }
  let(:issues) { FactoryGirl.build_list(:issue, 100) }
  let(:attrs) { FactoryGirl.attributes_for(:issue) }
  let(:issue_path) { File.realdirpath 'spec/tmp/issue' }
  let(:template) { <<-EOT.strip
# Lines beginning with # will be ignored.
Summary     : %{summary}
Kind        : %{kind}
Status      : %{status}
Owner       : %{owner}
# Everything below the --- is Issue Description
---
%{description}
EOT
  }  

  before do 
    FileUtils.rm_rf(TMP_PATH)
    FileUtils.mkdir_p(TMP_PATH)
  end
  after { FileUtils.rm_rf(TMP_PATH) }
  
  describe "init" do
    it "initializes the repo" do 
      File.exists?(taco.home).should_not be_true
      r, out = ex 'init'
      r.should eq 0
      out.should include taco.home
      File.exists?(taco.home).should be_true
      
      out.should include TacoCLI::RC_NAME   
      File.exists?(File.join(taco.home, TacoCLI::RC_NAME)).should be_true      
    end    
  end
  
  describe "help" do
    it "shows help when no arguments are given" do
      r, out = ex '', :stderr => true
      r.should_not eq 0
      out.should include '--help'
    end
  end
  
  describe "list" do   
    before { taco.init! ; taco.write! issues }
    
    it "lists issues" do
      r, out = ex 'list'
      r.should eq 0
      out.lines.to_a.size.should eq issues.size
      issues.each do |issue|
        out.should include issue.id[0...8]
        out.should include issue.summary
      end      
    end

    it "does something useful when listing 0 issues" do
      FileUtils.rm_rf(taco.home)
      
      r, out = ex 'list'
      r.should eq 0
      out.should =~ /Found no issues./
    end
  end
  
  describe "show" do    
    before { taco.init! ; taco.write! issues }
        
    it "displays an issue" do
      r, out = ex 'show %s' % issues[0].id
      r.should eq 0
      out.should eq issues[0].to_s

      r, out = ex 'show %s' % issues[0].id[0...8]
      r.should eq 0
      out.should eq issues[0].to_s
      
      r, out = ex 'show %s %s' % [ issues[0].id, issues[1].id ]
      r.should eq 0
      out.should eq issues[0].to_s + "\n\n" + issues[1].to_s
    end

    it "shows id" do
      r, out = ex 'show %s' % issues[0].id
      r.should eq 0
      out.should =~ /ID\s+:\s+#{issues[0].id}/
    end

    it "shows timestamps" do
      r, out = ex 'show %s' % issues[0].id
      r.should eq 0
      out.should =~ /Created At\s+:\s+#{date(issues[0].created_at)}/
      out.should =~ /Updated At\s+:\s+#{date(issues[0].updated_at)}/
    end
        
    it "does not display template comments" do
      r, out = ex 'show %s' % issues[0].id
      r.should eq 0
      out.should_not =~ /^#/
    end          
    
    it "displays an error message when issue is not found" do
      r, out = ex 'show 123abc'
      r.should_not eq 0
      out.should =~ /Issue not found./
    end
    
    it "displays an error message when given issue_id is ambiguous" do
      r, out = ex 'show 1'
      r.should_not eq 0
      out.should =~ /Found several matching issues/
    end    
  end
  
  describe "new" do
    before do
      taco.init!
      taco.write! issues
    
      open(issue_path, 'w') { |f| f.write(template % attrs) }    
    end
    
    after { File.unlink(issue_path) rescue nil }
    
    it "creates a new issue from a file" do    
      issues_before = taco.list
      r, out = ex 'new %s' % issue_path
      r.should eq 0
      out.should include "Created Issue "
      issue_id = out.split("Created Issue ")[1]
      
      issues_after = taco.list    
      issues_after.size.should eq issues_before.size + 1
    
      issue = taco.read(issue_id)
      attrs.each { |attr, value| issue.send(attr).should eq value }
    end
  
    it "creates a new issue interactively" do
      r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_INPUT_PATH' => issue_path }
      r.should eq 0
      out.should include "Created Issue "
      
      issue_id = out.split("Created Issue ")[1]
    
      issue = taco.read(issue_id)
      attrs.each { |attr, value| issue.send(attr).should eq value }
    end

    it "strips ruby format strings from the template" do
      r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
      r.should eq 0
      out.should include "Created Issue "
      
      issue_id = out.split("Created Issue ")[1]
    
      issue = taco.read(issue_id)
      issue.to_s.should_not include '%{summary}'
    end

    describe "tacorc" do
      describe "parse failure" do
        it "handles unknown defaults" do
          open(TACORC_PATH, 'w') { |f| f.write("DefaultFoo = Bar") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include "Unknown Issue attribute 'foo' on line 1"
        end
        
        it "handles unknown allowed values" do
          open(TACORC_PATH, 'w') { |f| f.write("Foo = Bar, Baz, Ick") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include "Unknown Issue attribute 'foo' on line 1"
        end

        it "does not allow defaults for non-settable attrs" do
          open(TACORC_PATH, 'w') { |f| f.write("DefaultId = Bar") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include "Cannot set default for write-protected Issue attribute 'id' on line 1"
        end
        
        it "does not allow acceptable values for non-settable attrs" do
          open(TACORC_PATH, 'w') { |f| f.write("Id = Bar, Baz, Ick") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include "Cannot set allowed values for write-protected Issue attribute 'id' on line 1"
        end
                  
        it "handles comments" do
          open(TACORC_PATH, 'w') { |f| f.write("#DefaultKind = Whiffle") }
          r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
          issue_id = out.split("Created Issue ")[1]

          issue = taco.read(issue_id)
          issue.kind.should_not eq 'Whiffle'
        end
        
        it "handles whitespace" do
          open(TACORC_PATH, 'w') { |f| f.write("\n\n\nDefaultKind = Whiffle") }
          r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
          issue_id = out.split("Created Issue ")[1]

          issue = taco.read(issue_id)
          issue.kind.should eq 'Whiffle'
        end          

        it "handles gibberish" do
          open(TACORC_PATH, 'w') { |f| f.write("gibblegubble") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include 'Unparseable stuff on line 1'
        end
      end
      
      it "creates a default .tacorc" do
        FileUtils.rm_rf(TMP_PATH)
        FileUtils.mkdir_p(TMP_PATH)
        
        r, out = ex 'init'
        r.should eq 0
        File.exists?(TACORC_PATH).should be_true
      end
    end
    
    describe "with tacorc" do
      let(:tacorc) { <<-EOT.strip
Kind = KindNumber1, KindNumber2, KindNumber3
DefaultKind = KindNumber2
EOT
      }
      
      before do
        open(TACORC_PATH, 'w') { |f| f.write(tacorc) }        
      end
      
      describe "default values" do
        it "sets default values for issue fields" do  
          r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
          r.should eq 0
          out.should include "Created Issue "

          issue_id = out.split("Created Issue ")[1]

          issue = taco.read(issue_id)
          issue.to_s.should_not include '%{kind}'        
          issue.to_s.should include 'KindNumber2'
        end
      end
    
      describe "validation" do
        it "doesn't allow disallowed-value values" do
          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "is not an allowed value for Kind"
        end

        it "doesn't allow changing read-only fields" do
          issue_text = "ID : 123abc\n" + open(issue_path) { |f| f.read }
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "Cannot set write-protected Issue attribute: id"          
        end
      
        it "doesn't allow empty required fields" do
          issue_text = "Summary:\nKind: KindNumber2\nStatus: Open\nOwner: bobdole\n---\nsome description"
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "Empty string is not allowed for summary"          
        end
        
        it "doesn't allow unknown fields" do
          issue_text = "Foo : Bar\n" + open(issue_path) { |f| f.read }
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "Unknown Issue attribute: foo"                    
        end
                     
      end
    end
    
    it "complains if no $EDITOR is set for interactive new" do
      r, out = ex 'new', :env => { 'EDITOR' => nil }
      r.should_not eq 0
      out.should include "Please define $EDITOR in your environment."      
    end
    
    it "does something nice when aborting new issue creation" do
      count = taco.list.size
      r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_ABORT' => 'yes' }
      r.should eq 0
      out.should include 'Aborted.'
      taco.list.size.should eq count
    end
  end
  
  describe "edit" do
    before { taco.init! ; taco.write! issues }
    
    it "edits an existing issue" do
      issue = taco.read issues[0].id
      
      r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is edited sparta!" }
      r.should eq 0
      out.should eq "Updated Issue #{issues[0].id}"
            
      reissue = taco.read(issues[0].id)
      reissue.summary.should eq issue.summary
      reissue.description.should include 'this is edited sparta!'
    end
    
    it "does nothing if edit is aborted" do
      issue = taco.read issues[0].id
      
      r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_ABORT' => "yes" }
      r.should eq 0
      out.should eq "Aborted."
            
      reissue = taco.read(issues[0].id)
      reissue.should eq issue
    end
        
    it "manages timestamps when editing" do
      issue = Issue.new(FactoryGirl.attributes_for(:issue, :created_at => Time.now - 1000, :updated_at => Time.now - 1000))
      taco.write! issue
      
      old_created_at = issue.created_at
      old_updated_at = issue.updated_at
      
      r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is edited sparta!" }
      r.should eq 0
      out.should eq "Updated Issue #{issue.id}"
            
      reissue = taco.read(issue.id)
      reissue.created_at.should eq old_created_at
      reissue.updated_at.should_not eq old_updated_at
    end
        
    it "shows a commented changelog when editing" do
      issue = taco.read issues[0].id
      r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_WRITE_INPUT' => EDITOR_WRITE_PATH, 'EDITOR_ABORT' => "yes" }

      input = open(EDITOR_WRITE_PATH) { |f| f.read }
      input.should include ('# ' + issue.changelog.map(&:to_s)[0])
    end
  end
  
  describe "changelog" do
    before { taco.init! ; taco.write! issues }
    
    it "shows revision history for an issue when given the -c commandline switch" do
      r, out = ex 'show -c %s' % issues[0].id
      r.should eq 0
      out.should eq issues[0].to_s(:changelog => true)
    end    
  end
  
  describe "template" do
    let(:tacorc) { <<-EOT.strip
Kind = KindNumber1, KindNumber2, KindNumber3
DefaultKind = KindNumber2
EOT
    }

    before do
      taco.init!
      open(TACORC_PATH, 'w') { |f| f.write(tacorc) }        
    end
    
    it "displays the Issue template" do
      r, out = ex 'template'
      r.should eq 0
      out.should eq template.gsub(/%{.*?}/, '').strip
    end
    
    it "displays the Issue template with defaults" do
      r, out = ex 'template -d'
      r.should eq 0
      out.should eq template.gsub(/%{kind}/, 'KindNumber2').gsub(/%{.*?}/, '').strip
    end
  end  
  
  describe "retry" do
    before do
      taco.init!
      taco.write! issues      
      open(TACORC_PATH, 'w') { |f| f.write("Kind = NotBogus1, NotBogus2") }
    end
    
    describe "new" do
      it "allows editor retry after failed validation in interactive mode" do
        r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is new issue sparta!", 'EDITOR_FIELD_KIND' => 'BOGUS' }
        r.should_not eq 0
        out.should include "is not an allowed value for Kind"
        out.should include "--retry"

        r, out = ex 'new --retry', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_FIELD_KIND' => 'NotBogus2' }
        r.should eq 0
        issue_id = out.split("Created Issue ")[1]

        issue = taco.read(issue_id)
        issue.description.should include "this is new issue sparta!"       
      end
      
      it "doesn't allow --retry if validation has not failed" do
        # try to --retry on a clean repo
        r, out = ex 'new --retry', :env => { 'EDITOR' => EDITOR_PATH }
        r.should_not eq 0
        out.should include "No previous Issue edit session was found."
        
        # a valid retry
        r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is new issue sparta!", 'EDITOR_FIELD_KIND' => 'BOGUS' }
        r.should_not eq 0
        out.should include "is not an allowed value for Kind"
        out.should include "--retry"

        r, out = ex 'new --retry' % issue_path, :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_FIELD_KIND' => 'NotBogus2' }
        r.should eq 0
        
        # now, there should be no --retry because the previous --retry succeeded
        #
        r, out = ex 'new --retry', :env => { 'EDITOR' => EDITOR_PATH }
        r.should_not eq 0
        out.should include "No previous Issue edit session was found."          
      end
            
      it "does not allow --retry after aborted interactive new" do
        r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_ABORT' => 'yes' }
        r.should eq 0
        out.should include 'Aborted.'
        
        r, out = ex 'new --retry', :env => { 'EDITOR' => EDITOR_PATH }
        r.should_not eq 0
        out.should include "No previous Issue edit session was found."        
      end
    end
    
    describe "edit" do
      it "allows editor retry after failed validation in interactive mode" do
        issue = taco.read issues[0].id

        r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is edited sparta!", 'EDITOR_FIELD_KIND' => 'BOGUS' }
        r.should_not eq 0
        out.should include "is not an allowed value for Kind"
        out.should include "--retry"

        r, out = ex "edit #{issue.id} --retry", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_FIELD_KIND' => 'NotBogus2' }
        r.should eq 0

        reissue = taco.read(issue.id)
        reissue.description.should include "this is edited sparta!"
      end

      it "doesn't allow --retry if validation has not failed" do
        issue = taco.read issues[0].id
        
        r, out = ex "edit #{issue.id} --retry"
        r.should_not eq 0
        out.should include "No previous Issue edit session was found."
        
        r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is new issue sparta!", 'EDITOR_FIELD_KIND' => 'BOGUS' }
        r.should_not eq 0
        out.should include "is not an allowed value for Kind"
        out.should include "--retry"

        r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_FIELD_KIND' => 'NotBogus2' }
        r.should eq 0
        
        # now, there should be no --retry because the previous --retry succeeded
        #
        r, out = ex "edit #{issue.id} --retry", :env => { 'EDITOR' => EDITOR_PATH }
        r.should_not eq 0
        out.should include "No previous Issue edit session was found."          
      end
      
      it "does not allow --retry after aborted interactive edit" do
        issue = taco.read issues[0].id
        
        r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_ABORT' => 'yes' }
        r.should eq 0
        out.should include 'Aborted.'
        
        r, out = ex "edit #{issue.id} --retry", :env => { 'EDITOR' => EDITOR_PATH }
        r.should_not eq 0
        out.should include "No previous Issue edit session was found."        
      end   
    end
  end
    
  describe "argument handling" do
    it "displays an error for wrong number of arguments" do
      r, out = ex 'init foo'
      r.should_not eq 0
      out.should include 'Unexpected arguments'

      r, out = ex 'list foo'
      r.should_not eq 0
      out.should include 'Unexpected arguments'
            
      r, out = ex 'new foo bar'
      r.should_not eq 0
      out.should include 'Unexpected arguments'
            
      r, out = ex 'edit foo bar'
      r.should_not eq 0
      out.should include 'Unexpected arguments'
                  
      r, out = ex 'template foo'
      r.should_not eq 0
      out.should include 'Unexpected arguments'
    end
  end

  describe "comment" do
    it "adds comments to an existing issue"
  end
  
end