# transpareo-md2pdf

Convert markdown to polished PDFs by rendering through headless
Chromium, so tables, code blocks and CSS behave the way they do on
the web instead of the way a bespoke PDF engine guesses.

Chromium is the only external program required. Markdown parsing,
syntax highlighting and PDF inspection are all gems, so
`bundle install` handles them.

## Install

```sh
gem install transpareo-md2pdf
```

Then check what the machine already has:

```sh
md2pdf doctor
```

```
  ok    chromium      148.0.7778.215  /usr/bin/chromium
  ok    commonmarker  2.9.0  gem
  ok    nokogiri      1.19.4  gem
  ok    rouge         4.7.0  gem
  ok    pdf-reader    2.15.1  gem
  ok    rubyzip       2.4.1  gem
```

If Chromium is missing, either install it with your package manager
or let md2pdf fetch a known-good build:

```sh
md2pdf install-deps
```

That downloads Google's `chrome-headless-shell` for your platform
into `~/.local/share/md2pdf`, verifies it against a SHA-256 sum
shipped in the gem, and unpacks it. It needs no root, never touches
your `PATH`, and never runs on its own. Add `--force` to reinstall
and `--latest` to take the current stable build instead of the
pinned one (which skips checksum verification, since there is
nothing pinned to compare against).

Chromium is resolved in this order:

1. the `CHROMIUM` environment variable
2. the directory written by `install-deps`
3. the first match on `PATH`
4. the standard macOS application bundles

## Usage

```sh
md2pdf file.md
md2pdf *.md                # all .md in current dir
md2pdf 'docs/*.md'         # globs are expanded internally
md2pdf                     # same as md2pdf *.md
md2pdf --flat file.md      # only H1 rendered as heading
md2pdf --unwrap file.md    # join hard-wrapped paragraphs
md2pdf --no-toc file.md    # skip the TOC
```

Output PDFs are written next to the input files unless `--output` or
`--output-dir` says otherwise.

A table of contents covering H2 and H3 is inserted by default on its
own page, between the title page and the first H2, with real page
numbers. It is skipped automatically for short documents: both
`--toc-min` (default 3 H2s) and `--toc-min-words` (default 1500
words) must be met.

### As a library

```ruby
require 'transpareo/md2pdf'

Transpareo::Md2pdf.convert('report.md', toc: true, locale: 'de')
```

`convert` returns true when the PDF was written. Missing
dependencies raise `Transpareo::Md2pdf::MissingDependencyError`;
render failures raise `Transpareo::Md2pdf::ConversionError`. Nothing
in the library calls `exit`.

## Options

**Content**

- `--flat` - Demote H2/H3 to bold paragraphs.
- `--unwrap` - Join hard-wrapped paragraph lines.
- `--no-toc` - Disable the table of contents.
- `--toc-depth=N` - TOC depth. 1 = H2 only, 2 = H2 + H3 (default),
  3 = also H4.
- `--toc-label=TEXT` - TOC heading text. Default per locale.
- `--toc-min=N` - Min H2 count to auto-include the TOC (default 3).
- `--toc-min-words=N` - Min word count to auto-include the TOC
  (default 1500). Both thresholds must be met.
- `--footnotes-label=TEXT` - Heading for the footnotes section.
  Default per locale. Pass an empty string to render the list with
  no heading.
- `--locale=CODE` - `en`, `de`, `fr`, `es`, `it`, `pt`, `nl`.
  Auto-detected from filenames like `report.de.md`, falling back to
  `en`. Sets the default TOC and footnote labels and the `lang`
  attribute on the output.

**Typography**

- `--font-size=Npt` - Body font size (default `11pt`).
- `--line-height=N` - Body line-height (default `1.8`).
- `--font-family="..."` - Body font stack.
- `--code-font-family="..."` - Monospace stack for code.

**Layout**

- `--page-size=NAME` - `A4`, `Letter`, `A5`, `Legal`, and so on.
- `--margins="T R B L"` - Page margins (default
  `"22mm 20mm 24mm 20mm"`).
- `--output=FILE` - Output path.
- `--output-dir=DIR` - Output directory.

**Branding**

- `--logo=PATH` - SVG logo. The header uses the original colors; the
  footer logo is derived from the same file in grey, so no second
  asset is needed. There is no built-in logo.
- `--no-header-logo` - Hide the first-page logo.
- `--no-footer-logo` - Hide the per-page footer logo.
- `--no-page-numbers` - Hide the page-number counter.

**Style**

- `--link-color=#hex` - Link color (default `#0a4a90`).
- `--custom-css=FILE` - Append your own stylesheet rules.

**Misc**

- `--open` - Open the PDF with `xdg-open` afterwards. Rejected when
  multiple files would be opened at once.
- `-v`, `--version` - Print the version.
- `-h`, `--help` - Print help.

## Title page

The H1 and lead block are vertically centered on page 1 **only when
the document has a TOC and no `::: intro :::` block.** Otherwise the
title flows from the top of page 1.

Use `::: intro :::` to keep an introduction on page 1, right after
the title:

```markdown
# Document Title

*Subtitle line.*

::: intro

A multi-paragraph introduction that lands on page 1, right after
the subtitle, before the TOC starts on the following page.

:::

## First Section
```

## Footnotes

Standard footnote syntax is supported and renders a list of sources
at the end of the document.

```markdown
The first attempt failed.[^attempt]
A later attempt succeeded.[^attempt]

[^attempt]: Internal lab note, 2026-04-19.
[^rfc]: IETF RFC 8785. https://rfc-editor.org/rfc/rfc8785.
```

Each `[^id]` becomes a numbered superscript link, numbered in the
order references appear. Entries whose definition text is identical
are merged into a single list item, which is what you want when the
same source is cited from several places. Every entry gets a
backlink to its first reference.

If the source ends with a manual heading like `## Footnotes`, that
heading is consumed so it does not double up with the rendered one.

The heading is configurable via `--footnotes-label="Sources"`, the
`footnotes-label` config key, or `--footnotes-label=""` for no
heading at all.

## How page numbers are resolved

The document is rendered twice. The first pass lays it out with
placeholder page numbers. Chromium writes a PDF destination for
every heading the TOC links to, so the second pass reads that table
to learn which page each heading landed on and bakes the real
numbers in. This roughly doubles render time.

Because the numbers come from the PDF's own structure rather than
from scraping extracted text, they are exact and do not depend on
how a text extractor reconstructs reading order. The TOC entry box
reserves space for the widest plausible number, so both passes lay
out identically.

## Configuration files

Settings come from three places. Highest priority first:

1. **CLI flags.**
2. **YAML front-matter** in the document, under an `md2pdf:` key so
   it cannot collide with anything else:

   ```markdown
   ---
   md2pdf:
     font-size: 14pt
     toc-label: Inhalt
   ---

   # My Document
   ```

   The whole block is consumed and stripped before rendering, so it
   never appears in the PDF.

3. **`.md2pdf.yml`**, found by walking up from the input file's
   directory until one is found or `$HOME` is reached:

   ```yaml
   font-size: 14pt
   line-height: 1.6
   page-size: A4
   margins: "22mm 20mm 24mm 20mm"
   toc-label: Contents
   logo: /path/to/logo.svg
   link-color: "#0a4a90"
   ```

YAML keys mirror the CLI flags without the `--` prefix
(`font-size`, `toc-label`, and `no-page-numbers` becomes
`page-numbers: false`).

## Environment variables

```
CHROMIUM=/usr/bin/chromium     Browser override
MD2PDF_LOGO=/path/to/logo.svg  Default for --logo
MD2PDF_HOME=~/.local/share/md2pdf   Managed install directory
```

## Docker

The bundled Dockerfile ships Chromium and the fonts it needs:

```sh
docker build -t transpareo-md2pdf .
docker run --rm -v "$PWD:/work" transpareo-md2pdf report.md
```

## Continuous integration

A fresh CI runner has no browser, so install one before rendering:

```yaml
- uses: ruby/setup-ruby@v1
  with:
    ruby-version: '3.3'
    bundler-cache: true

- name: Install Chromium
  run: sudo apt-get update && sudo apt-get install -y chromium

- run: bundle exec md2pdf docs/*.md
```

Alternatively drop the apt step and run `bundle exec md2pdf
install-deps`, which caches well because the download URL is pinned.

## Layout

```
exe/md2pdf                      CLI entrypoint
lib/transpareo/md2pdf.rb        module loader + convert()
  cli.rb                        argv parsing, doctor, install-deps
  config.rb                     config file + front-matter loader
  dependencies.rb               Chromium resolution and reporting
  document.rb                   parsed document + filter host
  errors.rb                     error hierarchy
  filters.rb                    ordered filter chain
  filters/slugs.rb              stable heading ids
  filters/title_page.rb         title page wrap
  filters/footnotes.rb          renumber, merge, render footnotes
  filters/demote.rb             --flat heading demotion
  filters/toc.rb                table of contents
  filters/code_highlight.rb     Rouge syntax highlighting
  filters/code_wbr.rb           break hints in inline code
  filters/tables.rb             table wrapping and header sizing
  highlighter.rb                Rouge lexer resolution
  installer.rb                  Chromium downloader
  locales.rb                    per-locale label defaults
  markdown.rb                   markdown to HTML, fenced divs
  page_index.rb                 heading to page map from the PDF
  platform.rb                   OS and CPU detection
  renderer.rb                   standalone HTML document
  runner.rb                     two-pass render pipeline
  style.rb                      CSS template loader
  style.css.erb                 print stylesheet
  unwrap.rb                     paragraph unwrap heuristic
```

## Development

```sh
bin/setup            # bundle install
rake test            # minitest suite
rake rubocop         # lint
rake checksums       # refresh pinned Chromium sums after a bump
```

The suite covers the filter chain, config resolution, locale
handling, the unwrap heuristic, CLI parsing and exit codes, the
dependency resolver and the installer. Integration tests drive a
real browser and skip when none is available, so the unit suite
still runs on a bare machine.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
