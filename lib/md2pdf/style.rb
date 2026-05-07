require 'erb'
require 'base64'

module Md2pdf
  module Style
    HEADER_LOGO_WIDTH_MM = 42.0
    HEADER_LOGO_HEIGHT_MM = 6.95
    FOOTER_LOGO_WIDTH_MM = 18.0
    FOOTER_LOGO_HEIGHT_MM = 2.98

    LOGO_DIR = '/home/punkrats/code/transpareo/backend/.sources/logo'
    DEFAULT_LOGO = "#{LOGO_DIR}/transpareo-color.svg"

    TEMPLATE_PATH = File.expand_path('style.css.erb', __dir__)

    DEFAULTS = {
      font_size: '11pt',
      line_height: '1.8',
      font_family: "'Plus Jakarta Sans', 'DejaVu Sans', " \
        "'Helvetica', sans-serif",
      code_font_family: "'JetBrains Mono', 'DejaVu Sans Mono', " \
        "'Menlo', monospace",
      page_size: 'A4',
      margins: '22mm 20mm 24mm 20mm',
      link_color: '#0a4a90',
      footer_grey: '#666',
      header_logo: true,
      footer_logo: true,
      page_numbers: true,
      logo: nil,
      custom_css: nil
    }.freeze

    module_function

    def build(**opts)
      cfg = DEFAULTS.merge(opts.compact)
      logo_path = cfg[:logo] || ENV['MD2PDF_LOGO'] || DEFAULT_LOGO

      header_uri = cfg[:header_logo] ? data_uri(
        logo_path, HEADER_LOGO_WIDTH_MM, HEADER_LOGO_HEIGHT_MM
      ) : nil
      footer_uri = cfg[:footer_logo] ? data_uri(
        logo_path, FOOTER_LOGO_WIDTH_MM, FOOTER_LOGO_HEIGHT_MM,
        recolor: cfg[:footer_grey]
      ) : nil

      font_size = cfg[:font_size]
      line_height = cfg[:line_height]
      font_family = cfg[:font_family]
      code_font_family = cfg[:code_font_family]
      page_size = cfg[:page_size]
      margins = cfg[:margins]
      link_color = cfg[:link_color]
      page_numbers = cfg[:page_numbers]
      custom_css = cfg[:custom_css] && File.exist?(cfg[:custom_css]) ?
        File.read(cfg[:custom_css]) : nil

      template = File.read(TEMPLATE_PATH)
      ERB.new(template, trim_mode: '-').result(binding)
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
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end

    def recolor_svg(svg, color)
      svg = svg.gsub(/fill="#[0-9a-fA-F]{3,8}"/, %(fill="#{color}"))
      svg = svg.gsub(/fill:\s*#[0-9a-fA-F]{3,8}/, "fill:#{color}")
      svg = svg.gsub(
        /stop-color:\s*#[0-9a-fA-F]{3,8}/, "stop-color:#{color}"
      )
      svg.gsub(
        /stop-color="#[0-9a-fA-F]{3,8}"/, %(stop-color="#{color}")
      )
    end
  end
end
