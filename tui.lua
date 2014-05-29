local curEnv = getfenv()
local names = {}

--[[ widget interface
properties
  name
  top, left, rows, cols
functions
  resize - change layout for drawing and resize child controls
  display - draw chars to term using standard term functions
  hit - custom hit code, usually not needed
--]]

-- Base class for all the things ----------------------------------------------
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
    while curEnv[self.type .. tostring(names[self.type])] ~= nil do
      names[self.type] = names[self.type] + 1
    end
    name = self.type .. tostring(names[self.type])
  end
  if curEnv[name] ~= nil then
    error("Duplicate widget name: " .. name)
  end
  widget.name = name
  curEnv[name] = widget

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

  return widget
end

function Widget:resize(top, left, rows, cols, term)
  self.top = top
  self.left = left
  self.rows = rows
  self.cols = cols
  self.term = term or self.term

  -- allocate space for padding
  if self.padding > 0 then
    top = top + self.padding
    left = left + self.padding
    rows = math.max(0, rows - self.padding * 2)
    cols = math.max(0, cols - self.padding * 2)
  end

  return top, left, rows, cols  
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
          self.term:setChar(row, col, self.borderChars[1])
        else
          -- top / bottom border
          self.term:setChar(row, col, self.borderChars[2])
        end
      elseif col < self.left + self.padding
          or col > self.left + self.cols - 1 - self.padding then
        -- left / right border
        self.term:setChar(row, col, self.borderChars[3])
      else
        self.term:setChar(row, col, self.bgChar)
      end
    end
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

function Container:resize(top, left, rows, cols, term)
  return Widget.resize(self, top, left, rows, cols, term)
end

function Container:hit(row, col)
  if self.inside then
    --print("looking in "..self.name)
    --print(row.." "..col)
    for i, widget in ipairs(self.inside) do
      --print(widget.name..": "..widget.top..","..widget.left.."-"..widget.rows..","..widget.cols)
      if row >= widget.top and row <= (widget.top + widget.rows - 1)
          and col >= widget.left and col <= (widget.left + widget.cols - 1) then
        --print("found "..widget.name)
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

function Panel:resize(top, left, rows, cols, term)
  top, left, rows, cols = Container.resize(self, top, left, rows, cols, term)

  -- loop through inside widgets allocating space first come first serve
  if self.inside then
    for i, widget in ipairs(self.inside) do
      if widget.side == "left" then
        if not widget.size then
          widget.size = cols
        end
        widget:resize(top, left, rows, math.min(widget.size, cols), term)
        left = math.min(left + cols, left + widget.cols + self.spacing)
        cols = math.max(0, cols - widget.cols - self.spacing)
      elseif widget.side == "right" then
        if not widget.size then
          widget.size = cols
        end
        widget:resize(top, left + cols - math.min(widget.size, cols), rows, math.min(widget.size, cols), term)
        cols = math.max(0, cols - widget.cols - self.spacing)
      elseif widget.side == "top" then
        if not widget.size then
          widget.size = rows
        end
        widget:resize(top, left, math.min(widget.size, rows), cols, term)
        top = math.min(top + rows, top + widget.rows + self.spacing)
        rows = math.max(0, rows - widget.rows - self.spacing)
      elseif widget.side == "bottom" then
        if not widget.size then
          widget.size = rows
        end
        widget:resize(top + rows - math.min(widget.size, rows), left, math.min(widget.size, rows), cols, term)
        rows = math.max(0, rows - widget.rows - self.spacing)
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
  Container.display(self)
  -- display title
  if self.title and self.padding > 0 then
    local left = math.max(0, math.min(2, self.cols - self.title:len()))
    self.term:write(self.top, self.left + left, self.title:sub(1, self.cols))
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

function Grid:resize(top, left, rows, cols, term)
  top, left, rows, cols = Container.resize(self, top, left, rows, cols, term)
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
      widget:resize(top + (gridRow - 1) * (gridRowSize + self.spacing),
                    left + (gridCol - 1) * (gridColSize + self.spacing),
                    (gridRowSize + self.spacing) * widget.rowSpan - self.spacing,
                    (gridColSize + self.spacing) * widget.colSpan - self.spacing,
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
  local text = self.text[self.value]:sub(1, cols)
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local top = self.top + self.padding + math.floor((rows - 1) / 2)
  local left = self.left + self.padding + math.floor((cols - text:len())/2)
  self.term:write(top, left, text)
end

function Button:mouse_click(evt)
  button.value = button.value + 1
  if button.value > #button.text then
    button.value = 1
  end
  Button.display(self)
end

setmetatable(Button, {
  __index = Widget,
  __call = Button.create
})

-- event stuff ----------------------------------------------------------------
--[[
Events:
  monitor_touch
  mouse_click
  mouse_scroll
  mouse_drag
  key
  char
--]]

function listen(widget, event, fn, capture)
  capture = type(capture) == "boolean" and capture or false
  if capture then
    event = "capture_" .. event
  end
  if type(widget) == "string" then
    for name, value in pairs(curEnv) do
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

function run(widget, term)
  while true do
    local rows, cols = term:getSize()
    widget:resize(1, 1, rows, cols, term)
    widget:display(term)
    term:display()  -- fake term, not needed in CC
    local c = io.read("*l")
    local event = {}
    for token in c:gmatch("[^%s]+") do
      table.insert(event, token)
    end
    event.name = table.remove(event, 1)
    if event.name == "mouse_click" then
      event[1] = tonumber(event[1])
      event[2] = tonumber(event[2])
      event[3] = tonumber(event[3])
    end
    if c == "exit" then
      return
    else
      local widgets = {}
      local currWidget = widget
      local propagate = true
      -- trickle down listeners
      while currWidget ~= nil do
        table.insert(widgets, 1, currWidget)
        -- look for listener on current widget
        if currWidget["capture_" .. event.name] ~= nil then
          local result = currWidget["capture_" .. event.name](currWidget, unpack(event))
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
          currWidget = currWidget.hit and currWidget:hit(event[2], event[3]) or nil
        else
          currWidget = currWidget.focus
        end
        if type(currWidget) == "boolean" then
          currWidget = nil
        end
      end
      -- bubble up listeners
      if propagate then
        for i, currWidget in ipairs(widgets) do
          if currWidget[event.name] ~= nil then
            local result = currWidget[event.name](currWidget, unpack(event))
            if result == false then
              propagate = false
              break
            end
          end
        end
      end
    end
  end
end

-- fake term for local testing
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
function Term:write(row, col, chars)
  for i = 1, chars:len() do
    self.text[row][col + i - 1] = chars:sub(i, i)
  end
end
function Term:getSize()
  return self.rows, self.cols
end

local t = Term:new(19, 51)

-- calculator logic
local calc = {
  scan = false,
  mantissa = 1,
  display = 0,
  num = 0,
  op = nil,
  lastnum = nil,
  lastop = nil,
  memory = 0
}
function calc:clear()
  if self.display == 0 then
    self.num = 0
    self.display = 0
    self.mantissa = 1
    self.scan = false
    self.op = nil
    self.lastnum = nil
  else
    self.display = 0
  end
end
function calc:number(num)
  if self.scan then
    if self.mantissa > 1 then
      self.display = self.display + num / self.mantissa
      self.mantissa = self.mantissa * 10
    else
      self.display = self.display * 10 + num
    end
  else
    self.num = self.display
    self.mantissa = 1
    self.display = num
    self.scan = true
  end
end
function calc:decimal()
  if not self.scan then
    self.num = self.display
    self.mantissa = 1
    self.display = 0
    self.scan = false
  end
  if self.mantissa == 1 then
    self.mantissa = self.mantissa * 10
  end
end
function calc:negative()
  self.display = -self.display
end
function calc:reciprocal()
  self.display = 1/self.display
  self.scan = false
end
function calc:exp()
  self.display = math.exp() .sqrt(self.display)
  self.scan = false
end
function calc:operation(op)
  self:calc()
  self.op = op
  self.scan = false
end
function calc:equal()
  if not self:calc() and self.lastop then
    if self.lastop == "+" then
      self.display = self.display + self.lastnum
    elseif self.lastop == "-" then
      self.display = self.display - self.lastnum
    elseif self.lastop == "*" then
      self.display = self.display * self.lastnum
    elseif self.lastop == "/" then
      self.display = self.display / self.lastnum
    elseif self.lastop == "^" then
      self.display = math.exp(self.display, self.lastnum)
    end
  end
  self.scan = nil
end
function calc:calc()
  if self.op then
    self.lastop = self.op
    self.lastnum = self.display
    if self.op == "+" then
      self.display = self.num + self.display
    elseif self.op == "-" then
      self.display = self.num - self.display
    elseif self.op == "*" then
      self.display = self.num * self.display
    elseif self.op == "/" then
      self.display = self.num / self.display
    elseif self.op == "^" then
      self.display = math.exp(self.num, self.display)
    end
    self.op = nil
    return true
  end
end
function calc:store()
  self.memory = self.display
  self.scan = false
end
function calc:recall()
  self.display = self.memory
  self.scan = false
end

-- calculator interface

local calculator = Grid{
  gridRows=5, gridCols=6, spacing=1,
  inside={
    Button{name="number_field", text="0", colSpan=6},
    Button{name="recall", text="MR", bgChar="."},
    Button{name="number7", text="7", data=7, bgChar="."},
    Button{name="number8", text="8", data=8, bgChar="."},
    Button{name="number9", text="9", data=9, bgChar="."},
    Button{name="divide", text="/", bgChar="."},
    Button{name="clear", text="C", bgChar="."},

    Button{name="store", text="MS", bgChar="."},
    Button{name="number4", text="4", data=4, bgChar="."},
    Button{name="number5", text="5", data=5, bgChar="."},
    Button{name="number6", text="6", data=6, bgChar="."},
    Button{name="multiply", text="*", bgChar="."},
    Button{name="negative", text="+/-", bgChar="."},

    Button{name="exp", text="^", bgChar="."},
    Button{name="number1", text="1", data=1, bgChar="."},
    Button{name="number2", text="2", data=2, bgChar="."},
    Button{name="number3", text="3", data=3, bgChar="."},
    Button{name="subtract", text="-", bgChar="."},
    Button{name="equal", text="=", bgChar=".", rowSpan=2},

    Button{name="reciprocal", text="1/x", bgChar="."},
    Button{name="number0", text="0", data=0, bgChar=".", colSpan=2},
    Button{name="decimal", text=".", bgChar=":"},
    Button{name="add", text="+", bgChar="."},
  }
}

function numberClick(self)
  calc.number(self.data)
  number_field.text[1] = tostring(calc.display)
end

for num = 0, 9 do
  listen("number"..tostring(num), "mouse_click", numberClick)
end

function decimal:mouse_click()
  calc:decimal()
  number_field.text[1] = tostring(calc.display)
end

function opClick(self)
  calc.operation(self.text[self.value])
  number_field.text[1] = tostring(calc.display)
end

listen("add", "mouse_click", opClick)
listen("subtract", "mouse_click", opClick)
listen("multiply", "mouse_click", opClick)
listen("divide", "mouse_click", opClick)
listen("exp", "mouse_click", opClick)

function reciprocal:mouse_click()
  calc:reciprocal()
  number_field.text[1] = tostring(calc.display)
end

function equal:mouse_click()
  calc:equal()
  number_field.text[1] = tostring(calc.display)
end

function clear:mouse_click()
  calc:clear()
  number_field.text[1] = tostring(calc.display)
end

function store:mouse_click()
  calc:store()
  number_field.text[1] = tostring(calc.display)
end

function recall:mouse_click()
  calc:recall()
  number_field.text[1] = tostring(calc.display)
end

function calculator:char(char)
  if char >= "0" and char <= "9" then
    calc:number(tonumber(char))
  elseif char == "." then
    calc:decimal()
  elseif char == "+" or char == "-" or char == "*" or char == "/" or char == "^" then
    calc:operation(char)
  elseif char == "=" then
    calc:equal()
  end
end

function calculator:key(key)
  if key == keys.enter then
    calc:equal()
  elseif key == keys.delete then
    calc:clear()
  end
end

run(calculator, t)