-- Collects every Note inline in the document, replaces it with a
-- numbered <sup> reference, and appends a section of definitions
-- with backrefs at the end. The section heading text is taken
-- from the `footnotes-title` metadata (default `Footnotes`). When
-- the input markdown already has a manual heading immediately
-- before the footnote definitions (e.g. `## Footnotes`), pandoc
-- consumes the definitions and leaves the heading dangling at the
-- end of the document; that trailing heading is removed here so
-- it does not double up with the auto-rendered section.

local function meta_string(meta, key, default)
  if meta[key] == nil then return default end
  return pandoc.utils.stringify(meta[key])
end

local notes = {}
local notes_by_key = {}
local first_ref_anchor = {}
local ref_counter = 0

function Note(elem)
  local key = pandoc.utils.stringify(elem.content)
  local id = notes_by_key[key]
  if not id then
    id = #notes + 1
    notes[id] = elem.content
    notes_by_key[key] = id
  end

  ref_counter = ref_counter + 1
  local anchor = 'fnref' .. id .. '-' .. ref_counter
  if not first_ref_anchor[id] then
    first_ref_anchor[id] = anchor
  end

  local link = pandoc.Link(
    { pandoc.Str(tostring(id)) },
    '#fn' .. id,
    '',
    pandoc.Attr(
      anchor,
      { 'footnote-ref' },
      { { 'role', 'doc-noteref' } }
    )
  )
  return pandoc.Superscript({ link })
end

local function strip_trailing_heading(blocks)
  for i = #blocks, 1, -1 do
    local b = blocks[i]
    if b.t == 'Header' then
      table.remove(blocks, i)
      return
    end
    if b.t ~= 'Null' then return end
  end
end

local function append_backref(item_blocks, anchor)
  for i = #item_blocks, 1, -1 do
    local b = item_blocks[i]
    if b.t == 'Para' or b.t == 'Plain' then
      table.insert(b.content, pandoc.Space())
      table.insert(b.content, pandoc.Link(
        { pandoc.Str('\u{21A9}') },
        '#' .. anchor,
        '',
        pandoc.Attr(
          '',
          { 'footnote-back' },
          { { 'role', 'doc-backlink' } }
        )
      ))
      return
    end
  end
  table.insert(item_blocks, pandoc.Para({
    pandoc.Link(
      { pandoc.Str('\u{21A9}') },
      '#' .. anchor,
      '',
      pandoc.Attr(
        '',
        { 'footnote-back' },
        { { 'role', 'doc-backlink' } }
      )
    )
  }))
end

local function render_item(blocks)
  local doc = pandoc.Pandoc(blocks)
  local html = pandoc.write(doc, 'html5')
  return html
end

function Pandoc(doc)
  if #notes == 0 then return doc end

  local title = meta_string(doc.meta, 'footnotes-title', 'Footnotes')

  strip_trailing_heading(doc.blocks)

  if title ~= '' then
    table.insert(doc.blocks, pandoc.Header(
      2,
      { pandoc.Str(title) },
      pandoc.Attr('footnotes', { 'footnotes-title' }, {})
    ))
  end

  local html_parts = {
    '<div id="footnotes-section" class="footnotes" role="doc-endnotes">',
    '<ol class="footnotes-list">'
  }
  for i, blocks in ipairs(notes) do
    local item = {}
    for _, b in ipairs(blocks) do table.insert(item, b) end
    append_backref(item, first_ref_anchor[i])
    html_parts[#html_parts + 1] =
      '<li id="fn' .. i .. '" role="doc-endnote">' ..
      render_item(item) .. '</li>'
  end
  html_parts[#html_parts + 1] = '</ol></div>'

  table.insert(
    doc.blocks,
    pandoc.RawBlock('html', table.concat(html_parts, '\n'))
  )
  return doc
end
