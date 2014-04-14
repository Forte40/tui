Panel = {}

setmetatable(Panel, {
  __call = function(self, arg)
    local panel = {}
    setmetatable(panel, self)
    self.__index = self
    -- top, bottom, left, right, fill (default)
    panel.side = arg.side or "fill"
    panel.size = arg.size or 0
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
        widget:resize(top, left, rows, math.min(widget.size, cols))
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
        widget:resize(top, left, math.min(widget.size, rows), cols)
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

function Panel:display()
  print(string.format("%d,%d %dx%d", self.top, self.left, self.rows, self.cols))
  if self.inside then
    for i, widget in ipairs(self.inside) do
      widget:display()
    end
  end
end

a = Panel{side="top", inside={
  Panel{side="left"},
  Panel{side="right"}
}}
for k, v in pairs(a) do
  print(k, ":", v)
end
a:resize(0, 0, 2, 3)
a:display()

