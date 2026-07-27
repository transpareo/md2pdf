# frozen_string_literal: true

require 'English'
require 'shellwords'
require 'tmpdir'
require 'fileutils'

module Transpareo
  module Md2pdf
    # Orchestrates one markdown file into one PDF.
    #
    # Rendering runs twice when the document gets a TOC: the first
    # pass lays the document out with placeholder page numbers, the
    # PDF's destination table says which page each heading landed
    # on, and the second pass bakes the real numbers in. The TOC
    # entry box reserves space for the widest plausible number so
    # both passes lay out identically.
    module Runner
      TOC_MIN_H2 = 3
      TOC_MIN_WORDS = 1500

      # The conventional name for standard input as a file argument.
      STDIN_MARKER = '-'

      # Filesystems stop well short of this, and a heading long
      # enough to hit it was never meant to be a filename.
      MAX_BASENAME = 80

      CHROMIUM_ARGS = %w[
        --headless=new
        --disable-gpu
        --no-sandbox
        --no-pdf-header-footer
        --virtual-time-budget=2000
      ].freeze

      # Whatever each desktop uses to hand a file to its default
      # application. The empty argument after `start` is the window
      # title, which cmd requires before it will accept a path.
      OPENERS = {
        macos: %w[open].freeze,
        linux: %w[xdg-open].freeze,
        windows: ['cmd', '/c', 'start', ''].freeze,
      }.freeze

      module_function

      # These are commands rather than predicates: producing the PDF
      # is the point and the boolean is just the outcome.
      # rubocop:disable Naming/PredicateMethod

      # Returns true when a PDF was written.
      def convert(md_path, flat:, unwrap:, toc: false, toc_depth: 2,
                  toc_label: nil, toc_min: TOC_MIN_H2,
                  toc_min_words: TOC_MIN_WORDS,
                  footnotes_label: nil, locale: nil,
                  output: nil, output_dir: nil, open: false,
                  style: {}, source_text: nil)
        source = source_text || read_file(md_path)
        return false unless source

        text = Config.strip_front_matter(source)
        text = Unwrap.call(text) if unwrap
        warn 'md2pdf: input is empty' if text.strip.empty?
        toc &&= h2_count(text) >= toc_min &&
                word_count(text) >= toc_min_words

        basename = basename_for(md_path, text)
        options = {
          flat: flat,
          toc: toc,
          toc_depth: toc_depth,
          toc_label: toc_label,
          footnotes_label: footnotes_label,
          locale: locale,
          basename: basename,
          base_dir: base_dir_for(md_path),
          css: Style.build(**with_footer_title(style, text)),
        }

        if to_stdout?(md_path, output, output_dir)
          emit(text, options)
        else
          write(text, options, md_path, basename, output, output_dir, open)
        end
      end

      def read_file(md_path)
        return as_utf8(File.read(md_path, encoding: 'UTF-8')) if
          File.exist?(md_path)

        warn "md2pdf: not found: #{md_path}"
        nil
      end

      # The markdown parser only accepts UTF-8, while Ruby tags what
      # it reads with the locale's encoding. Without this, a machine
      # running under LANG=C fails on any document at all.
      def as_utf8(text)
        text = text.dup.force_encoding(Encoding::UTF_8)
        return text if text.valid_encoding?

        warn 'md2pdf: input is not valid UTF-8, replacing bad bytes'
        text.scrub
      end

      def write(text, options, md_path, basename, output, output_dir, open)
        pdf_path = output_path(md_path, basename, output, output_dir)
        FileUtils.mkdir_p(File.dirname(pdf_path))
        render(text, pdf_path, options)
        report(pdf_path)
        open_pdf(pdf_path) if open
        true
      end

      # Streams the PDF to stdout. Progress goes to stderr here, or
      # it would land in the middle of the document being piped.
      def emit(text, options)
        if $stdout.tty?
          warn 'md2pdf: refusing to write a PDF to the terminal. Redirect stdout or pass --output.'
          return false
        end

        Dir.mktmpdir('md2pdf-out') do |dir|
          pdf_path = File.join(dir, 'stdout.pdf')
          render(text, pdf_path, options)
          warn "md2pdf: #{File.size(pdf_path)} bytes to stdout"
          $stdout.binmode
          $stdout.write(File.binread(pdf_path))
        end
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Reading from stdin leaves nothing to name the file after, so
      # the PDF goes to stdout unless a destination was given.
      def to_stdout?(md_path, output, output_dir)
        md_path == STDIN_MARKER && output.nil? && output_dir.nil?
      end

      def basename_for(md_path, text)
        return File.basename(md_path, '.md') unless md_path == STDIN_MARKER

        safe_basename(Document.title_of(text))
      end

      # A heading from piped input becomes a filename here, so it is
      # reduced to something that can only ever name a file in the
      # target directory. Left alone, a title containing a slash
      # creates directories and one containing `..` writes outside
      # the output directory entirely.
      def safe_basename(title)
        name = title.to_s
          .gsub(%r{[/\\]}, '-')
          .gsub(/[^\p{Word}\s.-]/u, '')
          .gsub(/\s+/, '-')
          .squeeze('-.')
          .sub(/\A[.-]+/, '')
          .sub(/[.-]+\z/, '')
          .slice(0, MAX_BASENAME).to_s
        name.empty? ? 'document' : name
      end

      def base_dir_for(md_path)
        return Dir.pwd if md_path == STDIN_MARKER

        File.dirname(File.expand_path(md_path))
      end

      # The footer carries the document's own title unless one was
      # given. An explicit empty string is a deliberate opt-out and
      # is left alone, which is why this tests for the key rather
      # than for a truthy value.
      def with_footer_title(style, text)
        return style if style.key?(:footer_title)

        style.merge(footer_title: Document.title_of(text))
      end

      # Runs the second pass only when the first actually produced
      # destinations to resolve.
      def render(text, pdf_path, options)
        Dir.mktmpdir('md2pdf') do |tmpdir|
          html_path = File.join(tmpdir, 'doc.html')

          File.write(html_path, build_html(text, options, {}))
          print_pdf(html_path, pdf_path)
          next unless options[:toc]

          pages = PageIndex.call(pdf_path)
          next if pages.empty?

          File.write(html_path, build_html(text, options, pages))
          print_pdf(html_path, pdf_path)
        end
      end

      def build_html(text, options, pages)
        doc = Document.from_markdown(
          text,
          toc: options[:toc],
          toc_depth: options[:toc_depth],
          toc_label: options[:toc_label],
          footnotes_label: options[:footnotes_label],
          base_dir: options[:base_dir],
          toc_pages: pages,
        )
        doc.apply(Filters.chain(flat: options[:flat], toc: options[:toc]))
        Renderer.document(
          body: doc.to_html,
          title: options[:basename],
          css: options[:css],
          lang: options[:locale],
        )
      end

      def print_pdf(html_path, pdf_path)
        args = [
          Dependencies.chromium!, *CHROMIUM_ARGS,
          "--print-to-pdf=#{pdf_path}", "file://#{html_path}",
        ]
        out = IO.popen(args, err: %i[child out], &:read)
        return true if $CHILD_STATUS&.success? && File.exist?(pdf_path)

        raise ConversionError, "chromium failed to render:\n#{out}"
      rescue Errno::ENOENT, Errno::EACCES => e
        raise MissingDependencyError.new(
          'chromium', "chromium could not be executed: #{e.message}",
        )
      end

      # Always absolute, so the line printed at the end says exactly
      # where the file landed rather than something the reader has
      # to resolve against a directory they have to guess.
      def output_path(md_path, basename, output, output_dir)
        return File.expand_path(output) if output

        dir = output_dir || base_dir_for(md_path)
        File.expand_path("#{basename}.pdf", dir)
      end

      def report(pdf_path)
        size = (File.size(pdf_path) / 1024.0).round(1)
        puts "#{pdf_path} (#{size} KB)"
      end

      def open_pdf(pdf_path)
        command = opener
        unless command
          warn 'md2pdf: no way to open a PDF on this platform. Set MD2PDF_OPENER to the command you use.'
          return false
        end

        silent = { out: File::NULL, err: File::NULL }
        pid = Process.spawn(*command, pdf_path, silent)
        Process.detach(pid)
        true
      rescue SystemCallError => e
        warn "md2pdf: could not open the PDF: #{e.message}"
        false
      end

      # MD2PDF_OPENER wins, so anyone whose desktop is not covered
      # here, or who simply prefers another viewer, can say so. It
      # has to name a real program: a shell alias or function is
      # invisible to a spawned process.
      def opener
        override = ENV['MD2PDF_OPENER'].to_s.strip
        return Shellwords.split(override) unless override.empty?

        OPENERS[Platform.os]
      end

      # Counts H2s outside fenced code, so a `## ` line inside a
      # sample does not inflate the TOC decision.
      def h2_count(text)
        count = 0
        in_code = false
        text.each_line do |line|
          if line.match?(/\A\s*```/)
            in_code = !in_code
            next
          end
          next if in_code

          count += 1 if line.match?(/\A## /)
        end
        count
      end

      def word_count(text)
        text.scan(/[[:alpha:][:digit:]]+/).size
      end
    end
  end
end
