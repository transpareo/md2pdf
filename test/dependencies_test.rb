# frozen_string_literal: true

require_relative 'test_helper'

class DependenciesTest < Minitest::Test
  include TestSupport

  Dependencies = Transpareo::Md2pdf::Dependencies
  Platform = Transpareo::Md2pdf::Platform

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
        Transpareo::Md2pdf::MissingDependencyError,
      ) { Dependencies.chromium! }
      assert_match(/install-deps/, error.message)
    end
  end

  # A file that exists and is executable is not a program that
  # runs. A downloaded Chromium carries no dependency closure, so
  # on a bare server it dies in the dynamic loader, and reporting
  # that install as healthy sends people hunting elsewhere.

  LOADER_ERROR = 'chrome-headless-shell: error while loading shared ' \
                 'libraries: libXdamage.so.1: cannot open shared object file'

  def test_a_binary_that_cannot_start_is_not_ok
    with_broken_chromium do
      row = Dependencies.chromium_status

      refute row[:ok]
      assert_match(/cannot start/, row[:problem])
    end
  end

  def test_the_failure_names_the_cause
    with_broken_chromium do
      assert_match(/libXdamage/, Dependencies.chromium_status[:problem])
    end
  end

  def test_a_broken_binary_carries_a_remedy
    with_broken_chromium do
      refute_empty Dependencies.chromium_status[:remedy].to_s
    end
  end

  def test_a_missing_binary_carries_a_different_remedy
    with_env('CHROMIUM' => '/nope', 'MD2PDF_HOME' => '/nope',
             'PATH' => '',) do
      row = Dependencies.chromium_status

      assert_equal 'not found', row[:problem]
      refute_empty row[:remedy].to_s
    end
  end

  def test_no_version_is_reported_for_a_binary_that_cannot_start
    with_broken_chromium do
      assert_nil Dependencies.chromium_status[:version]
    end
  end

  # The loader names only the first missing library, so fixing one
  # reveals the next. ldd lists them together.
  def test_every_missing_library_is_listed_not_just_the_first
    ldd = <<~LDD
      \tlinux-vdso.so.1 (0x00007ffd)
      \tlibXdamage.so.1 => not found
      \tlibc.so.6 => /usr/lib/libc.so.6 (0x00007f)
      \tlibXfixes.so.3 => not found
    LDD

    Dependencies.stub(:capture, ldd) do
      assert_equal %w[libXdamage.so.1 libXfixes.so.3],
                   Dependencies.missing_libraries('/any/binary')
    end
  end

  def test_missing_libraries_is_empty_when_ldd_is_unavailable
    Dependencies.stub(:capture, nil) do
      assert_empty Dependencies.missing_libraries('/any/binary')
    end
  end

  def test_the_problem_lists_libraries_when_ldd_can_name_them
    Dependencies.stub(:missing_libraries, %w[libA.so.1 libB.so.2]) do
      problem = Dependencies.startup_problem('/bin/x', 'some noise')

      assert_equal 'cannot start, missing libA.so.1, libB.so.2', problem
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

  def test_libraries_hint_is_never_empty
    refute_empty Dependencies.libraries_hint
  end

  # Naming the packages for the libraries actually missing, rather
  # than the whole of Chrome's closure. Two absent libraries is a
  # couple of hundred kilobytes; the full list is a page of
  # packages the machine mostly already has.

  MISSING = %w[libXdamage.so.1 libXfixes.so.3].freeze

  def test_debian_family_gets_the_two_packages_it_needs
    %i[debian ubuntu].each do |family|
      Platform.stub(:linux_family, family) do
        assert_equal 'sudo apt install libxdamage1 libxfixes3',
                     Dependencies.libraries_hint(MISSING)
      end
    end
  end

  def test_arch_lowercases_the_library_name
    Platform.stub(:linux_family, :arch) do
      assert_equal 'sudo pacman -S libxdamage libxfixes',
                   Dependencies.libraries_hint(MISSING)
    end
  end

  def test_fedora_keeps_the_library_capitalisation
    Platform.stub(:linux_family, :fedora) do
      assert_equal 'sudo dnf install libXdamage libXfixes',
                   Dependencies.libraries_hint(MISSING)
    end
  end

  def test_an_unknown_distro_still_names_the_libraries
    Platform.stub(:linux_family, :unknown) do
      hint = Dependencies.libraries_hint(MISSING)

      assert_match(/libXdamage\.so\.1/, hint)
    end
  end

  # The installer runs this, so it is argv rather than a sentence
  # to be split apart again.
  def test_the_command_is_built_as_arguments
    Platform.stub(:linux_family, :debian) do
      assert_equal %w[sudo apt install libxdamage1 libxfixes3],
                   Dependencies.library_command(MISSING)
    end
  end

  def test_there_is_no_command_for_a_distro_with_no_mapping
    Platform.stub(:linux_family, :unknown) do
      assert_nil Dependencies.library_command(MISSING)
    end
  end

  def test_there_is_no_command_when_nothing_is_missing
    Platform.stub(:linux_family, :debian) do
      assert_nil Dependencies.library_command([])
    end
  end

  # Debian names a library package after its soname, with enough
  # exceptions in Chrome's closure to be worth listing.
  def test_soname_maps_to_a_debian_package
    {
      'libXdamage.so.1' => 'libxdamage1',
      'libXfixes.so.3' => 'libxfixes3',
      'libgbm.so.1' => 'libgbm1',
      'libxkbcommon.so.0' => 'libxkbcommon0',
    }.each do |soname, package|
      assert_equal package, Dependencies.debian_package(soname)
    end
  end

  def test_the_exceptions_to_that_rule_are_handled
    {
      'libnss3.so' => 'libnss3',
      'libatk-1.0.so.0' => 'libatk1.0-0',
      'libX11.so.6' => 'libx11-6',
      'libcups.so.2' => 'libcups2',
      'libplc4.so' => 'libnspr4',
    }.each do |soname, package|
      assert_equal package, Dependencies.debian_package(soname)
    end
  end

  def test_duplicate_packages_are_listed_once
    sonames = %w[libnss3.so libnssutil3.so libsmime3.so]

    Platform.stub(:linux_family, :debian) do
      assert_equal 'sudo apt install libnss3',
                   Dependencies.libraries_hint(sonames)
    end
  end

  # Ubuntu has no chromium package, and its chromium-browser is a
  # shim that installs snapd plus a confined browser that cannot
  # read the temporary files md2pdf hands it.
  def test_ubuntu_is_not_told_to_apt_install_chromium
    Platform.stub(:linux_family, :ubuntu) do
      Platform.stub(:os, :linux) do
        hint = Dependencies.install_hint

        refute_match(/apt install chromium/, hint)
        assert_match(/install-deps/, hint)
      end
    end
  end

  def test_debian_is_still_told_to_apt_install_chromium
    Platform.stub(:linux_family, :debian) do
      Platform.stub(:os, :linux) do
        assert_equal 'sudo apt install chromium', Dependencies.install_hint
      end
    end
  end

  private

  # A Chromium that exists and is executable but exits the way the
  # dynamic loader does when a shared library is absent.
  def with_broken_chromium
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'chrome-headless-shell')
      File.write(path, "#!/bin/sh\necho '#{LOADER_ERROR}' >&2\nexit 127\n")
      File.chmod(0o755, path)
      with_env('CHROMIUM' => path) { yield path }
    end
  end
end
