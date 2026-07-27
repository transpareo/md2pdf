# frozen_string_literal: true

module Transpareo
  module Md2pdf
    # Argument parsing and dispatch.
    #
    # Every entry point returns an exit status instead of calling
    # exit, so the library stays usable in-process and only the
    # executable decides how the process terminates.
    module CLI
      HELP = <<~HELP
        Convert markdown to PDF through headless Chromium.

        Usage:
          md2pdf file.md
          md2pdf *.md                # all .md in current dir
          md2pdf 'docs/*.md'         # globs are expanded internally
          md2pdf                     # same as md2pdf *.md
          cat f.md | md2pdf - > f.pdf   # read stdin, write stdout
          md2pdf --flat file.md      # only H1 rendered as heading
          md2pdf --unwrap file.md    # join hard-wrapped paragraphs
          md2pdf --no-toc file.md    # skip the TOC

        Commands:
          doctor                 Report dependency status and exit.
          install-deps           Download a known-good Chromium into
                                 the gem-managed directory. Accepts
                                 --latest and --force. Never uses
                                 sudo.
            --with-libraries     If the download cannot start for
                                 want of shared libraries, show the
                                 package command and offer to run
                                 it under sudo.
            --yes                Answer that prompt in advance, for
                                 unattended installs.

        Configuration precedence (highest first):
          1. CLI flags
          2. YAML front-matter (md2pdf: block)
          3. .md2pdf.yml files between the document and $HOME,
             nearer ones winning
          4. ~/.config/md2pdf/config.yml, or ~/.md2pdf.yml

        Every layer is merged key by key, so a file only has to
        state what it changes.

        Content options:
          --flat                 Demote H2/H3 to bold paragraphs.
          --single-heading       Alias for --flat.
          --unwrap               Join hard-wrapped paragraph lines.
          --toc                  Force the table of contents on,
                                 ignoring the auto-skip thresholds.
          --no-toc               Disable the table of contents.
          --toc-depth=N          TOC depth (1=H2, 2=H2+H3, 3=+H4).
          --toc-label=TEXT       TOC heading text. Default per locale.
          --toc-min=N            Min H2s to auto-include TOC. Default 3.
          --toc-min-words=N      Min word count to auto-include TOC.
                                 Default 1500.
          --footnotes-label=TEXT Footnotes section heading text.
                                 Default per locale. Pass "" for none.
          --locale=CODE          Locale (en, de, fr, es, it, pt, nl).
                                 Auto-detected from filenames like
                                 foo.de.md; falls back to en.

        Typography:
          --font-size=Npt        Body font size. Default 11pt.
          --line-height=N        Body line-height. Default 1.8.
          --font-family="..."    Body font stack.
          --code-font-family=".."  Monospace stack for code.

        Layout:
          --page-size=NAME       A4, Letter, A5, Legal, etc. Default A4.
          --margins="T R B L"    Page margins. Default "22mm 20mm 24mm 20mm".
          --output=FILE          Output path. Default <input>.pdf.
          --output-dir=DIR       Output directory.

        Branding:
          --logo=PATH            Logo SVG. Footer auto-derives in grey.
          --footer-title=TEXT    Running text centred in the footer,
                                 between the logo and page number.
                                 Defaults to the document's H1.
                                 Pass "" to remove it.
          --no-header-logo       Hide first-page header logo.
          --no-footer-logo       Hide footer logo.
          --no-page-numbers      Hide page numbers.

        Style:
          --link-color=#hex      Link color. Default #0a4a90.
          --custom-css=FILE      Append custom CSS to the stylesheet.

        Misc:
          --open                 Open the PDF in the default viewer
                                 afterwards. Only allowed when a
                                 single file is being converted.
          -v, --version          Show version and exit.
          -h, --help             Show this help and exit.

        Output PDFs are placed next to the input files unless
        --output or --output-dir is given.

        A file argument of "-" reads standard input, and is assumed
        when nothing is named and stdin is not a terminal. Without
        a destination the PDF is written to stdout.
      HELP

      # A symbol sets that key true, a pair sets it to the given
      # value, and a hash applies several at once.
      BOOL_FLAGS = {
        '--flat' => :flat,
        '--single-heading' => :flat,
        '--unwrap' => :unwrap,
        # Asking for a TOC explicitly means wanting one, so this
        # also clears the thresholds that would auto-skip it.
        '--toc' => { toc: true, toc_min: 0, toc_min_words: 0 },
        '--no-toc' => [:toc, false],
        '--no-header-logo' => [:header_logo, false],
        '--no-footer-logo' => [:footer_logo, false],
        '--no-page-numbers' => [:page_numbers, false],
        '--open' => :open,
      }.freeze

      VALUE_FLAGS = {
        '--locale' => :locale,
        '--toc-depth' => :toc_depth_int,
        '--toc-label' => :toc_label,
        '--toc-min' => :toc_min_int,
        '--toc-min-words' => :toc_min_words_int,
        '--footnotes-label' => :footnotes_label,
        '--font-size' => :font_size,
        '--line-height' => :line_height,
        '--font-family' => :font_family,
        '--code-font-family' => :code_font_family,
        '--page-size' => :page_size,
        '--margins' => :margins,
        '--output' => :output,
        '--output-dir' => :output_dir,
        '--logo' => :logo,
        '--footer-title' => :footer_title,
        '--link-color' => :link_color,
        '--custom-css' => :custom_css,
      }.freeze

      OK = 0
      FAILURE = 1
      USAGE_ERROR = 2
      INTERRUPTED = 130

      module_function

      def run(argv)
        case argv.first
        when 'doctor' then return doctor
        when 'install-deps' then return install_deps(argv.drop(1))
        when '-v', '--version' then return version
        end

        convert_all(argv)
      rescue Error => e
        warn "md2pdf: #{e.message}"
        FAILURE
      rescue Interrupt
        warn 'md2pdf: interrupted'
        INTERRUPTED
      end

      def version
        puts "md2pdf #{VERSION}"
        OK
      end

      def doctor
        rows = Dependencies.status
        width = rows.map { |row| row[:name].length }.max
        rows.each { |row| puts doctor_line(row, width) }
        broken = rows.reject { |row| row[:ok] }
        return OK if broken.empty?

        # The remedy comes from the row, because a dependency that
        # is present but cannot start needs different advice from
        # one that is absent.
        warn ''
        broken.each do |row|
          warn "#{row[:name]}: #{row[:problem]}"
          warn "  #{row[:remedy]}" if row[:remedy]
        end
        FAILURE
      end

      def doctor_line(row, width)
        mark = row[:ok] ? 'ok  ' : 'MISS'
        detail = row[:problem] ||
                 [row[:version], row[:path]].compact.join('  ')
        format("  %<mark>s  %-#{width}<name>s  %<detail>s", {
                 mark: mark,
                 name: row[:name],
                 detail: detail,
               })
      end

      def install_deps(args)
        Installer.install(
          latest: args.include?('--latest'),
          force: args.include?('--force'),
          libraries: args.include?('--with-libraries'),
          assume_yes: args.include?('--yes'),
        )
        OK
      end

      def convert_all(argv)
        opts, files, help = parse(argv)
        return USAGE_ERROR if opts.nil?

        if help
          puts HELP
          return OK
        end

        files = filter_markdown(expand_args(files))
        return no_input if files.empty?

        if opts[:open] && files.size > 1
          warn "md2pdf: --open is only allowed for a single file (#{files.size} would be converted)"
          return USAGE_ERROR
        end

        results = files.map { |path| convert_one(path, opts) }
        results.all? ? OK : FAILURE
      end

      def no_input
        warn 'md2pdf: no .md files found.'
        FAILURE
      end

      # Returns [options, files, help], or nil options on a usage
      # error that the caller turns into an exit status.
      def parse(argv)
        opts = {}
        files = []
        help = false
        args = argv.dup

        until args.empty?
          arg = args.shift
          case arg
          when *BOOL_FLAGS.keys then apply_bool(opts, BOOL_FLAGS[arg])
          when '-h', '--help' then help = true
          when /\A-./ then return unless take_flag(opts, arg, args)
          else files << arg
          end
        end

        [opts, files, help]
      end

      # Consumes one value-carrying flag, in either `--key=value` or
      # `--key value` form. Returns false on a usage error, having
      # already reported it.
      # A command, not a predicate: it consumes the flag and reports
      # whether parsing may continue.
      # rubocop:disable Naming/PredicateMethod
      def take_flag(opts, arg, args)
        match = arg.match(/\A(--[a-z-]+)=(.*)\z/m)
        key = VALUE_FLAGS[match ? match[1] : arg]

        unless key
          warn "md2pdf: unknown option: #{arg}"
          return false
        end

        value = match ? match[2] : args.shift
        if value.nil?
          warn "md2pdf: #{arg} needs a value"
          return false
        end

        assign(opts, key, value)
        true
      end
      # rubocop:enable Naming/PredicateMethod

      def apply_bool(opts, target)
        case target
        when Hash then opts.merge!(target)
        when Array then opts[target[0]] = target[1]
        else opts[target] = true
        end
      end

      # Defaults to *.md in the current directory when nothing was
      # given, and expands globs internally so a quoted argument
      # like 'docs/*.md' behaves like a shell-expanded one.
      #
      # Piped input takes precedence over that default: globbing the
      # directory when someone pipes a document would convert an
      # unrelated file and report success.
      def expand_args(args)
        return [Runner::STDIN_MARKER] if args.empty? && !$stdin.tty?
        return Dir.glob('*.md') if args.empty?

        args.flat_map do |arg|
          next [arg] unless arg.match?(/[*?\[]/)

          matches = Dir.glob(arg)
          warn "md2pdf: no files match: #{arg}" if matches.empty?
          matches
        end
      end

      def filter_markdown(files)
        md, other = files.partition do |path|
          path == Runner::STDIN_MARKER || File.extname(path).downcase == '.md'
        end
        other.each do |path|
          warn "md2pdf: not a markdown file (skipping): #{path}"
        end
        md
      end

      def convert_one(path, cli_opts)
        return convert_stdin(cli_opts) if path == Runner::STDIN_MARKER

        Runner.convert(path, **Md2pdf.settings(path, cli_opts))
      end

      # stdin can only be read once, so the text is read here and
      # handed both to the settings resolver, which needs its front
      # matter, and to the renderer.
      def convert_stdin(cli_opts)
        if $stdin.tty?
          warn 'md2pdf: no input on stdin'
          return false
        end

        # Said before the read, not after. This call blocks until
        # the program upstream finishes and closes the pipe, so
        # without a word here a slow generator looks like md2pdf
        # hanging, and there is nothing on screen to tell them
        # apart.
        warn 'md2pdf: reading markdown from stdin'
        text = Runner.as_utf8($stdin.read)
        settings = Md2pdf.settings(Runner::STDIN_MARKER, cli_opts, text)
        Runner.convert(Runner::STDIN_MARKER, **settings, source_text: text)
      end

      def assign(opts, key, value)
        case key
        when :toc_depth_int
          opts[:toc] = true
          opts[:toc_depth] = value.to_i
        when :toc_min_int then opts[:toc_min] = value.to_i
        when :toc_min_words_int then opts[:toc_min_words] = value.to_i
        else opts[key] = value
        end
      end
    end
  end
end
