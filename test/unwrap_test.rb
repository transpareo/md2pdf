# frozen_string_literal: true

require_relative 'test_helper'

class UnwrapTest < Minitest::Test
  def call(text)
    Transpareo::Md2pdf::Unwrap.call(text)
  end

  def test_joins_consecutive_prose_lines
    assert_equal "foo bar baz\n", call("foo\nbar\nbaz\n")
  end

  def test_keeps_paragraph_breaks
    assert_equal "foo\n\nbar\n", call("foo\n\nbar\n")
  end

  def test_does_not_join_into_headings
    assert_equal "foo\n# Head\ntext\n", call("foo\n# Head\ntext\n")
  end

  def test_does_not_join_list_items
    assert_equal "- one\n- two\n", call("- one\n- two\n")
  end

  def test_does_not_join_ordered_list_items
    assert_equal "1. one\n2. two\n", call("1. one\n2. two\n")
  end

  def test_does_not_join_table_rows
    assert_equal "| a | b |\n| c | d |\n", call("| a | b |\n| c | d |\n")
  end

  def test_does_not_join_blockquotes
    assert_equal "> quote\n> more\n", call("> quote\n> more\n")
  end

  def test_preserves_fenced_code_blocks_verbatim
    src = "```\nline one\nline two\n```\n"

    assert_equal src, call(src)
  end
end
