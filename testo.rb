#!/usr/bin/env ruby

require 'rubygems'
require 'commander/import'

program :version, '0.0.1'
program :description, 'it has command lines'
 
command :init do |c|
  c.syntax = 'testo init [options]'
  c.summary = 'SUMMARY'
  c.description = 'DESCR'
  c.example 'description', 'command example'
  c.option '--some-switch', 'Some switch that does something'
  c.action do |args, options|
    p ask_editor
  end
end

command :new do |c|
  c.syntax = 'testo new [options]'
  c.summary = ''
  c.description = ''
  c.example 'description', 'command example'
  c.option '--some-switch', 'Some switch that does something'
  c.action do |args, options|
    # Do something or c.when_called Testo::Commands::New
  end
end

command :show do |c|
  c.syntax = 'testo show [options]'
  c.summary = ''
  c.description = ''
  c.example 'description', 'command example'
  c.option '--some-switch', 'Some switch that does something'
  c.action do |args, options|
    # Do something or c.when_called Testo::Commands::Show
  end
end

command :list do |c|
  c.syntax = 'testo list [options]'
  c.summary = ''
  c.description = ''
  c.example 'description', 'command example'
  c.option '--some-switch', 'Some switch that does something'
  c.action do |args, options|
    # Do something or c.when_called Testo::Commands::List
  end
end

