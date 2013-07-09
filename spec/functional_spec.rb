require 'taco'
require 'fileutils'

TACO_PATH = File.realdirpath "./taco.rb"
TMP_PATH = File.realdirpath "./spec/tmp"
TACORC_PATH = File.join(TMP_PATH, '.taco', '.tacorc')
EDITOR_PATH = File.realdirpath "./spec/editor.rb"

def ex(args, opts={:env => {}})
  r, w = IO.pipe

  cmd = "cd #{TMP_PATH} && #{TACO_PATH} #{args}"

  Process.wait(Process.spawn(opts[:env], cmd, :out => w))
  w.close

  [ $?.to_i, r.read.strip ]
end

describe "Command Line Interface" do
  let(:taco) { Taco.new TMP_PATH }
  let(:issues) { FactoryGirl.build_list(:issue, 100) }
  
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
    
    it "initializes non-CWD directory via env var" #v2.0
  end
  
  describe "help" do
    it "shows help when no arguments are given"
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
      r.should_not eq 0
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

    it "shows created_at" do
      r, out = ex 'show %s' % issues[0].id
      r.should eq 0
      out.should =~ /Created At\s+:\s+#{issues[0].created_at}/
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
      let(:template) { <<-EOT
# Lines beginning with # will be ignored.
Summary   : %{summary}
Kind      : %{kind}
# Everything past this line is Issue Description
%{description}
EOT
  }  
    let(:attrs) { FactoryGirl.attributes_for(:issue) }
    let(:issue_path) { File.realdirpath 'spec/tmp/issue' }

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
        
        it "handles unknown allowable values" do
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
          out.should include "Cannot set allowable values for write-protected Issue attribute 'id' on line 1"
        end
                  
        it "handles comments" do
          open(TACORC_PATH, 'w') { |f| f.write("#DefaultKind = Whiffle") }
          r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
          issue_id = out.split("Created Issue ")[1]

          issue = taco.read(issue_id)
          issue.kind.should_not eq 'Whiffle'
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
          issue_text = "Summary:\nKind: KindNumber2\nsome description"
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
             
        it "returns to the editor after failed validation in interactive mode so the user doesn't lose all their hard-typed information"
        
        it "allows users to specify required fields" # v2.0
      end
    end
    
    it "complains if no $EDITOR is set for interactive new" do
      r, out = ex 'new', :env => { 'EDITOR' => nil }
      r.should_not eq 0
      out.should include "Please define $EDITOR in your environment."      
    end
    
    it "does something nice when aborting new issue creation" do
      r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_ABORT' => 'yes' }
      r.should eq 0
      out.should include 'Aborted.'
    end
  end
  
  describe "edit" do
    it "edits an existing issue"
  end
  
  describe "comment" do
    it "adds comments to an existing issue"
  end
  
  describe "history" do
    it "shows revision history for an issue"
  end
  
  describe "template" do
    it "displays the Issue template"
    it "displays the Issue template with defaults"
  end  
end