# frozen_string_literal: true

require_relative 'test_helper'

class DependenciesTest < Minitest::Test
  include TestSupport

  Dependencies = Transpareo::Md2pdf::Dependencies

  def test_home_honours_md2pdf_home
    with_env('MD2PDF_HOME' => '/custom/place') do
      assert_equal '/custom/place', Dependencies.home
    end
  end

  def test_home_falls_back_to_xdg_data_home
    with_env('MD2PDF_HOME' => nil, 'XDG_DATA_HOME' => '/xdg') do
      assert_equal '/xdg/md2pdf', Dependencies.home
    end
  end

  def test_bin_dir_sits_under_home
    with_env('MD2PDF_HOME' => '/place') do
      assert_equal '/place/bin', Dependencies.bin_dir
    end
  end

  def test_env_override_with_a_path_is_taken_verbatim
    with_env('CHROMIUM' => '/opt/my/chrome') do
      assert_equal '/opt/my/chrome', Dependencies.from_env
    end
  end

  def test_env_override_ignored_when_blank
    with_env('CHROMIUM' => '') { assert_nil Dependencies.from_env }
  end

  def test_which_finds_an_executable_on_path
    Dir.mktmpdir do |dir|
      exe = File.join(dir, 'faux-browser')
      File.write(exe, "#!/bin/sh\n")
      File.chmod(0o755, exe)

      with_env('PATH' => dir) do
        assert_equal exe, Dependencies.which('faux-browser')
      end
    end
  end

  def test_which_ignores_non_executable_files
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'faux'), 'x')

      with_env('PATH' => dir) { assert_nil Dependencies.which('faux') }
    end
  end

  def test_which_ignores_directories
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, 'chromium'))

      with_env('PATH' => dir) do
        assert_nil Dependencies.which('chromium')
      end
    end
  end

  def test_managed_directory_beats_path
    Dir.mktmpdir do |home|
      bin = File.join(home, 'bin')
      FileUtils.mkdir_p(bin)
      managed = File.join(bin, 'chrome-headless-shell')
      File.write(managed, "#!/bin/sh\n")
      File.chmod(0o755, managed)

      with_env('MD2PDF_HOME' => home, 'CHROMIUM' => nil) do
        assert_equal managed, Dependencies.chromium
      end
    end
  end

  def test_chromium_bang_raises_a_helpful_error_when_absent
    with_env('MD2PDF_HOME' => '/nope', 'CHROMIUM' => nil, 'PATH' => '') do
      error = assert_raises(
        Transpareo::Md2pdf::MissingDependencyError
      ) { Dependencies.chromium! }
      assert_match(/install-deps/, error.message)
    end
  end

  def test_status_reports_every_runtime_gem
    names = Dependencies.status.map { |row| row[:name] }

    assert_includes names, 'chromium'
    assert_includes names, 'commonmarker'
    assert_includes names, 'nokogiri'
    assert_includes names, 'rouge'
    assert_includes names, 'pdf-reader'
  end

  def test_gem_statuses_are_all_loadable
    gems = Dependencies.gem_statuses

    broken = gems.reject { |row| row[:ok] }

    assert_empty broken, "not loadable: #{broken.inspect}"
  end

  def test_install_hint_is_never_empty
    refute_empty Dependencies.install_hint
  end
end
