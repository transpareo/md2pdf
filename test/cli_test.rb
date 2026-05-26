require_relative 'test_helper'

class CLITest < Minitest::Test
  def test_assign_toc_depth_also_enables_toc
    opts = {}
    Md2pdf::CLI.assign(opts, :toc_depth_int, '3')
    assert_equal 3, opts[:toc_depth]
    assert_equal true, opts[:toc]
  end

  def test_assign_toc_min_coerces_integer
    opts = {}
    Md2pdf::CLI.assign(opts, :toc_min_int, '5')
    assert_equal 5, opts[:toc_min]
  end

  def test_assign_toc_min_words_coerces_integer
    opts = {}
    Md2pdf::CLI.assign(opts, :toc_min_words_int, '900')
    assert_equal 900, opts[:toc_min_words]
  end

  def test_assign_passes_other_keys_through
    opts = {}
    Md2pdf::CLI.assign(opts, :locale, 'de')
    assert_equal 'de', opts[:locale]
  end

  def test_filter_markdown_drops_non_markdown
    out = nil
    _, err = capture_io do
      out = Md2pdf::CLI.filter_markdown(%w[a.md b.txt c.MD d.pdf])
    end
    assert_equal %w[a.md b.txt c.MD d.pdf].grep(/\.md\z/i), out
    assert_match(/b\.txt/, err)
    assert_match(/d\.pdf/, err)
  end
end
