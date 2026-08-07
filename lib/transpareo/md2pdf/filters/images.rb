# frozen_string_literal: true

require 'cgi'

module Transpareo
  module Md2pdf
    module Filters
      # Inlines local images as data URIs.
      #
      # The HTML handed to the browser lives in a temporary
      # directory, so a relative `![](diagram.png)` would resolve
      # against the wrong place and silently render as nothing.
      # Paths are resolved against the source document instead, and
      # the bytes are embedded, which also keeps the finished PDF
      # free of external references.
      #
      # Remote URLs are left alone for the browser to fetch.
      module Images
        MIME_TYPES = {
          '.png' => 'image/png',
          '.jpg' => 'image/jpeg',
          '.jpeg' => 'image/jpeg',
          '.gif' => 'image/gif',
          '.svg' => 'image/svg+xml',
          '.webp' => 'image/webp',
          '.avif' => 'image/avif',
          '.bmp' => 'image/bmp',
          '.ico' => 'image/x-icon',
        }.freeze

        REMOTE = %r{\A(?:https?:|data:|//)}i

        # Past this, a data URI costs more than it is worth; the
        # warning points at a document that will render slowly.
        LARGE_FILE_BYTES = 10 * 1024 * 1024

        module_function

        def call(doc)
          base_dir = doc[:base_dir] || Dir.pwd

          doc.fragment.css('img').each do |img|
            src = img['src'].to_s
            next if src.empty? || src.match?(REMOTE)

            uri = data_uri(resolve(src, base_dir))
            img['src'] = uri if uri
          end
        end

        def resolve(src, base_dir)
          path = src.sub(/[?#].*\z/, '')
          path = CGI.unescape(path) if path.include?('%')
          File.absolute_path?(path) ? path : File.join(base_dir, path)
        end

        def data_uri(path)
          unless File.file?(path)
            warn "md2pdf: image not found, skipping: #{path}"
            return nil
          end

          mime = MIME_TYPES[File.extname(path).downcase]
          unless mime
            warn "md2pdf: unsupported image type, skipping: #{path}"
            return nil
          end

          bytes = File.binread(path)
          warn "md2pdf: large image (#{bytes.bytesize / 1024 / 1024} MB): #{File.basename(path)}" if bytes.bytesize > LARGE_FILE_BYTES

          "data:#{mime};base64,#{[bytes].pack('m0')}"
        end
      end
    end
  end
end
