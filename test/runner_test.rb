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

  # The path is printed when the render finishes, so it has to say
  # where the file is without the reader resolving anything.
  def test_output_path_is_always_absolute
    Dir.chdir('/tmp') do
      path = Runner.output_path('doc.md', 'doc', 'out/report.pdf', nil)

      assert_equal '/tmp/out/report.pdf', path
    end
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

  # Every platform the gem supports needs its own opener: naming a
  # single tool leaves the flag doing nothing everywhere else.
  def test_knows_an_opener_for_every_supported_platform
    %i[macos linux windows].each do |os|
      command = Runner::OPENERS[os]

      refute_nil command, "no opener for #{os}"
      refute_empty command, "empty opener for #{os}"
    end
  end

  def test_uses_the_native_opener_per_platform
    assert_equal %w[open], Runner::OPENERS[:macos]
    assert_equal %w[xdg-open], Runner::OPENERS[:linux]
  end

  def test_env_override_beats_the_platform_default
    TestSupport.with_env('MD2PDF_OPENER' => 'zathura') do
      assert_equal %w[zathura], Runner.opener
    end
  end

  def test_env_override_may_carry_arguments
    TestSupport.with_env('MD2PDF_OPENER' => 'flatpak run org.x.Ev') do
      assert_equal %w[flatpak run org.x.Ev], Runner.opener
    end
  end

  def test_blank_env_override_falls_back_to_the_platform
    TestSupport.with_env('MD2PDF_OPENER' => '  ') do
      assert_equal Runner::OPENERS[:linux], Runner.opener
    end
  end

  def test_open_pdf_reports_failure_instead_of_raising
    result = nil
    _, err = capture_io do
      TestSupport.with_env('MD2PDF_OPENER' => nil) do
        Transpareo::Md2pdf::Platform.stub(:os, :plan9) do
          result = Runner.open_pdf('/tmp/whatever.pdf')
        end
      end
    end

    refute result
    assert_match(/MD2PDF_OPENER/, err)
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
