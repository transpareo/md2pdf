# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  FM = "---\nmd2pdf:\n  font-size: 14pt\n  bogus: 1\n---\nbody\n"

  def test_front_matter_yaml_extracts_block
    assert_equal "md2pdf:\n  font-size: 14pt\n  bogus: 1",
                 Transpareo::Md2pdf::Config.front_matter_yaml(FM)
  end

  def test_front_matter_yaml_nil_without_block
    assert_nil Transpareo::Md2pdf::Config.front_matter_yaml("# Title\n\nbody\n")
  end

  def test_strip_front_matter_removes_block
    assert_equal "body\n", Transpareo::Md2pdf::Config.strip_front_matter(FM)
  end

  def test_strip_front_matter_passthrough_without_block
    text = "# Title\n\nbody\n"

    assert_equal text, Transpareo::Md2pdf::Config.strip_front_matter(text)
  end

  def test_normalize_kebabs_to_snake_and_whitelists
    out = Transpareo::Md2pdf::Config.normalize('font-size' => '14pt',
                                               'bogus' => 1)

    assert_equal({ font_size: '14pt' }, out)
  end

  def test_load_front_matter_only_reads_md2pdf_key
    assert_equal({ font_size: '14pt' },
                 Transpareo::Md2pdf::Config.load_front_matter(FM))
    assert_empty(
      Transpareo::Md2pdf::Config.load_front_matter("---\nother: 1\n---\nx\n")
    )
  end

  def test_resolve_precedence_cli_over_front_matter_over_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.md2pdf.yml'),
                 "font-size: 10pt\nline-height: 1.5\n")
      md = File.join(dir, 'doc.md')
      File.write(md, "---\nmd2pdf:\n  font-size: 12pt\n---\nbody\n")

      cfg = Transpareo::Md2pdf::Config.resolve(md, font_size: '20pt')

      assert_equal '20pt', cfg[:font_size] # CLI wins
      assert_in_delta(1.5, cfg[:line_height]) # from file config
    end
  end

  def test_find_config_file_walks_up_to_parent
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, '.md2pdf.yml')
      File.write(cfg, "font-size: 9pt\n")
      sub = File.join(dir, 'a', 'b')
      FileUtils.mkdir_p(sub)

      assert_equal cfg, Transpareo::Md2pdf::Config.find_config_file(sub)
    end
  end

  def test_find_config_file_nil_when_absent
    Dir.mktmpdir do |dir|
      assert_nil Transpareo::Md2pdf::Config.find_config_file(dir)
    end
  end
end
