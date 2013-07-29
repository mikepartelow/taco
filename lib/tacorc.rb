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
  
        raise ParseError.new("Parse error on line #{index+1} of #{@path}") unless line =~ /^\s*schema_attr_update /
        
        begin
          eval "#{schema}.#{line.strip}"
        rescue NameError
          raise ParseError.new("Parse error on line #{index+1} of #{@path}")
        end
      end
    end
  end
end