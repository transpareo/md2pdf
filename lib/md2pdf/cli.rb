module Md2pdf
  module CLI
    HELP = <<~HELP
      Convert markdown to PDF via pandoc + Chromium headless.

      Usage:
        md2pdf file.md
        md2pdf *.md                # all .md in current dir
        md2pdf 'docs/*.md'         # globs are expanded internally
        md2pdf                     # same as md2pdf *.md
        md2pdf --flat file.md      # only H1 rendered as heading
        md2pdf --unwrap file.md    # join hard-wrapped paragraphs
        md2pdf --no-toc file.md    # skip the TOC

      Configuration precedence (highest first):
        1. CLI flags
        2. YAML front-matter (md2pdf: block)
        3. .md2pdf.yml in nearest parent directory

      Content options:
        --flat                 Demote H2/H3 to bold paragraphs.
        --unwrap               Join hard-wrapped paragraph lines.
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
        --no-header-logo       Hide first-page header logo.
        --no-footer-logo       Hide footer logo.
        --no-page-numbers      Hide page numbers.

      Misc:
        --open                 Open the generated PDF with xdg-open.
                               Only allowed when a single file is
                               being converted.

      Style:
        --link-color=#hex      Link color. Default #0a4a90.
        --custom-css=FILE      Append custom CSS to the stylesheet.

        -h, --help             Show this help and exit.

      Output PDFs are placed next to the input files unless
      --output or --output-dir is given.
    HELP

    BOOL_FLAGS = {
      '--flat' => :flat, '--single-heading' => :flat,
      '--unwrap' => :unwrap,
      '--toc' => :toc,
      '--no-toc' => [:toc, false],
      '--no-header-logo' => [:header_logo, false],
      '--no-footer-logo' => [:footer_logo, false],
      '--no-page-numbers' => [:page_numbers, false],
      '--open' => :open
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
      '--link-color' => :link_color,
      '--custom-css' => :custom_css
    }.freeze

    STYLE_KEYS = %i[
      font_size line_height font_family code_font_family
      page_size margins logo link_color custom_css
      header_logo footer_logo page_numbers
    ].freeze

    module_function

    def run(argv)
      cli_opts = {}
      files = []
      help = false

      args = argv.dup
      until args.empty?
        arg = args.shift
        if BOOL_FLAGS.key?(arg)
          target = BOOL_FLAGS[arg]
          if target.is_a?(Array)
            cli_opts[target[0]] = target[1]
          else
            cli_opts[target] = true
          end
        elsif (m = arg.match(/\A(--[a-z-]+)=(.*)\z/)) &&
              VALUE_FLAGS.key?(m[1])
          assign(cli_opts, VALUE_FLAGS[m[1]], m[2])
        elsif VALUE_FLAGS.key?(arg)
          val = args.shift or
            (warn "md2pdf: #{arg} needs a value"; exit 2)
          assign(cli_opts, VALUE_FLAGS[arg], val)
        elsif arg == '-h' || arg == '--help'
          help = true
        elsif arg.start_with?('-')
          warn "md2pdf: unknown option: #{arg}"
          exit 2
        else
          files << arg
        end
      end

      if help
        puts HELP
        exit 0
      end

      files = expand_args(files)
      files = filter_markdown(files)

      if files.empty?
        warn 'No .md files found.'
        exit 1
      end

      if cli_opts[:open] && files.size > 1
        warn "md2pdf: --open is only allowed for a single file " \
             "(#{files.size} would be converted)"
        exit 2
      end

      files.each { |path| convert_one(path, cli_opts) }
    end

    # Default to *.md in the current directory when nothing was
    # given, and expand glob patterns ourselves so quoted args
    # like `'docs/*.md'` work the same as a shell-expanded glob.
    def expand_args(args)
      return Dir.glob('*.md') if args.empty?

      args.flat_map do |arg|
        if arg.match?(/[*?\[]/)
          matches = Dir.glob(arg)
          warn "md2pdf: no files match: #{arg}" if matches.empty?
          matches
        else
          [arg]
        end
      end
    end

    def filter_markdown(files)
      md, other = files.partition do |path|
        File.extname(path).downcase == '.md'
      end
      other.each do |path|
        warn "md2pdf: not a markdown file (skipping): #{path}"
      end
      md
    end

    def convert_one(path, cli_opts)
      cfg = Config.resolve(path, cli_opts)
      locale = cfg[:locale] || Locales.detect(path) || 'en'
      labels = Locales.defaults_for(locale)
      style = STYLE_KEYS.each_with_object({}) do |k, h|
        h[k] = cfg[k] unless cfg[k].nil?
      end
      Runner.convert(
        path,
        flat: cfg.fetch(:flat, false),
        unwrap: cfg.fetch(:unwrap, false),
        toc: cfg.fetch(:toc, true),
        toc_depth: cfg.fetch(:toc_depth, 2),
        toc_label: cfg[:toc_label] || labels[:toc_label],
        toc_min: cfg.fetch(:toc_min, 3),
        toc_min_words: cfg.fetch(:toc_min_words, 1500),
        footnotes_label: cfg.fetch(:footnotes_label, labels[:footnotes_label]),
        locale: locale,
        output: cfg[:output],
        output_dir: cfg[:output_dir],
        open: cfg.fetch(:open, false),
        style: style
      )
    end

    def assign(opts, key, val)
      case key
      when :toc_depth_int
        opts[:toc] = true
        opts[:toc_depth] = val.to_i
      when :toc_min_int
        opts[:toc_min] = val.to_i
      when :toc_min_words_int
        opts[:toc_min_words] = val.to_i
      else
        opts[key] = val
      end
    end
  end
end
