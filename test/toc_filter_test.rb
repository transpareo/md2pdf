require_relative 'test_helper'

# Drives the real pandoc filter chain end to end and checks that
# headings carrying inline `code` keep clean, formatting-stripped
# text in the generated TOC. Skips when pandoc is unavailable.
class TocFilterTest < Minitest::Test
  FIXTURE = <<~MD
    # Title

    ## Plain heading

    Body text.

    ## Config `ApiConsumer` reference

    Body text.

    ## The `viewed_authority` action in `AuditLog`

    Body text.
  MD

  def setup
    skip 'pandoc not available' unless TestSupport.pandoc?
  end

  def test_inline_code_in_headings_renders_clean_toc_text
    texts = toc_texts(render_toc)
    assert_includes texts, 'Config ApiConsumer reference'
    assert_includes texts, 'The viewed_authority action in AuditLog'
  end

  def test_toc_carries_no_raw_html_or_dropped_code
    nav = render_toc
    refute_match(/&lt;code/, nav, 'TOC leaked escaped <code> markup')
    toc_texts(nav).each do |t|
      refute_match(/\S\s{2,}\S/, t,
        "TOC entry #{t.inspect} has a gap from dropped code")
    end
  end

  private

  # Render the document and return the <nav id="TOC"> fragment.
  def render_toc
    Dir.mktmpdir('md2pdf-test') do |dir|
      md = File.join(dir, 'doc.md')
      html = File.join(dir, 'doc.html')
      css = File.join(dir, 'style.css')
      pages = File.join(dir, 'pages.txt')
      File.write(md, FIXTURE)
      File.write(css, '')
      File.write(pages, '')

      args = Md2pdf::Runner.base_pandoc_args(
        md_tmp: md, css_path: css, html_tmp: html, basename: 'doc',
        flat: false, toc: true, toc_depth: 2, toc_label: 'Contents',
        footnotes_label: nil, locale: 'en', pages_file: pages
      )
      assert system(*args, out: File::NULL, err: File::NULL),
        'pandoc render failed'

      File.read(html)[/<nav id="TOC".*?<\/nav>/m] or
        flunk('no TOC nav in output')
    end
  end

  def toc_texts(nav)
    nav.scan(/class="toc-text">(.*?)<\/span>/m).flatten
  end
end
