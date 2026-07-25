# frozen_string_literal: true

require_relative 'test_helper'

class LocalesTest < Minitest::Test
  def test_detect_reads_locale_from_filename
    assert_equal 'de', Transpareo::Md2pdf::Locales.detect('foo.de.md')
    assert_equal 'fr', Transpareo::Md2pdf::Locales.detect('docs/bar.fr.md')
  end

  def test_detect_is_case_insensitive_and_downcases
    assert_equal 'de', Transpareo::Md2pdf::Locales.detect('FOO.DE.MD')
  end

  def test_detect_ignores_unknown_suffixes
    assert_nil Transpareo::Md2pdf::Locales.detect('script.js.md')
    assert_nil Transpareo::Md2pdf::Locales.detect('plain.md')
  end

  def test_defaults_for_known_locale
    assert_equal 'Inhalt', Transpareo::Md2pdf::Locales.defaults_for('de')[:toc_label]
    assert_equal 'Quellen',
                 Transpareo::Md2pdf::Locales.defaults_for('de')[:footnotes_label]
  end

  def test_defaults_for_unknown_locale_falls_back_to_en
    assert_equal Transpareo::Md2pdf::Locales.defaults_for('en'),
                 Transpareo::Md2pdf::Locales.defaults_for('xx')
  end

  def test_known
    assert Transpareo::Md2pdf::Locales.known?('pt')
    refute Transpareo::Md2pdf::Locales.known?('xx')
  end
end
