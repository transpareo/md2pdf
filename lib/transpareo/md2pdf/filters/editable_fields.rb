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
      # fields, looking each one up by its destination name in the
      # manifest this filter records on the document: the name is
      # the only part of this markup that survives printing, so it
      # is kept opaque and everything else rides in the manifest.
      #
      # The name's dots keep it out of Slugs territory: heading
      # slugs strip punctuation, so no heading can ever produce one
      # and hand its TOC link to a form field.
      module EditableFields
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
            spec = {
              kind: :checkbox,
              name: "checkbox-#{index + 1}",
              checked: !input['checked'].nil?,
            }
            id = register(doc, spec)
            input.replace(doc.build(anchor(id, 'form-checkbox')))
          end
        end

        # An input with no type is a text input, per HTML.
        def replace_text_inputs(doc)
          doc.fragment.css('input[type="text"], input:not([type])')
            .each_with_index do |input, index|
            spec = { kind: :text, name: "text-#{index + 1}" }
            id = register(doc, spec)
            html = anchor(id, 'form-text', width: input['size'])
            input.replace(doc.build(html))
          end
        end

        def register(doc, spec)
          id = "md2pdf.f.#{doc.fields.size + 1}"
          doc.fields[id] = spec
          id
        end

        # The size attribute counts characters, which is exactly
        # what the ch unit measures; anything else keeps the
        # stylesheet's default width.
        def anchor(id, css_class, width: nil)
          attrs = %(class="#{css_class}" href="##{id}" id="#{id}")
          attrs += %( style="width: #{width}ch") if
            width.to_s.match?(/\A\d+\z/)
          "<a #{attrs}></a>"
        end
      end
    end
  end
end
