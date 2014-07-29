local env = {}
setmetatable(env, {__index = _G})
setfenv(2, env)
setfenv(1, env)
local names = {}

-- Base class for all the things and event loop -------------------------------
Widget = {type="widget"}
Widget.__index = Widget

function Widget:create(arg)
  local widget = {}
  setmetatable(widget, self)

  -- set widget name to unique value
  local name = arg.name
  if not name then
    if names[self.type] == nil then
      names[self.type] = 1
    end
    while env[self.type .. tostring(names[self.type])] ~= nil do
      names[self.type] = names[self.type] + 1
    end
    name = self.type .. tostring(names[self.type])
  end
  if env[name] ~= nil then
    error("Duplicate widget name: " .. name)
  end
  widget.name = name
  env[name] = widget

  -- set widget default properties
  widget.data = arg.data
  widget.visible = true
  if arg.visible ~= nil then
    widget.visible = arg.visible
  end
  -- positioning info for panel or grid
  -- for panel
  widget.side = arg.side or "fill"
  widget.size = arg.size
  -- for grid
  widget.rowSpan = arg.rowSpan or 1
  widget.colSpan = arg.colSpan or 1

  widget.padding = arg.padding or 0
  widget.color = arg.color
  widget.bgChar = arg.bgChar or " "
  widget.borderChars = arg.borderChars or {" ", " ", " "}

  widget.textColor = arg.textColor or colors.white
  widget.backgroundColor = arg.backgroundColor or colors.black
  widget.bgTextColor = arg.bgTextColor or widget.textColor
  widget.bgBackgroundColor = arg.bgBackgroundColor or widget.backgroundColor
  widget.borderTextColor = arg.borderTextColor or widget.bgTextColor
  widget.borderBackgroundColor = arg.borderBackgroundColor or widget.bgBackgroundColor

  return widget
end

function Widget:resize(left, top, cols, rows, term)
  self.left = left
  self.top = top
  self.cols = cols
  self.rows = rows
  self.term = term or self.term

  -- allocate space for padding
  if self.padding > 0 then
    left = left + self.padding
    top = top + self.padding
    cols = math.max(0, cols - self.padding * 2)
    rows = math.max(0, rows - self.padding * 2)
  end

  return left, top, cols, rows  
end

function Widget:display()
  -- display border and background
  for row = self.top, self.top + self.rows - 1 do
    for col = self.left, self.left + self.cols - 1 do
      if row < self.top + self.padding
          or row > self.top + self.rows - 1 - self.padding then
        if col < self.left + self.padding
            or col > self.left + self.cols - 1 - self.padding then
          -- corner border
          self.term.setTextColor(self.borderTextColor)
          self.term.setBackgroundColor(self.borderBackgroundColor)
          self.term.setCursorPos(col, row)
          self.term.write(self.borderChars[1])
        else
          -- top / bottom border
          self.term.setTextColor(self.borderTextColor)
          self.term.setBackgroundColor(self.borderBackgroundColor)
          self.term.setCursorPos(col, row)
          self.term.write(self.borderChars[2])
        end
      elseif col < self.left + self.padding
          or col > self.left + self.cols - 1 - self.padding then
        -- left / right border
        self.term.setTextColor(self.borderTextColor)
        self.term.setBackgroundColor(self.borderBackgroundColor)
        self.term.setCursorPos(col, row)
        self.term.write(self.borderChars[3])
      else
        self.term.setTextColor(self.bgTextColor)
        self.term.setBackgroundColor(self.bgBackgroundColor)
        self.term.setCursorPos(col, row)
        self.term.write(self.bgChar)
      end
    end
  end
end

function Widget:run(term)
  self.running = true
  term.clear()
  local cols, rows = term.getSize()
  self:resize(1, 1, cols, rows, term)
  self:display()
  local widget = self
  -- set cursor position and blink
  while widget ~= nil do
    if widget.display_focus then
      widget:display_focus()
      widget = nil
    else
      widget = widget.focus
    end
    if type(widget) == "boolean" then
      widget = nil
    end
  end
  while self.running do
    local event = {os.pullEvent()}
    event.name = table.remove(event, 1)
    local widgets = {}
    local widget = self
    local propagate = true
    -- trickle down listeners
    while widget ~= nil do
      table.insert(widgets, 1, widget)
      -- look for listener on current widget
      if widget["capture_" .. event.name] ~= nil then
        local result = widget["capture_" .. event.name](widget, unpack(event))
        if result == false then
          propagate = false
          break
        end
      end
      -- get inside widget based on focus or location
      if event.name == "mouse_click" or 
          event.name == "mouse_scroll" or 
          event.name == "mouse_drag" or 
          event.name == "monitor_touch" then
        widget = widget.hit and widget:hit(event[2], event[3]) or nil
      else
        widget = widget.focus
      end
      if type(widget) == "boolean" then
        widget = nil
      end
    end
    -- bubble up listeners
    if propagate then
      for i, widget in ipairs(widgets) do
        if widget[event.name] ~= nil then
          local result = widget[event.name](widget, unpack(event))
          if result == false then
            propagate = false
            break
          end
        end
      end
    end
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

function Widget:stop()
  self.running = nil
  if self.outside then
    self.outside:stop()
  end
end

-- Base Class for all widgets that contain widgets ----------------------------
Container = {type="container"}
Container.__index = Container

function Container:create(arg)
  local container = Widget.create(self, arg)
  setmetatable(container, self)

  -- set container default properties
  container.spacing = arg.spacing or 0
  container.title = arg.title
  local focus
  if type(arg.inside) == "table" then
    container.inside = {}
    for i, innerWidget in ipairs(arg.inside) do
      innerWidget.outside = container
      table.insert(container.inside, innerWidget)
      if innerWidget.focus == true then
        focus = innerWidget
      end
    end
  end
  if focus == nil and container.inside ~= nil and #container.inside > 0 then
    focus = container.inside[1]
  end
  container.focus = focus

  return container
end

setmetatable(Container, {
  __index = Widget,
  __call = Container.create
})

function Container:resize(left, top, cols, rows, term)
  return Widget.resize(self, left, top, cols, rows, term)
end

function Container:hit(col, row)
  if self.inside then
    for i, widget in ipairs(self.inside) do
      if row >= widget.top and row <= (widget.top + widget.rows - 1)
          and col >= widget.left and col <= (widget.left + widget.cols - 1) then
        return widget
      end
    end
  end
end

function Container:display()
  Widget.display(self)

  -- display inside widgets
  if self.inside then
    for i, widget in ipairs(self.inside) do
      if widget.visible and widget.display then
        widget:display()
      end
    end
  end
end

-- Container that allows for positioning on edges -----------------------------
Panel = {type="panel"}
Panel.__index = Panel

function Panel:create(arg)
  local panel = Container.create(self, arg)

  -- set container default properties
  panel.title = arg.title

  return panel
end

function Panel:resize(left, top, cols, rows, term)
  left, top, cols, rows = Container.resize(self, left, top, cols, rows, term)

  -- loop through inside widgets allocating space first come first serve
  if self.inside then
    for i, widget in ipairs(self.inside) do
      if widget.side == "left" then
        if not widget.size then
          widget.size = cols
        end
        widget:resize(left, top, math.min(widget.size, cols), rows, term)
        left = math.min(left + cols, left + widget.cols + self.spacing)
        cols = math.max(0, cols - widget.cols - self.spacing)
      elseif widget.side == "right" then
        if not widget.size then
          widget.size = cols
        end
        widget:resize(left + cols - math.min(widget.size, cols), top, math.min(widget.size, cols), rows, term)
        cols = math.max(0, cols - widget.cols - self.spacing)
      elseif widget.side == "top" then
        if not widget.size then
          widget.size = rows
        end
        widget:resize(left, top, cols, math.min(widget.size, rows), term)
        top = math.min(top + rows, top + widget.rows + self.spacing)
        rows = math.max(0, rows - widget.rows - self.spacing)
      elseif widget.side == "bottom" then
        if not widget.size then
          widget.size = rows
        end
        widget:resize(left, top + rows - math.min(widget.size, rows), cols, math.min(widget.size, rows), term)
        rows = math.max(0, rows - widget.rows - self.spacing)
      else
        widget:resize(left, top, cols, rows, term)
        left = left + cols
        top = top + rows
        cols = 0
        rows = 0
      end
    end
  end
end

function Panel:display()
  Container.display(self)
  -- display title
  if self.title and self.padding > 0 then
    local left = math.max(0, math.min(2, self.cols - self.title:len()))
    self.term.setTextColor(self.borderTextColor)
    self.term.setBackgroundColor(self.borderBackgroundColor)
    self.term.setCursorPos(self.left + left, self.top)
    self.term.write(self.title:sub(1, self.cols))
  end
end

setmetatable(Panel, {
  __index = Container,
  __call = Panel.create
})

-- Container that allows for positioning in a grid ----------------------------
Grid = {type="grid"}
Grid.__index = Grid

function Grid:create(arg)
  local grid = Container.create(self, arg)

  -- set container default properties
  grid.title = arg.title
  grid.gridRows = arg.gridRows or 1
  grid.gridCols = arg.gridCols or 1

  return grid
end

function Grid:resize(left, top, cols, rows, term)
  left, top, cols, rows = Container.resize(self, left, top, cols, rows, term)
  -- calc grid spaces
  local gridRowSize = math.floor((rows - self.spacing * (self.gridRows - 1))/self.gridRows)
  local gridColSize = math.floor((cols - self.spacing * (self.gridCols - 1))/self.gridCols)
  -- center grid spaces in left over space
  top = top + math.floor((rows - ((gridRowSize + self.spacing) * self.gridRows - self.spacing)) / 2)
  left = left + math.floor((cols - ((gridColSize + self.spacing) * self.gridCols - self.spacing)) / 2)
  -- fill in grid spaces
  local gridRow = 1
  local gridCol = 1
  local grid = {} -- available spaces
  for row = 1, self.gridRows do
    grid[row] = {}
    for col = 1, self.gridCols do
      grid[row][col] = true
    end
  end
  if self.inside then
    for i, widget in ipairs(self.inside) do
      -- find next free grid space
      while true do
        if grid[gridRow] and grid[gridRow][gridCol] then
          break
        else
          gridCol = gridCol + 1
          if gridCol > self.gridCols then
            gridCol = 1
            gridRow = gridRow + 1
            if gridRow > self.gridRows then
              error("grid is not large enough: "..self.name)
            end
          end
        end
      end
      -- ensure widget has room to fit
      for row = gridRow, gridRow + widget.rowSpan - 1 do
        for col = gridCol, gridCol + widget.colSpan - 1 do
          if grid[row] and grid[row][col] then
            grid[row][col] = false
          else
            error("widget does not fit in grid: "..self.name.." "..widget.name)
          end
        end
      end
      widget:resize(left + (gridCol - 1) * (gridColSize + self.spacing),
                    top + (gridRow - 1) * (gridRowSize + self.spacing),
                    (gridColSize + self.spacing) * widget.colSpan - self.spacing,
                    (gridRowSize + self.spacing) * widget.rowSpan - self.spacing,
                    term)
    end
  end
end

setmetatable(Grid, {
  __index = Container,
  __call = Grid.create
})

-- Button widget, rotates between states on click -----------------------------
Button = {type="button"}
Button.__index = Button

function Button:create(arg)
  local button = Widget.create(self, arg)

  button.focus = arg.focus or false
  if type(arg.text) == "table" then
    button.text = arg.text
  else
    button.text = {arg.text}
  end
  button.value = arg.value or 1

  return button
end

function Button:display()
  Widget.display(self)
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local text = self.text[self.value]:sub(1, cols)
  local top = self.top + self.padding + math.floor((rows - 1) / 2)
  local left = self.left + self.padding + math.floor((cols - text:len())/2)
  self.term.setTextColor(self.textColor)
  self.term.setBackgroundColor(self.backgroundColor)
  self.term.setCursorPos(left, top)
  self.term.write(text:sub(1, cols))
end

function Button:mouse_click(evt)
  self.value = self.value + 1
  if self.value > #self.text then
    self.value = 1
  end
  Button.display(self)
end

setmetatable(Button, {
  __index = Widget,
  __call = Button.create
})

-- Text widget ----------------------------------------------------------------
Text = {type="text"}
Text.__index = Text

function Text:create(arg)
  local text = Widget.create(self, arg)

  text.focus = arg.focus or false
  text.value = tostring(arg.value or "")
  text.pos = arg.pos or arg.value:len()

  return text
end

function Text:display()
  Widget.display(self)
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local text = self.value:sub(1, cols)
  local top = self.top + self.padding
  local left = self.left + self.padding
  self.term.setTextColor(self.textColor)
  self.term.setBackgroundColor(self.backgroundColor)
  self.term.setCursorPos(left, top)
  self.term.write(text:sub(1, cols))
end

function Text:display_focus()
  local top = self.top + self.padding
  local left = self.left + self.padding + self.pos  
  self.term.setCursorPos(left, top)
  self.term.setCursorBlink(true)
end

function Text:char(char)
  self.value = self.value:sub(1, self.pos) .. char .. self.value:sub(self.pos + 1)
  self.pos = self.pos + 1
  self:display()
  self:display_focus()
  return false
end

function Text:key(key)
  if key == keys.delete then
    if self.pos < self.value:len() then
      self.value = self.value:sub(1, self.pos) .. self.value:sub(self.pos + 2)
      self:display()
      self:display_focus()
    end
  elseif key == keys.backspace then
    if self.pos > 0 then
      self.value = self.value:sub(1, self.pos - 1) .. self.value:sub(self.pos + 1)
      self.pos = self.pos - 1
      self:display()
      self:display_focus()
    end
  elseif key == keys.left then
    self.pos = math.max(0, self.pos - 1)
    self:display_focus()
  elseif key == keys.right then
    self.pos = math.min(self.value:len(), self.pos + 1)
    self:display_focus()
  elseif key == keys.home then
    self.pos = 0
    self:display_focus()
  elseif key == keys["end"] then
    self.pos = self.value:len()
    self:display_focus()
  else
    return true
  end
  return false
end

setmetatable(Text, {
  __index = Widget,
  __call = Text.create
})

-- Event listener -------------------------------------------------------------
function listen(widget, event, fn, capture)
  capture = type(capture) == "boolean" and capture or false
  if capture then
    event = "capture_" .. event
  end
  if type(widget) == "string" then
    for name, value in pairs(env) do
      if name == widget then
        widget = value
        break
      end
    end
  end
  if type(widget) == "table" and widget.name then
    widget[event] = fn
  else
    error("listener not attached, "..tostring(widget))
  end
end
