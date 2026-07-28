# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Replaces form controls - checkboxes, radio buttons, text
      # inputs, textareas and selects - with empty, self-linked
      # anchors that the stylesheet draws as boxes, circles and
      # blank lines.
      #
      # Chromium flattens form controls to pixels when printing,
      # but an anchor pointing into the document survives as a link
      # annotation carrying the element's exact page rectangle.
      # FormFields later rewrites those annotations into fillable
      # fields, looking each one up by its destination name in the
      # manifest this filter records on the document: the name is
      # the only part of this markup that survives printing, so it
      # is kept opaque and everything else - kind, name, options,
      # values, radio grouping - rides in the manifest.
      #
      # The name's dots keep it out of Slugs territory: heading
      # slugs strip punctuation, so no heading can ever produce one
      # and hand its TOC link to a form field.
      module EditableFields
        module_function

        def call(doc)
          replace_checkboxes(doc)
          replace_radios(doc)
          replace_text_inputs(doc)
          replace_textareas(doc)
          replace_selects(doc)
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

        # Radios group by their name attribute, HTML's own grouping
        # rule; an unnamed radio stands alone.
        def replace_radios(doc)
          used = Hash.new { |hash, key| hash[key] = {} }
          doc.fragment.css('input[type="radio"]')
            .each_with_index do |input, index|
            group = input['name'].to_s
            group = "radio-#{index + 1}" if group.empty?
            spec = {
              kind: :radio,
              group: group,
              export: export_for(input, used[group]),
              checked: !input['checked'].nil?,
            }
            id = register(doc, spec)
            input.replace(doc.build(anchor(id, 'form-radio')))
          end
        end

        # An input with no type is a text input, per HTML. A value
        # attribute prefills the field.
        def replace_text_inputs(doc)
          doc.fragment.css('input[type="text"], input:not([type])')
            .each_with_index do |input, index|
            spec = { kind: :text, name: "text-#{index + 1}" }
            value = input['value'].to_s
            spec[:value] = value unless value.empty?
            id = register(doc, spec)
            html = anchor(id, 'form-text', style: width_style(input))
            input.replace(doc.build(html))
          end
        end

        def replace_textareas(doc)
          doc.fragment.css('textarea').each_with_index do |area, index|
            unless area.text.strip.empty?
              warn 'md2pdf: textarea default text is not supported, ' \
                   'the field starts empty'
            end
            spec = { kind: :textarea, name: "textarea-#{index + 1}" }
            id = register(doc, spec)
            style = textarea_style(area)
            html = anchor(id, 'form-textarea', style: style)
            area.replace(doc.build(html))
          end
        end

        # Multiple-selection lists have no combo-box equivalent yet
        # and are left as they are, which prints them statically.
        def replace_selects(doc)
          doc.fragment.css('select:not([multiple])')
            .each_with_index do |select, index|
            options = select.css('option').map { |opt| opt.text.strip }
            options = [''] if options.empty?
            chosen = select.at_css('option[selected]')
            spec = {
              kind: :select,
              name: "select-#{index + 1}",
              options: options,
              value: chosen ? chosen.text.strip : options.first,
            }
            id = register(doc, spec)
            width = options.map(&:length).max + 4
            style = "width: #{width}ch"
            html = anchor(id, 'form-select', style: style)
            select.replace(doc.build(html))
          end
        end

        def register(doc, spec)
          id = "md2pdf.f.#{doc.fields.size + 1}"
          doc.fields[id] = spec
          id
        end

        # Export values become PDF names, so they are reduced to
        # name-safe characters and kept unique within the group.
        def export_for(input, used)
          base = input['value'].to_s.gsub(/[^\w-]/, '-')
          base = 'choice' if base.empty?
          count = used[base] || 0
          used[base] = count + 1
          count.positive? ? "#{base}-#{count}" : base
        end

        # The size attribute counts characters, which is exactly
        # what the ch unit measures; anything else keeps the
        # stylesheet's default width.
        def width_style(input)
          size = input['size'].to_s
          size.match?(/\A\d+\z/) ? "width: #{size}ch" : nil
        end

        # rows and cols size the box the way they size a textarea,
        # with half a line of breathing room in the height.
        def textarea_style(area)
          rows = area['rows'].to_s[/\A\d+\z/]&.to_i || 2
          style = "height: #{(rows * 1.5) + 0.5}em"
          cols = area['cols'].to_s[/\A\d+\z/]
          style += "; width: #{cols}ch" if cols
          style
        end

        def anchor(id, css_class, style: nil)
          attrs = %(class="#{css_class}" href="##{id}" id="#{id}")
          attrs += %( style="#{style}") if style
          "<a #{attrs}></a>"
        end
      end
    end
  end
end
