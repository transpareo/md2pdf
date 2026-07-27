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
    # Settings that reach the stylesheet rather than the pipeline.
    STYLE_KEYS = %i[
      font_size line_height font_family code_font_family
      page_size margins logo link_color custom_css
      header_logo footer_logo page_numbers footer_title
    ].freeze

    module_function

    # Convenience entry point for library use. Returns true when the
    # PDF was written.
    def convert(md_path, **options)
      Runner.convert(md_path, **settings(md_path, options))
    end

    # Everything Runner.convert needs for one document, resolved
    # from .md2pdf.yml, the document's front matter and the options
    # given here, in that order of increasing priority.
    #
    # The CLI goes through this too, so a flag, a config key and a
    # library argument all produce the same document.
    def settings(md_path, options = {}, text = nil)
      cfg = Config.resolve(md_path, options, text)
      custom = cfg[:locales]
      locale = cfg[:locale] || Locales.detect(md_path, custom) || 'en'
      labels = Locales.defaults_for(locale, custom)

      {
        flat: cfg.fetch(:flat, false),
        unwrap: cfg.fetch(:unwrap, false),
        toc: cfg.fetch(:toc, true),
        toc_depth: cfg.fetch(:toc_depth, 2),
        toc_label: cfg[:toc_label] || labels[:toc_label],
        toc_min: cfg.fetch(:toc_min, 3),
        toc_min_words: cfg.fetch(:toc_min_words, 1500),
        footnotes_label:
          cfg.fetch(:footnotes_label, labels[:footnotes_label]),
        locale: locale,
        output: cfg[:output],
        output_dir: cfg[:output_dir],
        open: cfg.fetch(:open, false),
        style: style_settings(cfg),
      }
    end

    def style_settings(cfg)
      STYLE_KEYS.each_with_object({}) do |key, out|
        out[key] = cfg[key] unless cfg[key].nil?
      end
    end
  end
end
