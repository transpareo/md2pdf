# frozen_string_literal: true

require_relative 'test_helper'

class FieldFontTest < Minitest::Test
  FieldFont = Transpareo::Md2pdf::FieldFont

  def test_families_strips_quotes_and_generic_keywords
    stack = %('Plus Jakarta Sans', "DejaVu Sans", sans-serif)

    assert_equal ['Plus Jakarta Sans', 'DejaVu Sans'],
                 FieldFont.families(stack)
  end

  def test_winansi_maps_the_euro_sign
    assert_equal 0x20AC, FieldFont::WINANSI[0x80 - 32]
  end

  def test_load_warns_and_returns_nil_for_unknown_families
    font = nil
    _, err = capture_io do
      font = FieldFont.load('NoSuchFontFamily12345')
    end

    assert_nil font
    assert_match(/falls back to Helvetica/, err)
  end

  def test_reads_metrics_from_a_resolved_font
    font = resolved_font

    assert_operator font.width_of('A'.ord), :>, 200
    assert_operator font.ascent, :>, 500
    assert_equal 224, font.widths.size
    assert_predicate font, :embeddable?
    refute_empty font.base_font
  end

  def test_space_is_narrower_than_m
    font = resolved_font

    assert_operator font.width_of(' '.ord), :<,
                    font.width_of('m'.ord)
  end

  private

  # Any resolvable family serves; the suite skips on systems
  # without fontconfig or common fonts.
  def resolved_font
    candidates = ['DejaVu Sans', 'Liberation Sans', 'Noto Sans',
                  'Arial',]
    candidates.each do |family|
      font = quietly { FieldFont.load(family) }
      return font if font
    end
    skip 'no resolvable font on this system'
  end

  def quietly
    result = nil
    capture_io { result = yield }
    result
  end
end
