# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Gives every heading a stable, unique id. The TOC, the page
      # probes and the footnote backrefs all address headings by id,
      # so this has to run before any of them.
      module Slugs
        module_function

        def call(doc)
          seen = Hash.new(0)

          doc.headings.each do |heading|
            next unless heading['id'].to_s.empty?

            base = slugify(heading.text) || 'section'
            seen[base] += 1
            suffix = seen[base] > 1 ? "-#{seen[base] - 1}" : ''
            heading['id'] = "#{base}#{suffix}"
          end
        end

        def slugify(text)
          slug = text.to_s.downcase.strip
            .gsub(/[^\p{Word}\s-]/u, '')
            .gsub(/[\s_]+/, '-')
            .gsub(/-+/, '-')
            .delete_prefix('-')
            .delete_suffix('-')
          slug.empty? ? nil : slug
        end
      end
    end
  end
end
