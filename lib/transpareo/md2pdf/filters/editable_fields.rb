# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Replaces checkboxes and text inputs with empty, self-linked
      # anchors that the stylesheet draws as a box or a blank line.
      #
      # Chromium flattens an <input> to pixels when printing, but an
      # anchor pointing into the document survives as a link
      # annotation carrying the element's exact page rectangle.
      # FormFields later rewrites those annotations into fillable
      # fields. The field's kind, order and checked state travel in
      # the anchor id, because the destination name is the only part
      # of this markup that reaches the PDF.
      #
      # The id's dots keep it out of Slugs territory: heading slugs
      # strip punctuation, so no heading can ever produce one of
      # these names and hand its TOC link to a form field.
      module EditableFields
        CHECKBOX_RE = /\Amd2pdf\.cb\.(\d+)(x)?\z/
        TEXT_RE = /\Amd2pdf\.tx\.(\d+)\z/

        module_function

        def call(doc)
          replace_checkboxes(doc)
          replace_text_inputs(doc)
        end

        # Any checkbox in the document qualifies, whether markdown's
        # task-list sugar or raw HTML placed wherever the author
        # wants a box, a table of approvals included.
        def replace_checkboxes(doc)
          doc.fragment.css('input[type="checkbox"]')
            .each_with_index do |input, index|
            checked = !input['checked'].nil?
            input.replace(doc.build(checkbox(index + 1, checked)))
          end
        end

        # An input with no type is a text input, per HTML.
        def replace_text_inputs(doc)
          doc.fragment.css('input[type="text"], input:not([type])')
            .each_with_index do |input, index|
            input.replace(doc.build(text(index + 1, input['size'])))
          end
        end

        def checkbox(number, checked)
          id = "md2pdf.cb.#{number}#{'x' if checked}"
          %(<a class="form-checkbox" href="##{id}" id="#{id}"></a>)
        end

        # The size attribute counts characters, which is exactly
        # what the ch unit measures; anything else keeps the
        # stylesheet's default width.
        def text(number, size)
          id = "md2pdf.tx.#{number}"
          width = ''
          width = %( style="width: #{size}ch") if
            size.to_s.match?(/\A\d+\z/)
          %(<a class="form-text" href="##{id}" id="#{id}"#{width}></a>)
        end
      end
    end
  end
end
