require 'erb'
require 'base64'

module Md2pdf
  module Style
    HEADER_LOGO_WIDTH_MM = 42.0
    HEADER_LOGO_HEIGHT_MM = 6.95
    FOOTER_LOGO_WIDTH_MM = 18.0
    FOOTER_LOGO_HEIGHT_MM = 2.98

    LOGO_DIR = '/home/punkrats/code/transpareo/backend/.sources/logo'
    DEFAULT_LOGO = "#{LOGO_DIR}/transpareo.svg"
    DEFAULT_LOGO_COLOR = "#{LOGO_DIR}/transpareo-color.svg"

    TEMPLATE_PATH = File.expand_path('style.css.erb', __dir__)

    module_function

    def build(logo: nil, logo_color: nil)
      logo ||= ENV['MD2PDF_LOGO'] || DEFAULT_LOGO
      logo_color ||= ENV['MD2PDF_LOGO_COLOR'] || DEFAULT_LOGO_COLOR

      header_uri = data_uri(
        logo_color, HEADER_LOGO_WIDTH_MM, HEADER_LOGO_HEIGHT_MM
      )
      footer_uri = data_uri(
        logo, FOOTER_LOGO_WIDTH_MM, FOOTER_LOGO_HEIGHT_MM, fill: '#666'
      )

      template = File.read(TEMPLATE_PATH)
      ERB.new(template, trim_mode: '-').result(binding)
    end

    def data_uri(path, width_mm, height_mm, fill: nil)
      return nil unless path && File.exist?(path)

      svg = File.read(path).sub(/<svg([^>]*)>/) do
        attrs = Regexp.last_match(1)
          .sub(/\swidth="[^"]+"/, %( width="#{width_mm}mm"))
          .sub(/\sheight="[^"]+"/, %( height="#{height_mm}mm"))
        attrs += %( fill="#{fill}") if fill
        "<svg#{attrs}>"
      end
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end
  end
end
