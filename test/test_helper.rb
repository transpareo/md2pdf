# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'fileutils'
require 'transpareo/md2pdf'

module TestSupport
  module_function

  # True when a usable Chromium is present. Integration tests that
  # actually render a PDF skip without one, so the unit suite still
  # runs on a bare machine.
  def chromium?
    return @chromium unless @chromium.nil?

    @chromium = !Transpareo::Md2pdf::Dependencies.chromium.nil?
  end

  # Runs markdown through the real filter chain and returns the
  # resulting HTML, with no browser involved.
  def render_html(text, **options)
    defaults = {
      toc: false,
      toc_depth: 2,
      toc_label: 'Contents',
      footnotes_label: 'Footnotes',
      toc_pages: {},
    }
    options = defaults.merge(options)
    flat = options.delete(:flat) || false
    editable = options.delete(:editable) || false
    doc = Transpareo::Md2pdf::Document.from_markdown(text, **options)
    doc.apply(
      Transpareo::Md2pdf::Filters.chain(
        flat: flat, toc: options[:toc], editable: editable,
      ),
    )
    doc.to_html
  end

  # Isolates ENV changes to the duration of the block.
  def with_env(values)
    original = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end
end
