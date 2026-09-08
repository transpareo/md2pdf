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

  # Hyphenation

  def test_column_alignment_from_markdown_beats_the_default
    css = with_env('MD2PDF_LOGO' => nil) { Style.build }

    assert_includes css, 'td[align="right"] { text-align: right; }'
    assert_includes css, 'td[align="center"] { text-align: center; }'
  end

  def test_hyphenation_is_on_by_default
    css = with_env('MD2PDF_LOGO' => nil) { Style.build }

    assert_includes css, 'hyphens: auto;'
    assert_includes css, 'hyphenate-limit-chars: 6 3 3;'
  end

  def test_hyphens_false_drops_every_hyphenation_rule
    css = with_env('MD2PDF_LOGO' => nil) do
      Style.build(hyphens: false)
    end

    refute_includes css, 'hyphens:'
    refute_includes css, 'hyphenate-limit-chars:'
  end

  # `hyphens` is inherited, so prose containers hand it to their
  # children. Anything holding an identifier has to opt out again
  # or the identifier acquires a hyphen that reads as its own.
  def test_identifiers_and_links_opt_out_of_hyphenation
    css = with_env('MD2PDF_LOGO' => nil) { Style.build }

    assert_includes css, "code, pre, a {\n  hyphens: none;\n}"
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
      uri = Style.data_uri(path, width: 10.0, height: 5.0)
      payload = uri.sub('data:image/svg+xml;base64,', '')

      refute_includes payload, "\n"
      assert_includes payload.unpack1('m0'), '10.0mm'
    end
  end

  def test_data_uri_is_nil_for_a_missing_file
    assert_nil Style.data_uri('/nope.svg', height: 1.0)
  end

  # Logo sizing

  def test_logos_fit_fixed_boxes_by_default
    with_svg do |path|
      header, footer = logo_svgs(Style.build(logo: path))

      assert_includes header, 'width="42.0mm" height="6.95mm"'
      assert_includes footer, 'width="18.0mm" height="2.98mm"'
    end
  end

  # With a height alone the width follows the SVG's own aspect
  # ratio, so a square icon comes out square rather than centred in
  # a wide box.
  def test_logo_height_replaces_the_box
    with_svg do |path|
      header, footer = logo_svgs(Style.build(logo: path, logo_height: 11))

      assert_includes header, 'height="11.0mm"'
      refute_match(/\swidth=/, header)
      assert_includes footer, 'width="18.0mm" height="2.98mm"'
    end
  end

  def test_footer_logo_height_sizes_the_footer_alone
    with_svg do |path|
      css = Style.build(logo: path, footer_logo_height: '4mm')
      header, footer = logo_svgs(css)

      assert_includes header, 'width="42.0mm" height="6.95mm"'
      assert_includes footer, 'height="4.0mm"'
      refute_match(/\swidth=/, footer)
    end
  end

  # An SVG without a viewBox has no aspect ratio of its own once
  # the width attribute is dropped, so one is derived from the
  # original dimensions.
  def test_height_alone_derives_a_viewbox_when_the_file_has_none
    with_svg do |path|
      header, = logo_svgs(Style.build(logo: path, logo_height: 8))

      assert_includes header, 'viewBox="0 0 10.0 10.0"'
    end
  end

  def test_height_alone_keeps_an_existing_viewbox
    svg = '<svg width="20pt" height="5pt" viewBox="0 0 4 1"></svg>'
    with_svg(svg) do |path|
      header, = logo_svgs(Style.build(logo: path, logo_height: 8))

      assert_includes header, 'viewBox="0 0 4 1"'
      assert_equal 1, header.scan('viewBox=').size
    end
  end

  def test_an_unparseable_height_warns_and_keeps_the_box
    with_svg do |path|
      header = nil
      _, err = capture_io do
        header, = logo_svgs(Style.build(logo: path, logo_height: 'tall'))
      end

      assert_match(/logo-height is not a length/, err)
      assert_includes header, 'width="42.0mm" height="6.95mm"'
    end
  end

  # Footer logo

  def test_footer_logo_names_a_file_of_its_own
    with_svg do |path|
      with_svg('<svg width="4" height="4"><rect fill="#00f"/></svg>') do |mark|
        css = Style.build(logo: path, footer_logo: mark)
        header, footer = logo_svgs(css)

        refute_equal header, footer
        assert_includes footer, '<rect fill="#666"/>'
        refute_includes footer, '#00f'
      end
    end
  end

  def test_footer_logo_false_hides_the_footer_placement
    with_svg do |path|
      css = Style.build(logo: path, footer_logo: false)

      assert_includes css, '@top-center'
      refute_includes css, '@bottom-left'
    end
  end

  def test_a_missing_footer_logo_warns_and_hides_the_placement
    with_svg do |path|
      css = nil
      _, err = capture_io do
        css = Style.build(logo: path, footer_logo: '/nope.svg')
      end

      assert_match(/logo not found/, err)
      assert_includes css, '@top-center'
      refute_includes css, '@bottom-left'
    end
  end

  def test_footer_logo_works_without_a_header_logo
    with_svg do |path|
      css = with_env('MD2PDF_LOGO' => nil) do
        Style.build(footer_logo: path)
      end

      refute_includes css, '@top-center'
      assert_includes css, '@bottom-left'
    end
  end

  # The header and footer SVGs, decoded from the stylesheet's data
  # URIs in document order.
  def logo_svgs(css)
    css.scan(%r{data:image/svg\+xml;base64,([A-Za-z0-9+/=]+)})
      .map { |(payload)| payload.unpack1('m0') }
      .reverse
  end

  def with_svg(content = SVG)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'logo.svg')
      File.write(path, content)
      yield path
    end
  end
end
