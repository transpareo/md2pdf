-- Normalizes code-block language tags to the lexers skylighting
-- actually ships, so common aliases get highlighted instead of
-- falling back to a plain, uncolored block. Pandoc's highlighter
-- only knows canonical names (`javascript`, not `js`; `yaml`, not
-- `yml`) and has no JSON-with-comments lexer at all, so `jsonc` /
-- `json5` route to the JavaScript lexer, which colors `//`
-- comments and object literals correctly.

local ALIASES = {
  jsonc = 'javascript',
  json5 = 'javascript',
  js = 'javascript',
  jsx = 'javascriptreact',
  ts = 'typescript',
  tsx = 'typescript',
  py = 'python',
  rb = 'ruby',
  sh = 'bash',
  shell = 'bash',
  console = 'bash',
  yml = 'yaml',
  md = 'markdown',
  docker = 'dockerfile',
  ['c++'] = 'cpp',
  ['c#'] = 'cs',
}

function CodeBlock(el)
  local changed = false
  for i, class in ipairs(el.classes) do
    local canonical = ALIASES[class:lower()]
    if canonical and canonical ~= class then
      el.classes[i] = canonical
      changed = true
    end
  end
  if changed then return el end
end
