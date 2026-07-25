# frozen_string_literal: true

module Transpareo
  module Md2pdf
    # Per-locale default labels, and locale detection from a
    # filename suffix such as `report.de.md`.
    module Locales
      DEFAULTS = {
        'en' => { toc_label: 'Contents',  footnotes_label: 'Footnotes' },
        'de' => { toc_label: 'Inhalt',    footnotes_label: 'Quellen' },
        'fr' => { toc_label: 'Sommaire',  footnotes_label: 'Notes' },
        'es' => { toc_label: 'Índice',    footnotes_label: 'Notas' },
        'it' => { toc_label: 'Indice',    footnotes_label: 'Note' },
        'pt' => { toc_label: 'Sumário',   footnotes_label: 'Notas' },
        'nl' => { toc_label: 'Inhoud',    footnotes_label: 'Voetnoten' }
      }.freeze

      FILENAME_RE = /\.([a-z]{2})\.md\z/i

      module_function

      # Pull the locale out of a filename like `foo.de.md`. Returns the
      # 2-letter code (downcased) only when it matches a known locale,
      # so unrelated suffixes (`script.js.md`) don't get misread.
      def detect(path)
        m = File.basename(path).match(FILENAME_RE)
        return nil unless m

        code = m[1].downcase
        DEFAULTS.key?(code) ? code : nil
      end

      def defaults_for(locale)
        DEFAULTS[locale] || DEFAULTS['en']
      end

      def known?(locale)
        DEFAULTS.key?(locale)
      end
    end
  end
end
