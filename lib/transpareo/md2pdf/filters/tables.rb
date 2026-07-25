# frozen_string_literal: true

require 'cgi'

module Transpareo
  module Md2pdf
    module Filters
      # Two table fixes that both exist to stop a wide table from
      # pushing the page past its width and triggering Chromium's
      # shrink-to-fit, which silently scales the whole document.
      #
      # The wrapper clips horizontal overflow instead of letting it
      # widen the page. Wrapping header words individually means a
      # column's intrinsic minimum width is set by its longest word
      # rather than its whole header string.
      module Tables
        module_function

        def call(doc)
          doc.fragment.css('table').each do |table|
            nowrap_header_words(doc, table)
            wrap(doc, table)
          end
        end

        def wrap(doc, table)
          return if table.parent&.[]('class').to_s.include?('table-wrap')

          wrapper = doc.build('<div class="table-wrap"></div>')
            .at_css('div')
          table.add_previous_sibling(wrapper)
          wrapper.add_child(table)
        end

        def nowrap_header_words(doc, table)
          table.css('thead th').each do |cell|
            cell.xpath('.//text()').each do |node|
              next if node.text.strip.empty?

              node.replace(doc.build(wrap_words(node.text)))
            end
          end
        end

        # Preserves the original spacing so the header reads the same,
        # only with each word individually unbreakable.
        def wrap_words(text)
          text.split(/(\s+)/).map do |part|
            if part.strip.empty?
              CGI.escapeHTML(part)
            else
              %(<span class="nobr">#{CGI.escapeHTML(part)}</span>)
            end
          end.join
        end
      end
    end
  end
end
