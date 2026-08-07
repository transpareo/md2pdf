# frozen_string_literal: true

require_relative 'test_helper'

class PageIndexTest < Minitest::Test
  PageIndex = Transpareo::Md2pdf::PageIndex

  def test_decode_restores_percent_encoded_utf8
    assert_equal 'die-aas-in-kürze',
                 PageIndex.decode(:'die-aas-in-k%C3%BCrze')
  end

  def test_decode_leaves_plain_ascii_names_alone
    assert_equal 'quellen', PageIndex.decode(:quellen)
  end

  def test_decode_keeps_names_that_decode_to_invalid_utf8
    assert_equal 'bad-%ff-name', PageIndex.decode(:'bad-%ff-name')
  end
end
