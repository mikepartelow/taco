require 'taco'

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
        schema_attr :baz, class: String, default: '', settable: true
        schema_attr :ick, class: Fixnum, default: 1, settable: true
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
           
    end
    
    describe "setter validations" do
      # baz is a String
      specify { expect { Foo.new.baz = nil }.to raise_error(TypeError) }
      specify { expect { Foo.new.baz = 123 }.to raise_error(TypeError) }
      specify { expect { Foo.new.baz = Time.new }.to raise_error(TypeError) }

      # ick is a Fixnum
      specify { expect { Foo.new.ick = nil }.to raise_error(TypeError) }
      specify { expect { Foo.new.ick = '123' }.to raise_error(TypeError) }
      specify { expect { Foo.new.ick = Time.new }.to raise_error(TypeError) }
      
    end
    
  end
end
