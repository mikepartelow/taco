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
  text = open(template_path, 'r') { |f| f.read }
  text = text.lines.map do |line|
    if line =~ /^(\w+)\s*:\s*$/
      if value = ENV["EDITOR_FIELD_#{$1.upcase}"]
        line = "#{$1} : #{value}"
      else
        line = "#{$1} : hello there"
      end
    elsif line =~ /^(\w+)\s*:\s*(\w+)$/
      if value = ENV["EDITOR_FIELD_#{$1.upcase}"]
        line = "#{$1} : #{value}"
      else
        line = line
      end      
    else
      line = line
    end
  end.join("\n")

  unless appended_text = ENV['EDITOR_APPEND']
    appended_text = "\nappended text!"
  end
  
  text += appended_text  
end

open(template_path, 'w') { |f| f.write(text) }
exit 0