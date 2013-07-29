require 'issue'
require 'json'

def date(t)
  t.strftime "%Y/%m/%d %H:%M:%S"
end

describe Issue do
  let(:valid_attributes) { { :id => 'abc123', 
                             :created_at => Time.new(2007, 5, 23, 5, 8, 23, '-07:00'), 
                             :updated_at => Time.new(2007, 5, 23, 5, 8, 23, '-07:00'), 
                             :summary => 'a summary', 
                             :kind => 'Defect', 
                             :status => 'Open',
                             :owner => 'bobdole',
                             :priority => 3,
                             :description => "a description\nin two lines", } }
  let(:issue) { Issue.new valid_attributes }
  let(:template) { Issue::TEMPLATE }  

  describe "methods" do
    subject { issue }
  
    it { should respond_to :to_s }
    it { should respond_to :valid? }
    it { should respond_to :new? }
    
    it { should respond_to :summary }
    it { should respond_to :kind }
    it { should respond_to :status }
    it { should respond_to :owner }
    it { should respond_to :priority }

    it { should respond_to :created_at }
    it { should_not respond_to :created_at= }

    it { should respond_to :updated_at }
    it { should_not respond_to :updated_at= }

    it { should respond_to :description }
  
    it { should respond_to :id }
    it { should_not respond_to(:id=) }
  
    it { should respond_to :to_json }
    
    it { should respond_to :to_template }
    it { should respond_to :update_from_template! }
    it { should respond_to :summary= }
    it { should respond_to :kind= }
    it { should respond_to :status= }
    it { should respond_to :owner= }
    it { should respond_to :priority= }

    it { should respond_to :description= }
    
    it { should respond_to :changelog }
    
    it { should be_valid }
  end
  
  describe "class members" do
    specify { Issue.should respond_to :from_json }    
  end
  
  describe "new?" do
    specify { Issue.new.should be_new }
    specify { Issue.new(valid_attributes).should_not be_new }
  end
  
  describe "validation" do    
    specify { Issue.new(valid_attributes).should be_valid } # has to be or it's a huge PITA to to change an attr to invalid for testing
    specify { Issue.new(valid_attributes.merge({:summary => ''})).should_not be_valid }
    specify { Issue.new(valid_attributes.merge({:summary => ' '})).should_not be_valid }
    specify { Issue.new(valid_attributes.merge({:summary => "\n"})).should_not be_valid }

    specify { Issue.new(valid_attributes.merge({:description => "multi\nline\ntest1"})).should be_valid }
    specify { Issue.new(valid_attributes.merge({:description => "multi\n\nline\ntest2"})).should be_valid }
    specify { Issue.new(valid_attributes.merge({:description => "multi\n\nline\n\ntest3"})).should be_valid }
    specify { Issue.new(valid_attributes.merge({:description => "multi\n\n line\n\ntest4"})).should be_valid }

    describe "type checking" do
      specify { expect { Issue.new(valid_attributes.merge({:created_at => "abc123"})) }.to raise_error(TypeError) }
      specify { expect { Issue.new(valid_attributes.merge({:created_at => 123})) }.to raise_error(TypeError) }
      
      specify { expect { Issue.new(valid_attributes.merge({:summary => Time.now})) }.to raise_error(TypeError) }
      specify { expect { Issue.new(valid_attributes.merge({:summary => 123})) }.to raise_error(TypeError) }
      specify { expect { Issue.new(valid_attributes.merge({:summary => nil})) }.to raise_error(TypeError) }
      
      specify { expect { Issue.new(valid_attributes.merge({:priority => '1x'})) }.to raise_error(TypeError) }
    end
    
    # describe "set_allowed_values!" do
          #   after { Issue.set_allowed_values! }
          #   
          #   it "should allow only particular values for checked fields" do
          #     Issue.set_allowed_values! :kind => [ 'Defect', 'Feature Request' ], :priority => [ 1, 2, 3, 4 ]
          #   
          #     issue.kind = 'Defect'
          #     issue.should be_valid
          # 
          #     issue.kind = 'Feature Request'
          #     issue.should be_valid
          # 
          #     issue.kind = 'Carmen Miranda'
          #     issue.should_not be_valid
          #   
          #     issue.kind = 'Defect'
          #     issue.should be_valid
          #   
          #     issue.priority = 9
          #     issue.should_not be_valid
          #   
          #     issue.priority = 3
          #     issue.should be_valid
          #   
          #     Issue.set_allowed_values!
          #     issue.kind = 'Carmen Miranda'
          #     issue.should be_valid
          #   end
          # 
          #   it "should convert Strings to Fixnums as appropriate in set_allowed_values!" do
          #     Issue.set_allowed_values! :priority => %w|1 2 3|
          #   
          #     issue.priority = 2
          #     issue.should be_valid
          #   end
          # end
          # 
          # it "should raise ArgumentError when setting allowed values for unrecognized attributes" do
          #   expect {
          #     Issue.set_allowed_values! :foo => [ 'bar', 'baz' ]
          #   }.to raise_error(ArgumentError)
          # end
          
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
              the_alleged_json.should_not be_nil
              expect { JSON.parse(the_alleged_json) }.to_not raise_error(JSON::ParserError)
            end
              
            it "should serialize from json" do
              the_json = issue.to_json
              reissue = Issue.from_json(the_json)
      
              reissue.should be_valid
              Issue.schema_attributes.keys.each do |attr|
                issue.send(attr).should eq reissue.send(attr)
              end
            end
          end
          
          describe "template" do
            it "should serialize from a template" do
              text = template % valid_attributes
            
              issue = Issue.from_template(text)
              issue.should be_valid
            
              valid_attributes.reject { |attr, value| [ :id, :created_at, :updated_at ].include? attr }.each { |attr, value| issue.send(attr).should eq value }      
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
      
            it "should raise ArgumentError when attempting to set updated_at" do
              text = "updated_at : 123abc\n" + (template % valid_attributes)        
              expect { issue = Issue.from_template(text) }.to raise_error(ArgumentError)
            end
            
            it "should update from a template" do
              reissue = Issue.new(valid_attributes.merge({:summary => 'different summary', :description => 'different descr'}))
              
              old_id = issue.id
              old_created_at = issue.created_at
              old_kind = issue.kind

              issue.update_from_template! reissue.to_template
              
              issue.id.should eq old_id
              issue.created_at.should eq old_created_at
              issue.summary.should eq 'different summary'
              issue.description.should eq 'different descr'
              issue.kind.should eq old_kind        
              issue.updated_at.should_not eq issue.created_at
            end
            
            it "should perform a more complicated update" do
              template =<<-EOT.strip
Summary     : a summary
Kind        : a kind
Status      : a status
Priority    : 2
Owner       : an owner
# Everything between the --- lines is Issue Description
---
descr1
descr2
---
EOT
              issue = Issue.from_template(template)
              issue.description.should eq "descr1\ndescr2"
            
              issue.update_from_template!(template.gsub(/descr2\n---/m, "descr2\ndescr3"))
              issue.description.should eq "descr1\ndescr2\ndescr3"
            end
          end
            
          it "raises on non-attribute lines that aren't part of the description" do
            template =<<-EOT.strip
something
Summary     : a summary
weird
Kind        : a kind
happening here
Status      : a status
Priority    : 3
Owner       : an owner
# Everything between the --- lines is Issue Description
---
this describes
 the issue
   quite well
---
EOT
            expect {
              Issue.from_template template
            }.to raise_error(ArgumentError)
          end
          
          it "is not disturbed by key:value pairs that appear in the description" do
            template =<<-EOT.strip
Summary     : a summary
Kind        : a kind
Status      : a status
Priority    : 3
Owner       : an owner
# Everything between the --- lines is Issue Description
---
this describes
 the issue
 as key: value
key2:value2
key3 :value3
key4: value4
key5 : value5
keyx:
:valuex
   quite well
---
EOT
            Issue.from_template(template).description.count(':').should eq 7
          end
          
          it "strips trailing whitespace from description" do
            template =<<-EOT
Summary     : a summary
Kind        : a kind
Status      : a status
Priority    : 3
Owner       : an owner
# Everything between the --- lines is Issue Description
---
l1
l2

---
EOT
            Issue.from_template(template).description.should_not end_with("\n")
          end
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

    it "sets updated_at if not given" do
      Issue.new.updated_at.should be_within(2).of(Time.now)
    end
    
    it "does not overwrite given created_at" do
      Issue.new(valid_attributes).created_at.should eq valid_attributes[:created_at]
    end

    it "does not overwrite given updated_at" do
      Issue.new(valid_attributes).updated_at.should eq valid_attributes[:updated_at]
    end
    
    it "strips Strings" do
      attrs = valid_attributes.dup
      attrs[:summary] += "\n\n\n"
      
      Issue.new(attrs).summary.should eq valid_attributes[:summary]
    end
        
    it "changes strings to Time objects as appropriate" do
      attrs = valid_attributes.merge(:created_at => valid_attributes[:created_at].to_s)
      
      issue = Issue.new(attrs)
      issue.should be_valid      
      issue.created_at.should eq valid_attributes[:created_at]
    end  
    
    it "changes strings to Fixnums as appropriate" do  
      attrs = valid_attributes.dup
      attrs[:priority] = attrs[:priority].to_s
      
      issue = Issue.new(attrs)
      issue.should be_valid 
    end
    
    it "initializes the changelog from arguments" do
      change = Change.new(:created_at => Time.new(2007, 5, 23, 5, 23, 5), :attribute => :summary, :new_value => "whatever")
      issue = Issue.new(valid_attributes, [ change ] )
      issue.changelog.size.should eq 1
      issue.changelog.should eq [ change ]
    end
  end
  
  describe "attributes" do
    describe "read" do
      specify { issue.summary.should eq valid_attributes[:summary] }
      specify { issue.kind.should eq valid_attributes[:kind] }
      specify { issue.priority.should eq valid_attributes[:priority] }
      specify { issue.created_at.should eq valid_attributes[:created_at] }
      specify { issue.updated_at.should eq valid_attributes[:updated_at] }
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
    end
    
    describe "updated_at" do
      it "automatically sets updated_at when creating a new issue" do
        Issue.new.created_at.should_not be_nil
      end
      
      it "automatically sets updated_at when setting an attribute" do
        old_updated_at = issue.updated_at
        old_updated_at.should eq valid_attributes[:updated_at]
        issue.summary = "foo bar"
        issue.updated_at.should_not eq old_updated_at
        issue.updated_at.should be_within(2).of(Time.now)
      end        
      
      it "does not have sub-second accuracy" do
        old_updated_at = issue.updated_at
        issue.summary = "foo bar"
        issue.updated_at.subsec.should eq 0
      end      
      
    end
    
    describe "assignment" do
      describe "write protection" do
        specify { expect { issue.created_at = "abc123" }.to raise_error(NoMethodError) }        
        specify { expect { issue.id = "abc123" }.to raise_error(NoMethodError) }        
      end
      
      describe "type checking" do
        specify { expect { issue.summary = nil }.to raise_error(TypeError) }        
        specify { expect { issue.summary = Time.now }.to raise_error(TypeError) }        
        specify { expect { issue.summary = 123 }.to raise_error(TypeError) }
        specify { expect { issue.priority = '123x' }.to raise_error(TypeError) }
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
Created At  : #{date(issue.created_at)}
Updated At  : #{date(issue.updated_at)}

Summary     : #{issue.summary}
Kind        : #{issue.kind}
Status      : #{issue.status}
Priority    : #{issue.priority}
Owner       : #{issue.owner}

---
#{issue.description}
EOT
      issue.to_s.should eq text
    end
  end
  
  describe "to_template" do
    it "should render a 'new issue' template when the issue is new" do
      new_issue_template = <<-EOT.strip
# New Issue
#
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
      Issue.new.to_template.should eq new_issue_template
    end
    
    it "should render an 'edit issue' template when the issue is not new" do
      edit_issue_template = <<-EOT.strip
# Edit Issue
#
# ID          : #{issue.id}
# Created At  : #{issue.created_at}
# Updated At  : #{issue.updated_at}
#

# Lines beginning with # will be ignored.
Summary     : #{issue.summary}
Kind        : #{issue.kind}
Status      : #{issue.status}
Priority    : #{issue.priority}
Owner       : #{issue.owner}

# Everything between the --- lines is Issue Description
---
#{issue.description}
---

# ChangeLog
#
#{issue.changelog.map { |c| %Q|# #{c.to_s.strip.gsub(/\n/, "\n# ")}| }.join("\n")}      
EOT
      # FIXME: copying the code from taco.rb to the spec (as with the changelog line above) is pretty lame.
      #
      issue.to_template.should eq edit_issue_template
    end
    
    it "should comment multi-line descriptions in the 'edit issue' template" do
      issue.description = "line1\nline2\nline3"
      issue.to_template.should include "# line2\n# line3"
    end
  end
  
  describe "comparable" do
    it "implements comparable such that issues are sortable by ascending created_at,id" do
      issue.should eq Issue.from_json(issue.to_json)
      attrs = valid_attributes.dup
      attrs.delete :id
      
      issue.should_not eq Issue.new(attrs) # because they have different ids
      
      later   = attrs[:created_at] + 100
      earlier = attrs[:created_at] - 100
      
      issue.should be < Issue.new(attrs.merge({:created_at => later}))
      issue.should be > Issue.new(attrs.merge({:created_at => earlier}))
      
      issues = (0...100).map { Issue.new(attrs) }
      issues[0].id.should_not eq issues[1].id
      issues.sort.should_not eq issues.shuffle
      issues.sort.should eq issues.sort_by(&:id)
    end
    
    it "implements equality" do
      reissue = Issue.from_json(issue.to_json)      
      issue.should eq reissue

      reissue.summary = "this makes a change"
      issue.should_not eq reissue
    end    
  end
  
  describe "changelog" do
    it "is empty on an Issue with only unsettable attributes" do
      issue = Issue.new
      issue.changelog.should eq []      
    end
    
    it "initializes the changelog from Issue::initialize" do
      issue.changelog.size.should eq Issue.schema_attributes.select { |attr, data| data[:settable] }.size
      Issue.schema_attributes.select { |attr, data| data[:settable] }.each do |attr, data|
        issue.changelog.any? { |change| change.attribute == attr }.should be_true
      end
    end
    
    it "records attribute changes" do
      old_issue_changelog_size = issue.changelog.size
      old_summary = issue.summary
      issue.summary = "summary is changed"
      issue.changelog.size.should eq 1 + old_issue_changelog_size
      
      issue.changelog[-1].created_at.should be_within(2).of(Time.now)
      issue.changelog[-1].attribute.should eq :summary
      issue.changelog[-1].old_value.should eq old_summary
      issue.changelog[-1].new_value.should eq "summary is changed"
    end

    it "does not record changes to updated_at, created_at, or id" do
      issue.changelog.any? { |change| change.attribute == :id || change.attribute == :created_at || change.attribute == :updated_at }.should be_false
      issue.summary = "this should update updated_at"
      issue.changelog.any? { |change| change.attribute == :id || change.attribute == :created_at || change.attribute == :updated_at }.should be_false
    end

    it "has a created_at timestamp for each entry" do
      issue.changelog.any? { |change| change.created_at.nil? }.should be_false
    end
    
    it "is not relevant for issue comparisons" do
      reissue = Issue.new(valid_attributes)
      issue.should eq reissue
      
      reissue.summary = "this makes a change"      
      issue.should_not eq reissue
      reissue.changelog.size.should be > issue.changelog.size      
      
      reissue.summary = issue.summary      
      reissue.changelog.size.should be > issue.changelog.size      

      # the two issues are not "eq" because the timestamps differ
      #
      Issue.schema_attributes.select { |attr, data| data[:settable] }.each do |attr, data|
        issue.send(attr).should eq reissue.send(attr)
      end
    end      
    
    it "shows the changelog in to_s (optionally)" do
      text = <<-EOT.strip
ID          : #{issue.id}
Created At  : #{date(issue.created_at)}
Updated At  : #{date(issue.updated_at)}

Summary     : #{issue.summary}
Kind        : #{issue.kind}
Status      : #{issue.status}
Priority    : #{issue.priority}
Owner       : #{issue.owner}

---
#{issue.description}
---

#{issue.changelog.map { |c| %Q|# #{c.to_s.strip.gsub(/\n/, "\n# ")}| }.join("\n")}      
EOT
      # FIXME: copying the code from taco.rb to the spec (as with the changelog line above) is pretty lame.
      #
  
      issue.to_s(:changelog => true).should eq text
    end
        
    describe "serialization" do
      it "gets jsonified by Issue.to_json" do
        old_summary = issue.summary
        issue.summary = "a new summary for a new era"
        the_alleged_json = issue.to_json
        the_alleged_json.should_not be_nil
        the_alleged_json.should include old_summary
        expect { JSON.parse(the_alleged_json) }.to_not raise_error(JSON::ParserError)         
      end      
      
      it "gets rubified by Issue.from_json" do
        old_summary = issue.summary
        issue.summary = "a new summary for a new era"
        changelog_size = issue.changelog.size
        the_alleged_json = issue.to_json
        
        reissue = Issue.from_json(the_alleged_json)
        reissue.changelog.size.should eq changelog_size
        reissue.changelog[-1].attribute.should eq :summary
        reissue.changelog[-1].old_value.should eq old_summary
        reissue.changelog[-1].new_value.should eq "a new summary for a new era"
      end        
    end
  end
  
  describe "backwards compatibility" do
    it "does not care if the JSON is missing fields" do
      issue.priority = 5
      the_json = issue.to_json
      the_hash = JSON.parse(the_json)
      the_hash['issue'].delete('priority')
      the_json = JSON.pretty_generate(the_hash)
      
      reissue = Issue.from_json(the_json)
      reissue.id.should eq issue.id
      reissue.priority.should eq 0
      
      issue.should be_valid
      reissue.should be_valid
      
      reissue.to_template.should include reissue.id
    end
  end
end