require_relative 'test_helper'

class RunnerTest < Minitest::Test
  def test_h2_count_counts_level_two_headings
    text = "# Title\n## A\n### sub\n## B\n"
    assert_equal 2, Md2pdf::Runner.h2_count(text)
  end

  def test_h2_count_ignores_headings_inside_code_fences
    text = "## A\n```\n## not a heading\n```\n## B\n"
    assert_equal 2, Md2pdf::Runner.h2_count(text)
  end

  def test_word_count_counts_alphanumeric_tokens
    assert_equal 4, Md2pdf::Runner.word_count('one two, three! four.')
  end

  def test_probe_regex_matches_marker_and_captures_id
    m = 'x [[md2pdf:foo-bar_baz]] y'.match(Md2pdf::Runner::PROBE_RE)
    assert_equal 'foo-bar_baz', m[1]
  end

  # Regression: the TOC must read heading text before code_wbr
  # rewrites inline code into raw HTML (which stringify drops),
  # otherwise code in headings vanishes from TOC entries.
  def test_toc_filter_runs_before_code_wbr
    args = build_args(flat: false, toc: true)
    assert_operator filter_index(args, Md2pdf::Runner::TOC_FILTER_PATH),
      :<, filter_index(args, Md2pdf::Runner::CODE_WBR_FILTER_PATH)
    assert_operator filter_index(args, Md2pdf::Runner::PROBE_FILTER_PATH),
      :<, filter_index(args, Md2pdf::Runner::CODE_WBR_FILTER_PATH)
  end

  def test_demote_runs_before_toc_when_flat
    args = build_args(flat: true, toc: true)
    assert_operator filter_index(args, Md2pdf::Runner::DEMOTE_FILTER_PATH),
      :<, filter_index(args, Md2pdf::Runner::TOC_FILTER_PATH)
  end

  def test_no_toc_filters_when_toc_disabled
    args = build_args(flat: false, toc: false)
    assert_nil filter_index(args, Md2pdf::Runner::TOC_FILTER_PATH)
    assert_nil filter_index(args, Md2pdf::Runner::PROBE_FILTER_PATH)
  end

  def test_no_demote_filter_when_not_flat
    args = build_args(flat: false, toc: true)
    assert_nil filter_index(args, Md2pdf::Runner::DEMOTE_FILTER_PATH)
  end

  def test_code_alias_filter_is_always_present
    args = build_args(flat: false, toc: false)
    refute_nil filter_index(args, Md2pdf::Runner::CODE_ALIAS_FILTER_PATH)
  end

  private

  # Index of a lua filter's path within the assembled args.
  def filter_index(args, path)
    args.index(path)
  end

  def build_args(flat:, toc:)
    Md2pdf::Runner.base_pandoc_args(
      md_tmp: 'in.md', css_path: 'style.css', html_tmp: 'out.html',
      basename: 'doc', flat: flat, toc: toc, toc_depth: 2,
      toc_label: nil, footnotes_label: nil, locale: nil,
      pages_file: 'pages.txt'
    )
  end
end
