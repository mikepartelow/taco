require 'taco'
require 'json'

describe Issue do
  let(:valid_attributes) { { :summary => 'a summary', :kind => 'Defect', :created_at => Time.new(2007, 5, 23, 5, 8, 23, '-07:00'), 
                             :description => "a description\nin two lines", } }
  let(:issue) { Issue.new valid_attributes }
  let(:template) { <<-EOT
# Lines beginning with # will be ignored.
Summary   : %{summary}
Kind      : %{kind}
# Everything past this line is Issue Description
%{description}
EOT
  }  

  describe "methods" do
    subject { issue }
  
    it { should respond_to :to_s }
    it { should respond_to :valid? }
    
    it { should respond_to :summary }
    it { should respond_to :kind }
    it { should respond_to :created_at }
    it { should_not respond_to :created_at= }

    it { should respond_to :description }
  
    it { should respond_to :id }
    it { should_not respond_to(:id=) }
  
    it { should respond_to :to_json }
  
    it { should respond_to :summary= }
    it { should respond_to :kind= }
    it { should respond_to :description= }
    
    it { should be_valid }
  end
  
  describe "class members" do
    specify { Issue.should respond_to :from_json }    
  end
  
  describe "validation" do    
    specify { Issue.new.should_not be_valid }
    specify { Issue.new(valid_attributes.merge({:summary => ''})).should_not be_valid }
    specify { Issue.new(valid_attributes.merge({:summary => ' '})).should_not be_valid }
    specify { Issue.new(valid_attributes.merge({:summary => "\n"})).should_not be_valid }

    specify { Issue.new(valid_attributes.merge({:description => "multi\nline\ntest1"})).should be_valid }
    specify { Issue.new(valid_attributes.merge({:description => "multi\n\nline\ntest2"})).should be_valid }
    specify { Issue.new(valid_attributes.merge({:description => "multi\n\nline\n\ntest3"})).should be_valid }
    specify { Issue.new(valid_attributes.merge({:description => "multi\n\n line\n\ntest4"})).should be_valid }

    describe "type checking" do
      specify { expect { Issue.new(valid_attributes.merge({:created_at => "abc123"})) }.to raise_error(ArgumentError) }
      specify { expect { Issue.new(valid_attributes.merge({:created_at => 123})) }.to raise_error(ArgumentError) }
      specify { expect { Issue.new(valid_attributes.merge({:created_at => nil})) }.to raise_error(ArgumentError) }
      
      specify { expect { Issue.new(valid_attributes.merge({:summary => Time.now})) }.to raise_error(ArgumentError) }
      specify { expect { Issue.new(valid_attributes.merge({:summary => 123})) }.to raise_error(ArgumentError) }
      specify { expect { Issue.new(valid_attributes.merge({:summary => nil})) }.to raise_error(ArgumentError) }
    end

    it "should allow only particular values for checked fields" do
      Issue.set_allowed_values :kind => [ 'Defect', 'Feature Request' ]
      
      issue.kind = 'Defect'
      issue.should be_valid

      issue.kind = 'Feature Request'
      issue.should be_valid
      
      issue.kind = 'Carmen Miranda'
      issue.should_not be_valid
    end
    
    it "should raise ArgumentError when setting allowed values for unrecognized attributes" do
      expect {
        Issue.set_allowed_values :foo => [ 'bar', 'baz' ]
      }.to raise_error(ArgumentError)
    end
    
    it "should not serialize while valid? returns false" do
      expect {
        Issue.new(valid_attributes.merge({:summary => "\n"})).to_json
      }.to raise_error(Issue::Invalid)
    end
    
    it "should raise Invalid when instructed" do
      expect {
        Issue.new(valid_attributes.merge({:summary => "\n"})).valid?(:raise => true)
      }.to raise_error(Issue::Invalid)
    end
  end
  
  describe "serialization" do
    describe "json" do
      it "should serialize to json" do
        the_alleged_json = issue.to_json
        expect { JSON.parse(the_alleged_json) }.to_not raise_error(JSON::ParserError)
      end
        
      it "should serialize from json" do
        the_json = issue.to_json
        reissue = Issue.from_json(the_json)

        reissue.should be_valid
        Issue::SCHEMA_ATTRIBUTES.keys.each do |attr|
          issue.send(attr).should eq reissue.send(attr)
        end
      end
    end
    
    describe "template" do
      it "should serialize from a template" do
        text = template % valid_attributes
      
        issue = Issue.from_template(text)
        issue.should be_valid
      
        valid_attributes.reject { |attr, value| attr == :created_at }.each { |attr, value| issue.send(attr).should eq value }      
      end
    
      it "should raise ArgumentError on unrecognized key/value pairs" do
        text = "WingleDingle : Forble Zorp\n" + (template % valid_attributes)
        expect { issue = Issue.from_template(text) }.to raise_error(ArgumentError)
      end
      
      it "should raise ArgumentError when attempting to set ID" do
        text = "ID : 123abc\n" + (template % valid_attributes)        
        expect { issue = Issue.from_template(text) }.to raise_error(ArgumentError)
      end
      
      it "should raise ArgumentError when attempting to set created_at" do
        text = "created_at : 123abc\n" + (template % valid_attributes)        
        expect { issue = Issue.from_template(text) }.to raise_error(ArgumentError)
      end
    end
      
    it "should do something sensible for non-key/value lines that aren't part of the description"
  end
  
  describe "initialization" do
    it "raises on unknown attributes" do
      expect {
        Issue.new valid_attributes.merge({:invalid => 'unknown attribute'})
      }.to raise_error(ArgumentError)
    end
    
    it "converts string keys to symbols" do
      attrs = valid_attributes.dup
      attrs.delete :summary
      attrs['summary'] = valid_attributes[:summary]
      
      Issue.new(attrs).summary.should eq valid_attributes[:summary]
    end
    
    it "sets created_at if not given" do
      Issue.new.created_at.should be_within(2).of(Time.now)
    end
    
    it "does not overwrite given created_at" do
      Issue.new(valid_attributes).created_at.should eq valid_attributes[:created_at]
    end
    
    it "strips Strings" do
      attrs = valid_attributes.dup
      attrs[:summary] += "\n\n\n"
      
      Issue.new(attrs).summary.should eq valid_attributes[:summary]
    end
        
    it "changes strings to Time objects as appropriate" do
      attrs = valid_attributes.dup
      attrs[:created_at] = attrs[:created_at].to_s
      
      issue = Issue.new(attrs)
      issue.should be_valid      
      Issue::SCHEMA_ATTRIBUTES.each do |attr, cls|
        next if attr == :id
        issue.send(attr).class.should eq valid_attributes[attr].class
        issue.send(attr).should eq valid_attributes[attr]
      end
    end    
  end
  
  describe "attributes" do
    describe "read" do
      specify { issue.summary.should eq valid_attributes[:summary] }
      specify { issue.kind.should eq valid_attributes[:kind] }
      specify { issue.created_at.should eq valid_attributes[:created_at] }
      specify { issue.description.should eq valid_attributes[:description] }
    end
    
    describe "id" do
      it "is unique" do
        Issue.new.id.should_not eq Issue.new.id
      end      
                        
      it "is assignable by initialization" do
        Issue.new({ :id => '123' }).id.should eq '123'
      end      
    end
    
    describe "created_at" do
      it "does not have sub-second accuracy" do
        t1 = valid_attributes[:created_at] + 0.5
        
        issue0 = Issue.new valid_attributes
        issue1 = Issue.new valid_attributes.merge({ :created_at => t1 })
        
        issue0.created_at.should eq issue1.created_at
      end
      
      it "should not allow assignment" do
        expect {
          issue.created_at = Time.now
        }.to raise_error(NoMethodError)
      end
    end
    
    describe "assignment" do
      describe "write protection" do
        specify { expect { issue.created_at = "abc123" }.to raise_error(NoMethodError) }        
        specify { expect { issue.id = "abc123" }.to raise_error(NoMethodError) }        
      end
      
      describe "type checking" do
        specify { expect { issue.summary = nil }.to raise_error(ArgumentError) }        
        specify { expect { issue.summary = Time.now }.to raise_error(ArgumentError) }        
        specify { expect { issue.summary = 123 }.to raise_error(ArgumentError) }
      end
      
      describe "cleanup" do
        it "strips strings" do
          issue.summary = "   one two three   \n   "
          issue.summary.should eq "one two three"          
        end
      end      
    end
  end
  
  describe "to_s" do
    it "should return a formatted string" do
      text = <<-EOT.strip
ID          : #{issue.id}
Created At  : #{issue.created_at}
Summary     : #{issue.summary}
Kind        : #{issue.kind}
---
#{issue.description}      
EOT
      issue.to_s.should eq text
    end
  end
  
  describe "comparable" do
    it "implements comparable such that issues are sortable by ascending created_at,id" do
      issue.should eq issue.dup
      
      issue.should_not eq Issue.new(valid_attributes) # because they have different ids
      
      later   = valid_attributes[:created_at] + 100
      earlier = valid_attributes[:created_at] - 100
      
      issue.should be < Issue.new(valid_attributes.merge({:created_at => later}))
      issue.should be > Issue.new(valid_attributes.merge({:created_at => earlier}))
      
      issues = (0...100).map { Issue.new(valid_attributes) }
      issues[0].id.should_not eq issues[1].id
      issues.sort.should_not eq issues.shuffle
      issues.sort.should eq issues.sort_by(&:id)
    end
  end
end