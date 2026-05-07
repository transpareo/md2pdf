-- Wrap the H1 + the leading lead blocks in
-- <div class="title-page"> so CSS can vertically center
-- them on the first page. The wrapping kicks in only
-- when the document gets a TOC and has no explicit
-- ::: intro ::: block. In every other case the
-- title and lead content flow normally from the top of
-- page 1, exactly as plain pandoc renders them.
--
-- Rule:
--   wrap when: TOC enabled AND no Div { class = "intro" }
--   else:      no wrap

local function is_intro(block)
  if block.t ~= 'Div' then return false end
  for _, c in ipairs(block.classes or {}) do
    if c == 'intro' then return true end
  end
  return false
end

function Pandoc(doc)
  local toc =
    pandoc.utils.stringify(doc.meta['md2pdf-toc'] or '') == 'true'
  if not toc then return doc end

  for _, b in ipairs(doc.blocks) do
    if is_intro(b) then return doc end
  end

  local h1_idx
  for i, b in ipairs(doc.blocks) do
    if b.t == 'Header' and b.level == 1 then
      h1_idx = i
      break
    end
  end
  if not h1_idx then return doc end

  local end_idx = #doc.blocks + 1
  for i = h1_idx + 1, #doc.blocks do
    local b = doc.blocks[i]
    if b.t == 'Header' and b.level == 2 then
      end_idx = i
      break
    end
  end

  local wrapped = {}
  for i = h1_idx, end_idx - 1 do
    table.insert(wrapped, doc.blocks[i])
  end
  local div = pandoc.Div(wrapped, pandoc.Attr('', { 'title-page' }, {}))

  local new_blocks = {}
  for i = 1, h1_idx - 1 do
    table.insert(new_blocks, doc.blocks[i])
  end
  table.insert(new_blocks, div)
  for i = end_idx, #doc.blocks do
    table.insert(new_blocks, doc.blocks[i])
  end
  doc.blocks = new_blocks
  return doc
end
