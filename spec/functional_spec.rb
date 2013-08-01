require 'taco/taco'
require 'taco/cli'
require 'fileutils'

def date(t)
  t.strftime "%Y/%m/%d %H:%M:%S"
end

def ex(args, opts={:env => {}, :stderr => false})
  opts[:env] ||= {}
  opts[:stderr] ||= false
  
  r, w = IO.pipe

  cmd = "cd #{TMP_PATH} && ruby -I#{LIB_PATH} #{TACO_PATH} #{args}"
  cmd += " 2>&1" if opts[:stderr]

  # FIXME: this code can't handle hundreds of lines out output. in that case, it hangs.
  #        see NOTE 123456
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
Priority    : %{priority}
Owner       : %{owner}

# Everything between the --- lines is Issue Description
---
%{description}
---
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
      
      out.should include TacoCLI::TACORC_NAME   
      out.should include TacoCLI::TACO_PROFILE_NAME
      File.exists?(File.join(taco.home, TacoCLI::TACORC_NAME)).should be_true      
      File.exists?(File.join(taco.home, TacoCLI::INDEX_ERB_NAME)).should be_true      
      File.exists?(File.join(taco.home, TacoCLI::TACO_PROFILE_NAME)).should be_true            
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
    
    describe "sorting" do      
      it "sorts by the given attributes" do
        i1, i2, i3, i4, i5, i6 = [
          FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner3', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind3', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind1', :owner => 'owner1', :priority => 3),      

          FactoryGirl.build(:issue, :summary => 'summary4', :kind => 'kind6', :owner => 'owner1', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary5', :kind => 'kind5', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary6', :kind => 'kind4', :owner => 'owner3', :priority => 3),      
        ]
      
        FileUtils.rm_rf(taco.home)
        taco.init!
        taco.write! [ i1, i2, i3, i4, i5, i6 ]
      
        r, out = ex 'list --sort priority,owner,kind'
        r.should eq 0
        [ i4, i1, i2, i5, i3, i6 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end
        
        r, out = ex 'list --sort kind,priority,owner'
        r.should eq 0
        [ i3, i1, i2, i6, i5, i4 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end        

        r, out = ex 'list --sort priority,kind,owner'
        r.should eq 0
        [ i1, i4, i2, i5, i3, i6 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end        
      end
      
      it "gives a nice error message for unknown attributes"
      
      it "sorts asc or desc as given"
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
    
    it "displays all issues" do
      r, out = ex 'show --all'
      r.should eq 0
      issues.each { |issue| out.should include issue.id }
    end
    
    it "displays all issues that match a filter" do
      kind2_issues = [ FactoryGirl.build(:issue, :kind => 'kind2'), FactoryGirl.build(:issue, :kind => 'kind2' ) ]
      taco.write! kind2_issues
      
      r, out = ex 'show --all kind:kind2'
      r.should eq 0
      issues.each { |issue| out.should_not include issue.id }
      kind2_issues.each { |issue| out.should include issue.id }      
    end
    
    it "does not allow filters without -all"    
    it "does not allow mixing of --all with issue ids"
    it "does not allow mixing of issue ids with filters"
    it "filters by attribute with spaces"
    it "filters by attribute with wildcard"        
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
        after { FileUtils.rm_rf(TMP_PATH) }
        
        it "handles unknown attrs" do
          open(TACORC_PATH, 'w') { |f| f.write("schema_attr_update :foo, default: 3") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include "line 1"
          out.should include "attribute foo"
        end
        
        it "does not allow defaults for non-settable attrs" do
          open(TACORC_PATH, 'w') { |f| f.write("schema_attr_update :id, default: 'abc'") }
          r, out = ex 'list'
          r.should_not eq 0
          out.should include "line 1"
          out.should include "cannot update non-settable"
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
schema_attr_update :kind, default: 'KindNumber2', validate: [ 'KindNumber1', 'KindNumber2', 'KindNumber3' ]
schema_attr_update :priority, validate: [ 1, 2, 3, 4, 5 ]
EOT
      }
      
      before { open(TACORC_PATH, 'w') { |f| f.write(tacorc) } }
      after { FileUtils.rm_rf(TMP_PATH) }      
      
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
          out.should include '"Defect" is not a valid value'
        end

        it "doesn't allow changing read-only fields" do
          issue_text = "ID : 123abc\n" + open(issue_path) { |f| f.read }
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "Cannot set write-protected Issue attribute: id"          
        end
      
        it "doesn't allow empty required fields" do
          issue_text = "Summary:\nKind: KindNumber2\nStatus: Open\nOwner: bobdole\nPriority: 3\n---\nsome description\n---"
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include 'attribute summary: "" is not a valid value'
        end
        
        it "doesn't allow unknown fields" do
          issue_text = "Foo : Bar\n" + open(issue_path) { |f| f.read }
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "Unknown Issue attribute: foo"                    
        end   
        
        it "constrains the Fixnum field priority" do
          issue_text = "Priority: 99\nSummary: foo\nKind: KindNumber2\nStatus: Open\nOwner: bobdole\n---\nsome description\n---"
          open(issue_path, 'w') { |f| f.write(issue_text) }

          r, out = ex 'new %s' % issue_path
          r.should_not eq 0
          out.should include "attribute priority: 99 is not a valid value"
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
    
    it "edits an issue with multi-line description" do
      issue = taco.read issues[0].id      
      old_description = issue.description
      r, out = ex "edit #{issue.id}", :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "this is edited sparta!" }

      issue = taco.read issue.id

      issue.description.should eq old_description + "\nthis is edited sparta!"
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
schema_attr_update :kind, default: 'KindNumber2', validate: [ 'KindNumber1', 'KindNumber2', 'KindNumber3' ]
EOT
    }

    before do
      taco.init!
      open(TACORC_PATH, 'w') { |f| f.write(tacorc) }        
    end
    
    after { FileUtils.rm_rf(TMP_PATH) }    
    
    it "displays the Issue template" do
      r, out = ex 'template'
      r.should eq 0
      out.should eq template.gsub(/%{.*?}/, '').strip
    end
    
    it "displays the Issue template with defaults" do
      r, out = ex 'template -d'
      r.should eq 0
      out.should eq template.gsub(/%{kind}/, 'KindNumber2').gsub(/%{priority}/, '0').gsub(/%{.*?}/, '').strip
    end
  end  
  
  describe "retry" do
    before do
      taco.init!
      taco.write! issues      
      open(TACORC_PATH, 'w') { |f| f.write("schema_attr_update :kind, validate: [ 'NotBogus1', 'NotBogus2' ]") }
    end
    
    after { FileUtils.rm_rf(TMP_PATH) }
    
    describe "new" do
      it "allows editor retry after failed validation in interactive mode" do
        r, out = ex 'new', :env => { 'EDITOR' => EDITOR_PATH, 'EDITOR_APPEND' => "\n\nthis is new issue sparta!", 'EDITOR_FIELD_KIND' => 'BOGUS' }
        r.should_not eq 0
        out.should include 'attribute kind: "BOGUS" is not a valid value'
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
        out.should include 'attribute kind: "BOGUS" is not a valid value'
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
        out.should include 'attribute kind: "BOGUS" is not a valid value'
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
        out.should include 'attribute kind: "BOGUS" is not a valid value'
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
  
  describe "list filters" do
    let(:issues) { [
      FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind1', :owner => 'owner1', :description => 'descr1'),
      FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner2', :description => 'descr2'),
      FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind3', :owner => 'owner3', :description => 'descr3'),      
    ] }
    
    before { taco.init! ; taco.write! issues }    
    after { FileUtils.rm_rf(TMP_PATH) }
  
    it "filters by attribute" do
      r, out = ex 'list kind:kind2'
      r.should eq 0
      out.should include 'summary2'      
    end

    it "filters by attribute case-insensitive" do
      r, out = ex 'list kind:Kind2'
      r.should eq 0
      out.should include 'summary2'      
    end
    
    it "filters by multiple attributes" do
      taco.write! FactoryGirl.build(:issue, :summary => 'summaryXYZ', :kind => 'kind2', :owner => 'owner3')
      
      r, out = ex 'list kind:kind2 owner:owner2'
      r.should eq 0
      out.should_not include 'summaryXYZ'
      out.should include 'summary2'
    end
      
    it "filters by priority" do
      taco.write! FactoryGirl.build(:issue, :summary => 'summaryXYZ', :kind => 'kind2', :owner => 'owner3', :priority => 5)
      
      r, out = ex 'list priority:5'
      r.should eq 0
      out.should include 'summaryXYZ'
    end
    
    it "filters by attribute with spaces"
    it "filters by attribute with wildcard"    
  end

  describe "html" do    
    it "generates html" do
      r, out = ex 'init'
      r.should eq 0

      taco.write! issues
   
      # NOTE 123456
      # FIXME: see the FIXME at ex()
      #
      r, out = ex 'html > /tmp/taco.spec.html'
      r.should eq 0

      out = open('/tmp/taco.spec.html') { |f| f.read }
      
      out.should include '<html>'
      out.should include '</html>'
      issues.each { |issue| out.should include issue.id }
    end
  end

  describe "taco_profile" do
    describe "sensible defaults" do
      it "has them"
    end
    
    describe "sorting" do
      after { FileUtils.rm_rf(TMP_PATH) }
      
      it "sorts with the given sort order" do
        # FIXME: stop copying and pasting this!!        
        i1, i2, i3, i4, i5, i6 = [
          FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner3', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind3', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind1', :owner => 'owner1', :priority => 3),      

          FactoryGirl.build(:issue, :summary => 'summary4', :kind => 'kind6', :owner => 'owner1', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary5', :kind => 'kind5', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary6', :kind => 'kind4', :owner => 'owner3', :priority => 3),      
        ]
      
        FileUtils.rm_rf(taco.home)
        taco.init!
        taco.write! [ i1, i2, i3, i4, i5, i6 ]
      
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("sort: priority,owner,kind") }        
        r, out = ex 'list'
        r.should eq 0
        [ i4, i1, i2, i5, i3, i6 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end
        
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("sort: kind,priority,owner") }                
        r, out = ex 'list'
        r.should eq 0
        [ i3, i1, i2, i6, i5, i4 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end        

        open(TACO_PROFILE_PATH, 'w') { |f| f.write("sort: priority,kind,owner") }                
        r, out = ex 'list'
        r.should eq 0
        [ i1, i4, i2, i5, i3, i6 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end                
      end
      
      it "ignores the taco_profile sort order if --sort is given" do
        # FIXME: stop copying and pasting this!!
        i1, i2, i3, i4, i5, i6 = [
          FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner3', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind3', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind1', :owner => 'owner1', :priority => 3),      

          FactoryGirl.build(:issue, :summary => 'summary4', :kind => 'kind6', :owner => 'owner1', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary5', :kind => 'kind5', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary6', :kind => 'kind4', :owner => 'owner3', :priority => 3),      
        ]
      
        FileUtils.rm_rf(taco.home)
        taco.init!
        taco.write! [ i1, i2, i3, i4, i5, i6 ]
      
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("sort: priority,owner,kind") }
        r, out = ex 'list --sort kind,priority,owner'
        r.should eq 0
        [ i3, i1, i2, i6, i5, i4 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end        
      end
    end

    describe "filtering" do
      after { FileUtils.rm_rf(TMP_PATH) }      
      
      it "filters with the given filters" do
        # FIXME: stop copying and pasting this!!        
        i1, i2, i3, i4, i5, i6 = [
          FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner3', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind3', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind1', :owner => 'owner1', :priority => 3),      

          FactoryGirl.build(:issue, :summary => 'summary4', :kind => 'kind6', :owner => 'owner1', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary5', :kind => 'kind5', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary6', :kind => 'kind4', :owner => 'owner3', :priority => 3),      
        ]
      
        FileUtils.rm_rf(taco.home)
        taco.init!
        taco.write! [ i1, i2, i3, i4, i5, i6 ]   
        
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("filters: owner:owner1\nsort:summary") }
        r, out = ex 'list'
        r.should eq 0
        [ i3, i4 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end             
      end
      
      it "ignores the taco_profile filters if filters are given on the command line" do
        # FIXME: stop copying and pasting this!!        
        i1, i2, i3, i4, i5, i6 = [
          FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner3', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind3', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind1', :owner => 'owner1', :priority => 3),      

          FactoryGirl.build(:issue, :summary => 'summary4', :kind => 'kind6', :owner => 'owner1', :priority => 1),
          FactoryGirl.build(:issue, :summary => 'summary5', :kind => 'kind5', :owner => 'owner2', :priority => 2),
          FactoryGirl.build(:issue, :summary => 'summary6', :kind => 'kind4', :owner => 'owner3', :priority => 3),      
        ]
      
        FileUtils.rm_rf(taco.home)
        taco.init!
        taco.write! [ i1, i2, i3, i4, i5, i6 ]   
        
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("filters: owner:owner1\nsort:summary") }
        r, out = ex 'list owner:owner3'
        r.should eq 0
        [ i1, i6 ].zip(out.lines).each do |issue, line|
          line.should include issue.summary
        end             
      end
    end

    describe "column list" do
      after { FileUtils.rm_rf(TMP_PATH) }      
   
      it "displays the given columns" do
        taco.init!
        taco.write! issues[0]
        
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("columns: short_id") }
        r, out = ex 'list'
        r.should eq 0
        out.should eq issues[0].id[0..7]
        
        open(TACO_PROFILE_PATH, 'w') { |f| f.write("columns: short_id,priority,summary") }
        r, out = ex 'list'
        r.should eq 0
        out.should eq "#{issues[0].id[0..7]} : #{issues[0].priority} : #{issues[0].summary}"
      end
    end
  end

  describe "comment" do
    it "adds comments to an existing issue"
  end
  
end