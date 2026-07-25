# frozen_string_literal: true

require_relative 'test_helper'

class MarkdownTest < Minitest::Test
  Markdown = Transpareo::Md2pdf::Markdown

  def test_expands_fenced_div_to_html
    out = Markdown.expand_fenced_divs("::: intro\n\ntext\n\n:::\n")

    assert_includes out, '<div class="intro">'
    assert_includes out, '</div>'
  end

  def test_supports_brace_wrapped_class_syntax
    out = Markdown.expand_fenced_divs("::: {.note}\nx\n:::\n")

    assert_includes out, '<div class="note">'
  end

  def test_leaves_colons_inside_code_fences_alone
    src = "```\n::: intro\n:::\n```\n"

    assert_equal src, Markdown.expand_fenced_divs(src)
  end

  def test_closes_unbalanced_div_at_end_of_document
    out = Markdown.expand_fenced_divs("::: intro\n\ntext\n")

    assert_equal 1, out.scan('<div class="intro">').size
    assert_equal 1, out.scan('</div>').size
  end

  def test_renders_gfm_tables
    assert_includes Markdown.to_html("| a |\n|---|\n| 1 |\n"), '<table>'
  end

  def test_renders_strikethrough_and_autolinks
    html = Markdown.to_html("~~gone~~ https://example.com\n")

    assert_includes html, '<del>'
    assert_includes html, '<a href="https://example.com"'
  end

  def test_leaves_code_blocks_unhighlighted_for_the_filter
    html = Markdown.to_html("```ruby\ndef a; end\n```\n")

    refute_includes html, 'style="color'
    assert_includes html, 'lang="ruby"'
  end
end
