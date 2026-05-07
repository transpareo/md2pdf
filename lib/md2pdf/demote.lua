-- Demote everything below H1 so the PDF has only
-- the title as a heading. H2 -> bold; H3+ -> bold-italic.
function Header(el)
  if el.level == 1 then
    return el
  end
  if el.level == 2 then
    return pandoc.Para({ pandoc.Strong(el.content) })
  end
  return pandoc.Para({
    pandoc.Strong({ pandoc.Emph(el.content) })
  })
end
