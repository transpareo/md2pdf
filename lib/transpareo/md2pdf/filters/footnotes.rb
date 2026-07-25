# frozen_string_literal: true

require 'cgi'

module Transpareo
  module Md2pdf
    module Filters
      # Rebuilds the footnote apparatus.
      #
      # commonmarker already parses `[^id]` references and gathers
      # the definitions, but it numbers them per label. This filter
      # renumbers in reference order and merges entries whose
      # definition text is identical, so citing the same source from
      # three places yields one numbered entry rather than three.
      #
      # A manual `## Footnotes` heading at the end of the source is
      # consumed here, so it does not double up with the heading
      # this filter renders.
      module Footnotes
        # U+21A9, the conventional footnote backlink glyph.
        BACKREF = "\u21A9"

        module_function

        def call(doc)
          section = doc.fragment.at_css('section[data-footnotes]')
          return unless section

          definitions = extract_definitions(section)
          section.remove
          return if definitions.empty?

          items = renumber(doc, definitions)
          return if items.empty?

          strip_trailing_heading(doc)
          append_section(doc, items)
        end

        # Maps each definition's element id to its rendered body and
        # a normalised key used to spot duplicates.
        def extract_definitions(section)
          section.css('li').each_with_object({}) do |li, out|
            id = li['id'].to_s
            next if id.empty?

            li.css('a.footnote-backref').each(&:remove)
            html = li.inner_html.strip
            out[id] = { html: html, key: normalize(li.text) }
          end
        end

        def normalize(text)
          text.gsub(/\s+/, ' ').strip
        end

        # Walks the references in document order, assigning numbers
        # as new definition texts are first seen.
        def renumber(doc, definitions)
          items = []
          by_key = {}
          counter = 0

          doc.fragment.css('sup.footnote-ref').each do |sup|
            link = sup.at_css('a')
            next unless link

            definition = definitions[link['href'].to_s.delete_prefix('#')]
            next unless definition

            index = by_key[definition[:key]]
            unless index
              items << { html: definition[:html], anchor: nil }
              index = items.size
              by_key[definition[:key]] = index
            end

            counter += 1
            anchor = "fnref#{index}-#{counter}"
            items[index - 1][:anchor] ||= anchor
            sup.replace(reference_markup(index, anchor))
          end

          items
        end

        def reference_markup(index, anchor)
          %(<sup class="footnote-ref"><a id="#{anchor}" ) +
            %(href="#fn#{index}" role="doc-noteref">#{index}</a></sup>)
        end

        # Removes a heading left dangling at the end of the document
        # once the definitions that followed it were gathered into
        # the footnotes section.
        def strip_trailing_heading(doc)
          last = doc.fragment.children.reverse.find do |node|
            node.element? || (node.text? && !node.text.strip.empty?)
          end
          last.remove if last&.element? && last.name.match?(/\Ah[1-6]\z/)
        end

        def append_section(doc, items)
          label = doc[:footnotes_label]
          unless label.to_s.empty?
            text = CGI.escapeHTML(label.to_s)
            doc.fragment.add_child(
              %(<h2 id="footnotes" class="footnotes-title">#{text}</h2>)
            )
          end
          doc.fragment.add_child(section_markup(items))
        end

        def section_markup(items)
          parts = [
            '<div id="footnotes-section" class="footnotes" ' \
            'role="doc-endnotes">',
            '<ol class="footnotes-list">'
          ]
          items.each_with_index do |item, i|
            parts << list_item(item, i + 1)
          end
          parts << '</ol></div>'
          parts.join("\n")
        end

        def list_item(item, index)
          back = %(<a href="##{item[:anchor]}" class="footnote-back" ) +
                 %(role="doc-backlink">#{BACKREF}</a>)
          %(<li id="fn#{index}" role="doc-endnote">) +
            "#{merge_backref(item[:html], back)}</li>"
        end

        # The backref belongs inside the last paragraph so it sits on
        # the same line as the closing text rather than below it.
        # Removing the original backref leaves whitespace behind, so
        # the tail is trimmed before the new one is appended.
        def merge_backref(html, back)
          if html.end_with?('</p>')
            "#{html[0...-4].rstrip} #{back}</p>"
          else
            "#{html.rstrip} #{back}"
          end
        end
      end
    end
  end
end
