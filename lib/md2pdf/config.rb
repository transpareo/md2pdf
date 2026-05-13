require 'yaml'

module Md2pdf
  module Config
    CONFIG_FILE = '.md2pdf.yml'

    # Whitelist of keys we accept from YAML config / front-matter.
    # All keys are normalised to snake_case symbols.
    KEYS = %i[
      flat unwrap toc toc_depth toc_label toc_min toc_min_words
      footnotes_label
      font_size line_height font_family code_font_family
      page_size margins
      output output_dir
      logo header_logo footer_logo page_numbers
      link_color custom_css
    ].freeze

    module_function

    # Resolve effective settings for a given input file. Precedence
    # (highest -> lowest): CLI -> YAML front-matter -> .md2pdf.yml
    # walked up from the input's directory.
    def resolve(md_path, cli_opts)
      base_dir = File.dirname(File.expand_path(md_path))
      file_config = load_config_file(find_config_file(base_dir))
      text = File.exist?(md_path) ? File.read(md_path) : ''
      front_matter = load_front_matter(text)
      file_config.merge(front_matter).merge(cli_opts)
    end

    # Walk up from start_dir, stopping at HOME (inclusive) or root.
    def find_config_file(start_dir)
      home = File.expand_path('~')
      dir = start_dir
      loop do
        path = File.join(dir, CONFIG_FILE)
        return path if File.file?(path)
        parent = File.dirname(dir)
        break if dir == parent
        break if dir == home
        dir = parent
      end
      nil
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
        out[key] = v if KEYS.include?(key)
      end
    end
  end
end
