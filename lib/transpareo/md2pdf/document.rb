# frozen_string_literal: true

require 'nokogiri'

module Transpareo
  module Md2pdf
    # The parsed document as it travels through the filter chain.
    #
    # Filters mutate `fragment` in place and read whatever they need
    # from `options`, which carries the resolved settings for this
    # conversion (TOC depth, labels, resolved page numbers, ...).
    class Document
      attr_reader :fragment, :options

      def initialize(html, **options)
        @fragment = Nokogiri::HTML5.fragment(html)
        @options = options
      end

      def self.from_markdown(text, **options)
        new(Markdown.to_html(text), **options)
      end

      # The document's own title, taken from its first H1. Read
      # after parsing rather than by matching `# ` on the source, so
      # setext headings work and inline markup is reduced to text.
      # Returns nil when the document has no H1.
      def self.title_of(markdown)
        heading = Nokogiri::HTML5
          .fragment(Markdown.to_html(markdown))
          .at_css('h1')
        return nil unless heading

        text = heading.text.gsub(/\s+/, ' ').strip
        text.empty? ? nil : text
      end

      def [](key)
        @options[key]
      end

      def apply(filters)
        filters.each { |filter| filter.call(self) }
        self
      end

      def headings(levels = 1..6)
        selector = Array(levels).map { |l| "h#{l}" }.join(',')
        fragment.css(selector)
      end

      def to_html
        fragment.to_html
      end

      # Builds a detached node in this document's context, so it can
      # be spliced into the fragment.
      def build(html)
        Nokogiri::HTML5.fragment(html)
      end
    end
  end
end
