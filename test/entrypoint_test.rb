# frozen_string_literal: true

require_relative 'test_helper'

# One resolver backs both the CLI and the library, so a flag, a
# config key and a library argument all produce the same document.
class EntrypointTest < Minitest::Test
  Md2pdf = Transpareo::Md2pdf

  def test_fills_in_locale_derived_labels
    in_doc do |md|
      settings = Md2pdf.settings(md)

      assert_equal 'Contents', settings[:toc_label]
      assert_equal 'Footnotes', settings[:footnotes_label]
    end
  end

  def test_detects_the_locale_from_the_filename
    in_doc(name: 'report.de.md') do |md|
      settings = Md2pdf.settings(md)

      assert_equal 'de', settings[:locale]
      assert_equal 'Inhalt', settings[:toc_label]
      assert_equal 'Quellen', settings[:footnotes_label]
    end
  end

  def test_explicit_option_beats_the_filename
    in_doc(name: 'report.de.md') do |md|
      assert_equal 'fr', Md2pdf.settings(md, locale: 'fr')[:locale]
    end
  end

  def test_unknown_filename_suffix_falls_back_to_english
    in_doc(name: 'script.js.md') do |md|
      assert_equal 'en', Md2pdf.settings(md)[:locale]
    end
  end

  def test_toc_is_on_by_default
    in_doc { |md| assert Md2pdf.settings(md)[:toc] }
  end

  def test_reads_the_config_file
    in_doc(config: "font-size: 15pt\nline-height: 1.4\n") do |md|
      style = Md2pdf.settings(md)[:style]

      assert_equal '15pt', style[:font_size]
      assert_in_delta(1.4, style[:line_height])
    end
  end

  def test_reads_a_logo_from_the_config_file
    in_doc(config: "logo: /brand/logo.svg\n") do |md|
      assert_equal '/brand/logo.svg', Md2pdf.settings(md)[:style][:logo]
    end
  end

  def test_front_matter_beats_the_config_file
    body = "---\nmd2pdf:\n  font-size: 20pt\n---\n\n# T\n"

    in_doc(config: "font-size: 9pt\n", body: body) do |md|
      assert_equal '20pt', Md2pdf.settings(md)[:style][:font_size]
    end
  end

  def test_explicit_options_beat_everything
    body = "---\nmd2pdf:\n  font-size: 20pt\n---\n\n# T\n"
    in_doc(config: "font-size: 9pt\n", body: body) do |md|
      settings = Md2pdf.settings(md, font_size: '30pt')

      assert_equal '30pt', settings[:style][:font_size]
    end
  end

  # Custom localizations

  def test_config_can_override_a_built_in_locale
    config = <<~YAML
      locales:
        de:
          toc-label: Inhaltsverzeichnis
    YAML
    in_doc(name: 'r.de.md', config: config) do |md|
      settings = Md2pdf.settings(md)

      assert_equal 'Inhaltsverzeichnis', settings[:toc_label]
      # Untouched labels keep their built-in value.
      assert_equal 'Quellen', settings[:footnotes_label]
    end
  end

  def test_config_can_add_an_unknown_locale
    config = <<~YAML
      locales:
        sv:
          toc-label: Innehall
          footnotes-label: Fotnoter
    YAML
    in_doc(name: 'r.sv.md', config: config) do |md|
      settings = Md2pdf.settings(md)

      assert_equal 'sv', settings[:locale]
      assert_equal 'Innehall', settings[:toc_label]
      assert_equal 'Fotnoter', settings[:footnotes_label]
    end
  end

  def test_an_explicit_label_still_beats_a_custom_locale
    config = "locales:\n  de:\n    toc-label: Inhaltsverzeichnis\n"
    in_doc(name: 'r.de.md', config: config) do |md|
      settings = Md2pdf.settings(md, toc_label: 'Agenda')

      assert_equal 'Agenda', settings[:toc_label]
    end
  end

  def test_unknown_label_keys_in_a_locale_are_dropped
    normalized = Transpareo::Md2pdf::Config.normalize(
      'locales' => { 'de' => { 'toc-label' => 'X', 'bogus' => 'Y' } }
    )

    assert_equal({ 'de' => { toc_label: 'X' } }, normalized[:locales])
  end

  def test_a_locale_entry_that_is_not_a_hash_is_ignored
    normalized = Transpareo::Md2pdf::Config.normalize(
      'locales' => { 'de' => 'nonsense' }
    )

    assert_empty normalized[:locales]
  end

  private

  def in_doc(name: 'doc.md', config: nil, body: "# Title\n")
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.md2pdf.yml'), config) if config
      md = File.join(dir, name)
      File.write(md, body)
      yield md
    end
  end
end
