require 'tmpdir'
require 'shellwords'
require 'fileutils'

module Md2pdf
  module Runner
    DEMOTE_FILTER_PATH = File.expand_path('demote.lua', __dir__)
    TOC_FILTER_PATH = File.expand_path('toc.lua', __dir__)
    PROBE_FILTER_PATH = File.expand_path('probe.lua', __dir__)
    TITLE_PAGE_FILTER_PATH = File.expand_path('title_page.lua', __dir__)
    FOOTNOTES_FILTER_PATH = File.expand_path('footnotes.lua', __dir__)

    PROBE_RE = /\[\[md2pdf:([^\]]+)\]\]/
    TOC_MIN_H2 = 3
    TOC_MIN_WORDS = 1500

    module_function

    def convert(md_path, flat:, unwrap:, toc: false, toc_depth: 2,
                toc_label: nil, toc_min: TOC_MIN_H2,
                toc_min_words: TOC_MIN_WORDS,
                footnotes_label: nil,
                output: nil, output_dir: nil, open: false,
                style: {})
      unless File.exist?(md_path)
        warn "Not found: #{md_path}"
        return
      end

      basename = File.basename(md_path, '.md')
      pdf_dir = output_dir || File.dirname(File.expand_path(md_path))
      pdf_path = output || File.join(pdf_dir, "#{basename}.pdf")
      FileUtils.mkdir_p(File.dirname(pdf_path))

      text = Config.strip_front_matter(File.read(md_path))
      text = Unwrap.call(text) if unwrap
      toc &&= h2_count(text) >= toc_min &&
        word_count(text) >= toc_min_words

      Dir.mktmpdir('md2pdf') do |tmpdir|
        md_tmp = File.join(tmpdir, 'doc.md')
        css_path = File.join(tmpdir, 'style.css')
        html_tmp = File.join(tmpdir, 'doc.html')
        pages_file = File.join(tmpdir, 'toc-pages.txt')
        File.write(md_tmp, text)
        File.write(css_path, Style.build(**style))
        File.write(pages_file, '')

        pandoc_args = base_pandoc_args(
          md_tmp: md_tmp, css_path: css_path, html_tmp: html_tmp,
          basename: basename, flat: flat, toc: toc,
          toc_depth: toc_depth, toc_label: toc_label,
          footnotes_label: footnotes_label,
          pages_file: pages_file
        )

        return unless render_pass(pandoc_args, html_tmp, pdf_path, md_path)

        if toc
          pages = extract_anchor_pages(pdf_path)
          if pages.any?
            File.write(
              pages_file,
              pages.map { |id, p| "#{id} #{p}" }.join("\n")
            )
            return unless render_pass(
              pandoc_args, html_tmp, pdf_path, md_path
            )
          end
        end

        size = (File.size(pdf_path) / 1024.0).round(1)
        puts "#{pdf_path} (#{size} KB)"
        open_pdf(pdf_path) if open
      end
    end

    def open_pdf(pdf_path)
      pid = Process.spawn(
        'xdg-open', pdf_path,
        out: '/dev/null', err: '/dev/null'
      )
      Process.detach(pid)
    rescue Errno::ENOENT
      warn 'md2pdf: xdg-open not found; cannot --open the PDF'
    end

    def base_pandoc_args(md_tmp:, css_path:, html_tmp:, basename:,
                         flat:, toc:, toc_depth:, toc_label:,
                         footnotes_label:, pages_file:)
      args = [
        PANDOC, md_tmp,
        '--from=gfm+fenced_divs',
        '--to=html5',
        '--standalone',
        '--variable', "pagetitle=#{basename}",
        '--css', css_path,
        '--embed-resources',
        '-o', html_tmp
      ]
      args += [
        '--lua-filter', TITLE_PAGE_FILTER_PATH,
        '--lua-filter', FOOTNOTES_FILTER_PATH,
        '--metadata', "md2pdf-toc=#{toc}"
      ]
      args += ['--lua-filter', DEMOTE_FILTER_PATH] if flat
      if footnotes_label
        args += ['--metadata', "footnotes-title=#{footnotes_label}"]
      end
      if toc
        args += [
          '--lua-filter', TOC_FILTER_PATH,
          '--lua-filter', PROBE_FILTER_PATH,
          '--metadata', "toc-depth=#{toc_depth}",
          '--metadata', "toc-pages-file=#{pages_file}"
        ]
        args += ['--metadata', "toc-title=#{toc_label}"] if toc_label
      end
      args
    end

    def render_pass(pandoc_args, html_tmp, pdf_path, md_path)
      unless system(*pandoc_args)
        warn "pandoc failed: #{md_path}"
        return false
      end

      chromium_args = [
        CHROMIUM,
        '--headless=new',
        '--disable-gpu',
        '--no-sandbox',
        "--print-to-pdf=#{pdf_path}",
        '--no-pdf-header-footer',
        '--virtual-time-budget=2000',
        "file://#{html_tmp}"
      ]

      out = IO.popen(chromium_args, err: %i[child out], &:read)
      unless $?.success? && File.exist?(pdf_path)
        warn "chromium failed: #{md_path}\n#{out}"
        return false
      end
      true
    end

    def h2_count(text)
      count = 0
      in_code = false
      text.each_line do |line|
        if line =~ /\A\s*```/
          in_code = !in_code
          next
        end
        next if in_code
        count += 1 if line =~ /\A## /
      end
      count
    end

    def word_count(text)
      text.scan(/[[:alpha:][:digit:]]+/).size
    end

    def extract_anchor_pages(pdf_path)
      pages = {}
      text = `pdftotext #{Shellwords.escape(pdf_path)} -`
      text.split("\f").each_with_index do |page_text, i|
        page_num = i + 1
        page_text.scan(PROBE_RE) do |m|
          pages[m[0]] ||= page_num
        end
      end
      pages
    end
  end
end
