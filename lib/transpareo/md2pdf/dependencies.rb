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
        '/Applications/Chromium.app/Contents/MacOS/Chromium'
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

        out = capture(path, '--version')
        match = out && out[/(\d+(?:\.\d+)+)/, 1]
        match && Gem::Version.new(match)
      rescue ArgumentError
        nil
      end

      # Runs `binary --version`, returning stdout or nil when the
      # binary is missing or refuses to run.
      def capture(path, *args)
        out = IO.popen([path, *args], err: %i[child out], &:read)
        $CHILD_STATUS&.success? ? out : nil
      rescue SystemCallError, IOError
        nil
      end

      def raise_missing
        raise MissingDependencyError.new(
          'chromium',
          "chromium not found.\n" \
          'Run `md2pdf install-deps` to fetch a known-good build, ' \
          "or install one yourself:\n  #{install_hint}"
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

      # Structured report backing `md2pdf doctor`.
      def status
        [chromium_status, *gem_statuses]
      end

      def chromium_status
        path = chromium
        row = { name: 'chromium', path: path, version: version(path) }
        return row.merge(ok: false, problem: 'not found') unless path

        row.merge(ok: true, problem: nil)
      end

      def gem_statuses
        RUNTIME_GEMS.map { |name| gem_status(name) }
      end

      def gem_status(name)
        version = Gem.loaded_specs[name]&.version ||
                  Gem::Specification.find_by_name(name).version
        { name: name, path: 'gem', version: version, ok: true,
          problem: nil }
      rescue StandardError
        { name: name, path: nil, version: nil, ok: false,
          problem: 'not installed' }
      end
    end
  end
end
