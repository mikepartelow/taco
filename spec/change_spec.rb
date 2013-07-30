require 'taco/change'

def date(t)
  t.strftime "%Y/%m/%d %H:%M:%S"
end


describe Change do
  let(:valid_change) { Change.new :attribute => :foo, :old_value => 'bar', :new_value => 'baz' }
  
  it { should respond_to :created_at }
  it { should respond_to :attribute }
  it { should respond_to :old_value }
  it { should respond_to :new_value }  
  
  it { should respond_to :valid? }
  it { should respond_to :to_json }
  it { should respond_to :to_s }
  
  specify { Change.should respond_to :from_json }
  
  describe "initialization" do
    it "initializes created_at" do
      Change.new.created_at.should be_within(2).of(Time.now)
    end
    
    it "sets attributes from arguments" do
      Change.new(:attribute => :foo).attribute.should eq :foo
    end
    
    it "sets created_at from arguments" do
      t = Time.new 2007, 5, 23, 5, 23, 5
      Change.new(:created_at => t).created_at.should eq t
    end
    
    it "raises ArgumentError on unknown arguments" do
      expect {
        Change.new(:foobar => :barbaz)
      }.to raise_error(ArgumentError)
    end
    
    it "changes types as needed" do
      change = Change.new :created_at => Time.new.to_s, :attribute => 'summary', :new_value => 'bar'
      change.created_at.class.should eq Time
      change.attribute.class.should eq Symbol
      change.new_value.class.should eq String
    end
  end
  
  describe "created_at" do
    it "does not have subsec accuracy" do
      bad_time = Time.new 2007, 5, 23, 5, 5, 5, 5
      
      Change.new(:created_at => bad_time).created_at.subsec.should eq 0      
      
      1.upto(100) { Change.new.created_at.subsec.should eq 0 }
    end
  end
  
  describe "valid?" do
    specify { Change.new.should_not be_valid }
    specify { valid_change.should be_valid }
  end
  
  describe "to_json" do
    it "raises Change::Invalid when calling to_json on an invalid Change" do
      expect {
        Change.new.to_json
      }.to raise_error(Change::Invalid)
    end
    
    it "should serialize to json" do      
      the_alleged_json = valid_change.to_json
      the_alleged_json.should_not be_nil
      expect { JSON.parse(the_alleged_json) }.to_not raise_error(JSON::ParserError)
    end  
    
    it "should serialize from json" do
      hopeful_change = Change::from_json(valid_change.to_json)
      hopeful_change.created_at.should eq valid_change.created_at
      hopeful_change.attribute.should eq valid_change.attribute
      hopeful_change.old_value.should eq valid_change.old_value
      hopeful_change.new_value.should eq valid_change.new_value 
    end      
    
    it "raises Change::Invalid when parsing invalid json" do
      expect {
        Change.from_json("foo bar baz")
      }.to raise_error(Change::Invalid)
    end
  end
  
  describe "to_s" do
    it "formats a simplified string" do
      expected = "#{valid_change.attribute} : #{valid_change.old_value} => #{valid_change.new_value}"
      valid_change.to_s(:simple => true).should eq expected
    end
    
    it "formats a string" do
      fields = [ date(valid_change.created_at), valid_change.attribute, valid_change.old_value, valid_change.new_value ]
      expected = "%10s : %12s : %s => %s" % fields
      
      valid_change.to_s.should eq expected
    end    
  end
end