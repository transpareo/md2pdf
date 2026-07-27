# frozen_string_literal: true

require 'rouge'

module Transpareo
  module Md2pdf
    # Syntax highlighting for fenced code blocks.
    #
    # Rouge already understands most short language names (`js`,
    # `rb`, `yml`), so only the cases it genuinely lacks are mapped
    # here. JSON-with-comments has no lexer anywhere, so it borrows
    # the JavaScript one, which colours `//` comments and object
    # literals correctly.
    module Highlighter
      ALIASES = {
        'jsonc' => 'javascript',
        'json5' => 'javascript',
        'console' => 'shell',
        'docker' => 'docker',
        'tsx' => 'typescript',
        'jsx' => 'javascript',
      }.freeze

      module_function

      def lexer_for(language)
        return nil if language.nil? || language.empty?

        name = language.downcase
        name = ALIASES.fetch(name, name)
        Rouge::Lexer.find_fancy(name) || Rouge::Lexer.find(name)
      end

      def highlight(code, language)
        lexer = lexer_for(language)
        return nil unless lexer

        formatter.format(lexer.lex(code))
      rescue StandardError
        nil
      end

      def formatter
        @formatter ||= Rouge::Formatters::HTMLInline.new(theme)
      end

      # Inline styles keep the printed PDF self-contained without
      # bloating the stylesheet with a full theme.
      def theme
        @theme ||= Rouge::Themes::Github.new
      end

      def reset!
        @formatter = nil
        @theme = nil
      end
    end
  end
end
