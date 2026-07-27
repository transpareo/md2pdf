# frozen_string_literal: true

require 'yaml'

require_relative 'locales'

module Transpareo
  module Md2pdf
    # Resolves effective settings from CLI flags, YAML front-matter
    # in the document, and the nearest .md2pdf.yml.
    module Config
      CONFIG_FILE = '.md2pdf.yml'

      # Whitelist of keys we accept from YAML config / front-matter.
      # All keys are normalised to snake_case symbols.
      KEYS = %i[
        locale locales
        flat unwrap toc toc_depth toc_label toc_min toc_min_words
        footnotes_label
        font_size line_height font_family code_font_family
        page_size margins
        output output_dir
        logo header_logo footer_logo page_numbers footer_title
        link_color custom_css
      ].freeze

      # `locales` is the one nested key: a map of locale code to
      # label overrides, so its inner keys need normalising too and
      # its outer keys must be left alone.
      NESTED_KEYS = %i[locales].freeze

      module_function

      # Resolve effective settings for a given input file. Precedence
      # (highest -> lowest): CLI -> YAML front-matter -> .md2pdf.yml
      # walked up from the input's directory.
      # `text` is supplied when the document did not come from a
      # file, since stdin can only be read once and its front matter
      # still has to configure the render.
      def resolve(md_path, cli_opts, text = nil)
        base_dir = File.dirname(File.expand_path(md_path))
        text ||= File.exist?(md_path) ? File.read(md_path) : ''
        front_matter = expand_paths(load_front_matter(text), base_dir)

        # A path is relative to whatever declared it, so each config
        # file is expanded against its own directory before the
        # layers are combined. Flags stay relative to the shell,
        # which is what typing a path into a terminal implies.
        settings = config_files(base_dir).reduce({}) do |merged, path|
          layer = expand_paths(load_config_file(path), File.dirname(path))
          combine(merged, layer)
        end

        combine(combine(settings, front_matter), cli_opts)
      end

      # Every config that applies here, least specific first: the
      # global one, then each ancestor from the outermost in.
      #
      # All of them are read and layered. Taking only the nearest
      # would mean a project file that sets a font size discards the
      # logo its parent directory established, which is the opposite
      # of what putting settings higher up is for.
      def config_files(start_dir)
        ([global_config_file] + ancestor_config_files(start_dir))
          .compact.uniq
      end

      # Honours XDG, and keeps ~/.md2pdf.yml working. Unlike the
      # ancestor walk this applies wherever the document lives, so a
      # file outside HOME still picks up personal defaults.
      def global_config_file
        [
          File.join(xdg_config_home, 'md2pdf', 'config.yml'),
          File.join(Dir.home, CONFIG_FILE),
        ].find { |path| File.file?(path) }
      rescue ArgumentError
        nil
      end

      def xdg_config_home
        ENV['XDG_CONFIG_HOME'] || File.join(Dir.home, '.config')
      end

      # Merges one layer over another. Only `locales` is combined
      # rather than replaced, so a project can add or adjust a
      # single locale without discarding the rest.
      def combine(base, overlay)
        base.merge(overlay) do |key, old, new|
          next new unless key == :locales &&
                          old.is_a?(Hash) && new.is_a?(Hash)

          old.merge(new) { |_code, a, b| a.merge(b) }
        end
      end

      # Every setting that names a file or directory. Outputs are
      # included deliberately: a committed `output-dir: build` means
      # build inside this project, not wherever the shell happens to
      # be standing.
      PATH_KEYS = %i[logo custom_css output output_dir].freeze

      def expand_paths(settings, dir)
        PATH_KEYS.each do |key|
          value = settings[key]
          next unless value.is_a?(String) && !value.empty?
          next if File.absolute_path?(value)

          settings[key] = File.expand_path(value, dir)
        end
        settings
      end

      # Every .md2pdf.yml between start_dir and HOME, returned
      # outermost first so nearer files layer over further ones.
      #
      # HOME itself is excluded: a config there is personal rather
      # than structural, and is picked up as the global layer so it
      # applies to documents outside HOME too.
      def ancestor_config_files(start_dir)
        home = File.expand_path('~')
        found = []
        dir = start_dir
        loop do
          break if dir == home

          path = File.join(dir, CONFIG_FILE)
          found << path if File.file?(path)

          parent = File.dirname(dir)
          break if dir == parent

          dir = parent
        end
        found.reverse
      end

      def load_config_file(path)
        return {} unless path

        data = YAML.safe_load_file(path)
        normalize(data)
      rescue StandardError => e
        warn "md2pdf: failed to load #{path}: #{e.message}"
        {}
      end

      # Front-matter format:
      #   ---
      #   md2pdf:
      #     font-size: 14pt
      #   ---
      def load_front_matter(text)
        yaml = front_matter_yaml(text)
        return {} unless yaml

        data = YAML.safe_load(yaml)
        return {} unless data.is_a?(Hash) && data['md2pdf'].is_a?(Hash)

        normalize(data['md2pdf'])
      rescue StandardError
        {}
      end

      # Returns the document body with any leading YAML front-matter
      # block stripped off, or the original text when none is present.
      def strip_front_matter(text)
        return text unless front_matter_yaml(text)

        idx = text.index("\n---", 4)
        after = text[(idx + 4)..]
        after.sub(/\A\r?\n/, '')
      end

      def front_matter_yaml(text)
        return nil unless text.start_with?("---\n")

        end_idx = text.index("\n---", 4)
        return nil unless end_idx

        text[4...end_idx]
      end

      def normalize(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), out|
          key = k.to_s.tr('-', '_').to_sym
          next unless KEYS.include?(key)

          out[key] = NESTED_KEYS.include?(key) ? normalize_locales(v) : v
        end
      end

      # locales:
      #   de:
      #     toc-label: Inhaltsverzeichnis
      #
      # Locale codes stay verbatim (downcased); only the label keys
      # inside are normalised, and unknown ones are dropped.
      def normalize_locales(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(code, labels), out|
          next unless labels.is_a?(Hash)

          entry = normalize_labels(labels)
          out[code.to_s.downcase] = entry unless entry.empty?
        end
      end

      def normalize_labels(labels)
        labels.each_with_object({}) do |(k, v), out|
          key = k.to_s.tr('-', '_').to_sym
          out[key] = v.to_s if Locales::LABEL_KEYS.include?(key)
        end
      end
    end
  end
end
