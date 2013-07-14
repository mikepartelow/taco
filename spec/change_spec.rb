require 'taco'

describe Issue::Change do
  let(:valid_change) { Issue::Change.new :attribute => 'foo', :old_value => 'bar', :new_value => 'baz' }
  
  it { should respond_to :created_at }
  it { should respond_to :attribute }
  it { should respond_to :old_value }
  it { should respond_to :new_value }  
  
  it { should respond_to :valid? }
  it { should respond_to :to_json }
  it { should respond_to :to_s }
  
  describe "initialization" do
    it "initializes created_at" do
      Issue::Change.new.created_at.should be_within(2).of(Time.now)
    end
    
    it "sets attributes from arguments" do
      Issue::Change.new(:attribute => :foo).attribute.should eq :foo
    end
    
    it "sets created_at from arguments" do
      t = Time.now - 100
      Issue::Change.new(:created_at => t).created_at.should eq t
    end
    
    it "raises ArgumentError on unknown arguments" do
      expect {
        Issue::Change.new(:foobar => :barbaz)
      }.to raise_error(ArgumentError)
    end
  end
  
  describe "valid?" do
    specify { Issue::Change.new.should_not be_valid }
    specify { valid_change.should be_valid }
  end
  
  describe "to_json" do
    it "raises Issue::Change::Invalid when calling to_json on an invalid Change" do
      expect {
        Issue::Change.new.to_json
      }.to raise_error(Issue::Change::Invalid)
    end
    
    it "should serialize to json" do      
      the_alleged_json = valid_change.to_json
      the_alleged_json.should_not be_nil
      expect { JSON.parse(the_alleged_json) }.to_not raise_error(JSON::ParserError)
    end    
  end
  
  describe "to_s" do
    it "formats a simplified string" do
      expected = "#{valid_change.attribute} : #{valid_change.old_value} => #{valid_change.new_value}"
      valid_change.to_s(:simple => true).should eq expected
    end
  end
end
