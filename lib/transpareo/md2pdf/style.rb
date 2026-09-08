# frozen_string_literal: true

require 'erb'

module Transpareo
  module Md2pdf
    # Builds the print stylesheet from the ERB template.
    #
    # Logos are inlined as base64 data URIs so the rendered HTML has
    # no external references. The footer logo is derived from the
    # header one by recolouring every fill to grey, so branding needs
    # a single asset rather than two; a brand whose footer mark is a
    # different drawing names a second file with `footer_logo`,
    # which is recoloured the same way.
    #
    # Each placement is sized to a fixed box of roughly 6:1 unless a
    # height is given, in which case the width follows the SVG's own
    # aspect ratio and a square icon stays square.
    module Style
      HEADER_LOGO_WIDTH_MM = 42.0
      HEADER_LOGO_HEIGHT_MM = 6.95
      FOOTER_LOGO_WIDTH_MM = 18.0
      FOOTER_LOGO_HEIGHT_MM = 2.98

      TEMPLATE_PATH = File.expand_path('style.css.erb', __dir__)

      # The root element's own size attributes, replaced by the
      # placement's size.
      SIZE_ATTR_RE = /\s(width|height)="([^"]*)"/

      DEFAULTS = {
        font_size: '11pt',
        line_height: '1.8',
        font_family: "'Plus Jakarta Sans', 'DejaVu Sans', 'Helvetica', sans-serif",
        code_font_family: "'JetBrains Mono', 'DejaVu Sans Mono', 'Menlo', monospace",
        page_size: 'A4',
        margins: '22mm 20mm 24mm 20mm',
        link_color: '#0a4a90',
        footer_grey: '#666',
        header_logo: true,
        footer_logo: true,
        page_numbers: true,
        hyphens: true,
        logo: nil,
        logo_height: nil,
        footer_logo_height: nil,
        custom_css: nil,
        footer_title: nil,
      }.freeze

      # Keys the ERB template reads straight off the config.
      PASSTHROUGH_KEYS = %i[
        font_size line_height font_family code_font_family
        page_size margins link_color page_numbers hyphens
      ].freeze

      module_function

      def build(**opts)
        cfg = DEFAULTS.merge(opts.compact)
        ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
          .result_with_hash(template_locals(cfg))
      end

      # The template reads these as bare locals, so they are handed
      # over as a hash rather than through an implicit binding.
      def template_locals(cfg)
        logo = resolve_logo(cfg[:logo])
        cfg.slice(*PASSTHROUGH_KEYS).merge(
          header_uri: header_uri(cfg, logo),
          footer_uri: footer_uri(cfg, footer_logo(cfg, logo)),
          footer_title: css_string(cfg[:footer_title]),
          custom_css: read_custom_css(cfg[:custom_css]),
        )
      end

      # Quotes a value for a CSS `content` property. Returns nil for
      # anything blank so the template can omit the box entirely.
      # Newlines are folded because a margin box is a single line.
      def css_string(value)
        text = value.to_s.gsub(/\s+/, ' ').strip
        return nil if text.empty?

        %("#{text.gsub(/[\\"]/) { |char| "\\#{char}" }}")
      end

      def header_uri(cfg, logo)
        return nil unless cfg[:header_logo] && logo

        height = height_mm(cfg[:logo_height], 'logo-height')
        data_uri(
          logo,
          height: height || HEADER_LOGO_HEIGHT_MM,
          width: height ? nil : HEADER_LOGO_WIDTH_MM,
        )
      end

      def footer_uri(cfg, logo)
        return nil unless logo

        height = height_mm(cfg[:footer_logo_height], 'footer-logo-height')
        data_uri(
          logo,
          height: height || FOOTER_LOGO_HEIGHT_MM,
          width: height ? nil : FOOTER_LOGO_WIDTH_MM,
          recolor: cfg[:footer_grey],
        )
      end

      # `footer_logo` is false to hide the placement, a path to give
      # it a mark of its own, and true to derive it from the header
      # logo. A named file that is missing warns and hides the
      # placement rather than quietly falling back to the header
      # mark, which is the very thing the setting was there to
      # replace.
      def footer_logo(cfg, logo)
        case cfg[:footer_logo]
        when false, nil then nil
        when String then resolve_logo(cfg[:footer_logo])
        else logo
        end
      end

      # A height in millimetres, given as a number or as a string
      # with or without the unit. Anything else is reported and
      # ignored, so a typo costs the size rather than the document.
      def height_mm(value, name)
        return nil if value.nil? || value.to_s.strip.empty?

        mm = Float(value.to_s.strip.sub(/mm\z/, ''), exception: false)
        return mm if mm&.positive?

        warn "md2pdf: #{name} is not a length in mm, ignoring: #{value}"
        nil
      end

      # An explicit --logo wins; otherwise MD2PDF_LOGO acts as the
      # per-machine default. There is deliberately no built-in logo:
      # an unbranded document is the right default for a
      # general-purpose tool.
      def resolve_logo(configured)
        candidate = configured || ENV.fetch('MD2PDF_LOGO', nil)
        return nil if candidate.nil? || candidate.empty?
        return candidate if File.exist?(candidate)

        warn "md2pdf: logo not found, rendering without it: #{candidate}"
        nil
      end

      def read_custom_css(path)
        return nil if path.nil? || path.empty?
        return File.read(path) if File.exist?(path)

        warn "md2pdf: custom CSS not found: #{path}"
        nil
      end

      # Without a width the SVG keeps its own aspect ratio, which
      # needs a viewBox: one is derived from the file's original
      # dimensions when the file has none.
      def data_uri(path, height:, width: nil, recolor: nil)
        return nil unless path && File.exist?(path)

        svg = File.read(path).sub(/<svg([^>]*)>/) do
          attrs = sized_attrs(Regexp.last_match(1), width, height)
          attrs += %( fill="#{recolor}") if recolor
          "<svg#{attrs}>"
        end
        svg = recolor_svg(svg, recolor) if recolor
        # pack('m0') is strict base64 without the stdlib base64 gem,
        # which stopped being a default gem in Ruby 3.4.
        "data:image/svg+xml;base64,#{[svg].pack('m0')}"
      end

      def sized_attrs(attrs, width, height)
        original = attrs.scan(SIZE_ATTR_RE).to_h
        sized = attrs.gsub(SIZE_ATTR_RE, '')
        sized += %( width="#{width}mm") if width
        sized += %( height="#{height}mm")
        return sized if width || sized.include?('viewBox=')

        w = original['width'].to_f
        h = original['height'].to_f
        return sized unless w.positive? && h.positive?

        sized + %( viewBox="0 0 #{w} #{h}")
      end

      def recolor_svg(svg, color)
        svg = svg.gsub(/fill="#[0-9a-fA-F]{3,8}"/, %(fill="#{color}"))
        svg = svg.gsub(/fill:\s*#[0-9a-fA-F]{3,8}/, "fill:#{color}")
        svg = svg.gsub(
          /stop-color:\s*#[0-9a-fA-F]{3,8}/, "stop-color:#{color}",
        )
        svg.gsub(
          /stop-color="#[0-9a-fA-F]{3,8}"/, %(stop-color="#{color}"),
        )
      end
    end
  end
end
