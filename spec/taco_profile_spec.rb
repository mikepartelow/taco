require 'taco/taco_profile'
require 'taco/issue'

describe TacoProfile do
  let(:taco_profile_text) { <<-EOT.strip
# comment, followed by a blank line (don't panic)

sort: priority,status,owner
filters: kind:open owner:mike
columns: short_id,priority,owner,status,summary
EOT
  }
  let(:taco_profile) { TacoProfile.new(taco_profile_text) }

  it "supports multiple repos" # for this, perhaps we need the concept of a "name" in a repo, otherwise we have to use /path/to/repo which is kinda lame

  describe "parsing" do
    it "parses the text" do
      taco_profile.sort_order.should eq [ :priority, :status, :owner ]
      taco_profile.filters.should eq [ 'kind:open', 'owner:mike' ]
      taco_profile.columns.should eq [ :short_id, :priority, :owner, :status, :summary ]
    end
    
    it "doesn't mind an empty file" do
      TacoProfile.new("")
      TacoProfile.new("\n")
      TacoProfile.new("  ")
      TacoProfile.new("  \n#")
    end
    
    it "raises on duplicate lines" do
      expect {
        TacoProfile.new("sort: priority,status\nsort: status,priority")
      }.to raise_error(ArgumentError)      
            
      expect {
        TacoProfile.new("filters: priority:1 status:open\nfilters: status:open priority:1")
      }.to raise_error(ArgumentError)      
      
      expect {
        TacoProfile.new("columns: priority,status\columns: status,priority")
      }.to raise_error(ArgumentError)            
    end
    
    it "raises on unknown sort attribute" do
      expect {
        TacoProfile.new('sort: priority,hamburger,status')
      }.to raise_error(ArgumentError)
    end
    
    it "raises on unknown filter attribute" do
      expect {
        TacoProfile.new('filters: kind:open hamburger:hamburger')
      }.to raise_error(ArgumentError)
    end
    
    it "raises on unknown column attribute" do
      expect {
        TacoProfile.new('columns: short_id,hamburger,owner')
      }.to raise_error(ArgumentError)
    end
  end  
  
  describe "defaults" do
    it "sets defaults when given no input" do
      p = TacoProfile.new(nil)
      p.columns.should eq [ :short_id, :priority, :summary ]
      p.sort_order.should eq [ :created_at, :id ]
      p.filters.should eq []
    end
    
    it "sets deftauls when given partial input" do
      p = TacoProfile.new("sort: priority,status")
      p.columns.should eq [ :short_id, :priority, :summary ]
      p.sort_order.should eq [ :priority, :status ]      
      p.filters.should eq []
    end
  end
end