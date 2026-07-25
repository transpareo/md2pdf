# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Wraps the H1 and the lead blocks that follow it in
      # <div class="title-page"> so CSS can centre them vertically
      # on page 1.
      #
      # This only applies when the document gets a TOC and has no
      # explicit `::: intro :::` block. In every other case the
      # title flows from the top of page 1 instead.
      module TitlePage
        module_function

        def call(doc)
          return unless doc[:toc]
          return if doc.fragment.at_css('div.intro')

          h1 = doc.fragment.at_css('h1')
          return unless h1

          lead = collect_lead(h1)
          wrapper = doc.build('<div class="title-page"></div>')
            .at_css('div')

          h1.add_previous_sibling(wrapper)
          lead.each { |node| wrapper.add_child(node) }
        end

        # The H1 plus every following sibling up to the first H2.
        def collect_lead(title)
          nodes = [title]
          node = title.next_sibling
          while node
            break if node.element? && node.name == 'h2'

            nodes << node
            node = node.next_sibling
          end
          nodes
        end
      end
    end
  end
end
