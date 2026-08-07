# frozen_string_literal: true

require 'pdf-reader'

module Transpareo
  module Md2pdf
    # Works out which page each heading landed on, so the second
    # render pass can bake real page numbers into the TOC.
    #
    # Chromium emits a PDF destination for every element an internal
    # link points at, which is exactly the set of headings the TOC
    # links to. Reading that table is exact: it needs no marker text
    # in the document and does not depend on how a PDF text
    # extractor happens to reconstruct reading order.
    module PageIndex
      module_function

      # Returns { heading_id => page_number }.
      def call(pdf_path)
        reader = PDF::Reader.new(pdf_path)
        objects = reader.objects
        catalog = objects.deref(objects.trailer[:Root])
        numbers = page_numbers(objects, catalog)

        destinations(objects, catalog).each_with_object({}) do |kv, out|
          name, value = kv
          page = resolve_page(objects, value, numbers)
          out[decode(name)] = page if page
        end
      rescue StandardError => e
        warn "md2pdf: could not read page numbers: #{e.message}"
        {}
      end

      # Chromium names each destination after the URL fragment of
      # the link that points at it, so a non-ASCII heading id
      # arrives percent-encoded: `k%C3%BCrze` for `kürze`. Decoding
      # restores the document's id; a name whose decoded bytes are
      # not valid UTF-8 was never percent-encoded text and is kept
      # as it came.
      def decode(name)
        raw = name.to_s.gsub(/%\h\h/) { |hex| hex[1, 2].to_i(16).chr }
        utf = raw.force_encoding(Encoding::UTF_8)
        utf.valid_encoding? ? utf : name.to_s
      end

      # Maps each page's object reference to its 1-based number by
      # walking the page tree, which may nest.
      def page_numbers(objects, catalog)
        refs = collect_pages(objects, catalog[:Pages], [])
        refs.each_with_object({}).with_index do |(ref, out), i|
          out[key(ref)] = i + 1
        end
      end

      def collect_pages(objects, ref, acc)
        node = objects.deref(ref)
        return acc unless node

        if node[:Type] == :Pages
          Array(objects.deref(node[:Kids])).each do |kid|
            collect_pages(objects, kid, acc)
          end
        else
          acc << ref
        end
        acc
      end

      # Chromium writes a plain /Dests dictionary; the name-tree form
      # under /Names is also accepted for other producers.
      def destinations(objects, catalog)
        direct = objects.deref(catalog[:Dests])
        return direct if direct.is_a?(Hash)

        names = objects.deref(catalog[:Names])
        tree = names && objects.deref(names[:Dests])
        return {} unless tree

        flatten_name_tree(objects, tree)
      end

      def flatten_name_tree(objects, node, acc = {})
        if (names = objects.deref(node[:Names]))
          names.each_slice(2) { |name, value| acc[name] = value }
        end
        Array(objects.deref(node[:Kids])).each do |kid|
          flatten_name_tree(objects, objects.deref(kid), acc)
        end
        acc
      end

      # A destination is [page_ref, /XYZ, left, top, zoom], possibly
      # wrapped in a dictionary under /D.
      def resolve_page(objects, value, numbers)
        target = objects.deref(value)
        target = objects.deref(target[:D]) if target.is_a?(Hash)
        return nil unless target.is_a?(Array)

        ref = target.first
        return nil unless ref.is_a?(PDF::Reader::Reference)

        numbers[key(ref)]
      end

      def key(ref)
        [ref.id, ref.gen]
      end
    end
  end
end
