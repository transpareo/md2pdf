# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org).

## [1.0.0]

First release as a gem.

### Added

- `md2pdf doctor` reports every dependency with its version, its
  resolved path and a package-manager hint for the running system.
- `md2pdf install-deps` downloads a pinned, SHA-256 verified
  `chrome-headless-shell` into the gem-managed directory. It needs no
  root, never runs implicitly, and takes `--latest` and `--force`.
- Syntax highlighting actually renders. Previous versions emitted
  highlight markup that no stylesheet matched, so every code block
  printed monochrome.
- `--version` flag.
- Library entry point `Transpareo::Md2pdf.convert(path, **options)`.

### Changed

- **pandoc is no longer required.** Markdown is parsed by
  commonmarker, transformed by Ruby filters over Nokogiri, and
  highlighted by Rouge. The nine Lua filters are gone. Chromium is
  now the only external program the gem needs.
- **`pdftotext` is no longer required.** TOC page numbers come from
  the PDF's own destination table rather than from scraping extracted
  text, which is exact instead of layout-dependent.
- Headings no longer carry invisible `[[md2pdf:id]]` marker text, so
  copying text out of a PDF no longer picks up internal markers.
- Chromium is resolved from `CHROMIUM`, then the gem-managed
  directory, then `PATH`, then the standard macOS app bundles.
- `CLI.run` returns an exit status instead of calling `exit`, so the
  library is usable in-process.

### Fixed

- Headings that landed on certain pages could resolve to no page
  number at all, leaving `?` in the table of contents.
- A missing pandoc reported `pandoc failed: <your document>`, blaming
  the document rather than the absent program. A missing Chromium
  raised an unhandled `Errno::ENOENT` with a raw backtrace. Both now
  raise `MissingDependencyError` with an actionable message.
- The default logo path pointed at a directory that existed only on
  the original author's machine. Logo resolution is now `--logo`,
  then `MD2PDF_LOGO`, then no logo.
- A missing `--logo` or `--custom-css` file warns and continues
  instead of being silently ignored.
- Glob arguments are sorted, so multi-file runs are deterministic.

### Removed

- The `--single-heading` alias remains, but the `code_alias` Lua
  filter is gone; Rouge resolves language aliases natively.
