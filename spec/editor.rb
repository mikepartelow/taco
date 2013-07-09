#!/bin/env ruby
template_path = ARGV[0]
if input_path = ENV['EDITOR_INPUT_PATH']
  text = open(input_path, 'r') { |f| f.read }
else
  text = open(template_path, 'r') { |f| f.read }
  text.gsub! /\s+:\s+/, " : hello there\n"
  text += "\nappended text!"
end

open(template_path, 'w') { |f| f.write(text) }

exit 0