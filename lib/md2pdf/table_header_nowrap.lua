-- Wraps each whitespace-delimited word in a table header cell
-- with <span class="nobr">. The header row then breaks only
-- between words, never inside one: "Was sie sehen" can wrap
-- as Was / sie / sehen, but single-word headers like "Aspekt"
-- or "Wo" stay intact. The table's intrinsic column min-width
-- is set by the longest word, not the entire header string,
-- so headers no longer push the table past 100% width.

local function wrap_words(inlines)
  local out = {}
  for _, inl in ipairs(inlines) do
    if inl.t == 'Str' then
      out[#out + 1] = pandoc.Span(
        { inl }, pandoc.Attr('', { 'nobr' }, {})
      )
    else
      out[#out + 1] = inl
    end
  end
  return out
end

local function process_blocks(blocks)
  for _, b in ipairs(blocks or {}) do
    if b.content then b.content = wrap_words(b.content) end
  end
end

local function process_row(row)
  for _, cell in ipairs(row.cells) do
    process_blocks(cell.contents)
  end
end

function Table(t)
  if t.head and t.head.rows then
    for _, row in ipairs(t.head.rows) do process_row(row) end
  end
  return t
end
