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
      out.should include(taco.home)
      File.exists?(taco.home).should be_true
      
      out.should include(TacoCLI::RC_NAME)   
      File.exists?(File.join(taco.home, TacoCLI::RC_NAME)).should be_true      
    end
    
    it "initializes non-CWD directory via env var"
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
        out.should include(issue.id[0...8])
        out.should include(issue.summary)
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
    
    after { File.unlink(issue_path) }
    
    it "creates a new issue from a file" do    
      issues_before = taco.list
      r, out = ex 'new %s' % issue_path
      r.should eq 0
      out.should include("Created Issue ")
      issue_id = out.split("Created Issue ")[1]
      
      issues_after = taco.list    
      issues_after.size.should eq issues_before.size + 1
    
      issue = taco.read(issue_id)
      attrs.each { |attr, value| issue.send(attr).should eq value }
    end
  
    it "creates a new issue interactively" do
      r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_INPUT_PATH' => issue_path }
      r.should eq 0
      out.should include("Created Issue ")
      
      issue_id = out.split("Created Issue ")[1]
    
      issue = taco.read(issue_id)
      attrs.each { |attr, value| issue.send(attr).should eq value }
    end

    it "strips ruby format strings from the template" do
      r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
      r.should eq 0
      out.should include("Created Issue ")
      
      issue_id = out.split("Created Issue ")[1]
    
      issue = taco.read(issue_id)
      issue.to_s.should_not include('%{summary}')
    end

    describe "tacorc" do
      it "gives helpful error message on parse failure"
      it "warns on missing .tacorc"
      it "creates a useful default .tacorc"
      it "does not allow defaults for non-settable attrs"
    end
    
    describe "default values" do
      let(:tacorc) { <<-EOT.strip
DefaultKind = MagicString
EOT
}
      it "sets default values for issue fields" do
        open(TACORC_PATH, 'w') { |f| f.write(tacorc) }
  
        r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH }
        r.should eq 0
        out.should include("Created Issue ")

        issue_id = out.split("Created Issue ")[1]

        issue = taco.read(issue_id)
        issue.to_s.should_not include('%{kind}')        
        issue.to_s.should include('MagicString')
      end
    end
    
    describe "validation" do
      it "doesn't allow disallowed-value values"
      it "doesn't allow wrong-type values"
      it "doesn't allow empty required fields"
      it "doesn't allow unknown fields"
      it "doesn't allow changing read-only fields"
    end
    
    it "complains if no $EDITOR is set for interactive new"
    it "exits nonzero if no issue is created"
    it "does something nice when aborting new issue creation"
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