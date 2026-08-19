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
          # GFM's tagfilter escapes textarea, style and friends
          # even with unsafe rendering on. The document is the
          # author's own, and editable mode needs raw textareas.
          tagfilter: false,
          # Left off deliberately: commonmarker's version injects an
          # empty <a class="anchor"> into every heading, which then
          # leaks into demoted paragraphs and TOC text. The Slugs
          # filter assigns ids instead, with no extra markup.
          header_ids: nil,
        },
        render: {
          unsafe: true,
          hardbreaks: false,
          # An escaped character renders as itself. The default
          # wraps each one in a <span data-escaped-char>, which
          # nothing styles and which would otherwise reach the
          # filters and the PDF's text layer.
          escaped_char_spans: false,
        },
      }.freeze

      FENCE_RE = /\A\s*(?:```|~~~)/
      DIV_OPEN_RE = /\A:{3,}\s*\{?\.?([a-zA-Z][\w-]*)\}?\s*\z/
      DIV_CLOSE_RE = /\A:{3,}\s*\z/

      FIRST_ITEM_RE = /\A1[.)]\s/
      SECOND_ITEM_RE = /\A\s*2[.)]\s/

      # A line that opens a block of its own, so a marker below it
      # begins a list rather than interrupting a paragraph. Blank
      # lines count: they end the paragraph above.
      BLOCK_START_RE = /
        \A\s*
        (?:\z | [\#>|] | :{3,} | < | \[.*\]: | \d+[.)]\s | [-*+]\s
          | `{3} | ~{3} | -{3,}\s*\z | ={3,}\s*\z)
      /x

      module_function

      def to_html(text)
        Commonmarker.to_html(
          utf8(expand_fenced_divs(guard_ordinals(text))),
          options: OPTIONS,
          plugins: { syntax_highlighter: nil },
        )
      end

      # The parser rejects anything not tagged UTF-8, and joining an
      # empty array yields a US-ASCII string, so an empty document
      # would otherwise fail here rather than render as one blank
      # page. Enforced at the boundary that has the requirement.
      def utf8(text)
        return text if text.encoding == Encoding::UTF_8

        text.dup.force_encoding(Encoding::UTF_8)
      end

      # Escapes a `1.` that opens a hard-wrapped line of prose, where
      # CommonMark would otherwise start a list mid-sentence. Only
      # `1.` may interrupt a paragraph, so every other ordinal
      # already survives and this is the one that misfires on a date
      # such as `1. Januar`. It is left alone where the document
      # means a list.
      def guard_ordinals(text)
        lines = text.lines
        in_code = false

        guarded = lines.each_with_index.map do |line, i|
          if line.match?(FENCE_RE)
            in_code = !in_code
            next line
          end
          next line if in_code || !line.match?(FIRST_ITEM_RE)
          next line unless interrupts_paragraph?(lines, i)
          next line if list_intended?(lines, i)

          # `1\.` is a number and a full stop, not a list marker.
          "1\\#{line[1..]}"
        end

        guarded.join
      end

      # True only directly under paragraph text, the one position
      # where CommonMark starts a list in the middle of a sentence.
      def interrupts_paragraph?(lines, index)
        return false if index.zero?

        !lines[index - 1].match?(BLOCK_START_RE)
      end

      def list_intended?(lines, index)
        introduces_list?(lines[index - 1]) || second_item?(lines, index)
      end

      # Trailing emphasis and quotes do not change how a line ends,
      # so `**Vorgehen:**` introduces a list as plainly as `Vorgehen:`.
      def introduces_list?(line)
        line.strip.sub(/[*_`"')\]]+\z/, '').end_with?(':')
      end

      # Looks for a `2.` through the rest of the block, so a first
      # item wrapped over several lines still counts as a list.
      def second_item?(lines, index)
        blank = false
        lines[(index + 1)..].each do |line|
          if line.strip.empty?
            return false if blank

            blank = true
            next
          end
          return true if line.match?(SECOND_ITEM_RE)
          return false if blank && !line.start_with?(' ')

          blank = false
        end
        false
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
