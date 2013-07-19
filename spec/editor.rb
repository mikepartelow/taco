#!/bin/env ruby

# FIXME: this whole file has become a giant pile of crap.  
#
template_path = ARGV[0]

if write_path = ENV['EDITOR_WRITE_INPUT']
  text = open(template_path, 'r') { |f| f.read }
  open(write_path, 'w') { |f| f.write(text) }
  exit 0
end

exit(1) if ENV['EDITOR_ABORT']

if input_path = ENV['EDITOR_INPUT_PATH']
  text = open(input_path, 'r') { |f| f.read }
else
  unless appended_text = ENV['EDITOR_APPEND']
    appended_text = "\nappended text!"
  end
  
  delimiters = 0
  
  text = open(template_path, 'r') { |f| f.read }
  text = text.lines.map do |line|
    if line =~ /^(\w+)\s*:\s*$/
      if value = ENV["EDITOR_FIELD_#{$1.upcase}"]
        "#{$1} : #{value}"
      else
        "#{$1} : hello there"
      end
    elsif line =~ /^(\w+)\s*:\s*(\w+)$/
      if value = ENV["EDITOR_FIELD_#{$1.upcase}"]
        "#{$1} : #{value}"
      else
        line
      end      
    elsif line =~ /^---$/
      delimiters += 1
      if delimiters == 2
        appended_text + "\n" + line 
      else
        line
      end
    else      
      line
    end
  end.map(&:rstrip).join("\n")  
end

open(template_path, 'w') { |f| f.write(text) }
exit 0