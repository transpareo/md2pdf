# frozen_string_literal: true

require_relative 'test_helper'

class RunnerTest < Minitest::Test
  Runner = Transpareo::Md2pdf::Runner

  def test_h2_count_counts_level_two_headings
    assert_equal 2, Runner.h2_count("# T\n## A\n### sub\n## B\n")
  end

  def test_h2_count_ignores_headings_inside_code_fences
    text = "## A\n```\n## not a heading\n```\n## B\n"

    assert_equal 2, Runner.h2_count(text)
  end

  def test_word_count_counts_alphanumeric_tokens
    assert_equal 4, Runner.word_count('one two, three! four.')
  end

  def test_output_path_defaults_next_to_input
    path = Runner.output_path('/tmp/a/doc.md', 'doc', nil, nil)

    assert_equal '/tmp/a/doc.pdf', path
  end

  def test_output_path_honours_explicit_output
    path = Runner.output_path('/tmp/a/doc.md', 'doc', '/x/y.pdf', nil)

    assert_equal '/x/y.pdf', path
  end

  def test_output_path_honours_output_dir
    path = Runner.output_path('/tmp/a/doc.md', 'doc', nil, '/out')

    assert_equal '/out/doc.pdf', path
  end

  def test_convert_reports_missing_input_without_raising
    result = nil
    _, err = capture_io do
      result = Runner.convert(
        '/nonexistent/x.md', flat: false, unwrap: false
      )
    end

    refute result
    assert_match(/not found/, err)
  end

  def test_build_html_wraps_body_in_a_document
    html = Runner.build_html(
      "# Title\n\ntext\n",
      { flat: false, toc: false, toc_depth: 2, toc_label: nil,
        footnotes_label: nil, locale: 'de', basename: 'doc',
        css: 'body{}' },
      {}
    )

    assert_includes html, '<!DOCTYPE html>'
    assert_includes html, '<html lang="de">'
    assert_includes html, '<title>doc</title>'
    assert_includes html, 'body{}'
  end
end
