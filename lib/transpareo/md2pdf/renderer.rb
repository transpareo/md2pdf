# frozen_string_literal: true

require 'cgi'

module Transpareo
  module Md2pdf
    # Wraps the filtered body in a standalone HTML document with the
    # stylesheet inlined, so Chromium can render it straight off disk
    # with no external requests.
    module Renderer
      module_function

      def document(body:, title:, css:, lang: nil)
        <<~HTML
          <!DOCTYPE html>
          <html#{lang_attr(lang)}>
          <head>
          <meta charset="utf-8">
          <title>#{CGI.escapeHTML(title.to_s)}</title>
          <style>
          #{css}
          </style>
          </head>
          <body>
          #{body}
          </body>
          </html>
        HTML
      end

      def lang_attr(lang)
        lang.to_s.empty? ? '' : %( lang="#{CGI.escapeHTML(lang.to_s)}")
      end
    end
  end
end
