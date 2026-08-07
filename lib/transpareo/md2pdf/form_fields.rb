# frozen_string_literal: true

require 'pdf-reader'
require 'zlib'

module Transpareo
  module Md2pdf
    # Rewrites the link annotations planted by the EditableFields
    # filter into real AcroForm fields.
    #
    # No browser prints form fields, so the fields are added after
    # the fact by appending an incremental update to the finished
    # PDF. Each link annotation already sits in its page's /Annots
    # with the exact rectangle Chromium laid the element out at, so
    # the rewrite replaces those objects in place, keeping their
    # numbers: the pages are never touched, and only the catalog is
    # replaced to declare the form. A reader that ignores the update
    # still sees the original static document.
    #
    # Radio widgets become kids of one parent field per group.
    # Prefilled values are drawn as real appearance streams rather
    # than left to /NeedAppearances, which poppler ignores for
    # buttons; and every widget carries a zero-width border so no
    # viewer draws its own frame inside the printed one.
    module FormFields
      # Text-field rectangles are inset relative to the printed box:
      # the left inset pads typed text away from the printed border,
      # and the downward shift settles the viewer's vertically
      # centred text just above the printed rule. Textareas inset
      # all four edges, their text filling top to bottom; selects
      # only pad the left. Checkboxes and radios keep the printed
      # box exactly, so the mark lands inside it.
      TEXT_PAD_LEFT = 3.0
      TEXT_DROP = 0.5
      TEXTAREA_INSET = 2.0
      SELECT_PAD_LEFT = 2.5

      module_function

      # Rewrites the annotations named in `manifest`, the filter's
      # {destination name => field spec} record. Returns the number
      # of fields created, zero when nothing matched.
      def call(pdf_path, manifest, font_size: nil, font_family: nil)
        return 0 if manifest.nil? || manifest.empty?

        bytes = File.binread(pdf_path)
        objects = PDF::Reader.new(pdf_path).objects
        guard(objects)

        fields = editable_annotations(objects, manifest)
        return 0 if fields.empty?

        update = Update.new(bytes, objects, fields,
                            font_size, font_family,)
        File.binwrite(pdf_path, bytes + update.render)
        fields.size
      end

      # Both conditions are outside what Chromium produces, and
      # writing into either would corrupt more than it adds.
      def guard(objects)
        raise Error, 'cannot add form fields to an encrypted PDF' if objects.trailer[:Encrypt]

        catalog = objects.deref(objects.trailer[:Root])
        return unless catalog[:AcroForm]

        raise Error, 'the PDF already carries form fields'
      end

      # Every link annotation whose destination the filter planted,
      # joined with its manifest spec and the page it sits on.
      def editable_annotations(objects, manifest)
        objects.page_references.flat_map do |page_ref|
          page = objects.deref(page_ref)
          Array(objects.deref(page[:Annots])).filter_map do |ref|
            next unless ref.is_a?(PDF::Reader::Reference)

            annot = objects.deref(ref)
            spec = manifest[annot[:Dest].to_s]
            next unless spec

            spec.merge(ref: ref, page: page_ref, rect: annot[:Rect])
          end
        end
      end

      # CSS pt survive printing one to one, no px scale factor.
      def body_size(font_size)
        size = font_size.to_s.to_f
        size.positive? ? size : 11.0
      end

      # WinAnsi, so umlauts and friends survive the base font.
      def helvetica
        {
          Type: :Font,
          Subtype: :Type1,
          BaseFont: :Helvetica,
          Encoding: :WinAnsiEncoding,
        }
      end

      # The trailer's /Size is the conventional answer, but it is
      # taken from the file rather than trusted blindly: a stale
      # Size would hand out an object number that is already taken.
      def next_id(objects)
        top = 0
        objects.each_key { |ref| top = ref.id if ref.id > top }
        [top, objects.trailer[:Size].to_i - 1].max + 1
      end

      # Byte offset of the previous cross-reference table, read from
      # the tail of the file the way a PDF reader does.
      def prev_offset(bytes)
        offset = bytes[/startxref\s+(\d+)\s+%%EOF\s*\z/m, 1]
        raise Error, 'no cross-reference offset found' unless offset

        offset.to_i
      end

      # One subsection per contiguous run of object numbers.
      def xref_table(offsets)
        sections = offsets.keys.sort.slice_when { |a, b| b != a + 1 }
        lines = sections.map do |ids|
          rows = ids.map { |id| format("%010d 00000 n \n", offsets[id]) }
          "#{ids.first} #{ids.size}\n#{rows.join}"
        end
        "xref\n#{lines.join}"
      end

      def trailer(objects, offsets, prev, xref_at)
        dict = objects.trailer.dup
        dict[:Size] = [dict[:Size].to_i, offsets.keys.max + 1].max
        dict[:Prev] = prev
        "trailer\n#{ser(dict)}\nstartxref\n#{xref_at}\n%%EOF\n"
      end

      # Writes one value in PDF syntax. Covers the types Chromium's
      # catalog and trailer actually contain; anything else is a
      # sign the input is not the file this module was written for.
      def ser(value)
        case value
        when Hash
          "<< #{value.map { |k, v| "/#{k} #{ser(v)}" }.join(' ')} >>"
        when Array then "[#{value.map { |v| ser(v) }.join(' ')}]"
        when Symbol then "/#{value}"
        when PDF::Reader::Reference then "#{value.id} #{value.gen} R"
        when String then "(#{escape(value)})"
        when Integer, Float, true, false then value.to_s
        else raise Error, "cannot write #{value.class} into a PDF"
        end
      end

      # Literal-string escaping for the characters PDF treats
      # specially.
      def escape(text)
        text.gsub(/[\\()]/) { |char| "\\#{char}" }
      end

      def ref(number)
        PDF::Reader::Reference.new(number, 0)
      end

      # Builds the appended revision for one set of fields. An
      # instance owns the growing byte string and the object-number
      # counter, which a pile of threaded parameters kept obscuring.
      class Update
        # Field quadding values, the PDF names for text alignment.
        QUADDING = { center: 1, right: 2 }.freeze

        # The keys that make widgets of one field interchangeable.
        # Kids inherit them from the first member, so a value given
        # on any one control shows on every clone.
        IDENTITY = %i[name value checked options align
                      font_size].freeze

        # Standard Helvetica advance widths in thousandths of the
        # em, ASCII 32 to 126; everything else uses the average
        # lowercase width. Only the fallback needs them: an
        # embedded field font carries its own metrics.
        HELVETICA_WIDTHS = [
          278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584,
          278, 333, 278, 278, 556, 556, 556, 556, 556, 556, 556, 556,
          556, 556, 278, 278, 584, 584, 584, 556, 1015, 667, 667, 722,
          722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
          667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278,
          278, 278, 469, 556, 333, 556, 556, 500, 556, 556, 278, 556,
          556, 222, 222, 500, 222, 833, 556, 556, 556, 556, 333, 500,
          278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
        ].freeze

        def initialize(bytes, objects, fields, font_size, font_family)
          @bytes = bytes
          @objects = objects
          @fields = fields
          @size = FormFields.body_size(font_size) - 1
          @font_family = font_family
        end

        def render
          @out = +''.b
          @out << "\n" unless @bytes.end_with?("\n")
          @offsets = {}
          @next_id = FormFields.next_id(@objects)
          add_shared
          add_fields
          add_catalog
          finish
        end

        private

        def kinds
          @kinds ||= @fields.map { |field| field[:kind] }.uniq
        end

        def alloc
          id = @next_id
          @next_id += 1
          id
        end

        def add(number, body)
          @offsets[number] = @bytes.bytesize + @out.bytesize
          @out << "#{number} 0 obj\n#{body}\nendobj\n"
        end

        def font_needed?
          kinds.intersect?(%i[text textarea select])
        end

        def add_shared
          add_font if font_needed?
          @faces = {}
          add_faces(:checkbox) { |w, h| tick(w, h) }
          add_faces(:radio) { |w, _h| dot(w) }
        end

        def add_font
          @font_id = alloc
          @field_font = FieldFont.load(@font_family)
          if @field_font
            add_embedded_font
          else
            add(@font_id, FormFields.ser(FormFields.helvetica))
          end
        end

        def add_embedded_font
          file_id = alloc
          desc_id = alloc
          add_font_file(file_id)
          add(desc_id, FormFields.ser(descriptor(file_id)))
          add(@font_id, FormFields.ser(font_dict(desc_id)))
        end

        def add_font_file(file_id)
          data = Zlib::Deflate.deflate(@field_font.bytes)
          dict = { Filter: :FlateDecode, Length: data.bytesize }
          if @field_font.open_type?
            dict[:Subtype] = :OpenType
          else
            dict[:Length1] = @field_font.bytes.bytesize
          end
          body = "#{FormFields.ser(dict)}\nstream\n#{data}\nendstream"
          add(file_id, body)
        end

        def descriptor(file_id)
          font = @field_font
          desc = {
            Type: :FontDescriptor,
            FontName: font.base_font.to_sym,
            Flags: 32,
            FontBBox: font.bbox,
            ItalicAngle: font.italic_angle,
            Ascent: font.ascent,
            Descent: font.descent,
            CapHeight: font.cap_height,
            StemV: 80,
            MissingWidth: 0,
          }
          key = font.open_type? ? :FontFile3 : :FontFile2
          desc[key] = FormFields.ref(file_id)
          desc
        end

        def font_dict(desc_id)
          {
            Type: :Font,
            Subtype: :TrueType,
            BaseFont: @field_font.base_font.to_sym,
            FirstChar: 32,
            LastChar: 255,
            Widths: @field_font.widths,
            Encoding: :WinAnsiEncoding,
            FontDescriptor: FormFields.ref(desc_id),
          }
        end

        # One on/off appearance pair serves every mark of a kind:
        # the boxes all come from one CSS rule, and a viewer scales
        # a stream's BBox to its widget's Rect anyway.
        def add_faces(kind)
          box = @fields.find { |field| field[:kind] == kind }
          return unless box

          width = box[:rect][2] - box[:rect][0]
          height = box[:rect][3] - box[:rect][1]
          on_id = alloc
          off_id = alloc
          add(on_id, stream(width, height, yield(width, height)))
          add(off_id, stream(width, height, ''))
          @faces[kind] = {
            on: FormFields.ref(on_id),
            off: FormFields.ref(off_id),
          }
        end

        # Widgets that share one manifest entry are one field seen
        # in several places: Chromium reprints a table header on
        # every page its table breaks across, so the header's
        # controls print again with the same destination. Each such
        # cluster becomes one parent field with the widgets as
        # kids, the radio-group shape, so a value edited anywhere
        # updates every appearance. Two standalone fields with one
        # name would instead go stale wherever they were not
        # edited. Radio groups cluster by group name, everything
        # else by field name.
        def add_fields
          @tops = []
          clusters.each_value do |members|
            if members.first[:kind] == :radio
              add_group(members, radio_parent(members))
            elsif members.size > 1
              unified = unify(members)
              add_group(unified, cluster_parent(unified))
            else
              add_single(members.first)
            end
          end
        end

        def unify(members)
          shared = members.first.slice(*IDENTITY)
          members.map { |member| member.except(*IDENTITY).merge(shared) }
        end

        def clusters
          @fields.group_by do |field|
            if field[:kind] == :radio
              [:radio, field[:group]]
            else
              [field[:kind], field[:name]]
            end
          end
        end

        def add_single(field)
          @tops << field[:ref]
          merged = widget_base(field)
            .merge(field_part(field))
            .merge(mark_part(field))
          add(field[:ref].id, FormFields.ser(merged))
        end

        def add_group(members, parent_dict)
          id = alloc
          parent = FormFields.ref(id)
          @tops << parent
          add(id, FormFields.ser(parent_dict))
          members.each do |field|
            kid = widget_base(field)
              .merge(Parent: parent)
              .merge(mark_part(field))
            add(field[:ref].id, FormFields.ser(kid))
          end
        end

        # The parent carries the field's identity - name, value,
        # kind - and the kids only their looks and places.
        def cluster_parent(members)
          field_part(members.first)
            .merge(Kids: members.map { |member| member[:ref] })
        end

        def radio_parent(members)
          checked = members.find { |member| member[:checked] }
          {
            FT: :Btn,
            T: members.first[:group],
            Ff: 32_768,
            V: checked ? checked[:export].to_sym : :Off,
            Kids: members.map { |member| member[:ref] },
          }
        end

        def widget_base(field)
          {
            Type: :Annot,
            Subtype: :Widget,
            F: 4,
            Rect: rect_for(field),
            P: field[:page],
            BS: { W: 0 },
          }
        end

        def field_part(field)
          part =
            case field[:kind]
            when :checkbox then checkbox_field(field)
            when :textarea then textarea_field(field)
            when :select then select_field(field)
            else text_field(field)
            end
          part[:Q] = QUADDING[field[:align]] if field[:align]
          part
        end

        def mark_part(field)
          case field[:kind]
          when :checkbox then checkbox_mark(field)
          when :radio then radio_mark(field)
          when :textarea then textarea_mark(field)
          else value_mark(field)
          end
        end

        def checkbox_field(field)
          {
            FT: :Btn,
            T: field[:name],
            V: field[:checked] ? :Yes : :Off,
          }
        end

        def checkbox_mark(field)
          state = field[:checked] ? :Yes : :Off
          faces = @faces[:checkbox]
          {
            AS: state,
            AP: { N: { Yes: faces[:on], Off: faces[:off] } },
          }
        end

        # Kids carry no name or value of their own; the parent does.
        def radio_mark(field)
          export = field[:export].to_sym
          faces = @faces[:radio]
          {
            AS: field[:checked] ? export : :Off,
            AP: { N: { export => faces[:on], Off: faces[:off] } },
          }
        end

        def text_field(field)
          {
            FT: :Tx,
            T: field[:name],
            V: pdf_text(field[:value]),
            DA: da_for(field),
          }
        end

        def textarea_field(field)
          text_field(field).merge(Ff: 4096)
        end

        # Multiline prefills wrap on the embedded font's metrics
        # and clip at the box, the way the widget itself would.
        def textarea_mark(field)
          value = pdf_text(field[:value])
          return {} if value.empty?

          x1, y1, x2, y2 = rect_for(field)
          size = size_for(field)
          lines = wrap_lines(value, x2 - x1 - 2, size)
          content = multiline_text(lines, y2 - y1, size)
          id = alloc
          add(id, stream(x2 - x1, y2 - y1, content, font: true))
          { AP: { N: FormFields.ref(id) } }
        end

        def wrap_lines(value, width, size)
          value.split("\n", -1).flat_map do |paragraph|
            wrap_paragraph(paragraph, width, size)
          end
        end

        def wrap_paragraph(paragraph, width, size)
          lines = ['']
          paragraph.split.each do |word|
            joined = lines.last.empty? ? word : "#{lines.last} #{word}"
            if text_width(joined, size) <= width
              lines[-1] = joined
            elsif text_width(word, size) <= width
              lines << word
            else
              lines.concat(hard_break(word, width, size))
            end
          end
          lines
        end

        # A word wider than the box breaks mid-word rather than
        # vanish past the edge.
        def hard_break(word, width, size)
          pieces = ['']
          word.each_char do |char|
            if text_width(pieces.last + char, size) <= width
              pieces[-1] += char
            else
              pieces << char
            end
          end
          pieces
        end

        # Lines past the box are clipped; a reader scrolls them in
        # the live field, exactly as with typed overflow.
        def multiline_text(lines, height, size)
          leading = size * 1.2
          room = (((height - size - 1) / leading).floor + 1)
            .clamp(0, lines.size)
          body = lines.first(room)
            .map { |line| "(#{FormFields.escape(line)}) Tj T*" }
            .join(' ')
          "BT /F1 #{fmt(size)} Tf #{fmt(leading)} TL " \
            "1 #{fmt(height - size)} Td #{body} ET"
        end

        # A drawn appearance for the widget's own rectangle, when
        # the field carries a value to show.
        def value_mark(field)
          ap = value_appearance(field, pdf_text(field[:value]))
          ap ? { AP: { N: ap } } : {}
        end

        def select_field(field)
          {
            FT: :Ch,
            T: field[:name],
            V: pdf_text(field[:value]),
            Opt: field[:options].map { |opt| pdf_text(opt) },
            DA: da_for(field),
            Ff: 131_072,
          }
        end

        def rect_for(field)
          x1, y1, x2, y2 = field[:rect]
          case field[:kind]
          when :text
            [x1 + TEXT_PAD_LEFT, y1 - TEXT_DROP, x2, y2 - TEXT_DROP]
          when :textarea
            [x1 + TEXTAREA_INSET, y1 + TEXTAREA_INSET,
             x2 - TEXTAREA_INSET, y2 - TEXTAREA_INSET,]
          when :select
            [x1 + SELECT_PAD_LEFT, y1, x2, y2]
          else
            field[:rect]
          end
        end

        # Prefilled values are drawn once, here, so no viewer ever
        # has to synthesize an appearance for the pristine document.
        def value_appearance(field, value)
          return nil if value.empty?

          x1, y1, x2, y2 = rect_for(field)
          size = size_for(field)
          x = text_x(field, value, x2 - x1, size)
          content = "BT /F1 #{fmt(size)} Tf #{fmt(x)} " \
                    "#{fmt(baseline(field, y2 - y1, size))} Td " \
                    "(#{FormFields.escape(value)}) Tj ET"
          id = alloc
          add(id, stream(x2 - x1, y2 - y1, content, font: true))
          FormFields.ref(id)
        end

        # A boxed control centres its text; an underline field sits
        # just above the rule, leaving descender room.
        def baseline(field, height, size)
          return (height - (size * 0.72)) / 2 if
            field[:kind] == :select

          size * 0.2
        end

        # Where a drawn value starts, honouring the field's own
        # alignment the way viewers will honour its quadding.
        def text_x(field, value, width, size)
          case field[:align]
          when :center
            [(width - text_width(value, size)) / 2, 0.5].max
          when :right
            [width - text_width(value, size) - 2, 0.5].max
          else
            0.5
          end
        end

        def text_width(value, size)
          thousandths = value.each_byte.sum { |byte| char_width(byte) }
          thousandths * size / 1000.0
        end

        def char_width(byte)
          return @field_font.width_of(byte) if @field_font

          index = byte - 32
          (0..94).cover?(index) ? HELVETICA_WIDTHS[index] : 556
        end

        def da
          @da ||= "/F1 #{fmt(@size)} Tf 0 g"
        end

        # An author-given size is used exactly; only the derived
        # default steps one point under the body.
        def da_for(field)
          size = field[:font_size]
          size ? "/F1 #{fmt(size)} Tf 0 g" : da
        end

        def size_for(field)
          field[:font_size] || @size
        end

        # Helvetica is written with WinAnsi encoding, so values are
        # transcoded to it; anything it cannot carry is replaced
        # rather than silently mangled.
        def pdf_text(value)
          text = value.to_s
          encoded = text.encode('Windows-1252',
                                invalid: :replace,
                                undef: :replace,
                                replace: '?',)
          warn "md2pdf: field text reduced to Latin script: #{text}" if encoded.include?('?') && !text.include?('?')
          encoded.force_encoding(Encoding::BINARY)
        end

        def stream(width, height, content, font: false)
          resources = {}
          resources = { Font: { F1: FormFields.ref(@font_id) } } if
            font
          dict = {
            Type: :XObject,
            Subtype: :Form,
            FormType: 1,
            BBox: [0, 0, width, height],
            Resources: resources,
            Length: content.bytesize,
          }
          "#{FormFields.ser(dict)}\nstream\n#{content}\nendstream"
        end

        def tick(width, height)
          format(
            'q %.2f w 1 J 1 j 0.15 0.15 0.15 RG ' \
            '%.2f %.2f m %.2f %.2f l %.2f %.2f l S Q',
            width * 0.12,
            width * 0.22, height * 0.52,
            width * 0.42, height * 0.28,
            width * 0.78, height * 0.72,
          )
        end

        # A filled dot approximated with four beziers; the tangent
        # runs at 0.152 of the width for a quarter circle of this
        # radius.
        def dot(width)
          mid = width * 0.5
          high = mid + (width * 0.22)
          low = mid - (width * 0.22)
          lean_up = mid + (width * 0.152)
          lean_dn = mid - (width * 0.152)
          format(
            'q 0.15 0.15 0.15 rg %.2f %.2f m ' \
            '%.2f %.2f %.2f %.2f %.2f %.2f c ' \
            '%.2f %.2f %.2f %.2f %.2f %.2f c ' \
            '%.2f %.2f %.2f %.2f %.2f %.2f c ' \
            '%.2f %.2f %.2f %.2f %.2f %.2f c f Q',
            high, mid,
            high, lean_up, lean_up, high, mid, high,
            lean_dn, high, low, lean_up, low, mid,
            low, lean_dn, lean_dn, low, mid, low,
            lean_up, low, high, lean_dn, high, mid,
          )
        end

        def fmt(number)
          format('%g', number.round(2))
        end

        def add_catalog
          root = @objects.trailer[:Root]
          catalog = @objects.deref(root).dup
          catalog[:AcroForm] = acro_form
          add(root.id, FormFields.ser(catalog))
        end

        # Kid widgets stay out of /Fields; their parents stand in.
        def acro_form
          form = { Fields: @tops }
          if @font_id
            form[:DA] = da
            form[:DR] = { Font: { F1: FormFields.ref(@font_id) } }
          end
          form
        end

        def finish
          xref_at = @bytes.bytesize + @out.bytesize
          @out << FormFields.xref_table(@offsets)
          @out << FormFields.trailer(@objects, @offsets,
                                     FormFields.prev_offset(@bytes),
                                     xref_at,)
          @out
        end
      end
    end
  end
end
