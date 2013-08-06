
module Commander
  module HelpFormatter
    autoload :Base, 'taco/commander/help_formatters/base'
    autoload :Terminal, 'taco/commander/help_formatters/terminal'
    autoload :TerminalCompact, 'taco/commander/help_formatters/terminal_compact'

    module_function
    def indent amount, text
      text.gsub("\n", "\n" + (' ' * amount))
    end
  end
end
