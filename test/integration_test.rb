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

  def test_editable_creates_fillable_checkbox_fields
    in_document(tasks_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md, editable: true) }
      fields = fields_of(File.join(dir, 'doc.pdf'))

      assert_equal(%w[checkbox-1 checkbox-2],
                   fields.map { |f| f[:T] },)
      assert_equal(%i[Off Yes], fields.map { |f| f[:V] })
      fields.each do |field|
        assert_equal :Widget, field[:Subtype]
        assert_operator field[:Rect][2] - field[:Rect][0], :>, 5
      end
    end
  end

  def test_editable_creates_text_fields_from_raw_inputs
    source = "# Form\n\nName: <input type=\"text\" size=\"30\">\n"
    in_document(source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md, editable: true) }
      fields = fields_of(File.join(dir, 'doc.pdf'))

      assert_equal(['text-1'], fields.map { |f| f[:T] })
      assert_equal :Tx, fields.first[:FT]
      assert_includes fields.first[:DA], 'Helv'
      assert_operator fields.first[:Rect][2] - fields.first[:Rect][0],
                      :>, 100
    end
  end

  def test_editable_defaults_to_a_static_document
    in_document(tasks_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md) }

      assert_empty fields_of(File.join(dir, 'doc.pdf'))
    end
  end

  def test_editable_without_inputs_appends_nothing
    in_document(short_source) do |md, dir|
      capture_io { Transpareo::Md2pdf.convert(md, editable: true) }
      pdf = File.join(dir, 'doc.pdf')

      assert_empty fields_of(pdf)
      assert_includes all_text(pdf).gsub(/\s+/, ''), 'Justaparagraph.'
    end
  end

  def test_editable_falls_back_to_static_when_injection_fails
    in_document(tasks_source) do |md, dir|
      boom = lambda do |_pdf|
        raise Transpareo::Md2pdf::Error, 'no room at the inn'
      end
      err = Transpareo::Md2pdf::FormFields.stub(:call, boom) do
        capture_io do
          Transpareo::Md2pdf.convert(md, editable: true)
        end[1]
      end
      pdf = File.join(dir, 'doc.pdf')

      assert_match(/static document/, err)
      assert_empty fields_of(pdf)
      assert_includes all_text(pdf), 'done'
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

  def tasks_source
    "# Tasks\n\n- [ ] open\n- [x] done\n"
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

  # The form's field dictionaries, in declaration order; empty when
  # the document declares no form at all.
  def fields_of(pdf)
    objects = PDF::Reader.new(pdf).objects
    catalog = objects.deref(objects.trailer[:Root])
    form = objects.deref(catalog[:AcroForm])
    return [] unless form

    Array(objects.deref(form[:Fields])).map { |f| objects.deref(f) }
  end
end
