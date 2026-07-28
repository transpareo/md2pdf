# frozen_string_literal: true

require 'pdf-reader'

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
    module FormFields
      # Text-field rectangles are inset relative to the printed box:
      # the left inset pads typed text away from the printed border,
      # and the downward shift settles the viewer's vertically
      # centred text just above the printed rule, the way writing
      # sits on a ruled line, without floating up to the box centre.
      # Checkboxes keep the printed box exactly, so the tick lands
      # inside it.
      TEXT_PAD_LEFT = 3.0
      TEXT_DROP = 0.5

      module_function

      # Rewrites the annotations named in `manifest`, the filter's
      # {destination name => field spec} record. Returns the number
      # of fields created, zero when nothing matched.
      def call(pdf_path, manifest, font_size: nil)
        return 0 if manifest.nil? || manifest.empty?

        bytes = File.binread(pdf_path)
        objects = PDF::Reader.new(pdf_path).objects
        guard(objects)

        fields = editable_annotations(objects, manifest)
        return 0 if fields.empty?

        default_da = default_appearance(font_size)
        revision = update(bytes, objects, fields, default_da)
        File.binwrite(pdf_path, bytes + revision)
        fields.size
      end

      # Both conditions are outside what Chromium produces, and
      # writing into either would corrupt more than it adds.
      def guard(objects)
        if objects.trailer[:Encrypt]
          raise Error, 'cannot add form fields to an encrypted PDF'
        end

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

      # One point under the body size, so typed text reads as part
      # of the document without crowding the box. CSS pt survive
      # printing one to one, no px scale factor involved.
      def default_appearance(font_size)
        body = font_size.to_s.to_f
        body = 11.0 unless body.positive?
        "/Helv #{format('%g', body - 1)} Tf 0 g"
      end

      # The appended revision: the shared objects each field kind
      # needs, one widget per field reusing the link's object
      # number, the catalog with the form declaration, and the
      # cross-reference section that makes them current.
      def update(bytes, objects, fields, default_da)
        out = +''
        out << "\n" unless bytes.end_with?("\n")
        offsets = {}
        add = lambda do |number, body|
          offsets[number] = bytes.bytesize + out.bytesize
          out << "#{number} 0 obj\n#{body}\nendobj\n"
        end

        ids = allocate_ids(objects, fields)
        add_objects(add, objects, fields, ids, default_da)

        xref_at = bytes.bytesize + out.bytesize
        out << xref_table(offsets)
        out << trailer(objects, offsets, prev_offset(bytes), xref_at)
      end

      # Object numbers for the shared objects: checkbox appearance
      # streams when there are checkboxes, the font when there are
      # text fields.
      def allocate_ids(objects, fields)
        kinds = fields.map { |field| field[:kind] }.uniq
        ids = {}
        id = next_id(objects)
        if kinds.include?(:checkbox)
          ids[:yes] = id
          ids[:off] = id + 1
          id += 2
        end
        ids[:font] = id if kinds.include?(:text)
        ids
      end

      def add_objects(add, objects, fields, ids, default_da)
        add_shared(add, fields, ids)
        fields.each do |field|
          add.call(field[:ref].id, ser(widget(field, ids, default_da)))
        end
        catalog = form_catalog(objects, fields, ids, default_da)
        add.call(objects.trailer[:Root].id, ser(catalog))
      end

      # The checkbox rectangles all come from one CSS rule, and a
      # viewer scales an appearance's BBox to its widget's Rect
      # anyway, so one on/off pair serves every checkbox.
      def add_shared(add, fields, ids)
        add_checkbox_appearances(add, fields, ids) if ids[:yes]
        add.call(ids[:font], ser(helvetica)) if ids[:font]
      end

      def add_checkbox_appearances(add, fields, ids)
        box = fields.find { |field| field[:kind] == :checkbox }
        width = box[:rect][2] - box[:rect][0]
        height = box[:rect][3] - box[:rect][1]
        on = appearance(width, height, tick(width, height))
        add.call(ids[:yes], on)
        add.call(ids[:off], appearance(width, height, ''))
      end

      def widget(field, ids, default_da)
        specific = if field[:kind] == :checkbox
                     checkbox_widget(field, ids)
                   else
                     text_widget(field, default_da)
                   end
        base = {
          Type: :Annot,
          Subtype: :Widget,
          F: 4,
          Rect: rect_for(field),
          P: field[:page],
        }
        base.merge(specific)
      end

      def rect_for(field)
        return field[:rect] unless field[:kind] == :text

        x1, y1, x2, y2 = field[:rect]
        [x1 + TEXT_PAD_LEFT, y1 - TEXT_DROP, x2, y2 - TEXT_DROP]
      end

      def checkbox_widget(field, ids)
        state = field[:checked] ? :Yes : :Off
        {
          FT: :Btn,
          T: field[:name],
          V: state,
          AS: state,
          AP: { N: { Yes: ref(ids[:yes]), Off: ref(ids[:off]) } },
        }
      end

      # No appearance stream: the field starts empty, and viewers
      # build the appearance from /DA once someone types.
      def text_widget(field, default_da)
        { FT: :Tx, T: field[:name], V: '', DA: default_da }
      end

      # A form XObject drawn with plain path operators, so no font
      # resources are needed. The empty variant is the unchecked
      # state: the box outline is already part of the page content,
      # printed from the filter's CSS, and stays visible under a
      # transparent appearance.
      def appearance(width, height, content)
        dict = {
          Type: :XObject,
          Subtype: :Form,
          FormType: 1,
          BBox: [0, 0, width, height],
          Resources: {},
          Length: content.bytesize,
        }
        "#{ser(dict)}\nstream\n#{content}\nendstream"
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

      def helvetica
        { Type: :Font, Subtype: :Type1, BaseFont: :Helvetica }
      end

      # The replacement catalog: everything the original said, plus
      # the form declaration listing every widget. Text fields need
      # the form-level font resource their /DA names.
      def form_catalog(objects, fields, ids, default_da)
        form = { Fields: fields.map { |field| field[:ref] } }
        if ids[:font]
          form[:DA] = default_da
          form[:DR] = { Font: { Helv: ref(ids[:font]) } }
        end
        catalog = objects.deref(objects.trailer[:Root]).dup
        catalog[:AcroForm] = form
        catalog
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
        when String then "(#{value.gsub(/[\\()]/) { |c| "\\#{c}" }})"
        when Integer, Float, true, false then value.to_s
        else raise Error, "cannot write #{value.class} into a PDF"
        end
      end

      def ref(number)
        PDF::Reader::Reference.new(number, 0)
      end
    end
  end
end
