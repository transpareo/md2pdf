# frozen_string_literal: true

require_relative 'test_helper'

class FiltersTest < Minitest::Test
  include TestSupport

  Filters = Transpareo::Md2pdf::Filters

  def test_chain_puts_demote_before_toc
    chain = Filters.chain(flat: true, toc: true)

    assert_operator chain.index(Filters::Demote), :<,
                    chain.index(Filters::Toc)
  end

  def test_chain_puts_toc_before_code_wbr
    chain = Filters.chain(flat: false, toc: true)

    assert_operator chain.index(Filters::Toc), :<,
                    chain.index(Filters::CodeWbr)
  end

  def test_chain_omits_toc_filters_when_disabled
    chain = Filters.chain(flat: false, toc: false)

    assert_nil chain.index(Filters::Toc)
  end

  def test_chain_omits_demote_when_not_flat
    chain = Filters.chain(flat: false, toc: true)

    assert_nil chain.index(Filters::Demote)
  end

  # Slugs

  def test_assigns_unique_heading_ids
    html = render_html("## Alpha\n\n## Alpha\n")

    assert_includes html, 'id="alpha"'
    assert_includes html, 'id="alpha-1"'
  end

  def test_slugifies_punctuation_away
    assert_includes render_html("## Hello, World!\n"),
                    'id="hello-world"'
  end

  # Demote

  def test_demote_turns_h2_into_bold_paragraph
    html = render_html("## Section\n", flat: true)

    assert_includes html, '<strong>Section</strong>'
    refute_includes html, '<h2'
  end

  def test_demote_turns_h3_into_bold_italic
    html = render_html("### Deep\n", flat: true)

    assert_includes html, '<strong><em>Deep</em></strong>'
  end

  # Title page

  def test_wraps_title_when_toc_and_no_intro
    html = render_html("# T\n\nlead\n\n## S\n", toc: true)

    assert_includes html, 'class="title-page"'
  end

  def test_no_title_wrap_without_toc
    refute_includes render_html("# T\n\n## S\n", toc: false),
                    'title-page'
  end

  def test_no_title_wrap_when_intro_present
    src = "# T\n\n::: intro\n\nhi\n\n:::\n\n## S\n"

    refute_includes render_html(src, toc: true), 'title-page'
  end

  # TOC

  def test_toc_lists_headings_with_placeholder_pages
    html = render_html("# T\n\n## A\n\n### B\n", toc: true)

    assert_includes html, 'id="TOC"'
    assert_includes html, '<span class="toc-page">?</span>'
  end

  def test_toc_uses_resolved_page_numbers
    html = render_html(
      "# T\n\n## A\n", toc: true, toc_pages: { 'a' => 4 }
    )

    assert_includes html, '<span class="toc-page">4</span>'
  end

  def test_toc_depth_one_excludes_h3
    html = render_html("## A\n\n### B\n", toc: true, toc_depth: 1)

    refute_includes html, 'toc-l3'
  end

  def test_toc_depth_three_includes_h4
    html = render_html(
      "## A\n\n### B\n\n#### C\n", toc: true, toc_depth: 3
    )

    assert_includes html, 'toc-l4'
  end

  def test_toc_escapes_heading_text
    html = render_html("## A & <b>\n", toc: true)

    assert_includes html, '&amp;'
    refute_includes html, '<span class="toc-text">A & <b>'
  end

  def test_no_marker_text_is_injected_into_headings
    html = render_html("## Alpha\n", toc: true)

    refute_includes html, 'md2pdf:'
    assert_includes html, '<h2 id="alpha">Alpha</h2>'
  end

  # Code

  def test_highlights_fenced_code
    html = render_html("```ruby\ndef a; end\n```\n")

    assert_includes html, 'style="color'
  end

  def test_leaves_unknown_language_unhighlighted
    html = render_html("```notalanguage\nplain\n```\n")

    refute_includes html, 'style="color'
    assert_includes html, 'plain'
  end

  def test_injects_wbr_into_inline_code
    html = render_html("`a/b_cD`\n")

    assert_includes html, 'a/<wbr>b_<wbr>c<wbr>D'
  end

  def test_does_not_touch_code_inside_pre
    refute_includes render_html("```\na/b\n```\n"), '<wbr>'
  end

  def test_escapes_html_in_inline_code
    assert_includes render_html("`<script>`\n"), '&lt;script&gt;'
  end

  # Tables

  def test_wraps_tables
    html = render_html("| a |\n|---|\n| 1 |\n")

    assert_includes html, '<div class="table-wrap">'
  end

  def test_wraps_header_words_individually
    html = render_html("| one two |\n|---|\n| x |\n")

    assert_equal 2, html.scan('class="nobr"').size
  end

  # Footnotes

  def test_merges_footnotes_with_identical_text
    src = "a[^x] b[^y]\n\n[^x]: Same text.\n[^y]: Same text.\n"
    html = render_html(src)

    assert_equal 1, html.scan('role="doc-endnote"').size
  end

  def test_keeps_distinct_footnotes_separate
    src = "a[^x] b[^y]\n\n[^x]: One.\n[^y]: Two.\n"

    assert_equal 2, render_html(src).scan('role="doc-endnote"').size
  end

  def test_numbers_footnotes_in_reference_order
    src = "a[^x] b[^y]\n\n[^x]: One.\n[^y]: Two.\n"
    html = render_html(src)

    assert_match(/href="#fn1"[^>]*>1</, html)
    assert_match(/href="#fn2"[^>]*>2</, html)
  end

  def test_consumes_trailing_manual_footnotes_heading
    src = "a[^x]\n\n## Footnotes\n\n[^x]: One.\n"
    html = render_html(src)

    assert_equal 1, html.scan('Footnotes').size
  end

  def test_omits_heading_when_label_blank
    src = "a[^x]\n\n[^x]: One.\n"
    html = render_html(src, footnotes_label: '')

    refute_includes html, 'footnotes-title'
    assert_includes html, 'footnotes-section'
  end

  def test_no_footnote_section_without_references
    refute_includes render_html("plain text\n"), 'footnotes-section'
  end
end
