# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org).

## [1.0.0]

First release as a gem.

### Added

- Images. Paths resolve relative to the markdown file rather than
  the working directory, and local files are embedded as data URIs
  so the finished PDF carries its own artwork. PNG, JPEG, GIF, SVG,
  WebP, AVIF, BMP and ICO. Remote sources are left for the browser.
- A `locales:` block in the config file overrides the built-in
  label sets and defines locales that are not built in. Filename
  detection recognises configured codes, so `handbok.sv.md` picks
  up a custom Swedish entry.
- `md2pdf doctor` reports every dependency with its version, its
  resolved path and a package-manager hint for the running system.
- `md2pdf install-deps` downloads a pinned, SHA-256 verified
  `chrome-headless-shell` into the gem-managed directory. It needs no
  root, never runs implicitly, and takes `--latest` and `--force`.
- Syntax highlighting actually renders. Previous versions emitted
  highlight markup that no stylesheet matched, so every code block
  printed monochrome.
- Fenced divs of any name: `::: warning` becomes
  `<div class="warning">`, so `--custom-css` can style callouts,
  admonitions and pull quotes. `::: intro` keeps its special
  meaning for the title page.
- Standard input. `-` names stdin and is assumed when nothing else
  is given and stdin is not a terminal. Without `--output` the PDF
  goes to stdout, with progress on stderr so it cannot land inside
  the document, and md2pdf refuses to write PDF bytes to a
  terminal. Front matter in piped input is honoured as usual.
- A running footer title, centred between the logo and the page
  number. It carries the document's own H1 by default, is
  overridden with `--footer-title` or `footer-title:`, and is
  removed by passing an empty string.
- `MD2PDF_OPENER` overrides the viewer `--open` launches, and may
  carry arguments.
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

- Relative `logo`, `custom-css`, `output` and `output-dir` paths
  resolve against the file that declared them: a config file
  against itself, front matter against its document, a flag against
  the shell. Previously all were resolved against the working
  directory, so a committed `.md2pdf.yml` only worked when run from
  one particular place.
- The path printed after each render is now absolute, so it says
  where the file landed rather than leaving the reader to resolve
  it against a directory they have to guess.
- A filename derived from a piped document's heading is reduced to
  a safe path component. A heading containing a slash created
  directories, one containing `..` wrote outside `--output-dir`
  altogether, and one starting with a dot produced a hidden file,
  all silently and with a zero exit status.
- Piping a document while the working directory contained any
  `.md` file silently converted that unrelated file and reported
  success, discarding the piped input. Piped input now wins over
  the directory glob.
- Input is read as UTF-8 rather than in the locale's encoding. The
  markdown parser accepts only UTF-8, so under `LANG=C` every
  document failed with a type error from inside the parser. Invalid
  bytes are now scrubbed with a warning instead of crashing.
- `--open` hardcoded `xdg-open`, so it warned and did nothing on
  macOS, a platform this gem ships Chromium builds for. It now uses
  `open` on macOS, `xdg-open` on Linux and `start` on Windows.
- `Transpareo::Md2pdf.convert` ignored `.md2pdf.yml` and front
  matter entirely, and produced an unlabelled table of contents and
  footnotes section, because settings resolution lived in the CLI.
  One resolver now backs both, so a flag, a config key and a
  library argument produce the same document.
- `--toc` did nothing distinguishable from the default: it set the
  flag but the auto-skip thresholds still applied, so there was no
  way to force a TOC onto a short document short of setting both
  thresholds to zero. It now clears them.
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
