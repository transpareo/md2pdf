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
      # Default appearance for text fields, required by the spec.
      # Helvetica is one of the base fonts every viewer carries.
      TEXT_DA = '/Helv 10 Tf 0 g'

      module_function

      # Returns the number of fields created, zero when the PDF has
      # no editable annotations.
      def call(pdf_path)
        bytes = File.binread(pdf_path)
        objects = PDF::Reader.new(pdf_path).objects
        guard(objects)

        fields = editable_annotations(objects)
        return 0 if fields.empty?

        File.binwrite(pdf_path, bytes + update(bytes, objects, fields))
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
      # with the page it sits on and what its name encodes.
      def editable_annotations(objects)
        objects.page_references.flat_map do |page_ref|
          page = objects.deref(page_ref)
          Array(objects.deref(page[:Annots])).filter_map do |ref|
            next unless ref.is_a?(PDF::Reader::Reference)

            field_from(objects.deref(ref), ref, page_ref)
          end
        end
      end

      def field_from(annot, ref, page_ref)
        dest = annot[:Dest].to_s
        base = { ref: ref, page: page_ref, rect: annot[:Rect] }
        if (m = Filters::EditableFields::CHECKBOX_RE.match(dest))
          base.merge(kind: :checkbox, number: m[1].to_i,
                     checked: !m[2].nil?,)
        elsif (m = Filters::EditableFields::TEXT_RE.match(dest))
          base.merge(kind: :text, number: m[1].to_i)
        end
      end

      # The appended revision: the shared objects each field kind
      # needs, one widget per field reusing the link's object
      # number, the catalog with the form declaration, and the
      # cross-reference section that makes them current.
      def update(bytes, objects, fields)
        out = +''
        out << "\n" unless bytes.end_with?("\n")
        offsets = {}
        add = lambda do |number, body|
          offsets[number] = bytes.bytesize + out.bytesize
          out << "#{number} 0 obj\n#{body}\nendobj\n"
        end

        add_objects(add, objects, fields, allocate_ids(objects, fields))

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

      def add_objects(add, objects, fields, ids)
        add_shared(add, fields, ids)
        fields.each do |field|
          add.call(field[:ref].id, ser(widget(field, ids)))
        end
        add.call(objects.trailer[:Root].id,
                 ser(form_catalog(objects, fields, ids)),)
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
        add.call(ids[:yes],
                 appearance(width, height, tick(width, height)),)
        add.call(ids[:off], appearance(width, height, ''))
      end

      def widget(field, ids)
        specific = if field[:kind] == :checkbox
                     checkbox_widget(field, ids)
                   else
                     text_widget(field)
                   end
        {
          Type: :Annot, Subtype: :Widget, F: 4,
          Rect: field[:rect], P: field[:page],
        }.merge(specific)
      end

      def checkbox_widget(field, ids)
        state = field[:checked] ? :Yes : :Off
        {
          FT: :Btn, T: "checkbox-#{field[:number]}",
          V: state, AS: state,
          AP: { N: { Yes: ref(ids[:yes]), Off: ref(ids[:off]) } },
        }
      end

      # No appearance stream: the field starts empty, and viewers
      # build the appearance from /DA once someone types.
      def text_widget(field)
        { FT: :Tx, T: "text-#{field[:number]}", V: '', DA: TEXT_DA }
      end

      # A form XObject drawn with plain path operators, so no font
      # resources are needed. The empty variant is the unchecked
      # state: the box outline is already part of the page content,
      # printed from the filter's CSS, and stays visible under a
      # transparent appearance.
      def appearance(width, height, content)
        dict = ser(
          Type: :XObject, Subtype: :Form, FormType: 1,
          BBox: [0, 0, width, height],
          Resources: {}, Length: content.bytesize,
        )
        "#{dict}\nstream\n#{content}\nendstream"
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
      def form_catalog(objects, fields, ids)
        form = { Fields: fields.map { |field| field[:ref] } }
        if ids[:font]
          form[:DA] = TEXT_DA
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
