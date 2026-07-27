# frozen_string_literal: true

require_relative 'filters/slugs'
require_relative 'filters/editable_fields'
require_relative 'filters/images'
require_relative 'filters/title_page'
require_relative 'filters/footnotes'
require_relative 'filters/demote'
require_relative 'filters/toc'
require_relative 'filters/code_highlight'
require_relative 'filters/code_wbr'
require_relative 'filters/tables'

module Transpareo
  module Md2pdf
    # Assembles the ordered filter chain for one conversion.
    #
    # Order is load-bearing in three places. Slugs must precede
    # anything that links to a heading. Demote must precede the TOC
    # so a flattened document exposes no headings to it. CodeWbr
    # rewrites inline code into markup the text-reading filters can
    # no longer parse, so it runs after them.
    module Filters
      module_function

      def chain(flat:, toc:, editable: false)
        chain = [Slugs, Images, TitlePage, Footnotes]
        chain << EditableFields if editable
        chain << Demote if flat
        chain << Toc if toc
        chain + [CodeHighlight, CodeWbr, Tables]
      end
    end
  end
end
