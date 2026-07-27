# frozen_string_literal: true

require_relative 'test_helper'

class StyleTest < Minitest::Test
  include TestSupport

  Style = Transpareo::Md2pdf::Style

  SVG = '<svg width="10" height="10"><path fill="#ff0000"/></svg>'

  def test_builds_css_with_the_configured_values
    css = with_env('MD2PDF_LOGO' => nil) do
      Style.build(font_size: '13pt', link_color: '#abcdef')
    end

    assert_includes css, '13pt'
    assert_includes css, '#abcdef'
  end

  def test_renders_without_a_logo_by_default
    css = with_env('MD2PDF_LOGO' => nil) { Style.build }

    refute_includes css, 'data:image/svg+xml'
  end

  def test_uses_md2pdf_logo_from_the_environment
    with_svg do |path|
      css = with_env('MD2PDF_LOGO' => path) { Style.build }

      assert_includes css, 'data:image/svg+xml;base64,'
    end
  end

  def test_explicit_logo_beats_the_environment
    with_svg do |path|
      css = with_env('MD2PDF_LOGO' => '/nope.svg') do
        Style.build(logo: path)
      end

      assert_includes css, 'data:image/svg+xml;base64,'
    end
  end

  def test_warns_and_continues_when_the_logo_is_missing
    css = nil
    _, err = capture_io do
      css = with_env('MD2PDF_LOGO' => nil) do
        Style.build(logo: '/definitely/not/here.svg')
      end
    end

    assert_match(/logo not found/, err)
    refute_includes css, 'data:image/svg+xml'
  end

  def test_appends_custom_css
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'extra.css')
      File.write(path, '.mine { color: red; }')
      css = with_env('MD2PDF_LOGO' => nil) do
        Style.build(custom_css: path)
      end

      assert_includes css, '.mine { color: red; }'
    end
  end

  def test_warns_when_custom_css_is_missing
    _, err = capture_io do
      with_env('MD2PDF_LOGO' => nil) do
        Style.build(custom_css: '/nope.css')
      end
    end

    assert_match(/custom CSS not found/, err)
  end

  # Footer title

  def test_no_footer_title_box_by_default
    css = with_env('MD2PDF_LOGO' => nil) { Style.build }

    refute_includes css, '@bottom-center'
  end

  def test_renders_a_footer_title_between_logo_and_page_number
    css = with_env('MD2PDF_LOGO' => nil) do
      Style.build(footer_title: 'Quarterly Report')
    end

    assert_includes css, '@bottom-center'
    assert_includes css, 'content: "Quarterly Report";'
  end

  def test_footer_title_escapes_quotes_and_backslashes
    assert_equal '"a \\"b\\" c"', Style.css_string('a "b" c')
    assert_equal '"a \\\\ b"', Style.css_string('a \\ b')
  end

  def test_footer_title_folds_newlines_onto_one_line
    assert_equal '"one two"', Style.css_string("one\n  two")
  end

  def test_blank_footer_title_is_treated_as_absent
    assert_nil Style.css_string('   ')
    assert_nil Style.css_string(nil)
  end

  def test_footer_logo_is_recoloured_to_grey
    recoloured = Style.recolor_svg(SVG, '#666')

    assert_includes recoloured, 'fill="#666"'
    refute_includes recoloured, '#ff0000'
  end

  def test_data_uri_is_strict_base64
    with_svg do |path|
      uri = Style.data_uri(path, 10.0, 5.0)
      payload = uri.sub('data:image/svg+xml;base64,', '')

      refute_includes payload, "\n"
      assert_includes payload.unpack1('m0'), '10.0mm'
    end
  end

  def test_data_uri_is_nil_for_a_missing_file
    assert_nil Style.data_uri('/nope.svg', 1.0, 1.0)
  end

  def with_svg
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'logo.svg')
      File.write(path, SVG)
      yield path
    end
  end
end
