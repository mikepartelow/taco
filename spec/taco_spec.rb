require 'taco'
require 'fileutils'

describe Taco do
  let(:root) { 'spec/tmp' }
  let(:taco) { Taco.new root }

  subject { taco }
  
  it { should respond_to :home }

  describe "initialization" do
    it "should find a home" do
      taco.home.should start_with root
    end    
  end
  
  describe "interface" do
    before { FileUtils.rm_rf root }
    after { FileUtils.rm_rf root }
    
    let(:issue) { FactoryGirl.build :issue }
    let(:issues) { FactoryGirl.build_list :issue, 10 }
    
    describe "init!" do
      it "creates the home directory and config file" do
        taco.init!
        File.exists?(taco.home).should be_true
      end
    
      it "raises an exception if initializing an existing directory" do
        taco.init!
        expect {
          taco.init!        
        }.to raise_error(IOError)
      end
    
      it "returns a string with the initialized home dir" do      
        taco.init!.should include(File.join(root, Taco::HOME_DIR))
      end
    end  
    
    describe "write!" do
      before { taco.init! }
      
      it "writes the issue to a file named by the issue id" do
        taco.write! issue
        File.exists?(File.join(taco.home, issue.id)).should be_true
      end
      
      it "accepts an array of issues to write" do
        taco.write! issues
        issues.each { |i| File.exists?(File.join(taco.home, i.id)).should be_true }
      end

      it "should overwite an issue with the same id (aka modify an issue)" do
        taco.write! issue
        
        issue.summary = "and no-one can talk to a horse, of course"
        taco.write! issue
        
        reissue = taco.read issue.id
        reissue.summary.should eq "and no-one can talk to a horse, of course"
      end
      
      it "raises on invalid issue" do
        invalid_issue = Issue.new
        invalid_issue.should_not be_valid
        
        expect {
          taco.write! invalid_issue
        }.to raise_error(Issue::Invalid)
      end      
    end
    
    describe "read" do
      before { taco.init! }
      
      it "reads an issue" do
        taco.write! issue
        reissue = taco.read issue.id
        reissue.should eq issue
      end
      
      it "raises NotFound if the issue cannot be found" do
        expect {
          taco.read "123abc"
        }.to raise_error(Taco::NotFound)
      end

      it "accepts shortened id" do
        taco.write! issue
        reissue = taco.read issue.id[0...8]
        reissue.should eq issue
      end
      
      it "raises Issue::Invalid if the file is unparseable" do
        id = '123abc'
        open(File.join(taco.home, id), 'w') { |f| f.write("garbage") }
        
        expect {
          taco.read '123abc'
        }.to raise_error(Issue::Invalid)        
      end
      
      it "raises Ambiguous if the shortened id is ambiguous" do
        expect {
          taco.write! issues
          taco.read '1' # it is possible for this spec to fail if none or only one of the issues has 1 in the id. unlikely.
        }.to raise_error(Taco::Ambiguous)
      end
      
      it "raises Issue::Invalid if the issue id does not match the filename" do
        the_json = issue.to_json
        open(File.join(taco.home, '123abc'), 'w') { |f| f.write(the_json) }
        
        expect {
          taco.read '123abc'
        }.to raise_error(Issue::Invalid)
      end      
    end
  
    describe "list" do    
      before { taco.init! }    
    
      it "returns an empty array when there are no issues" do
        taco.list.should eq []
      end
    
      it "lists a single issue" do
        taco.write! issue
        taco.list.should eq [ issue ]
      end
      
      it "lists multiple issues" do
        taco.write! issues
        taco.list.should eq issues.sort
      end

      it "lists issues in order of ascending created_at" do
        issues = (0...100).map do |n|
          Issue.new FactoryGirl.attributes_for(:issue, :created_at => Time.now - n * 2)
        end.shuffle
                           
        taco.write! issues
        taco.list.should eq issues.sort_by(&:created_at)
      end
      
      it "lists issues in order of ascending id when created_at is equal" do
        the_time = Time.now
        issues = (0...100).map do |n|
          Issue.new FactoryGirl.attributes_for(:issue, :created_at => the_time)
        end

        taco.write! issues
        taco.list.should eq issues.sort_by(&:id)
      end
            
      it "lists shortened ids" do
        expected_list = issues.map { |i| [ i, i.id[0...8] ] }.sort_by { |a| a[0] }
        
        taco.write! issues        
        taco.list(:short_ids => true).should eq expected_list
      end
      
      it "uses slightly longer short_ids when there is id overlap" do
        i0 = Issue.new FactoryGirl.attributes_for(:issue).merge({:id => 'abc123xyz'})
        i1 = Issue.new FactoryGirl.attributes_for(:issue).merge({:id => 'abc123xyt'})        
        taco.write! [ i0, i1 ]
        
        taco.list(:short_ids => true).sort.should eq [ [ i0, 'abc123xyz' ], [ i1, 'abc123xyt' ] ].sort
      end
      
      it "raises Issue::Invalid on files that are in the issue path that aren't issues" do
        open(File.join(taco.home, '123abc'), 'w') { |f| f.write("a horse is a horse of course of course") }
        
        expect {
          taco.list
        }.to raise_error(Issue::Invalid)                
      end

      it "raises Issue::Invalid if the issue id does not match the filename" do
        the_json = issue.to_json
        open(File.join(taco.home, '123abc'), 'w') { |f| f.write(the_json) }
        
        expect {
          taco.list
        }.to raise_error(Issue::Invalid)        
      end  
      
      describe "filters" do
        let(:issues) { [
          FactoryGirl.build(:issue, :summary => 'summary1', :kind => 'kind1', :owner => 'owner1', :description => 'descr1'),
          FactoryGirl.build(:issue, :summary => 'summary2', :kind => 'kind2', :owner => 'owner2', :description => 'descr2'),
          FactoryGirl.build(:issue, :summary => 'summary3', :kind => 'kind3', :owner => 'owner3', :description => 'descr3'),      
        ] }

        before { taco.write! issues }
        
        it "filters Issues" do
          taco.list(:filters => [ 'kind:kind2' ]).should eq [ issues[1] ]
        end
      end      
    end
  end
end