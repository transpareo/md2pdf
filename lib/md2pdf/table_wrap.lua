-- Wraps every table in a <div class="table-wrap"> with
-- max-width:100% + overflow-x:hidden. This isolates any
-- horizontal overflow caused by wide table content (long
-- headers with white-space:nowrap, untruncated code spans
-- etc.) so it does NOT push the document past the page width
-- and trigger Chromium's shrink-to-fit. The cost: the
-- right edge of an oversized table is clipped instead of
-- visibly extending off the page.

function Table(t)
  return pandoc.Div({ t }, pandoc.Attr('', { 'table-wrap' }, {}))
end
