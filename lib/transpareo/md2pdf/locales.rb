# frozen_string_literal: true

module Transpareo
  module Md2pdf
    # Per-locale default labels, and locale detection from a
    # filename suffix such as `report.de.md`.
    #
    # A config file can override any of these and add locales that
    # are not built in, so a project can ship its own wording
    # without the gem having to know about it.
    module Locales
      DEFAULTS = {
        'en' => { toc_label: 'Contents',  footnotes_label: 'Footnotes' },
        'de' => { toc_label: 'Inhalt',    footnotes_label: 'Quellen' },
        'fr' => { toc_label: 'Sommaire',  footnotes_label: 'Notes' },
        'es' => { toc_label: 'Índice',    footnotes_label: 'Notas' },
        'it' => { toc_label: 'Indice',    footnotes_label: 'Note' },
        'pt' => { toc_label: 'Sumário',   footnotes_label: 'Notas' },
        'nl' => { toc_label: 'Inhoud',    footnotes_label: 'Voetnoten' },
      }.freeze

      LABEL_KEYS = %i[toc_label footnotes_label].freeze

      FILENAME_RE = /\.([a-z]{2,3})\.md\z/i

      module_function

      # Built-in labels merged with whatever the config supplied. A
      # custom entry only has to name the labels it changes.
      def table(overrides = nil)
        return DEFAULTS if overrides.nil? || overrides.empty?

        DEFAULTS.merge(overrides) do |_code, built_in, custom|
          built_in.merge(custom)
        end
      end

      # Pulls the locale out of a filename like `report.de.md`, only
      # when the code names a locale we actually know, so unrelated
      # suffixes such as `script.js.md` are not misread.
      def detect(path, overrides = nil)
        match = File.basename(path).match(FILENAME_RE)
        return nil unless match

        code = match[1].downcase
        table(overrides).key?(code) ? code : nil
      end

      def defaults_for(locale, overrides = nil)
        known = table(overrides)
        known[locale] || known['en'] || DEFAULTS['en']
      end

      def known?(locale, overrides = nil)
        table(overrides).key?(locale)
      end
    end
  end
end
