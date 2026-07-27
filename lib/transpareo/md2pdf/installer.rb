# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'

module Transpareo
  module Md2pdf
    # Fetches a known-good Chromium into the gem-managed directory,
    # so a machine with only Ruby can render PDFs without root.
    #
    # Downloads happen only when the user explicitly asks for them.
    # Nothing here runs implicitly during a conversion: a silent
    # hundred-megabyte fetch is a surprise nobody wants.
    #
    # `chrome-headless-shell` is Google's purpose-built headless
    # binary. It is roughly a third of full Chrome and supports the
    # printing path this gem uses.
    module Installer
      # The build this gem is tested against. Chrome for Testing
      # keeps every published version online indefinitely, so a pin
      # stays resolvable rather than rotting.
      CHROME_VERSION = '151.0.7922.47'

      CHROME_BASE =
        'https://storage.googleapis.com/chrome-for-testing-public'

      VERSIONS_URL = 'https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json'

      # SHA-256 of each pinned archive, verified before unpacking.
      # Regenerate with `rake checksums` after bumping the version.
      CHECKSUMS = {
        'linux64' =>
          'e60f546a64ecc6b5b5ddbde7b47f1304fc8fdba9ea65fd63c16bbc994787b3d5',
        'mac-x64' =>
          'c59bae764cfd38c6f26b076f19bee73dea6f8aa416781ce7467bf363db9e3996',
        'mac-arm64' =>
          '0bf92463e337d207792b6ba460a06db1d40ab048e72f80cf608942cd7885552f',
      }.freeze

      MAX_REDIRECTS = 5

      module_function

      def install(version: CHROME_VERSION, latest: false, force: false,
                  libraries: false, assume_yes: false)
        slug = require_slug!
        version = resolve_latest(slug) if latest
        target = File.join(Dependencies.home, 'chrome', version)

        if File.directory?(target) && !force
          puts "chromium #{version} already installed at #{target}"
        else
          fetch_into(target, version, slug, latest)
          puts "chromium #{version} installed to #{target}"
        end

        # Rewritten even when the tree was already there: a run
        # interrupted between unpacking and this point left the
        # binary without its shim, and rerunning has to repair
        # that rather than demand --force.
        write_shim(target, slug)
        verify_runs(libraries: libraries, assume_yes: assume_yes)
      end

      # The unpacked tree is staged beside its destination and
      # renamed into place only when complete, so an interrupted
      # extraction leaves a .partial directory the next run
      # replaces, never a half-populated tree that passes for
      # installed. Beside the target rather than in the tmpdir,
      # because rename is atomic only within one filesystem and
      # /tmp is often another.
      def fetch_into(target, version, slug, latest)
        Dir.mktmpdir('md2pdf-install') do |tmp|
          archive = File.join(tmp, 'chrome.zip')
          download(chrome_url(version, slug), archive)
          verify(archive, latest ? nil : CHECKSUMS[slug])
          staging = "#{target}.partial"
          FileUtils.rm_rf(staging)
          unpack(archive, staging)
          promote(staging, target)
        end
      end

      def promote(staging, target)
        FileUtils.rm_rf(target)
        File.rename(staging, target)
        target
      end

      # Unpacking is not installing. The archive carries no
      # dependency closure, so on a bare server the binary lands
      # intact and still cannot start. Reporting success here is
      # what sends someone hunting through their own application
      # for a fault that is ours to name.
      def verify_runs(libraries: false, assume_yes: false)
        result = Dependencies.probe(shim_path)
        return shim_path if result[:ok]

        missing = missing_for(result[:output])
        if libraries && install_libraries(missing, assume_yes: assume_yes)
          return verify_after_libraries
        end

        raise_unusable(result[:output], missing)
      end

      def missing_for(output)
        found = Dependencies.missing_libraries(shim_path)
        found.empty? ? Dependencies.named_libraries(output) : found
      end

      def verify_after_libraries
        result = Dependencies.probe(shim_path)
        return shim_path if result[:ok]

        raise_unusable(result[:output], missing_for(result[:output]))
      end

      def raise_unusable(output, missing)
        raise UnusableDependencyError.new(
          'chromium',
          "chromium was downloaded but cannot start.\n  #{Dependencies.startup_problem(shim_path, output)}\nInstall what it is missing:\n  #{Dependencies.libraries_hint(missing)}",
        )
      end

      # Escalating to root is never a side effect here: it happens
      # only when asked for, only after showing the exact command,
      # and only with someone present to answer, so an unattended
      # run fails with the command printed instead of blocking on a
      # password prompt nobody will see.
      #
      # A command, not a predicate: installing is the point and the
      # boolean says whether it happened.
      # rubocop:disable Naming/PredicateMethod
      def install_libraries(missing, assume_yes: false)
        command = Dependencies.library_command(missing)
        return false unless command

        puts "\nwill run:\n  #{command.join(' ')}"
        return false unless assume_yes || confirmed?
        return true if system(*command)

        warn "md2pdf: `#{command.join(' ')}` failed"
        false
      end
      # rubocop:enable Naming/PredicateMethod

      def confirmed?
        unless $stdin.tty?
          warn 'md2pdf: not a terminal, skipping. Pass --yes to run it.'
          return false
        end

        print 'continue? [y/N] '
        $stdin.gets.to_s.strip.casecmp('y').zero?
      end

      # Chrome for Testing publishes glibc builds only, so a musl
      # system (Alpine) is refused before the download rather than
      # after, when the binary would die in the dynamic loader and
      # the error would blame libraries no package can supply.
      def require_slug!
        slug = Platform.chrome_slug
        if slug.nil?
          raise_unsupported(
            "no prebuilt Chromium for #{Platform.os}/#{Platform.arch}",
          )
        end
        return slug unless Platform.musl?

        raise_unsupported(
          'the prebuilt Chromium needs glibc, which this system lacks',
        )
      end

      def raise_unsupported(reason)
        raise UnsupportedPlatformError,
              "#{reason}. Install one with your package manager instead:\n  #{Dependencies.install_hint}"
      end

      def chrome_url(version, slug)
        "#{CHROME_BASE}/#{version}/#{slug}/chrome-headless-shell-#{slug}.zip"
      end

      def resolve_latest(slug)
        data = JSON.parse(fetch(VERSIONS_URL))
        version = data.dig('channels', 'Stable', 'version')
        raise Error, 'could not resolve latest Chromium' unless version

        warn "md2pdf: --latest skips checksum verification (#{slug})"
        version
      end

      def download(url, dest)
        puts "downloading #{url}"
        File.open(dest, 'wb') { |file| stream(url, file) }
        dest
      end

      def verify(path, expected)
        actual = Digest::SHA256.file(path).hexdigest
        if expected.nil? || expected == 'PENDING'
          warn "md2pdf: no pinned checksum, got sha256 #{actual}"
          return actual
        end
        return actual if actual == expected

        raise ChecksumError,
              "checksum mismatch\n  expected #{expected}\n  actual   #{actual}"
      end

      def unpack(archive, target)
        require 'zip'

        FileUtils.mkdir_p(target)
        Zip::File.open(archive) do |zip|
          zip.each { |entry| extract(entry, target) }
        end
        target
      end

      def extract(entry, target)
        path = File.join(target, entry.name)
        raise Error, "unsafe archive path: #{entry.name}" unless
          File.expand_path(path).start_with?(File.expand_path(target))

        FileUtils.mkdir_p(File.dirname(path))
        entry.extract(path) { true }
        File.chmod(0o755, path) if entry.file? && executable_name?(path)
      end

      def executable_name?(path)
        File.basename(path).start_with?('chrome') ||
          File.extname(path).empty?
      end

      # Chromium locates its resources relative to the real binary,
      # so bin/ gets a shim that execs it in place rather than a
      # symlink that would move it out of its own directory.
      def write_shim(target, slug)
        real = File.join(
          target, "chrome-headless-shell-#{slug}", 'chrome-headless-shell',
        )
        FileUtils.mkdir_p(Dependencies.bin_dir)
        File.write(shim_path, "#!/bin/sh\nexec #{real.inspect} \"$@\"\n")
        File.chmod(0o755, shim_path)
        shim_path
      end

      def shim_path
        File.join(Dependencies.bin_dir, 'chrome-headless-shell')
      end

      def fetch(url, limit = MAX_REDIRECTS)
        body = +''
        stream(url, body, limit)
        body
      end

      # Writes the response body into `sink`, which is anything that
      # responds to `<<`. Follows redirects, which the Google
      # storage endpoints use.
      def stream(url, sink, limit = MAX_REDIRECTS)
        raise Error, "too many redirects for #{url}" if limit.zero?

        uri = URI.parse(url)
        Net::HTTP.start(
          uri.host, uri.port, use_ssl: uri.scheme == 'https',
        ) do |http|
          http.request(Net::HTTP::Get.new(uri)) do |response|
            case response
            when Net::HTTPSuccess
              response.read_body { |chunk| sink << chunk }
            when Net::HTTPRedirection
              return stream(response['location'], sink, limit - 1)
            else
              raise Error,
                    "download failed: #{response.code} #{response.message}"
            end
          end
        end
      end
    end
  end
end
