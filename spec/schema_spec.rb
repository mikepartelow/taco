require 'schema'

describe Schema do
  it "can be included in another class" do
    class Foo
      include Schema
    end
  end
  
  describe "behavior" do
    before do
      class Foo
        include Schema
        
        schema_attr :bar, class: String, default: 'abc123'
        schema_attr :baz, class: String, default: 'x', settable: true, values: lambda { |v| v !~ /^\s*$/ }
        schema_attr :ick, class: Fixnum, default: 1, settable: true, values: [1,2,3,4,5]
        schema_attr :thud, class: String, default: 'a', settable: true, values: %w(a b c)
        schema_attr :wank, class: String, default: '', settable: true
        schema_attr :crud, class: Fixnum, default: 1, settable: true, coerce: false
        schema_attr :frob, class: String, default: '', settable: true, transform: false
      end
    end
    
    after do
      Object.send(:remove_const, :Foo)
      Object.send(:remove_const, :Bar) rescue nil
      Object.send(:remove_const, :Baz) rescue nil            
    end
    
    it "creates getters with default value" do
      Foo.new.bar.should eq 'abc123'
    end
    
    it "is not settable by default" do
      expect { Foo.new.bar = 'x' }.to raise_error(NoMethodError)
    end
    
    it "creates setters" do
      f = Foo.new
      f.baz = 'xyz'
      f.baz.should eq 'xyz'
      f.ick = 999
      f.ick.should eq 999
    end
    
    it "does not create setters for non-settable attributes" do
      expect { Foo.new.bar = 'x' }.to raise_error(NoMethodError)
    end
    
    describe "schema_attr argument validation" do
      it "requires a class" do
        expect {
          class Bar
            include Schema
          
            schema_attr :baz, default: '123'
          end 
        }.to raise_error(TypeError)

        expect {
          class Bar
            include Schema
          
            schema_attr :baz, class: 'this is not a class'
          end 
        }.to raise_error(TypeError)
      end
    
      it "requires a default" do
        expect {
          class Bar
            include Schema
          
            schema_attr :baz, class: String
          end 
        }.to raise_error(TypeError)
      end
    
      it "requires a default of the proper type" do
        expect {
          class Bar
            include Schema
          
            schema_attr :baz, class: Fixnum, default: 'this is not a Fixnum'
          end 
        }.to raise_error(TypeError)            
      end 
      
      it "does not allow duplicate declarations" do
        expect {
          class Bar
            include Schema

            schema_attr :baz, class: String, default: 'baz'
            schema_attr :baz, class: String, default: 'baz'
          end 
        }.to raise_error(ArgumentError)
      end 
      
      it "does not mind 'duplicate' declarations in different classes" do
        class Bar
          include Schema

          schema_attr :baz, class: String, default: 'baz'
        end 
        
        class Baz
          include Schema

          schema_attr :baz, class: String, default: 'baz'
        end         
      end    
            
      it "allows a properly typed Array for :values" do
        class Bar
          include Schema

          schema_attr :baz, class: String, default: 'baz', values: ['a', 'b', 'c']
        end 
        
        expect {
          class Baz
            include Schema

            schema_attr :baz, class: String, default: 'baz', values: [1, 2, 3]
          end           
        }.to raise_error(TypeError)
      end
      
      it "allows a Proc for :values" do
        class Bar
          include Schema

          schema_attr :baz, class: String, default: 'baz', values: lambda { |x| true }
        end 
      end
      
      it "does not allow other types for :values" do
        expect {
          class Bar
            include Schema

            schema_attr :baz, class: String, default: 'baz', values: 2
          end           
        }.to raise_error(ArgumentError)
      end
    end
    
    describe "instance variable validations" do
      describe "type checking" do
        # baz is a String
        specify { expect { Foo.new.baz = nil }.to raise_error(TypeError) }
        specify { expect { Foo.new.baz = 123 }.to raise_error(TypeError) }
        specify { expect { Foo.new.baz = Time.new }.to raise_error(TypeError) }

        # ick is a Fixnum
        specify { expect { Foo.new.ick = nil }.to raise_error(TypeError) }
        specify { expect { Foo.new.ick = 'abc' }.to raise_error(TypeError) }
        specify { expect { Foo.new.ick = Time.new }.to raise_error(TypeError) }
      end
      
      describe "valid?" do
        let(:foo) { Foo.new }
        
        it "is valid by default" do
          foo.should be_valid
        end
        
        describe "disallowed values" do
          specify { foo.baz = ''; foo.should_not be_valid }          
          specify { foo.baz = '     '; foo.should_not be_valid }
          specify { foo.baz = "\n"; foo.should_not be_valid }
          specify { foo.ick = 77; foo.should_not be_valid }
          specify { foo.thud = 'd'; foo.should_not be_valid }
        end
        
        describe "allowed values" do
          specify { foo.baz = 'hello world'; foo.should be_valid }          
          specify { foo.ick = 3; foo.should be_valid }          
          specify { foo.thud = 'c'; foo.should be_valid }
        end        
      end
      
      describe "coercion" do
        let(:foo) { Foo.new }
        
        it "should coerce String to Fixnum by default" do
          foo.ick = '3'
          foo.should be_valid
          foo.ick.should eq 3
        end
        
        it "should not coerce String to Fixnum when coercion is disabled" do
          expect { foo.crud = '3' }.to raise_error(TypeError)
        end
        
        it "shouldn't coerce non-Strings into Fixnum" do
          expect { foo.ick = Time.new }.to raise_error(TypeError)
        end
      
        it "should raise TypeError when failing to coerce a String to Fixnum" do
          expect { foo.ick = 'abc' }.to raise_error(TypeError)
        end
        
        it "should coerce String to Time"        
        it "should raise TypeError when failing to coerce a String to Time"        
        
        it "should do custom coercion" do
          class Bar
            include Schema

            schema_attr :baz, class: String, default: 'baz', settable: true, coerce: lambda { |baz| (baz + 3).to_s }
          end
          
          bar = Bar.new
          bar.baz = 2
          bar.baz.should eq '5'
        end
          
      end
      
      describe "transform" do
        let(:foo) { Foo.new }
        
        it "should strip whitespace from String by default" do
          foo.wank = "\n   foo bar baz   \n  \t  "
          foo.should be_valid
          foo.wank.should eq "foo bar baz"
        end
        
        it "should not strip whitespace from String when transform is disabled" do
          foo.frob = "\n   foo bar baz   \n  \t  "
          foo.should be_valid
          foo.frob.should eq "\n   foo bar baz   \n  \t  "
        end
        
        it "should do custom transformation" do
          class Bar
            include Schema

            schema_attr :baz, class: String, default: 'baz', settable: true, transform: lambda { |baz| baz += 'xyz' }
          end
          
          bar = Bar.new
          bar.baz = "abc"
          bar.baz.should eq "abcxyz"
        end      
      end
    end
  end
end

__END__
                
        
        
        

                
                                
                coerce:
                  - default on
                    - String => Fixnum
                    - String => Time
                  - can set to false
                  - can set to Proc
                  
                munge:
                  - default on
                    - String => strip
                    - Time => -subsec
                  - can set to false
                  - can set to Proc
                  
                valid:
                  - rename :values
                
        fail "what are we trying to accomplish here?"
                  

        it "should truncate subsec precision of Time"
        it "should raise [X] when failing to coerce a String to Time"
      end
    end
    
  end
end
