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
resolved page numbers. Auto-skipped if the document has
fewer than 3 H2 headings.

Output PDFs are placed next to the input files.

## Options

- `--flat` — Demote H2/H3 to bold paragraphs so the PDF has
  only the H1 title as a heading.
- `--unwrap` — Join hard-wrapped paragraph lines before
  rendering. Off by default; pandoc handles soft-wrapped
  paragraphs as a single paragraph already, and unwrap can
  occasionally corrupt nested fenced code blocks.
- `--no-toc` — Disable the table of contents.
- `--toc-depth=N` — TOC depth. 1 = H2 only, 2 = H2 + H3
  (default), 3 = also H4.

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

## TOC rendering

Real page numbers are resolved via a two-pass render:
invisible probes are added to each heading on pass 1,
located via `pdftotext`, then baked into the TOC on pass 2.
Roughly doubles render time. The TOC entry box reserves
space for the largest plausible page number so layout is
stable across passes.

## Configuration

Override defaults via env:

    PANDOC=/usr/bin/pandoc
    CHROMIUM=/usr/bin/chromium
    MD2PDF_LOGO=/path/to/footer-logo.svg
    MD2PDF_LOGO_COLOR=/path/to/header-logo.svg

The header logo prints once on the first page; the footer
logo prints on every page in monochrome. Both are optional.

## Layout

    bin/md2pdf                  CLI entrypoint
    lib/md2pdf.rb               module loader
    lib/md2pdf/cli.rb           argv parsing + dispatch
    lib/md2pdf/runner.rb        pandoc + chromium pipeline
    lib/md2pdf/style.rb         CSS template loader
    lib/md2pdf/style.css.erb    print stylesheet
    lib/md2pdf/unwrap.rb        paragraph unwrap heuristic
    lib/md2pdf/demote.lua       pandoc filter for --flat
    lib/md2pdf/toc.lua          builds the TOC AST node
    lib/md2pdf/probe.lua        invisible heading probes for
                                two-pass page-number resolution
