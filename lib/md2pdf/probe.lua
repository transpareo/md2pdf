-- Add an invisible text probe to each H2/H3 so the
-- first-pass PDF can be searched for headings via
-- pdftotext. Probes survive PDF text extraction and
-- contribute negligibly to layout (1px font, transparent
-- fill, collapsed letter-spacing). The runner reads probe
-- positions from the intermediate PDF, then re-renders
-- with the resolved page numbers in the TOC.

function Header(el)
  if el.level < 2 or el.level > 3 then return el end
  if not el.identifier or el.identifier == '' then return el end

  local marker = pandoc.RawInline(
    'html',
    '<span class="md2pdf-probe">[[md2pdf:' .. el.identifier .. ']]</span>'
  )
  el.content:insert(1, marker)
  return el
end
