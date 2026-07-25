# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Demotes everything below H1 so the PDF carries only the
      # title as a real heading. H2 becomes bold, H3 and deeper
      # become bold italic.
      module Demote
        module_function

        def call(doc)
          doc.headings(2..6).each do |heading|
            level = heading.name[1].to_i
            inner = level == 2 ? bold(heading) : bold_italic(heading)
            para = doc.build("<p>#{inner}</p>").at_css('p')
            para['id'] = heading['id'] if heading['id']
            heading.replace(para)
          end
        end

        def bold(heading)
          "<strong>#{heading.inner_html}</strong>"
        end

        def bold_italic(heading)
          "<strong><em>#{heading.inner_html}</em></strong>"
        end
      end
    end
  end
end
