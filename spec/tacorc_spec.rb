require 'tacorc'
require 'schema'

TMP_PATH = File.realdirpath "./spec/tmp"
TACORC_PATH = File.join(TMP_PATH, 'tacorc')

describe TacoRc do
  let(:tacorc) { <<-EOT.strip
# comment, followed by a blank line (don't panic)

schema_attr_update :stringy, default: 'Val1', validate: [ 'Val1', 'Val2' ]
schema_attr_update :inty, default: 3, validate: [ 1, 2, 3, 4, 5 ]
EOT
  }

  before do
    FileUtils.mkdir_p(TMP_PATH)    
    open(TACORC_PATH, 'w') { |f| f.write(tacorc) }
    
    Object.send(:remove_const, :Dingus) rescue nil
    
    class Dingus
      include Schema

      schema_attr :stringy, class: String, settable: true
      schema_attr :inty, class: Fixnum, settable: true 
    end    
  end
  after { FileUtils.rm_rf(TMP_PATH) }      
  
  it "is initialized with a path" do
    TacoRc.new TACORC_PATH
  end
  
  it "raises ArgumentError if no file exists at the given path" do
    expect { TacoRc.new '/path/to/nowhere' }.to raise_error(ArgumentError)
  end
  
  describe "parsing" do
    it "raises TacoRc::ParseError on parse error" do
      open(TACORC_PATH, 'w') { |f| f.write("BAD IDEA") }
      expect { TacoRc.new(TACORC_PATH).update_schema! Dingus }.to raise_error(TacoRc::ParseError)      
            
      open(TACORC_PATH, 'w') { |f| f.write("schema_attr_update :no_such_thing, default: 'What'") }
      expect { TacoRc.new(TACORC_PATH).update_schema! Dingus }.to raise_error(TacoRc::ParseError)      
      
      open(TACORC_PATH, 'w') { |f| f.write("to_s") }
      expect { TacoRc.new(TACORC_PATH).update_schema! Dingus }.to raise_error(TacoRc::ParseError)      
      
      open(TACORC_PATH, 'w') { |f| f.write("schema_attr_update :stringy, default: 99") }
      expect { TacoRc.new(TACORC_PATH).update_schema! Dingus }.to raise_error(TacoRc::ParseError)            
    end
    
    it "updates a Schema" do
      dingus = Dingus.new
      
      dingus.stringy.should eq ''
      dingus.inty.should eq 0
      dingus.stringy = "hello, sailor"
      dingus.inty = 99
      dingus.should be_valid
      
      TacoRc.new(TACORC_PATH).update_schema! Dingus
      
      dingus = Dingus.new

      dingus.stringy.should eq 'Val1'
      dingus.inty.should eq 3
      dingus.stringy = "hello, sailor"
      dingus.inty = 99
      dingus.should_not be_valid
      dingus.stringy = "Val2"
      dingus.inty = 3
      dingus.should be_valid
    end
  end
end
