# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Moves the whitespace that opens the text after a bold or
      # italic run to the end of that run.
      #
      # Chromium draws a word space in the face of the text it
      # belongs to. After `**Sitz:** Tech` the space opens the
      # regular run, and an extractor that reads the PDF run by run
      # and trims each run's leading whitespace reads `Sitz:Tech`.
      # Inside the bold run the space ends a run instead, which
      # every extractor keeps. The space then takes the bold face's
      # width, a tenth of a point wider at body size.
      #
      # Inline code is left alone: its space would be set in the
      # monospace face, visibly wider.
      module StyleSpaces
        STYLED = 'strong, b, em, i'

        LEADING_SPACE = /\A[ \t\r\n]+/

        module_function

        def call(doc)
          doc.fragment.css(STYLED).each do |run|
            following = run.next_sibling
            next unless following&.text?

            space = following.content[LEADING_SPACE]
            next unless space

            last = run.xpath('.//text()').last
            next unless last

            last.content = last.content + space
            following.content = following.content.delete_prefix(space)
          end
        end
      end
    end
  end
end
