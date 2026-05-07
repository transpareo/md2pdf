-- Build a TOC from H2/H3 headings and insert it before
-- the first H2, so the title (H1) stays on page 1 and the
-- TOC lands on its own page (CSS page-break around it).
--
-- Skipped if the document has fewer than `toc-min-h2`
-- H2 headings (default 3). Depth is controlled by
-- `toc-depth` (default 2). Title via `toc-title`.

local function escape(s)
  s = s:gsub('&', '&amp;')
  s = s:gsub('<', '&lt;')
  s = s:gsub('>', '&gt;')
  s = s:gsub('"', '&quot;')
  return s
end

local function meta_string(meta, key, default)
  if meta[key] == nil then return default end
  return pandoc.utils.stringify(meta[key])
end

local function load_pages(path)
  local pages = {}
  if not path or path == '' then return pages end
  local f = io.open(path, 'r')
  if not f then return pages end
  for line in f:lines() do
    local id, page = line:match('^(%S+)%s+(%d+)$')
    if id and page then pages[id] = tonumber(page) end
  end
  f:close()
  return pages
end

function Pandoc(doc)
  local depth = tonumber(meta_string(doc.meta, 'toc-depth', '2')) or 2
  local title = meta_string(doc.meta, 'toc-title', 'Contents')
  local min_h2 = tonumber(meta_string(doc.meta, 'toc-min-h2', '3')) or 3
  local pages = load_pages(meta_string(doc.meta, 'toc-pages-file', ''))

  local headings = {}
  local h2_count = 0
  for i = 1, #doc.blocks do
    local b = doc.blocks[i]
    if b.t == 'Header' then
      if b.level == 2 then h2_count = h2_count + 1 end
      if b.level >= 2 and b.level <= depth then
        headings[#headings + 1] = b
      end
    end
  end

  if h2_count < min_h2 then return doc end

  local parts = { '<nav id="TOC" role="doc-toc">' }
  if title ~= '' then
    parts[#parts + 1] =
      '<h2 class="toc-title">' .. escape(title) .. '</h2>'
  end
  parts[#parts + 1] = '<ul class="toc-list">'
  for _, h in ipairs(headings) do
    local id = h.identifier or ''
    local text = pandoc.utils.stringify(h.content)
    local cls = 'toc-l' .. h.level
    local page = pages[id] and tostring(pages[id]) or '?'
    parts[#parts + 1] = string.format(
      '<li class="%s"><a href="#%s">' ..
        '<span class="toc-text">%s</span>' ..
        '<span class="toc-dots"></span>' ..
        '<span class="toc-page">%s</span>' ..
      '</a></li>',
      cls, id, escape(text), escape(page)
    )
  end
  parts[#parts + 1] = '</ul></nav>'

  local toc_block = pandoc.RawBlock('html', table.concat(parts, '\n'))

  local out = {}
  local inserted = false
  for i = 1, #doc.blocks do
    local b = doc.blocks[i]
    if not inserted and b.t == 'Header' and b.level == 2 then
      out[#out + 1] = toc_block
      inserted = true
    end
    out[#out + 1] = b
  end
  if not inserted then
    table.insert(out, 1, toc_block)
  end
  doc.blocks = out
  return doc
end
