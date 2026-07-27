# frozen_string_literal: true

require 'erb'

module Transpareo
  module Md2pdf
    # Builds the print stylesheet from the ERB template.
    #
    # Logos are inlined as base64 data URIs so the rendered HTML has
    # no external references. The footer logo is derived from the
    # same file as the header one by recolouring every fill to grey,
    # so branding needs a single asset rather than two.
    module Style
      HEADER_LOGO_WIDTH_MM = 42.0
      HEADER_LOGO_HEIGHT_MM = 6.95
      FOOTER_LOGO_WIDTH_MM = 18.0
      FOOTER_LOGO_HEIGHT_MM = 2.98

      TEMPLATE_PATH = File.expand_path('style.css.erb', __dir__)

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
        logo: nil,
        custom_css: nil,
        footer_title: nil,
      }.freeze

      # Keys the ERB template reads straight off the config.
      PASSTHROUGH_KEYS = %i[
        font_size line_height font_family code_font_family
        page_size margins link_color page_numbers
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
          footer_uri: footer_uri(cfg, logo),
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

        data_uri(logo, HEADER_LOGO_WIDTH_MM, HEADER_LOGO_HEIGHT_MM)
      end

      def footer_uri(cfg, logo)
        return nil unless cfg[:footer_logo] && logo

        data_uri(
          logo, FOOTER_LOGO_WIDTH_MM, FOOTER_LOGO_HEIGHT_MM,
          recolor: cfg[:footer_grey],
        )
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

      def data_uri(path, width_mm, height_mm, recolor: nil)
        return nil unless path && File.exist?(path)

        svg = File.read(path).sub(/<svg([^>]*)>/) do
          attrs = Regexp.last_match(1)
            .sub(/\swidth="[^"]+"/, %( width="#{width_mm}mm"))
            .sub(/\sheight="[^"]+"/, %( height="#{height_mm}mm"))
          attrs += %( fill="#{recolor}") if recolor
          "<svg#{attrs}>"
        end
        svg = recolor_svg(svg, recolor) if recolor
        # pack('m0') is strict base64 without the stdlib base64 gem,
        # which stopped being a default gem in Ruby 3.4.
        "data:image/svg+xml;base64,#{[svg].pack('m0')}"
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
