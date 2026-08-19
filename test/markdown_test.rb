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

  # Joining an empty array yields a US-ASCII string, which the
  # parser rejects outright, so an empty document used to abort
  # with a type error raised from inside commonmarker.
  def test_renders_an_empty_document
    assert_equal '', Markdown.to_html('').strip
  end

  def test_renders_a_whitespace_only_document
    assert_equal '', Markdown.to_html("  \n\n ").strip
  end

  def test_accepts_ascii_tagged_input
    html = Markdown.to_html('# Hi'.dup.force_encoding('US-ASCII'))

    assert_includes html, '<h1'
  end

  def test_keeps_non_ascii_content_intact
    assert_includes Markdown.to_html('# Grüße'), 'Grüße'
  end

  def test_renders_gfm_tables
    assert_includes Markdown.to_html("| a |\n|---|\n| 1 |\n"), '<table>'
  end

  def test_renders_strikethrough_and_autolinks
    html = Markdown.to_html("~~gone~~ https://example.com\n")

    assert_includes html, '<del>'
    assert_includes html, '<a href="https://example.com"'
  end

  # Ordinals

  # CommonMark lets only `1.` interrupt a paragraph, so a German
  # date at the head of a hard-wrapped line turned the rest of the
  # sentence into a list item.
  def test_a_wrapped_ordinal_stays_prose
    html = Markdown.to_html(
      "Eine ab dem\n1. Januar gültige Erklärung, und weiter.\n",
    )

    refute_includes html, '<ol'
    assert_includes html, '1. Januar gültige Erklärung'
  end

  def test_an_ordinal_keeps_its_list_when_a_second_item_follows
    html = Markdown.to_html("Schritte:\n1. Erstens\n2. Zweitens\n")

    assert_includes html, '<ol'
    assert_includes html, '<li>Erstens</li>'
  end

  # The first item is often wrapped over several lines, so the `2.`
  # that proves it is a list can be some way down the block.
  def test_a_second_item_after_a_wrapped_first_one_still_counts
    html = Markdown.to_html(
      "Schritte:\n1. Erstens, mit einer\n   Fortsetzung.\n2. Zweitens\n",
    )

    assert_includes html, '<ol'
  end

  # A colon introduces a list, so a single-item one is left alone
  # rather than being read back as a sentence.
  def test_a_lone_item_under_a_colon_stays_a_list
    assert_includes Markdown.to_html("Vorgehen:\n1. Nur eins\n"), '<ol'
  end

  def test_trailing_emphasis_does_not_hide_the_colon
    html = Markdown.to_html("**Vorgehen:**\n1. Nur eins\n")

    assert_includes html, '<ol'
  end

  def test_a_list_after_a_blank_line_is_never_touched
    assert_includes Markdown.to_html("Text\n\n1. Erstens\n"), '<ol'
  end

  def test_an_ordinal_inside_a_code_fence_is_left_verbatim
    html = Markdown.to_html("Text:\n\n```\nam\n1. Januar\n```\n")

    refute_includes html, '<ol'
    assert_includes html, '1. Januar'
  end

  # The escape is an implementation detail of keeping the sentence
  # whole and must not reach the reader as markup.
  def test_the_escape_does_not_leak_into_the_html
    html = Markdown.to_html("Eine ab dem\n1. Januar gültige Erklärung.\n")

    refute_includes html, 'data-escaped-char'
    refute_includes html, '1\.'
  end

  def test_leaves_code_blocks_unhighlighted_for_the_filter
    html = Markdown.to_html("```ruby\ndef a; end\n```\n")

    refute_includes html, 'style="color'
    assert_includes html, 'lang="ruby"'
  end
end
