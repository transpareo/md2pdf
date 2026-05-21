-- Inserts <wbr> hints inside inline `code` spans at break-friendly
-- positions (path separators, snake_case underscores, dots,
-- camelCase boundaries, etc.) so narrow table cells can break a
-- long identifier between segments instead of mid-character.

local function html_escape(s)
  s = s:gsub('&', '&amp;')
  s = s:gsub('<', '&lt;')
  s = s:gsub('>', '&gt;')
  return s
end

local function inject_wbr(s)
  s = s:gsub('([/_%-.#:{}])', '%1<wbr>')
  s = s:gsub('(%l)(%u)', '%1<wbr>%2')
  return s
end

local function attr_str(attr)
  local parts = {}
  if attr.identifier and attr.identifier ~= '' then
    parts[#parts + 1] = ' id="' .. attr.identifier .. '"'
  end
  if attr.classes and #attr.classes > 0 then
    parts[#parts + 1] =
      ' class="' .. table.concat(attr.classes, ' ') .. '"'
  end
  for _, kv in ipairs(attr.attributes or {}) do
    parts[#parts + 1] =
      ' ' .. kv[1] .. '="' .. html_escape(kv[2]) .. '"'
  end
  return table.concat(parts)
end

function Code(el)
  local text = inject_wbr(html_escape(el.text))
  return pandoc.RawInline(
    'html', '<code' .. attr_str(el.attr) .. '>' .. text .. '</code>'
  )
end
