require 'factory_girl'

FactoryGirl.find_definitions

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'
end

LIB_PATH = File.realdirpath "./lib"
TACO_PATH = File.realdirpath "./bin/taco"
TMP_PATH = File.realdirpath "./spec/tmp"
TACO_HOME_PATH = File.join(TMP_PATH, '.taco')
TACORC_PATH = File.join(TACO_HOME_PATH, '.tacorc')
EDITOR_PATH = File.realdirpath "./spec/editor.rb"
EDITOR_WRITE_PATH = File.join(TMP_PATH, 'editor_output.txt')