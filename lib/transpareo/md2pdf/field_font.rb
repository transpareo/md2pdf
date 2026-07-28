# frozen_string_literal: true

module Transpareo
  module Md2pdf
    # Loads the document's body font for embedding into form
    # fields.
    #
    # Chromium embeds only a subset of the glyphs the page used,
    # which cannot serve text a reader will type later, so the
    # field font has to be embedded whole. The file is resolved
    # through fontconfig, the same lookup Chromium's rendering went
    # through, and the metrics the appearance streams need are read
    # from the font's own tables rather than from any built-in
    # width list.
    class FieldFont
      GENERIC = %w[serif sans-serif monospace cursive fantasy
                   system-ui ui-sans-serif ui-serif].freeze

      # WinAnsi code points for byte values 32..255, resolved
      # through Ruby's Windows-1252 tables; unassigned bytes map
      # to nil.
      WINANSI = (32..255).map do |code|
        [code].pack('C').force_encoding(Encoding::Windows_1252)
          .encode(Encoding::UTF_8).ord
      rescue Encoding::UndefinedConversionError
        nil
      end.freeze

      class << self
        # The first family of the CSS stack that fontconfig
        # resolves to itself and that may legally be embedded;
        # nil, with a warning, when there is none.
        def load(font_family)
          families(font_family).each do |family|
            path = resolve(family)
            next unless path

            font = read(path)
            return font if font
          end
          warn 'md2pdf: no embeddable field font found, ' \
               'field text falls back to Helvetica'
          nil
        end

        # The CSS stack, quotes stripped, generic keywords
        # dropped: they name a preference, not a font.
        def families(font_family)
          font_family.to_s.split(',').filter_map do |name|
            name = name.strip.delete('"\'')
            next if name.empty? || GENERIC.include?(name.downcase)

            name
          end
        end

        # fc-match always answers with its best guess, so the
        # answer only counts when it actually is the requested
        # family.
        def resolve(family)
          # rubocop:disable Style/FormatStringToken
          # The template is fc-match syntax, not a Ruby format.
          out = IO.popen(
            ['fc-match', '-f', '%{family}\n%{file}', family], &:read
          )
          # rubocop:enable Style/FormatStringToken
          matched, path = out.to_s.split("\n")
          names = matched.to_s.downcase.split(',')
          names.include?(family.downcase) ? path : nil
        rescue SystemCallError
          nil
        end

        def read(path)
          font = new(File.binread(path))
          return font if font.embeddable?

          warn "md2pdf: #{File.basename(path)} forbids embedding"
          nil
        rescue StandardError => e
          warn "md2pdf: could not read #{path}: #{e.message}"
          nil
        end
      end

      attr_reader :bytes, :widths, :ascent, :descent, :italic_angle,
                  :bbox

      def initialize(bytes)
        @bytes = bytes
        @tables = parse_tables
        parse_head
        parse_hhea_hmtx
        parse_cmap
        parse_os2
        parse_post
        @widths = build_widths
      end

      # An OpenType file with PostScript outlines embeds as
      # FontFile3; a TrueType-flavoured one as FontFile2.
      def open_type?
        @open_type
      end

      # fsType bit 2 is the licence's no-embedding flag.
      def embeddable?
        @fs_type.nobits?(0x2)
      end

      def base_font
        name = postscript_name.to_s.gsub(/[^\w-]/, '')
        name.empty? ? 'EmbeddedFont' : name
      end

      def cap_height
        @cap_height || (ascent * 0.7).round
      end

      # Advance width for one WinAnsi byte, thousandths of the em.
      def width_of(byte)
        widths[byte - 32] || 0
      end

      private

      def u16(pos) = @bytes[pos, 2].unpack1('n')
      def s16(pos) = @bytes[pos, 2].unpack1('s>')
      def u32(pos) = @bytes[pos, 4].unpack1('N')

      # The table directory; for a collection, its first font.
      def parse_tables
        base = @bytes[0, 4] == 'ttcf' ? u32(12) : 0
        @open_type = @bytes[base, 4] == 'OTTO'
        count = u16(base + 4)
        (0...count).each_with_object({}) do |i, tables|
          rec = base + 12 + (i * 16)
          tables[@bytes[rec, 4]] = u32(rec + 8)
        end
      end

      def table(tag)
        @tables[tag] || raise(Error, "font lacks a #{tag} table")
      end

      def em(value)
        (value * 1000 / @units).round
      end

      def parse_head
        head = table('head')
        @units = u16(head + 18).to_f
        @bbox = [s16(head + 36), s16(head + 38),
                 s16(head + 40), s16(head + 42),].map { |v| em(v) }
      end

      def parse_hhea_hmtx
        hhea = table('hhea')
        @ascent = em(s16(hhea + 4))
        @descent = em(s16(hhea + 6))
        count = u16(hhea + 34)
        hmtx = table('hmtx')
        @advances = (0...count).map { |i| u16(hmtx + (i * 4)) }
      end

      # Glyphs past the metrics count repeat the last advance.
      def advance(gid)
        @advances[gid] || @advances.last || 0
      end

      def parse_cmap
        cmap = table('cmap')
        count = u16(cmap + 2)
        subtables = (0...count).map do |i|
          rec = cmap + 4 + (i * 8)
          [u16(rec), u16(rec + 2), cmap + u32(rec + 4)]
        end
        @cmap = pick_subtable(subtables)
        raise Error, 'font has no usable character map' unless @cmap
      end

      # Windows Unicode first, then the Unicode platforms; format
      # 4 covers the WinAnsi range, format 12 is accepted for
      # fonts that only carry the full-repertoire table.
      def pick_subtable(subtables)
        [[3, 1], [0, 3], [0, 4], [3, 10], [0, 6]].each do |plat, enc|
          hit = subtables.find { |p, e, _o| p == plat && e == enc }
          next unless hit

          fmt = u16(hit[2])
          return [fmt, hit[2]] if [4, 12].include?(fmt)
        end
        nil
      end

      def glyph_for(codepoint)
        fmt, offset = @cmap
        return glyph_fmt4(offset, codepoint) if fmt == 4

        glyph_fmt12(offset, codepoint)
      end

      def glyph_fmt4(offset, code)
        seg2 = u16(offset + 6)
        ends = offset + 14
        starts = ends + seg2 + 2
        deltas = starts + seg2
        ranges = deltas + seg2
        (0...(seg2 / 2)).each do |i|
          next if u16(ends + (i * 2)) < code

          return glyph_in_segment(code, starts + (i * 2),
                                  deltas + (i * 2), ranges + (i * 2),)
        end
        0
      end

      def glyph_in_segment(code, start_at, delta_at, range_at)
        start = u16(start_at)
        return 0 if start > code

        delta = s16(delta_at)
        range = u16(range_at)
        return (code + delta) & 0xFFFF if range.zero?

        gid = u16(range_at + range + ((code - start) * 2))
        gid.zero? ? 0 : (gid + delta) & 0xFFFF
      end

      def glyph_fmt12(offset, code)
        (0...u32(offset + 12)).each do |i|
          rec = offset + 16 + (i * 12)
          next if code > u32(rec + 4)
          return 0 if code < u32(rec)

          return u32(rec + 8) + (code - u32(rec))
        end
        0
      end

      def parse_os2
        os2 = @tables['OS/2']
        @fs_type = 0
        @cap_height = nil
        return unless os2

        @fs_type = u16(os2 + 8)
        @cap_height = em(s16(os2 + 88)) if u16(os2) >= 2
      end

      def parse_post
        post = @tables['post']
        @italic_angle = 0
        return unless post

        @italic_angle = @bytes[post + 4, 4].unpack1('l>') / 65_536.0
      end

      def postscript_name
        name = @tables['name']
        return nil unless name

        strings = name + u16(name + 4)
        (0...u16(name + 2)).each do |i|
          rec = name + 6 + (i * 12)
          next unless u16(rec + 6) == 6

          value = @bytes[strings + u16(rec + 10), u16(rec + 8)]
          return decode_name(u16(rec), value)
        end
        nil
      end

      # Windows name strings are UTF-16; Macintosh ones are close
      # enough to ASCII for a PostScript name.
      def decode_name(platform, value)
        return value if platform != 3

        value.force_encoding(Encoding::UTF_16BE)
          .encode(Encoding::UTF_8)
      end

      def build_widths
        WINANSI.map do |codepoint|
          next 0 unless codepoint

          gid = glyph_for(codepoint)
          gid.zero? ? 0 : em(advance(gid))
        end
      end
    end
  end
end
