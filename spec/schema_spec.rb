require 'schema'

THE_TIME = Time.new 2007, 5, 23, 3, 25, 0, "-07:00"

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
        schema_attr :baz, class: String, default: 'x', settable: true, validate: lambda { |v| v !~ /^\s*$/ }
        schema_attr :ick, class: Fixnum, default: 1, settable: true, validate: [1,2,3,4,5]
        schema_attr :thud, class: String, default: 'a', settable: true, validate: %w(a b c)
        schema_attr :wank, class: String, default: '', settable: true
        schema_attr :crud, class: Fixnum, default: 1, settable: true, coerce: false
        schema_attr :frob, class: String, default: '', settable: true, transform: false
        schema_attr :scro, class: Time, default: lambda { THE_TIME }, settable: true
        schema_attr :nart, class: Time, default: lambda { THE_TIME }, settable: true, coerce: false
        schema_attr :wozt, class: String
        schema_attr :wizt, class: Fixnum
        schema_attr :wuzt, class: Time
      end
    end
    
    after do
      Object.send(:remove_const, :Foo)
      Object.send(:remove_const, :Bar) rescue nil
      Object.send(:remove_const, :Baz) rescue nil            
    end
    
    it "creates getters with default value" do
      Foo.new.bar.should eq 'abc123'
      Foo.new.scro.should eq THE_TIME
      Foo.new.wozt.should eq ''
      Foo.new.wizt.should eq 0
      Foo.new.wuzt.should be_within(2).of(Time.now)
      p "--"
      p Foo.new.wuzt.subsec
      p "--"
      Foo.new.wuzt.subsec should eq 0
    end
    
    it "checks the type of Proc defaults at get-time" do
      class Bar
        include Schema
      
        schema_attr :scro, class: Time, default: lambda { 'boy howdy!' }, settable: true
      end
      bar = Bar.new
      expect { bar.scro }.to raise_error(TypeError)      
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
      the_time = THE_TIME
      f.scro = the_time
      f.scro.should eq the_time
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
            
      it "allows a properly typed Array for :validate" do
        class Bar
          include Schema

          schema_attr :baz, class: String, default: 'baz', validate: ['a', 'b', 'c']
        end 
        
        expect {
          class Baz
            include Schema

            schema_attr :baz, class: String, default: 'baz', validate: [1, 2, 3]
          end           
        }.to raise_error(TypeError)
      end
      
      it "allows a Proc for :validate" do
        class Bar
          include Schema

          schema_attr :baz, class: String, default: 'baz', validate: lambda { |x| true }
        end 
      end
      
      it "does not allow other types for :validate" do
        expect {
          class Bar
            include Schema

            schema_attr :baz, class: String, default: 'baz', validate: 2
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
        
        # scro is a Time
        specify { expect { Foo.new.scro = nil }.to raise_error(TypeError) }
        specify { expect { Foo.new.scro = 123 }.to raise_error(TypeError) }
        specify { expect { Foo.new.scro = 'abc' }.to raise_error(TypeError) }
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
        
        it "should coerce String to Time" do
          foo.scro = THE_TIME.to_s
          foo.scro.class.should eq Time
          foo.scro.should eq the_time
        end
            
        it "should raise TypeError when failing to coerce a String to Time" do
          expect { foo.scro = 'foo bar' }.to raise_error(TypeError)
        end
        
        it "should raise TypeError when coercions are disabled and a String is assigned to a Time field" do
          foo.nart = THE_TIME
          foo.nart.should eq THE_TIME
          expect { foo.nart = THE_TIME.to_s }.to raise_error(TypeError)
        end
        
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
        
        it "should remove subsec precision from Time by default" do
          the_time = Time.at(1179915900, 12345)
          the_time.subsec.should_not eq 0
          
          foo.scro = the_time
          foo.scro.subsec.should eq 0
          foo.scro.should eq Time.at(1179915900)
        end
        
        it "should remove subsec precision from Time default" do
          class Bar
            include Schema

            schema_attr :baz, class: Time            
            schema_attr :ick, class: Time, default: lambda { Time.at(1179915900, 12345) }
          end
          
          bar = Bar.new
          bar.baz.subsec.should eq 0          
          bar.ick.subsec.should eq 0          
        end
      end
    end
  end
end

__END__

transform must be part of GET: this way we can always scrub Times, even defaults, even un-settables.
Time scrub transform can't be disabled (spec this)

NO: ALWAYS create a setter, but make it private in case of unsettables.  then, in getter, call the setter.


.to_hash
attributes? maybe class needs attr_reader :schema_attrs (in which case stop calling instance_variable_get): nah, then we could write to opts
"runtime" updating (aka set_allowed_values).  maybe a schema_attr_remove?