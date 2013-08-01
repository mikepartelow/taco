# .taco/.tacorc describes properties of the taco repository
# contrast with ~/.taco_profile

class TacoRc
  class ParseError < Exception; end
  
  def initialize(path)
    raise ArgumentError.new("no such file: #{path}") unless File.exists? path
    @path = path
  end
  
  def update_schema!(schema)
    open(@path) do |f|
      f.readlines.each_with_index do |line, index|
        next if line =~ /^#/ || line =~ /^\s*$/
  
        raise ParseError.new("Parse error on line #{index+1} of #{@path}: line does not begin with schema_attr_update") unless line =~ /^\s*schema_attr_update /
        
        begin
          eval "#{schema}.#{line.strip}"
        rescue KeyError, TypeError, NameError => e
          raise ParseError.new("Parse error on line #{index+1} of #{@path}: #{e.to_s}")           
        end
      end
    end
  end
end