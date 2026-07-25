# frozen_string_literal: true

require_relative 'md2pdf/version'
require_relative 'md2pdf/errors'
require_relative 'md2pdf/platform'
require_relative 'md2pdf/dependencies'
require_relative 'md2pdf/locales'
require_relative 'md2pdf/config'
require_relative 'md2pdf/unwrap'
require_relative 'md2pdf/markdown'
require_relative 'md2pdf/highlighter'
require_relative 'md2pdf/document'
require_relative 'md2pdf/filters'
require_relative 'md2pdf/renderer'
require_relative 'md2pdf/page_index'
require_relative 'md2pdf/style'
require_relative 'md2pdf/runner'
require_relative 'md2pdf/installer'
require_relative 'md2pdf/cli'

module Transpareo
  # Converts markdown to PDF by rendering through a headless browser,
  # so tables, code blocks and CSS behave the way they do on the web
  # rather than the way a bespoke PDF engine guesses.
  module Md2pdf
    DEFAULT_OPTIONS = { flat: false, unwrap: false, toc: true }.freeze

    module_function

    # Convenience entry point for library use. Returns true when the
    # PDF was written.
    def convert(md_path, **options)
      Runner.convert(md_path, **DEFAULT_OPTIONS, **options)
    end
  end
end
