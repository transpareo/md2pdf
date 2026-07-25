# frozen_string_literal: true

module Transpareo
  module Md2pdf
    # Joins hard-wrapped prose back into single logical lines, so a
    # document written at 72 columns reflows to the PDF's measure
    # instead of breaking where the author's editor happened to.
    #
    # Structural lines are never joined. Fenced code is copied
    # through verbatim.
    module Unwrap
      FENCE = /\A\s*```/

      # A line matching any of these starts something new, so it is
      # never appended to the line above it.
      OPENS_BLOCK = [
        /\A#/,           # heading
        /\A[-*+] /,      # bullet item
        /\A\d+\. /,      # ordered item
        /\A>/,           # blockquote
        /\A\|/,          # table row
        /\A```/,         # fence
        /\A---+\s*\z/,   # setext rule
        /\A===+\s*\z/,   # setext rule
        /\A\[.*\]:/      # link reference definition
      ].freeze

      # A line matching any of these cannot absorb the line below it.
      CLOSES_BLOCK = [
        /\A#/,
        /\A\|/,
        /\A---+\s*\z/,
        /\A===+\s*\z/
      ].freeze

      module_function

      def call(text)
        out = []
        in_code = false

        text.lines.map(&:rstrip).each do |line|
          in_code = !in_code if line.match?(FENCE)

          if !in_code && !line.match?(FENCE) && joinable?(out.last, line)
            out[-1] = "#{out[-1]} #{line.lstrip}"
          else
            out << line
          end
        end

        "#{out.join("\n")}\n"
      end

      def joinable?(prev, line)
        return false if prev.nil? || line.nil?
        return false if line.strip.empty? || prev.strip.empty?

        current = line.lstrip
        previous = prev.lstrip
        return false if OPENS_BLOCK.any? { |re| current.match?(re) }
        return false if CLOSES_BLOCK.any? { |re| previous.match?(re) }

        # An indented line under a "label:" line is a deliberate
        # continuation, such as a definition or a config sample.
        !(previous.end_with?(':') && line.match?(/\A\s{2,}/))
      end
    end
  end
end
