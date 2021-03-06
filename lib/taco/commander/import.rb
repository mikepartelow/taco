
require 'taco/commander'
require 'taco/commander/delegates'

include Commander::Delegates

$terminal.wrap_at = HighLine::SystemExtensions.terminal_size.first - 5 rescue 80 if $stdin.tty?
at_exit { run! }
