# frozen_string_literal: true

require_relative 'test_helper'

# Drives the real browser. Skips when no Chromium is available so the
# unit suite still runs on a bare machine.
class IntegrationTest < Minitest::Test
  include TestSupport

  SENTENCE = 'Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore.'
  LONG_BODY = ([SENTENCE] * 30).join(' ')

  def setup
    skip 'chromium not available' unless TestSupport.chromium?
  end

  def test_renders_a_pdf_next_to_the_input
    in_document(short_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }

      assert_path_exists File.join(dir, 'doc.pdf')
    end
  end

  def test_resolves_real_page_numbers_into_the_toc
    in_document(long_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }
      pdf = File.join(dir, 'doc.pdf')

      pages = Transpareo::Md2pdf::PageIndex.call(pdf)

      assert_operator pages.size, :>=, 6

      toc = page_text(pdf, 2)

      refute_includes toc, '?', 'TOC still shows placeholder pages'
      assert_includes toc.gsub(/\s+/, ''), 'Section1'
    end
  end

  def test_page_index_maps_headings_to_ascending_pages
    in_document(long_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }
      pages = Transpareo::Md2pdf::PageIndex.call(
        File.join(dir, 'doc.pdf'),
      )
      numbers = %w[section-1 section-2 section-3].map { |k| pages[k] }

      assert_equal numbers, numbers.compact.sort
    end
  end

  def test_skips_the_toc_for_a_short_document
    in_document(short_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }

      refute_includes page_text(File.join(dir, 'doc.pdf'), 1),
                      'Contents'
    end
  end

  def test_honours_an_explicit_output_path
    in_document(short_source) do |md, dir|
      out = File.join(dir, 'nested', 'custom.pdf')
      capture_io { Transpareo::Md2pdf.convert(md, output: out) }

      assert_path_exists out
    end
  end

  # PDF text extraction collapses inter-word spacing in some
  # layouts, so this compares with whitespace removed.
  def test_renders_footnotes_into_the_document
    source = "# T\n\nClaim.[^a] Same.[^a]\n\n[^a]: The source note.\n"
    in_document(source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }
      text = all_text(File.join(dir, 'doc.pdf')).gsub(/\s+/, '')

      assert_includes text, 'Thesourcenote.'
    end
  end

  def test_does_not_leak_marker_text_into_the_pdf
    in_document(long_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }

      refute_includes all_text(File.join(dir, 'doc.pdf')), 'md2pdf:'
    end
  end

  def test_missing_chromium_raises_a_helpful_error
    in_document(short_source) do |md, _dir|
      with_env('CHROMIUM' => '/definitely/not/a/browser',
               'MD2PDF_HOME' => '/nope',) do
        error = assert_raises(
          Transpareo::Md2pdf::MissingDependencyError,
        ) { capture_io { Transpareo::Md2pdf.convert(md) } }
        assert_match(/chromium/, error.message)
      end
    end
  end

  private

  def in_document(source)
    Dir.mktmpdir do |dir|
      md = File.join(dir, 'doc.md')
      File.write(md, source)
      with_env('MD2PDF_LOGO' => nil) { yield md, dir }
    end
  end

  def short_source
    "# Short\n\nJust a paragraph.\n"
  end

  def long_source
    sections = (1..8).map do |i|
      "## Section #{i}\n\n#{LONG_BODY}\n\n### Sub #{i}\n\nMore.\n"
    end
    "# Long Document\n\n*Subtitle.*\n\n#{sections.join("\n")}"
  end

  def page_text(pdf, number)
    PDF::Reader.new(pdf).pages[number - 1].text
  end

  def all_text(pdf)
    PDF::Reader.new(pdf).pages.map(&:text).join("\n")
  end
end
