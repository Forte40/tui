Panel = {}

local nextId = 0
setmetatable(Panel, {
  __call = function(self, arg)
    nextId = nextId + 1
    local panel = {id = nextId}
    setmetatable(panel, self)
    self.__index = self
    -- top, bottom, left, right, fill (default)
    panel.side = arg.side or "fill"
    panel.size = arg.size
    panel.color = arg.color
    if type(arg.inside) == "table" then
      panel.inside = {}
      for i, innerWidget in ipairs(arg.inside) do
        innerWidget.outside = panel
        table.insert(panel.inside, innerWidget)
      end
    end
    return panel
  end
})

function Panel:resize(top, left, rows, cols)
  -- loop through inside widgets allocating space
  self.top = top
  self.left = left
  self.rows = rows
  self.cols = cols
  if self.inside then
    for i, widget in ipairs(self.inside) do
      if widget.side == "left" then
        if not widget.size then
          widget.size = cols
        end
        widget:resize(top, left, rows, math.min(widget.size, cols))
        left = left + widget.cols
        cols = cols - widget.cols
      elseif widget.side == "right" then
        if not widget.size then
          widget.size = cols
        end
        widget:resize(top, left + cols - math.min(widget.size, cols), rows, math.min(widget.size, cols))
        cols = cols - widget.cols
      elseif widget.side == "top" then
        if not widget.size then
          widget.size = rows
        end
        widget:resize(top, left, math.min(widget.size, rows), cols)
        top = top + widget.rows
        rows = rows - widget.rows
      elseif widget.side == "bottom" then
        if not widget.size then
          widget.size = rows
        end
        widget:resize(top + rows - math.min(widget.size, rows), left, math.min(widget.size, rows), cols)
        rows = rows - widget.rows
      else
        widget:resize(top, left, rows, cols)
        top = top + rows
        left = left + cols
        rows = 0
        cols = 0
      end
    end
  end
end

function Panel:display(term)
  print(string.format("%s: %d,%d %dx%d", self.side, self.top, self.left, self.rows, self.cols))
  if self.inside then
    for i, widget in ipairs(self.inside) do
      widget:display()
    end
  end
end

Term = {}
function Term:new(rows, cols)
  local obj = {}
  setmetatable(obj, self)
  self.__index = self
  obj.rows = rows
  obj.cols = cols
  obj.text = {}
  for row = 1, rows do
    table.insert(obj.text, {})
    for col = 1, cols do
      table.insert(obj.text[row], ".")
    end
  end
  return obj
end
function Term:getSize()
  return self.rows, self.cols
end
function Term:display()
  for row, rowData in ipairs(self.text) do
    for col, colData in ipairs(rowData) do
      io.write(colData)
    end
    io.write("\n")
  end
end
function Term:setChar(row, col, char)
  self.text[row][col] = char
end

t = Term:new(12, 12)

a = Panel{spacing=1, inside={
  Panel{side="left", size=4},
  Panel{side="right", size=4},
  Panel{side="top", size=3},
  Panel{side="bottom", size=3},
  Panel{}
}}
for k, v in pairs(a) do
  print(k, ":", v)
end
a:resize(0, 0, 12, 12)
a:display(t)
t:display()