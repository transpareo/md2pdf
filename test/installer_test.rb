# frozen_string_literal: true

require_relative 'test_helper'

class InstallerTest < Minitest::Test
  Installer = Transpareo::Md2pdf::Installer

  def test_chrome_url_matches_the_published_layout
    url = Installer.chrome_url('151.0.7922.47', 'linux64')

    assert_equal 'https://storage.googleapis.com/chrome-for-testing-public/151.0.7922.47/linux64/chrome-headless-shell-linux64.zip', url
  end

  def test_a_checksum_is_pinned_for_every_supported_platform
    Transpareo::Md2pdf::Platform::CHROME_SLUGS.each_value do |slug|
      checksum = Installer::CHECKSUMS[slug]

      refute_nil checksum, "no checksum pinned for #{slug}"
      assert_match(/\A[0-9a-f]{64}\z/, checksum)
    end
  end

  def test_verify_accepts_a_matching_digest
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'f')
      File.write(path, 'hello')
      digest = Digest::SHA256.hexdigest('hello')

      assert_equal digest, Installer.verify(path, digest)
    end
  end

  def test_verify_rejects_a_mismatched_digest
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'f')
      File.write(path, 'hello')
      assert_raises(Transpareo::Md2pdf::ChecksumError) do
        Installer.verify(path, 'f' * 64)
      end
    end
  end

  def test_verify_warns_but_passes_when_no_checksum_is_known
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'f')
      File.write(path, 'hello')
      _, err = capture_io { Installer.verify(path, nil) }

      assert_match(/no pinned checksum/, err)
    end
  end

  def test_extract_refuses_paths_escaping_the_target
    entry = Struct.new(:name).new('../escaped')

    Dir.mktmpdir do |dir|
      assert_raises(Transpareo::Md2pdf::Error) do
        Installer.extract(entry, dir)
      end
    end
  end

  # Escalating to root is never a side effect. It happens only when
  # asked for, only after the exact command is shown, and only with
  # someone present to answer.

  MISSING = %w[libXdamage.so.1 libXfixes.so.3].freeze

  def test_libraries_are_not_installed_unless_asked_for
    calls = []
    capture_io do
      $stdin.stub(:tty?, false) do
        Installer.stub(:system, lambda { |*args|
          calls << args
          true
        },) do
          Transpareo::Md2pdf::Platform.stub(:linux_family, :debian) do
            refute Installer.install_libraries(MISSING, assume_yes: false)
          end
        end
      end
    end

    assert_empty calls
  end

  def test_an_unattended_run_refuses_rather_than_blocking
    out = nil
    _, err = capture_io do
      $stdin.stub(:tty?, false) do
        Transpareo::Md2pdf::Platform.stub(:linux_family, :debian) do
          out = Installer.install_libraries(MISSING, assume_yes: false)
        end
      end
    end

    refute out
    assert_match(/not a terminal/, err)
    assert_match(/--yes/, err)
  end

  def test_yes_runs_the_command_without_a_prompt
    ran = nil
    capture_io do
      Installer.stub(:system, lambda { |*args|
        ran = args
        true
      },) do
        Transpareo::Md2pdf::Platform.stub(:linux_family, :debian) do
          Installer.install_libraries(MISSING, assume_yes: true)
        end
      end
    end

    assert_equal %w[sudo apt install libxdamage1 libxfixes3], ran
  end

  def test_the_command_is_shown_before_it_runs
    out, = capture_io do
      Installer.stub(:system, ->(*_args) { true }) do
        Transpareo::Md2pdf::Platform.stub(:linux_family, :debian) do
          Installer.install_libraries(MISSING, assume_yes: true)
        end
      end
    end

    assert_match(/will run:/, out)
    assert_match(/sudo apt install libxdamage1 libxfixes3/, out)
  end

  # A distro with no package mapping yields advice rather than a
  # command, and there is nothing safe to run in that case.
  def test_nothing_runs_when_there_is_no_sudo_command_to_run
    calls = []
    Installer.stub(:system, lambda { |*args|
      calls << args
      true
    },) do
      Transpareo::Md2pdf::Platform.stub(:linux_family, :unknown) do
        refute Installer.install_libraries(MISSING, assume_yes: true)
      end
    end

    assert_empty calls
  end

  def test_a_failed_package_install_is_reported_not_swallowed
    result = nil
    _, err = capture_io do
      Installer.stub(:system, ->(*_args) { false }) do
        Transpareo::Md2pdf::Platform.stub(:linux_family, :debian) do
          result = Installer.install_libraries(MISSING, assume_yes: true)
        end
      end
    end

    refute result
    assert_match(/failed/, err)
  end

  def test_shim_path_lives_in_the_managed_bin_dir
    TestSupport.with_env('MD2PDF_HOME' => '/place') do
      assert_equal '/place/bin/chrome-headless-shell',
                   Installer.shim_path
    end
  end
end
