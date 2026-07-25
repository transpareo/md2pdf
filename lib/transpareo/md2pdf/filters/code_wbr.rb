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

        module_function

        def call(doc)
          doc.fragment.css('code').each do |code|
            next if code.parent&.name == 'pre'

            code.inner_html = inject(CGI.escapeHTML(code.text))
          end
        end

        def inject(text)
          text.gsub(SEPARATORS, '\1<wbr>').gsub(CAMEL_CASE, '\1<wbr>\2')
        end
      end
    end
  end
end
