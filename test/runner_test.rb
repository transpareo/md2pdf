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
        '/nonexistent/x.md', flat: false, unwrap: false,
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

  # Standard input

  def test_stdin_defaults_to_writing_the_pdf_to_stdout
    assert Runner.to_stdout?('-', nil, nil)
  end

  def test_an_explicit_destination_beats_stdout
    refute Runner.to_stdout?('-', '/tmp/x.pdf', nil)
    refute Runner.to_stdout?('-', nil, '/tmp/out')
  end

  def test_a_named_file_never_goes_to_stdout
    refute Runner.to_stdout?('doc.md', nil, nil)
  end

  # There is no filename to derive one from, so the heading names
  # the document instead.
  def test_stdin_names_the_document_after_its_heading
    assert_equal 'Piped', Runner.basename_for('-', "# Piped\n")
    assert_equal 'document', Runner.basename_for('-', "no heading\n")
  end

  # That heading is untrusted input on its way to a filesystem path.

  def test_a_heading_cannot_create_directories
    assert_equal 'Q3-Q4-Report', Runner.safe_basename('Q3/Q4 Report')
    assert_equal 'a-b', Runner.safe_basename('a\\b')
  end

  def test_a_heading_cannot_escape_the_output_directory
    %w[../../escaped ../.. .. ./x].each do |attempt|
      name = Runner.safe_basename(attempt)

      refute_includes name, '/'
      refute_includes name, '..'
      refute name.start_with?('.'), "#{name.inspect} is a hidden file"
    end
  end

  def test_a_heading_cannot_produce_a_hidden_file
    refute Runner.safe_basename('.hidden').start_with?('.')
    assert_equal 'document', Runner.safe_basename('...')
  end

  def test_spaces_become_dashes_so_the_name_is_shell_friendly
    assert_equal 'Quarterly-Report', Runner.safe_basename('Quarterly Report')
  end

  def test_punctuation_is_dropped_from_the_name
    assert_equal 'What-Now', Runner.safe_basename('What? "Now"!')
  end

  def test_a_very_long_heading_is_truncated
    assert_operator Runner.safe_basename('x' * 500).length, :<=,
                    Runner::MAX_BASENAME
  end

  def test_an_unusable_heading_falls_back_to_a_generic_name
    assert_equal 'document', Runner.safe_basename('///')
    assert_equal 'document', Runner.safe_basename('')
    assert_equal 'document', Runner.safe_basename(nil)
  end

  def test_non_ascii_headings_are_kept
    assert_equal 'Grüße-und-Berichte',
                 Runner.safe_basename('Grüße und Berichte')
  end

  def test_a_named_file_keeps_its_own_basename
    assert_equal 'report', Runner.basename_for('a/report.md', "# X\n")
  end

  def test_stdin_resolves_relative_assets_against_the_cwd
    assert_equal Dir.pwd, Runner.base_dir_for('-')
  end

  def test_refuses_to_write_a_pdf_to_the_terminal
    result = nil
    _, err = capture_io do
      $stdout.stub(:tty?, true) { result = Runner.emit('# x', {}) }
    end

    refute result
    assert_match(/refusing to write a PDF to the terminal/, err)
  end

  # Encoding

  # commonmarker only accepts UTF-8, and Ruby tags what it reads
  # with the locale's encoding, so a LANG=C machine would otherwise
  # fail on every document.
  def test_retags_ascii_input_as_utf8
    text = Runner.as_utf8('# Title'.dup.force_encoding('US-ASCII'))

    assert_equal Encoding::UTF_8, text.encoding
  end

  def test_keeps_valid_utf8_intact
    assert_equal 'Grüße', Runner.as_utf8('Grüße')
  end

  def test_scrubs_invalid_bytes_rather_than_crashing
    result = nil
    _, err = capture_io do
      result = Runner.as_utf8("bad \xFF byte".dup.force_encoding('BINARY'))
    end

    assert_predicate result, :valid_encoding?
    assert_match(/not valid UTF-8/, err)
  end

  # Footer title

  def test_footer_defaults_to_the_document_title
    style = Runner.with_footer_title({}, "# Quarterly Report\n\nx\n")

    assert_equal 'Quarterly Report', style[:footer_title]
  end

  def test_an_explicit_footer_title_wins
    style = Runner.with_footer_title(
      { footer_title: 'Custom' }, "# Quarterly Report\n",
    )

    assert_equal 'Custom', style[:footer_title]
  end

  # An empty string is how a caller says "no footer title", so it
  # must not be mistaken for "unset" and refilled from the heading.
  def test_an_explicit_empty_footer_title_is_respected
    style = Runner.with_footer_title(
      { footer_title: '' }, "# Quarterly Report\n",
    )

    assert_equal '', style[:footer_title]
  end

  def test_footer_title_is_nil_without_a_heading
    style = Runner.with_footer_title({}, "just a paragraph\n")

    assert_nil style[:footer_title]
  end

  def test_build_html_wraps_body_in_a_document
    html = Runner.build_html(
      "# Title\n\ntext\n",
      {
        flat: false,
        toc: false,
        toc_depth: 2,
        toc_label: nil,
        footnotes_label: nil,
        locale: 'de',
        basename: 'doc',
        css: 'body{}',
      },
      {},
    )

    assert_includes html, '<!DOCTYPE html>'
    assert_includes html, '<html lang="de">'
    assert_includes html, '<title>doc</title>'
    assert_includes html, 'body{}'
  end
end
