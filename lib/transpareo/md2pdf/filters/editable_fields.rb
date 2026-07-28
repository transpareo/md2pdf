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
          names = {}
          replace_checkboxes(doc, names)
          replace_radios(doc, names)
          replace_text_inputs(doc, names)
          replace_textareas(doc, names)
          replace_selects(doc, names)
        end

        # Any checkbox in the document qualifies, whether markdown's
        # task-list sugar or raw HTML placed wherever the author
        # wants a box, a table of approvals included.
        def replace_checkboxes(doc, names)
          doc.fragment.css('input[type="checkbox"]')
            .each_with_index do |input, index|
            fallback = "checkbox-#{index + 1}"
            spec = {
              kind: :checkbox,
              name: named(names, :checkbox, input, fallback),
              checked: !input['checked'].nil?,
            }
            id = register(doc, spec)
            style = merge_styles(input['style'])
            html = anchor(id, 'form-checkbox', style: style)
            input.replace(doc.build(html))
          end
        end

        # Radios group by their name attribute, HTML's own grouping
        # rule; an unnamed radio stands alone.
        def replace_radios(doc, names)
          used = Hash.new { |hash, key| hash[key] = {} }
          doc.fragment.css('input[type="radio"]')
            .each_with_index do |input, index|
            group = named(names, :radio, input, "radio-#{index + 1}")
            spec = {
              kind: :radio,
              group: group,
              export: export_for(input, used[group]),
              checked: !input['checked'].nil?,
            }
            id = register(doc, spec)
            style = merge_styles(input['style'])
            html = anchor(id, 'form-radio', style: style)
            input.replace(doc.build(html))
          end
        end

        # An input with no type is a text input, per HTML. A value
        # attribute prefills the field.
        def replace_text_inputs(doc, names)
          doc.fragment.css('input[type="text"], input:not([type])')
            .each_with_index do |input, index|
            fallback = "text-#{index + 1}"
            spec = {
              kind: :text,
              name: named(names, :text, input, fallback),
            }
            value = input['value'].to_s
            spec[:value] = value unless value.empty?
            add_text_style(spec, input)
            id = register(doc, spec)
            style = merge_styles(width_style(input), input['style'])
            html = anchor(id, 'form-text', style: style)
            input.replace(doc.build(html))
          end
        end

        # Text inside the element prefills the field, newlines kept;
        # the customary newline right after the opening tag is not
        # content.
        def replace_textareas(doc, names)
          doc.fragment.css('textarea').each_with_index do |area, index|
            fallback = "textarea-#{index + 1}"
            spec = {
              kind: :textarea,
              name: named(names, :textarea, area, fallback),
            }
            value = area.text.sub(/\A\r?\n/, '')
            spec[:value] = value unless value.strip.empty?
            add_text_style(spec, area)
            id = register(doc, spec)
            style = merge_styles(textarea_style(area), area['style'])
            html = anchor(id, 'form-textarea', style: style)
            area.replace(doc.build(html))
          end
        end

        # Multiple-selection lists have no combo-box equivalent yet
        # and are left as they are, which prints them statically.
        def replace_selects(doc, names)
          doc.fragment.css('select:not([multiple])')
            .each_with_index do |select, index|
            spec = select_spec(select, names, index)
            add_text_style(spec, select)
            id = register(doc, spec)
            style = merge_styles(select_width(spec[:options]),
                                 select['style'],)
            html = anchor(id, 'form-select', style: style)
            select.replace(doc.build(html))
          end
        end

        def select_spec(select, names, index)
          options = select.css('option').map { |opt| opt.text.strip }
          options = [''] if options.empty?
          chosen = select.at_css('option[selected]')
          {
            kind: :select,
            name: named(names, :select, select, "select-#{index + 1}"),
            options: options,
            value: chosen ? chosen.text.strip : options.first,
          }
        end

        # The name attribute names the PDF field, so a filled form
        # reads back with the author's keys. Controls of one kind
        # sharing a name become one field showing the same value
        # everywhere; a name already taken by another kind is
        # suffixed instead, because two field kinds cannot fuse.
        def named(names, kind, node, fallback)
          name = node['name'].to_s.strip
          name = fallback if name.empty?
          name = untangle(names, name) if
            names.key?(name) && names[name] != kind
          names[name] = kind
          name
        end

        def untangle(names, base)
          count = 2
          count += 1 while names.key?("#{base}-#{count}")
          warn "md2pdf: field name #{base} is used by another " \
               "control kind, renaming to #{base}-#{count}"
          "#{base}-#{count}"
        end

        # Wide enough for the longest option plus the arrow.
        def select_width(options)
          "width: #{options.map(&:length).max + 4}ch"
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

        # A style attribute styles the printed box, but these two
        # properties also reach into the field itself, where CSS
        # cannot: the alignment becomes the field's quadding and
        # the size its text size, so what a reader types matches
        # what the page promised.
        def add_text_style(spec, node)
          style = node['style'].to_s
          if (align = style[/text-align\s*:\s*(center|right)/, 1])
            spec[:align] = align.to_sym
          end
          size = font_size_from(style)
          spec[:font_size] = size if size
        end

        # Field text sizes are points; px print at three quarters
        # of a point. Relative units have nothing to resolve
        # against inside a field and are left to the stylesheet.
        def font_size_from(style)
          match = style.match(/font-size\s*:\s*([\d.]+)(pt|px)/)
          return nil unless match

          value = match[1].to_f
          match[2] == 'px' ? value * 0.75 : value
        end

        # Author styles come last, so they win over the generated
        # geometry.
        def merge_styles(*styles)
          merged = styles.compact.reject(&:empty?).join('; ')
          merged.empty? ? nil : merged
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
