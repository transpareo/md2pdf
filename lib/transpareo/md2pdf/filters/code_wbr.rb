# frozen_string_literal: true

require 'cgi'

module Transpareo
  module Md2pdf
    module Filters
      # Inserts <wbr> hints inside inline `code` spans at
      # break-friendly positions, so a narrow table cell can break a
      # long identifier between segments instead of overflowing.
      #
      # This rewrites the element's markup, so it has to run after
      # every filter that reads code text as plain text.
      module CodeWbr
        SEPARATORS = %r{([/_\-.#:{}])}
        CAMEL_CASE = /([a-z])([A-Z])/

        # Marks a break point while the text is still raw. The
        # markdown parser rewrites NUL to U+FFFD before any filter
        # runs, so no real content can carry one.
        MARK = "\u0000"

        module_function

        def call(doc)
          doc.fragment.css('code').each do |code|
            next if code.parent&.name == 'pre'

            code.inner_html = inject(code.text)
          end
        end

        # Splits on the raw text and escapes each segment
        # afterwards. Escaping first would produce entities such as
        # `&#39;` for an apostrophe, whose `#` reads as a separator,
        # and a `<wbr>` spliced into an entity leaves a stray
        # ampersand that renders as literal `&#39;`.
        def inject(text)
          segments(text).map { |s| CGI.escapeHTML(s) }.join('<wbr>')
        end

        def segments(text)
          text
            .gsub(SEPARATORS, "\\1#{MARK}")
            .gsub(CAMEL_CASE, "\\1#{MARK}\\2")
            .split(MARK, -1)
        end
      end
    end
  end
end
