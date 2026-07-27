# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  include TestSupport

  FM = "---\nmd2pdf:\n  font-size: 14pt\n  bogus: 1\n---\nbody\n"

  # Runs the block against a throwaway HOME, so the real one is
  # never read and never written.
  def in_tree
    Dir.mktmpdir do |tmp|
      home = File.join(tmp, 'home')
      FileUtils.mkdir_p(home)
      with_env('HOME' => home, 'XDG_CONFIG_HOME' => nil) do
        yield home, tmp
      end
    end
  end

  def mkdir(*parts)
    path = File.join(*parts)
    FileUtils.mkdir_p(path)
    path
  end

  def write_config(dir, yaml)
    File.write(File.join(dir, '.md2pdf.yml'), yaml)
  end

  def settings_for(dir)
    md = File.join(dir, 'r.md')
    File.write(md, "# R\n")
    Transpareo::Md2pdf.settings(md)
  end

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
                                               'bogus' => 1,)

    assert_equal({ font_size: '14pt' }, out)
  end

  def test_load_front_matter_only_reads_md2pdf_key
    assert_equal({ font_size: '14pt' },
                 Transpareo::Md2pdf::Config.load_front_matter(FM),)
    assert_empty(
      Transpareo::Md2pdf::Config.load_front_matter("---\nother: 1\n---\nx\n"),
    )
  end

  def test_resolve_precedence_cli_over_front_matter_over_file
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.md2pdf.yml'),
                 "font-size: 10pt\nline-height: 1.5\n",)
      md = File.join(dir, 'doc.md')
      File.write(md, "---\nmd2pdf:\n  font-size: 12pt\n---\nbody\n")

      cfg = Transpareo::Md2pdf::Config.resolve(md, font_size: '20pt')

      assert_equal '20pt', cfg[:font_size] # CLI wins
      assert_in_delta(1.5, cfg[:line_height]) # from file config
    end
  end

  def test_the_walk_reaches_a_config_several_levels_up
    Dir.mktmpdir do |dir|
      cfg = File.join(dir, '.md2pdf.yml')
      File.write(cfg, "font-size: 9pt\n")
      sub = File.join(dir, 'a', 'b')
      FileUtils.mkdir_p(sub)

      assert_equal [cfg],
                   Transpareo::Md2pdf::Config.ancestor_config_files(sub)
    end
  end

  # Layering

  # Settings put higher up exist to apply further down. Reading
  # only the nearest file would mean a project that sets one thing
  # discards everything its parents established.
  def test_a_nearer_config_layers_over_a_further_one
    in_tree do |home|
      write_config(home, "logo: /global.svg\nfont-size: 9pt\n")
      project = mkdir(home, 'project')
      write_config(project, "font-size: 14pt\n")

      style = settings_for(project)[:style]

      assert_equal '14pt', style[:font_size]
      assert_equal '/global.svg', style[:logo]
    end
  end

  def test_every_ancestor_contributes
    in_tree do |home|
      write_config(home, "logo: /global.svg\n")
      docs = mkdir(home, 'docs')
      write_config(docs, "link-color: \"#222222\"\n")
      deep = mkdir(docs, 'q3')
      write_config(deep, "font-size: 13pt\n")

      style = settings_for(deep)[:style]

      assert_equal '/global.svg', style[:logo]
      assert_equal '#222222', style[:link_color]
      assert_equal '13pt', style[:font_size]
    end
  end

  # The ancestor walk stops at HOME, so a document elsewhere would
  # otherwise get no personal defaults at all.
  def test_the_global_config_applies_outside_home
    in_tree do |home, tmp|
      write_config(home, "logo: /global.svg\n")
      outside = mkdir(tmp, 'elsewhere')

      assert_equal '/global.svg', settings_for(outside)[:style][:logo]
    end
  end

  def test_an_xdg_config_is_preferred_over_the_home_dotfile
    in_tree do |home|
      write_config(home, "logo: /dotfile.svg\n")
      xdg = mkdir(home, '.config', 'md2pdf')
      File.write(File.join(xdg, 'config.yml'), "logo: /xdg.svg\n")

      assert_equal '/xdg.svg', settings_for(home)[:style][:logo]
    end
  end

  def test_locales_merge_across_layers_instead_of_replacing
    in_tree do |home|
      write_config(home, <<~YAML)
        locales:
          de:
            toc-label: Inhalt Global
          sv:
            toc-label: Innehall
      YAML
      project = mkdir(home, 'project')
      write_config(project, <<~YAML)
        locales:
          de:
            footnotes-label: Projektquellen
      YAML

      cfg = Transpareo::Md2pdf::Config.resolve(
        File.join(project, 'r.de.md'), {},
      )

      # The project adds a label without dropping the global one,
      # and the unrelated locale survives.
      assert_equal 'Inhalt Global', cfg[:locales]['de'][:toc_label]
      assert_equal 'Projektquellen',
                   cfg[:locales]['de'][:footnotes_label]
      assert_equal 'Innehall', cfg[:locales]['sv'][:toc_label]
    end
  end

  def test_each_layer_resolves_its_own_relative_paths
    in_tree do |home|
      write_config(home, "logo: brand/logo.svg\n")
      project = mkdir(home, 'project')
      write_config(project, "custom-css: styles/print.css\n")

      style = settings_for(project)[:style]

      assert_equal File.join(home, 'brand', 'logo.svg'), style[:logo]
      assert_equal File.join(project, 'styles', 'print.css'),
                   style[:custom_css]
    end
  end

  # Order is what makes layering work, so it is asserted directly
  # rather than inferred from a merged result.
  def test_ancestors_come_back_outermost_first
    in_tree do |home|
      docs = mkdir(home, 'docs')
      deep = mkdir(docs, 'q3')
      write_config(docs, "logo: /a.svg\n")
      write_config(deep, "logo: /b.svg\n")

      assert_equal [
        File.join(docs, '.md2pdf.yml'), File.join(deep, '.md2pdf.yml'),
      ], Transpareo::Md2pdf::Config.ancestor_config_files(deep)
    end
  end

  # HOME belongs to the global layer, so the walk must not also
  # claim it, or the global file would be both.
  def test_the_walk_stops_below_home
    in_tree do |home|
      write_config(home, "logo: /home.svg\n")
      project = mkdir(home, 'project')

      assert_empty Transpareo::Md2pdf::Config
        .ancestor_config_files(project)
    end
  end

  def test_no_ancestors_when_none_exist
    Dir.mktmpdir do |dir|
      assert_empty Transpareo::Md2pdf::Config.ancestor_config_files(dir)
    end
  end
end
