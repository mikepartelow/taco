#!/bin/env ruby

exit(1) if ENV['EDITOR_ABORT']

template_path = ARGV[0]
if input_path = ENV['EDITOR_INPUT_PATH']
  text = open(input_path, 'r') { |f| f.read }
else
  text = open(template_path, 'r') { |f| f.read }
  text = text.lines.map do |line|
    if line =~ /^(\w+)\s*:\s*$/
      line = "#{$1} : hello there"
    else
      line = line
    end
  end.join("\n")

  unless appended_text = env['EDITOR_APPEND']
    appended_text = "\nappended text!"
  end
  
  text += appended_text  
end

open(template_path, 'w') { |f| f.write(text) }

exit 0