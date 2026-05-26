require_relative 'test_helper'

# Drives the real pandoc filter chain and checks that code-block
# language aliases skylighting doesn't ship (`jsonc`, `js`, `yml`,
# ...) get rewritten to a real lexer, so the block is highlighted
# instead of rendered as a plain, uncolored <pre>.
class CodeAliasTest < Minitest::Test
  def setup
    skip 'pandoc not available' unless TestSupport.pandoc?
  end

  def test_jsonc_is_highlighted_via_javascript_lexer
    html = render("```jsonc\n{\n  // note\n  \"a\": 1\n}\n```\n")
    assert_match(/class="sourceCode javascript"/, html)
    assert_match(/class="co"/, html, 'comment was not highlighted')
  end

  def test_json5_routes_to_javascript_lexer
    html = render("```json5\n{ \"a\": 1 }\n```\n")
    assert_match(/class="sourceCode javascript"/, html)
  end

  def test_short_aliases_map_to_canonical_lexers
    {
      'js' => 'javascript', 'ts' => 'typescript', 'py' => 'python',
      'rb' => 'ruby', 'yml' => 'yaml', 'sh' => 'bash'
    }.each do |name, lexer|
      html = render("```#{name}\nx\n```\n")
      assert_match(/class="sourceCode #{lexer}"/, html,
        "#{name} did not map to #{lexer}")
    end
  end

  def test_uppercase_alias_is_normalized
    html = render("```JS\nx\n```\n")
    assert_match(/class="sourceCode javascript"/, html)
  end

  def test_known_lexer_passes_through
    html = render("```ruby\nx = 1\n```\n")
    assert_match(/class="sourceCode ruby"/, html)
  end

  def test_unknown_language_is_left_unhighlighted
    html = render("```nonsense\nx\n```\n")
    refute_match(/class="sourceCode/, html)
  end

  private

  def render(md_text)
    Dir.mktmpdir('md2pdf-test') do |dir|
      md = File.join(dir, 'doc.md')
      html = File.join(dir, 'doc.html')
      css = File.join(dir, 'style.css')
      pages = File.join(dir, 'pages.txt')
      File.write(md, md_text)
      File.write(css, '')
      File.write(pages, '')

      args = Md2pdf::Runner.base_pandoc_args(
        md_tmp: md, css_path: css, html_tmp: html, basename: 'doc',
        flat: false, toc: false, toc_depth: 2, toc_label: nil,
        footnotes_label: nil, locale: 'en', pages_file: pages
      )
      assert system(*args, out: File::NULL, err: File::NULL),
        'pandoc render failed'
      File.read(html)
    end
  end
end
