# frozen_string_literal: true

require 'English'
require_relative 'errors'
require_relative 'platform'

module Transpareo
  module Md2pdf
    # Locates Chromium, the one external program this gem needs.
    #
    # Markdown parsing, highlighting and PDF text extraction are all
    # handled by gems, so a browser is the only thing left that has
    # to come from outside RubyGems.
    #
    # Lookup order, highest priority first:
    #   1. the CHROMIUM environment variable
    #   2. the directory written by `md2pdf install-deps`
    #   3. the first match on PATH
    #   4. the standard macOS application bundles
    module Dependencies
      # `chrome-headless-shell` leads because it is what install-deps
      # fetches and it is purpose-built for exactly this job.
      CHROMIUM_NAMES = %w[
        chrome-headless-shell
        chromium
        chromium-browser
        google-chrome-stable
        google-chrome
        chrome
      ].freeze

      MACOS_APP_PATHS = [
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
      ].freeze

      # Reported by `doctor`. Versions come from the loaded specs
      # rather than per-gem constants, which are named inconsistently
      # and in some cases do not exist at all.
      RUNTIME_GEMS = %w[
        commonmarker nokogiri rouge pdf-reader rubyzip
      ].freeze

      module_function

      # Root of the gem-managed install tree.
      def home
        ENV['MD2PDF_HOME'] || File.join(xdg_data_home, 'md2pdf')
      end

      def xdg_data_home
        ENV['XDG_DATA_HOME'] || File.join(Dir.home, '.local', 'share')
      end

      def bin_dir
        File.join(home, 'bin')
      end

      def chromium
        from_env || from_managed || from_path || from_app_bundle
      end

      def chromium!
        chromium or raise_missing
      end

      def from_env
        value = ENV['CHROMIUM'].to_s
        return nil if value.empty?
        return value if value.include?(File::SEPARATOR)

        which(value)
      end

      def from_managed
        CHROMIUM_NAMES
          .map { |name| File.join(bin_dir, name) }
          .find { |path| File.executable?(path) }
      end

      def from_path
        CHROMIUM_NAMES.filter_map { |name| which(name) }.first
      end

      def from_app_bundle
        return nil unless Platform.os == :macos

        MACOS_APP_PATHS.find { |path| File.executable?(path) }
      end

      def which(name)
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |dir|
          next if dir.empty?

          candidate = File.join(dir, name)
          return candidate if File.executable?(candidate) &&
                              !File.directory?(candidate)
        end
        nil
      end

      def version(path = chromium)
        return nil unless path

        result = probe(path)
        return nil unless result[:ok]

        match = result[:output][/(\d+(?:\.\d+)+)/, 1]
        match && Gem::Version.new(match)
      rescue ArgumentError
        nil
      end

      # Starts the binary and keeps what it said.
      #
      # A file that exists and is executable is not a program that
      # runs: a downloaded build carries no dependency closure, so
      # on a bare server it dies in the dynamic loader. Checking
      # only for the file reports such an install as healthy.
      def probe(path)
        out = IO.popen([path, '--version'], err: %i[child out], &:read)
        { ok: $CHILD_STATUS&.success? || false, output: out.to_s.strip }
      rescue SystemCallError, IOError => e
        { ok: false, output: "#{e.class}: #{e.message}" }
      end

      # Runs a command, returning stdout or nil when it fails.
      def capture(path, *args)
        out = IO.popen([path, *args], err: %i[child out], &:read)
        $CHILD_STATUS&.success? ? out : nil
      rescue SystemCallError, IOError
        nil
      end

      # The dynamic loader names only the first library it cannot
      # find, so fixing one reveals the next. ldd lists them all at
      # once, which turns several rounds of this into one.
      def missing_libraries(path)
        out = capture('ldd', path)
        return [] unless out

        out.lines
          .filter_map { |line| line[/^\s*(\S+)\s*=>\s*not found/, 1] }
          .uniq
      end

      # ldd gives the complete list. Where it is unavailable, the
      # loader's own complaint still names the first library, which
      # beats quoting a truncated sentence back at the reader.
      def startup_problem(path, output)
        missing = missing_libraries(path)
        missing = named_libraries(output) if missing.empty?
        return "cannot start, missing #{missing.join(', ')}" if missing.any?

        "cannot start: #{first_line(output)}"
      end

      def named_libraries(output)
        output.to_s.scan(/\blib\S+?\.so(?:\.\d+)*/).uniq
      end

      def first_line(output)
        line = output.to_s.lines.first.to_s.strip
        line.empty? ? 'no output' : line
      end

      def raise_missing
        raise MissingDependencyError.new(
          'chromium',
          "chromium not found.\nRun `md2pdf install-deps` to fetch a known-good build, or install one yourself:\n  #{install_hint}",
        )
      end

      # Best-effort package-manager line for the running system.
      def install_hint
        case Platform.os
        when :macos then 'brew install --cask chromium'
        when :linux then linux_install_hint
        else 'https://www.chromium.org/getting-involved/download-chromium'
        end
      end

      def linux_install_hint
        case Platform.linux_family
        when :arch then 'sudo pacman -S chromium'
        when :fedora then 'sudo dnf install chromium'
        when :alpine then 'sudo apk add chromium'
        when :debian then 'sudo apt install chromium'
        else 'install chromium with your package manager'
        end
      end

      # The libraries a headless Chrome needs. A distro package
      # pulls these in as dependencies; a downloaded archive does
      # not, which is why a bare server needs them named.
      LIBRARY_PACKAGES = {
        debian: 'sudo apt install libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2',
        fedora: 'sudo dnf install nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon libXcomposite libXdamage libXfixes libXrandr mesa-libgbm pango cairo alsa-lib',
        arch: 'sudo pacman -S nss nspr atk at-spi2-atk libcups libdrm libxkbcommon libxcomposite libxdamage libxfixes libxrandr mesa pango cairo alsa-lib',
        alpine: 'sudo apk add nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon libxcomposite libxdamage libxfixes libxrandr mesa-gbm pango cairo alsa-lib',
      }.freeze

      # Installing the distro's own chromium is the other way out:
      # it drags the whole closure in, then md2pdf finds it on PATH.
      def libraries_hint
        LIBRARY_PACKAGES[Platform.linux_family] ||
          "install the shared libraries headless Chrome needs, or #{install_hint}"
      end

      # Structured report backing `md2pdf doctor`.
      def status
        [chromium_status, *gem_statuses]
      end

      def chromium_status
        path = chromium
        row = { name: 'chromium', path: path, version: nil }
        # An explicit CHROMIUM is taken at face value when resolving,
        # so a path naming nothing reaches here and has to be told
        # apart from a binary that exists but will not start.
        unless path && File.file?(path)
          return row.merge(
            ok: false,
            problem: 'not found',
            remedy: install_hint,
          )
        end

        result = probe(path)
        return chromium_ok(row, result[:output]) if result[:ok]

        row.merge(
          ok: false,
          problem: startup_problem(path, result[:output]),
          remedy: libraries_hint,
        )
      end

      def chromium_ok(row, output)
        match = output[/(\d+(?:\.\d+)+)/, 1]
        row.merge(
          version: match && Gem::Version.new(match),
          ok: true,
          problem: nil,
          remedy: nil,
        )
      end

      def gem_statuses
        RUNTIME_GEMS.map { |name| gem_status(name) }
      end

      def gem_status(name)
        version = Gem.loaded_specs[name]&.version ||
                  Gem::Specification.find_by_name(name).version
        {
          name: name,
          path: 'gem',
          version: version,
          ok: true,
          problem: nil,
        }
      rescue StandardError
        {
          name: name,
          path: nil,
          version: nil,
          ok: false,
          problem: 'not installed',
        }
      end
    end
  end
end
