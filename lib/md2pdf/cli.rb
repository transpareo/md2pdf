module Md2pdf
  module CLI
    HELP = <<~HELP
      Convert markdown to PDF via pandoc + Chromium headless.

      Usage:
        md2pdf file.md
        md2pdf *.md
        md2pdf --flat file.md      # only H1 rendered as heading
        md2pdf --unwrap file.md    # join hard-wrapped paragraphs
        md2pdf --no-toc file.md    # skip the TOC
        md2pdf                     # all .md in current dir

      A table of contents (H2 + H3) is inserted by default
      between the title page and the first H2, on its own
      page, with resolved page numbers. Auto-skipped if the
      document has fewer than 3 H2 headings.

      Options:
        --flat            Demote H2/H3 to bold paragraphs so
                          the PDF has only the H1 title as a
                          heading.
        --unwrap          Join hard-wrapped paragraph lines
                          before rendering. Off by default —
                          pandoc handles soft-wrapped
                          paragraphs as a single paragraph
                          already, and unwrap can occasionally
                          corrupt nested fenced code blocks.
                          Use on sources whose paragraphs are
                          hard-wrapped at a column limit.
        --no-toc          Disable the table of contents.
        --toc-depth=N     TOC depth (1 = H2 only, 2 = H2+H3,
                          3 = also H4). Default 2.
        --toc-label=TEXT  TOC heading text. Default "Contents".
        -h, --help        Show this help and exit.

      Output PDFs are placed next to the input files.
    HELP

    module_function

    def run(argv)
      flat = false
      unwrap_source = false
      toc = true
      toc_depth = 2
      toc_label = nil
      files = []
      help = false

      args = argv.dup
      until args.empty?
        arg = args.shift
        case arg
        when '--flat', '--single-heading'
          flat = true
        when '--unwrap'
          unwrap_source = true
        when '--toc'
          toc = true
        when '--no-toc'
          toc = false
        when /\A--toc-depth=(\d+)\z/
          toc_depth = Regexp.last_match(1).to_i
        when /\A--toc-label=(.+)\z/
          toc_label = Regexp.last_match(1)
        when '--toc-label'
          toc_label = args.shift or
            (warn 'md2pdf: --toc-label needs a value'; exit 2)
        when '-h', '--help'
          help = true
        when /\A--?/
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

      files = Dir.glob('*.md') if files.empty?

      if files.empty?
        warn 'No .md files found.'
        exit 1
      end

      files.each do |path|
        Runner.convert(
          path,
          flat: flat,
          unwrap_source: unwrap_source,
          toc: toc,
          toc_depth: toc_depth,
          toc_label: toc_label
        )
      end
    end
  end
end
