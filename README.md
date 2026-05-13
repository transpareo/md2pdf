# md2pdf

Convert markdown to PDF via `pandoc` -> HTML -> headless
Chromium. Browsers handle table layout, code blocks, and
CSS far better than wkhtmltopdf.

## Install

Requires `pandoc`, `chromium`, and `pdftotext` (poppler)
on PATH. `pdftotext` is only needed for `--toc`. Symlink
the executable into a directory on your PATH:

    ln -s ~/code/md2pdf/bin/md2pdf ~/.local/bin/md2pdf

## Usage

    md2pdf file.md
    md2pdf *.md
    md2pdf --flat file.md      # only H1 rendered as heading
    md2pdf --unwrap file.md    # join hard-wrapped paragraphs
    md2pdf --no-toc file.md    # skip the TOC
    md2pdf                     # all .md in current dir

A table of contents (H2 + H3) is inserted by default on its
own page, between the title page and the first H2, with
resolved page numbers. Auto-skipped for short documents:
both `--toc-min` (default 3 H2s) and `--toc-min-words`
(default 1500 words) must be met. Tune either threshold to
taste.

Output PDFs are placed next to the input files.

## Options

**Content**

- `--flat` — Demote H2/H3 to bold paragraphs.
- `--unwrap` — Join hard-wrapped paragraph lines.
- `--no-toc` — Disable the table of contents.
- `--toc-depth=N` — TOC depth. 1 = H2 only, 2 = H2 + H3
  (default), 3 = also H4.
- `--toc-label=TEXT` — TOC heading text. Default `Contents`.
- `--toc-min=N` — Min H2 count to auto-include TOC (default 3).
- `--toc-min-words=N` — Min word count to auto-include TOC
  (default 1500). Both this and `--toc-min` must be met.
- `--footnotes-label=TEXT` — Heading for the footnotes
  section at the end of the document. Default `Footnotes`.
  Pass an empty string (`--footnotes-label=""`) to render
  the list without a heading.

**Typography**

- `--font-size=Npt` — Body font size (default `11pt`).
- `--line-height=N` — Body line-height (default `1.8`).
- `--font-family="..."` — Body font stack.
- `--code-font-family="..."` — Monospace stack for code.

**Layout**

- `--page-size=NAME` — `A4`, `Letter`, `A5`, `Legal`, …
- `--margins="T R B L"` — Page margins (default
  `"22mm 20mm 24mm 20mm"`).
- `--output=FILE` — Output path.
- `--output-dir=DIR` — Output directory.

**Branding**

- `--logo=PATH` — SVG logo. Header uses the original colors;
  footer is **derived automatically** in grey from the same
  file (no second logo needed).
- `--no-header-logo` — Hide the first-page logo.
- `--no-footer-logo` — Hide the per-page footer logo.
- `--no-page-numbers` — Hide the page-number counter.

**Style**

- `--link-color=#hex` — Link color (default `#0a4a90`).
- `--custom-css=FILE` — Append your own stylesheet rules.

**Misc**

- `--open` — Open each generated PDF with `xdg-open` after
  rendering. Useful for quick previews.

## Title page

The H1 + lead block is vertically centered on page 1
**only when the document has a TOC and no `::: intro :::`
block.** In every other case (no TOC, or `::: intro :::`
present) the title flows from the top of page 1 as plain
pandoc would render it.

Use `::: intro :::` to keep your introduction on page 1
flowing right after the title:

```markdown
# Document Title

*Subtitle line.*

::: intro

A multi-paragraph introduction that lands on page 1,
right after the subtitle, before the TOC kicks in on
the following page.

:::

## First Section
```

## Footnotes

Pandoc's footnote syntax is supported and used to render a
list of sources at the end of the document.

```markdown
The first attempt failed.[^attempt]
A later attempt succeeded.[^attempt]

[^attempt]: Internal lab note, 2026-04-19.
[^rfc]: IETF RFC 8785. https://rfc-editor.org/rfc/rfc8785.
```

Each `[^id]` reference becomes a numbered superscript link.
All definitions are collected into a single `Footnotes`
section appended to the document, with a backref arrow on
every entry. References that share the same definition text
are deduplicated to a single list item — useful when the
same source is cited from multiple places.

If the source markdown ends with a manual heading like
`## Footnotes`, that heading is consumed automatically so
it doesn't double up with the auto-rendered section.

The section heading is configurable:

- `--footnotes-label="Sources"` (CLI)
- `footnotes-label: Quellen` (YAML front-matter or
  `.md2pdf.yml`)
- `--footnotes-label=""` to render the list without any
  heading

## TOC rendering

Real page numbers are resolved via a two-pass render:
invisible probes are added to each heading on pass 1,
located via `pdftotext`, then baked into the TOC on pass 2.
Roughly doubles render time. The TOC entry box reserves
space for the largest plausible page number so layout is
stable across passes.

## Configuration files

Settings can come from three places. Precedence,
highest first:

1. **CLI flags** — single-doc, highest priority.
2. **YAML front-matter** in the document itself — lives
   under an `md2pdf:` key so it doesn't collide with
   anything else:

   ```markdown
   ---
   md2pdf:
     font-size: 14pt
     toc-label: Inhalt
   ---

   # My Document
   ```

   The whole `---…---` block is consumed by md2pdf and
   stripped before pandoc renders the body, so it never
   appears in the PDF.

3. **`.md2pdf.yml`** — project defaults. md2pdf walks up
   from the input file's directory until it finds one
   (or hits `$HOME`):

   ```yaml
   font-size: 14pt
   line-height: 1.6
   page-size: A4
   margins: "22mm 20mm 24mm 20mm"
   toc-label: Contents
   logo: /path/to/logo.svg
   link-color: "#0a4a90"
   ```

YAML keys mirror the CLI flag names without the `--`
prefix (`font-size`, `toc-label`, `no-page-numbers` →
`page-numbers: false`, etc.).

## Environment variables

    PANDOC=/usr/bin/pandoc
    CHROMIUM=/usr/bin/chromium
    MD2PDF_LOGO=/path/to/logo.svg

`MD2PDF_LOGO` is the fallback for `--logo`. The footer
logo on every page is derived from the same file with
all colors recoloured to grey; no second file needed.

## Layout

    bin/md2pdf                  CLI entrypoint
    lib/md2pdf.rb               module loader
    lib/md2pdf/cli.rb           argv parsing + dispatch
    lib/md2pdf/config.rb        config-file + front-matter loader
    lib/md2pdf/runner.rb        pandoc + chromium pipeline
    lib/md2pdf/style.rb         CSS template loader
    lib/md2pdf/style.css.erb    print stylesheet
    lib/md2pdf/unwrap.rb        paragraph unwrap heuristic
    lib/md2pdf/demote.lua       pandoc filter for --flat
    lib/md2pdf/footnotes.lua    pandoc filter for footnotes
    lib/md2pdf/toc.lua          builds the TOC AST node
    lib/md2pdf/title_page.lua   title-page wrap filter
    lib/md2pdf/probe.lua        invisible heading probes for
                                two-pass page-number resolution
