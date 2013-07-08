#!/bin/env ruby
template_path = ARGV[0]
input_path = ENV['EDITOR_INPUT_PATH']

text = open(input_path, 'r') { |f| f.read }

open(template_path, 'w') { |f| f.write(text) }

exit 0