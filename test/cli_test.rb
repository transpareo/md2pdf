# frozen_string_literal: true

require_relative 'test_helper'

class CLITest < Minitest::Test
  CLI = Transpareo::Md2pdf::CLI

  def test_assign_toc_depth_also_enables_toc
    opts = {}
    CLI.assign(opts, :toc_depth_int, '3')

    assert_equal 3, opts[:toc_depth]
    assert opts[:toc]
  end

  def test_assign_coerces_integer_flags
    opts = {}
    CLI.assign(opts, :toc_min_int, '5')
    CLI.assign(opts, :toc_min_words_int, '900')

    assert_equal 5, opts[:toc_min]
    assert_equal 900, opts[:toc_min_words]
  end

  def test_assign_passes_other_keys_through
    opts = {}
    CLI.assign(opts, :locale, 'de')

    assert_equal 'de', opts[:locale]
  end

  def test_filter_markdown_drops_non_markdown
    out = nil
    _, err = capture_io do
      out = CLI.filter_markdown(%w[a.md b.txt c.MD d.pdf])
    end

    assert_equal %w[a.md c.MD], out
    assert_match(/b\.txt/, err)
    assert_match(/d\.pdf/, err)
  end

  def test_parse_reads_inline_and_separate_values
    opts, files, = CLI.parse(%w[--font-size=13pt --locale de a.md])

    assert_equal '13pt', opts[:font_size]
    assert_equal 'de', opts[:locale]
    assert_equal %w[a.md], files
  end

  def test_parse_handles_negating_flags
    opts, = CLI.parse(%w[--no-toc --no-page-numbers])

    refute opts[:toc]
    refute opts[:page_numbers]
  end

  def test_toc_flag_clears_the_auto_skip_thresholds
    opts, = CLI.parse(%w[--toc])

    assert opts[:toc]
    assert_equal 0, opts[:toc_min]
    assert_equal 0, opts[:toc_min_words]
  end

  def test_an_explicit_threshold_after_toc_still_wins
    opts, = CLI.parse(%w[--toc --toc-min=4])

    assert_equal 4, opts[:toc_min]
  end

  def test_single_heading_is_an_alias_for_flat
    opts, = CLI.parse(%w[--single-heading])

    assert opts[:flat]
  end

  def test_parse_accepts_an_empty_value
    opts, = CLI.parse(['--footnotes-label='])

    assert_equal '', opts[:footnotes_label]
  end

  def test_parse_rejects_an_unknown_option
    opts = nil
    _, err = capture_io { opts, = CLI.parse(%w[--nonsense]) }

    assert_nil opts
    assert_match(/unknown option/, err)
  end

  def test_parse_rejects_an_unknown_assignment_flag
    opts = nil
    _, err = capture_io { opts, = CLI.parse(%w[--nope=1]) }

    assert_nil opts
    assert_match(/unknown option/, err)
  end

  def test_parse_rejects_a_value_flag_without_a_value
    opts = nil
    _, err = capture_io { opts, = CLI.parse(%w[--locale]) }

    assert_nil opts
    assert_match(/needs a value/, err)
  end

  def test_run_returns_usage_error_for_a_bad_option
    status = nil
    capture_io { status = CLI.run(%w[--nonsense]) }

    assert_equal CLI::USAGE_ERROR, status
  end

  def test_run_returns_ok_for_help
    status = nil
    out, = capture_io { status = CLI.run(%w[--help]) }

    assert_equal CLI::OK, status
    assert_match(/Convert markdown to PDF/, out)
  end

  def test_run_reports_version
    status = nil
    out, = capture_io { status = CLI.run(%w[--version]) }

    assert_equal CLI::OK, status
    assert_match(/md2pdf #{Transpareo::Md2pdf::VERSION}/, out)
  end

  def test_run_fails_when_no_markdown_is_found
    status = nil
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { capture_io { status = CLI.run([]) } }
    end

    assert_equal CLI::FAILURE, status
  end

  def test_run_rejects_open_with_multiple_files
    status = nil
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'a.md'), '# a')
      File.write(File.join(dir, 'b.md'), '# b')
      Dir.chdir(dir) { capture_io { status = CLI.run(%w[--open]) } }
    end

    assert_equal CLI::USAGE_ERROR, status
  end

  def test_expand_args_sorts_glob_matches
    Dir.mktmpdir do |dir|
      %w[b.md a.md].each { |n| File.write(File.join(dir, n), 'x') }

      Dir.chdir(dir) do
        assert_equal %w[a.md b.md], CLI.expand_args(['*.md'])
      end
    end
  end

  def test_expand_args_warns_when_a_glob_matches_nothing
    _, err = capture_io { CLI.expand_args(['nope/*.md']) }

    assert_match(/no files match/, err)
  end

  # Documentation drift is the failure mode here: a flag gets added
  # and only the person who added it knows about it.
  def test_every_flag_appears_in_the_help_text
    undocumented = all_flags.reject { |flag| CLI::HELP.include?(flag) }

    assert_empty undocumented, "not in --help: #{undocumented.inspect}"
  end

  def test_every_flag_appears_in_the_readme
    readme = File.read(File.expand_path('../README.md', __dir__))
    undocumented = all_flags.reject { |flag| readme.include?(flag) }

    assert_empty undocumented, "not in README: #{undocumented.inspect}"
  end

  def test_every_config_key_appears_in_the_readme
    readme = File.read(File.expand_path('../README.md', __dir__))
    keys = Transpareo::Md2pdf::Config::KEYS.map { |k| k.to_s.tr('_', '-') }
    undocumented = keys.reject { |key| readme.include?(key) }

    assert_empty undocumented, "not in README: #{undocumented.inspect}"
  end

  def test_doctor_line_marks_missing_dependencies
    row = { name: 'chromium', ok: false, problem: 'not found',
            version: nil, path: nil }

    assert_match(/MISS/, CLI.doctor_line(row, 8))
  end

  def test_doctor_line_marks_present_dependencies
    row = { name: 'rouge', ok: true, problem: nil,
            version: '4.2.0', path: 'gem' }
    line = CLI.doctor_line(row, 8)

    assert_match(/ok/, line)
    assert_match(/4\.2\.0/, line)
  end

  private

  def all_flags
    CLI::BOOL_FLAGS.keys + CLI::VALUE_FLAGS.keys +
      %w[-h --help -v --version doctor install-deps --latest --force]
  end
end
