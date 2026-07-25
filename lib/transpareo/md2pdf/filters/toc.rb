# frozen_string_literal: true

require 'cgi'

module Transpareo
  module Md2pdf
    module Filters
      # Builds the table of contents and inserts it before the first
      # H2, so the title keeps page 1 and the TOC lands on its own
      # page. Page numbers come from the previous render pass and
      # show as `?` on the first pass, before any are known.
      module Toc
        module_function

        def call(doc)
          depth = doc[:toc_depth] || 2
          levels = 2..(depth + 1)
          headings = doc.headings(levels)
          return if headings.empty?

          nav = doc.build(markup(doc, headings)).at_css('nav')
          anchor = doc.fragment.at_css('h2')

          if anchor
            anchor.add_previous_sibling(nav)
          else
            doc.fragment.children.first&.add_previous_sibling(nav)
          end
        end

        def markup(doc, headings)
          label = doc[:toc_label]
          parts = ['<nav id="TOC" role="doc-toc">']
          unless label.to_s.empty?
            parts << %(<h2 class="toc-title">#{esc(label)}</h2>)
          end
          parts << '<ul class="toc-list">'
          headings.each { |h| parts << entry(doc, h) }
          parts << '</ul></nav>'
          parts.join("\n")
        end

        def entry(doc, heading)
          id = heading['id'].to_s
          level = heading.name[1].to_i
          page = (doc[:toc_pages] || {})[id] || '?'
          [
            %(<li class="toc-l#{level}"><a href="##{esc(id)}">),
            %(<span class="toc-text">#{esc(heading.text)}</span>),
            '<span class="toc-dots"></span>',
            %(<span class="toc-page">#{esc(page)}</span>),
            '</a></li>'
          ].join
        end

        def esc(value)
          CGI.escapeHTML(value.to_s)
        end
      end
    end
  end
end
