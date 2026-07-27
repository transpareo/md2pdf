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

      # Enough of a file to see a shebang and the line after it.
      SHIM_PROBE_BYTES = 512

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
        out = capture('ldd', real_binary(path))
        return [] unless out

        out.lines
          .filter_map { |line| line[/^\s*(\S+)\s*=>\s*not found/, 1] }
          .uniq
      end

      # A managed Chromium is reached through a shim, and ldd has
      # nothing to say about a shell script: it answers "not a
      # dynamic executable" and the caller falls back to the
      # loader's message, which names one library at a time. Ask
      # about the program the shim runs instead.
      def real_binary(path)
        head = File.read(path, SHIM_PROBE_BYTES).to_s
        return path unless head.start_with?('#!')

        target = head[/^exec\s+"([^"]+)"/, 1]
        target && File.file?(target) ? target : path
      rescue SystemCallError, ArgumentError
        path
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
        # Ubuntu ships no chromium package, and its chromium-browser
        # is a shim that installs snapd and a confined browser. A
        # confined browser cannot read the temporary files md2pdf
        # hands it, so the download is the better route here.
        when :ubuntu then 'md2pdf install-deps'
        else 'install chromium with your package manager'
        end
      end

      INSTALL_COMMANDS = {
        debian: 'sudo apt install',
        ubuntu: 'sudo apt install',
        fedora: 'sudo dnf install',
        arch: 'sudo pacman -S',
        alpine: 'sudo apk add',
      }.freeze

      # Debian and Ubuntu name a library package after its soname:
      # libXdamage.so.1 is in libxdamage1. These are the members of
      # Chrome's closure that break that rule.
      DEBIAN_PACKAGE_NAMES = {
        'libX11.so.6' => 'libx11-6',
        'libasound.so.2' => 'libasound2',
        'libatk-1.0.so.0' => 'libatk1.0-0',
        'libatk-bridge-2.0.so.0' => 'libatk-bridge2.0-0',
        'libatspi.so.0' => 'libatspi2.0-0',
        'libcairo-gobject.so.2' => 'libcairo-gobject2',
        'libcups.so.2' => 'libcups2',
        'libdbus-1.so.3' => 'libdbus-1-3',
        'libgdk-3.so.0' => 'libgtk-3-0',
        'libglib-2.0.so.0' => 'libglib2.0-0',
        'libgtk-3.so.0' => 'libgtk-3-0',
        'libnspr4.so' => 'libnspr4',
        'libnss3.so' => 'libnss3',
        'libnssutil3.so' => 'libnss3',
        'libpango-1.0.so.0' => 'libpango-1.0-0',
        'libpangocairo-1.0.so.0' => 'libpangocairo-1.0-0',
        'libplc4.so' => 'libnspr4',
        'libplds4.so' => 'libnspr4',
        'libsmime3.so' => 'libnss3',
      }.freeze

      # The command to install exactly the libraries missing, as
      # argv, or nil when this system has no mapping for them.
      #
      # Built as data rather than a sentence, because the installer
      # runs it. Splitting a display string back into arguments
      # works right up until a package name or path contains a
      # space.
      def library_command(missing = [])
        command = INSTALL_COMMANDS[Platform.linux_family]
        packages = library_packages(missing)
        return nil if command.nil? || packages.empty?

        command.split + packages
      end

      # Names the packages for the libraries actually missing, not
      # the whole of Chrome's closure. Two absent libraries is a
      # couple of hundred kilobytes; the full list is a page of
      # packages the machine mostly already has.
      def libraries_hint(missing = [])
        command = library_command(missing)
        return generic_library_hint(missing) unless command

        command.join(' ')
      end

      def library_packages(missing)
        case Platform.linux_family
        when :debian, :ubuntu then missing.map { |so| debian_package(so) }
        # Fedora keeps the library's own capitalisation, libXdamage;
        # Arch and Alpine lowercase it.
        when :fedora then missing.map { |so| soname_stem(so) }
        when :arch, :alpine
          missing.map { |so| soname_stem(so).downcase }
        else []
        end.uniq
      end

      def debian_package(soname)
        DEBIAN_PACKAGE_NAMES[soname] ||
          soname.sub(/\.so(?:\.(\d+))?.*\z/) { Regexp.last_match(1) }
            .downcase
      end

      def soname_stem(soname)
        soname.sub(/\.so(?:\..*)?\z/, '')
      end

      def generic_library_hint(missing)
        return "install #{missing.join(', ')}" if missing.any?

        'install the shared libraries headless Chrome needs'
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

        missing = missing_libraries(path)
        missing = named_libraries(result[:output]) if missing.empty?
        row.merge(
          ok: false,
          problem: startup_problem(path, result[:output]),
          remedy: libraries_hint(missing),
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
