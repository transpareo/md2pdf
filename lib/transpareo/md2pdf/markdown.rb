# frozen_string_literal: true

require 'commonmarker'

module Transpareo
  module Md2pdf
    # Markdown to HTML, via commonmarker (GFM).
    #
    # Two things happen here that commonmarker does not do itself:
    # fenced divs (`::: intro`) are rewritten to raw HTML before
    # parsing, and syntax highlighting is left switched off so the
    # Highlighter filter can colour code with a print-friendly
    # theme instead of commonmarker's dark inline styles.
    module Markdown
      OPTIONS = {
        parse: { smart: false },
        extension: {
          table: true,
          strikethrough: true,
          autolink: true,
          tasklist: true,
          footnotes: true,
          description_lists: true,
          # Left off deliberately: commonmarker's version injects an
          # empty <a class="anchor"> into every heading, which then
          # leaks into demoted paragraphs and TOC text. The Slugs
          # filter assigns ids instead, with no extra markup.
          header_ids: nil
        },
        render: { unsafe: true, hardbreaks: false }
      }.freeze

      FENCE_RE = /\A\s*(?:```|~~~)/
      DIV_OPEN_RE = /\A:{3,}\s*\{?\.?([a-zA-Z][\w-]*)\}?\s*\z/
      DIV_CLOSE_RE = /\A:{3,}\s*\z/

      module_function

      def to_html(text)
        Commonmarker.to_html(
          expand_fenced_divs(text),
          options: OPTIONS,
          plugins: { syntax_highlighter: nil }
        )
      end

      # Rewrites `::: name` / `:::` pairs into raw div tags, which
      # CommonMark passes through untouched while still parsing the
      # markdown between them. Fenced code blocks are skipped so a
      # literal `:::` in a code sample survives verbatim.
      def expand_fenced_divs(text)
        depth = 0
        in_code = false

        lines = text.lines.map do |line|
          stripped = line.chomp

          if stripped.match?(FENCE_RE)
            in_code = !in_code
            next line
          end
          next line if in_code

          if (m = stripped.match(DIV_OPEN_RE))
            depth += 1
            next %(<div class="#{m[1]}">\n)
          end

          if depth.positive? && stripped.match?(DIV_CLOSE_RE)
            depth -= 1
            next "</div>\n"
          end

          line
        end

        lines.join + ("</div>\n" * depth)
      end
    end
  end
end
