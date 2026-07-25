# frozen_string_literal: true

require 'English'
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

      CHROMIUM_ARGS = %w[
        --headless=new
        --disable-gpu
        --no-sandbox
        --no-pdf-header-footer
        --virtual-time-budget=2000
      ].freeze

      module_function

      # Returns true when a PDF was written. Named as a command
      # rather than a predicate because writing the file is the
      # point; the boolean is just the outcome.
      # rubocop:disable Naming/PredicateMethod
      def convert(md_path, flat:, unwrap:, toc: false, toc_depth: 2,
                  toc_label: nil, toc_min: TOC_MIN_H2,
                  toc_min_words: TOC_MIN_WORDS,
                  footnotes_label: nil, locale: nil,
                  output: nil, output_dir: nil, open: false,
                  style: {})
        unless File.exist?(md_path)
          warn "md2pdf: not found: #{md_path}"
          return false
        end

        basename = File.basename(md_path, '.md')
        pdf_path = output_path(md_path, basename, output, output_dir)
        FileUtils.mkdir_p(File.dirname(pdf_path))

        text = Config.strip_front_matter(File.read(md_path))
        text = Unwrap.call(text) if unwrap
        toc &&= h2_count(text) >= toc_min &&
                word_count(text) >= toc_min_words

        render(text, pdf_path, {
                 flat: flat, toc: toc, toc_depth: toc_depth,
                 toc_label: toc_label, footnotes_label: footnotes_label,
                 locale: locale, basename: basename,
                 css: Style.build(**style)
               })

        report(pdf_path)
        open_pdf(pdf_path) if open
        true
      end
      # rubocop:enable Naming/PredicateMethod

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
          toc_pages: pages
        )
        doc.apply(
          Filters.chain(flat: options[:flat], toc: options[:toc])
        )
        Renderer.document(
          body: doc.to_html, title: options[:basename],
          css: options[:css], lang: options[:locale]
        )
      end

      def print_pdf(html_path, pdf_path)
        args = [
          Dependencies.chromium!, *CHROMIUM_ARGS,
          "--print-to-pdf=#{pdf_path}", "file://#{html_path}"
        ]
        out = IO.popen(args, err: %i[child out], &:read)
        return true if $CHILD_STATUS&.success? && File.exist?(pdf_path)

        raise ConversionError, "chromium failed to render:\n#{out}"
      rescue Errno::ENOENT, Errno::EACCES => e
        raise MissingDependencyError.new(
          'chromium', "chromium could not be executed: #{e.message}"
        )
      end

      def output_path(md_path, basename, output, output_dir)
        return output if output

        dir = output_dir || File.dirname(File.expand_path(md_path))
        File.join(dir, "#{basename}.pdf")
      end

      def report(pdf_path)
        size = (File.size(pdf_path) / 1024.0).round(1)
        puts "#{pdf_path} (#{size} KB)"
      end

      def open_pdf(pdf_path)
        pid = Process.spawn(
          'xdg-open', pdf_path, out: File::NULL, err: File::NULL
        )
        Process.detach(pid)
      rescue Errno::ENOENT
        warn 'md2pdf: xdg-open not found; cannot open the PDF'
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
