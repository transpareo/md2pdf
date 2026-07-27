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

  def test_shim_path_lives_in_the_managed_bin_dir
    TestSupport.with_env('MD2PDF_HOME' => '/place') do
      assert_equal '/place/bin/chrome-headless-shell',
                   Installer.shim_path
    end
  end
end
