# Contributing

## Setup

```sh
bin/setup            # bundle install, then a dependency check
```

You need a Chromium or Chrome on the machine. `bin/setup` tells you
whether one was found; `bundle exec exe/md2pdf install-deps` fetches
one if not.

## Tasks

```sh
rake test            # minitest suite
rake rubocop         # lint
rake readme_pdf      # re-render docs/README.pdf and the screenshot
rake checksums       # refresh pinned Chromium sums after a bump
```

Integration tests drive a real browser and skip when none is
available, so the unit suite still runs on a bare machine. CI fails
the build if anything skipped, because a silently shrinking suite is
worse than a red one.

## How a document becomes a PDF

```
markdown
  strip front matter, optionally unwrap paragraphs   Config, Unwrap
  rewrite ::: fenced divs into raw HTML              Markdown
  parse to HTML                                      commonmarker
  transform the DOM through the filter chain         Filters
  wrap in a standalone HTML document                 Renderer
  print to PDF                                       Chromium
  read heading destinations, render again            PageIndex
```

The second pass only runs for documents with a table of contents,
and only when the first pass produced destinations to resolve.

## Filter order is load-bearing

`Filters.chain` assembles the pipeline. Three constraints:

- `Slugs` runs first. Everything that links to a heading needs ids
  to exist.
- `Demote` runs before `Toc`, so a `--flat` document exposes no
  headings for the table of contents to collect.
- `CodeWbr` runs last. It rewrites inline code into markup that the
  text-reading filters can no longer parse.

There are tests asserting each of these. If you reorder the chain
and they fail, the test is right.

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

## Style

RuboCop is the arbiter and CI enforces it. Beyond that:

- Lines stay within 80 columns.
- Comments explain why, not what. A comment that would stop making
  sense once the surrounding work is forgotten is saying the wrong
  thing.
- No em-dashes or arrow glyphs anywhere, including comments and
  commit messages. Use a spaced hyphen.

## Adding a filter

Filters are modules with a single `call(doc)` that mutate
`doc.fragment` in place. Add the file under `filters/`, require it
in `filters.rb`, place it in `chain` with a comment if its position
matters, and test it through `TestSupport#render_html`, which runs
the real chain without a browser.

## Releasing

1. Bump `lib/transpareo/md2pdf/version.rb`.
2. Move the unreleased notes in `CHANGELOG.md` under the new
   version.
3. `rake build` then `rake release`.

Bumping the pinned Chromium in `installer.rb` means re-running
`rake checksums` and pasting the results into `CHECKSUMS`. The
macOS archives cannot be smoke-tested from Linux, so say so in the
pull request if that is all you did.
