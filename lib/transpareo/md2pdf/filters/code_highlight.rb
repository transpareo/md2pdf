# frozen_string_literal: true

module Transpareo
  module Md2pdf
    module Filters
      # Colours fenced code blocks with Rouge, using inline styles so
      # the PDF stays self-contained. Blocks with no language, or an
      # unknown one, are left as plain text.
      module CodeHighlight
        module_function

        def call(doc)
          doc.fragment.css('pre > code').each do |code|
            pre = code.parent
            language = pre['lang'].to_s
            pre['class'] = [pre['class'], 'sourceCode'].compact.join(' ')
            code['class'] =
              ['sourceCode', language].reject(&:empty?).join(' ')

            highlighted = Highlighter.highlight(code.text, language)
            code.inner_html = highlighted if highlighted
          end
        end
      end
    end
  end
end
