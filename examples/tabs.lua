-- tabs
loadfile("tui.lua")()

mon = peripheral.find("monitor")

local test = Panel{inside = {
  Panel{side="top", size=3, inside={
    Button{name="close", side="right", size=3, text="X", backgroundColor=colors.gray, textColor=colors.red},
  }},
  Tab{tabs={
    {"one", Panel{title="panel one", padding=1, borderChars={"+","-","|"}}},
    {"two", Panel{title="panel two", padding=1, borderChars={"#","=","H"}}}
  }}
}}

function close:mouse_click()
  self:stop()
end

test:run(term, mon)