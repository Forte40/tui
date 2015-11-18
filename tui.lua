local env = {} -- create temp environment that will go away when the script ends
setmetatable(env, {__index = _G}) -- populate with global environment
setfenv(2, env) -- set calling script to this new environment
setfenv(1, env) -- set this script to this new environment

local names = {}

function split_lines(str)
  local lines = {}
  if str == nil then
    table.insert(lines, "")
    return lines
  end
  local pos = 0
  while true do
    local newPos = str:find("\n", pos)
    if newPos == nil then
      table.insert(lines, str:sub(pos))
      break
    else
      table.insert(lines, str:sub(pos, newPos - 1))
      pos = newPos + 1
    end
  end
  return lines
end

-- Base class for all the things and event loop -------------------------------
Widget = {type="widget"}
Widget.__index = Widget
-- TODO: log function on widget with control file

function Widget:create(opt)
  local widget = {}
  setmetatable(widget, self)

  -- set widget name to unique value
  local name = opt.name
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
  widget.data = opt.data
  widget.visible = true
  if opt.visible ~= nil then
    widget.visible = opt.visible
  end
  -- positioning info for panel or grid
  -- for panel
  widget.side = opt.side or "fill"
  widget.size = opt.size
  -- for grid
  widget.rowSpan = opt.rowSpan or 1
  widget.colSpan = opt.colSpan or 1

  widget.padding = opt.padding or 0
  widget.color = opt.color
  widget.bgChar = opt.bgChar or " "
  widget.borderChars = opt.borderChars or {" ", " ", " "}

  widget.textColor = opt.textColor or colors.white
  widget.backgroundColor = opt.backgroundColor or colors.black
  widget.bgTextColor = opt.bgTextColor or widget.textColor
  widget.bgBackgroundColor = opt.bgBackgroundColor or widget.backgroundColor
  widget.borderTextColor = opt.borderTextColor or widget.bgTextColor
  widget.borderBackgroundColor = opt.borderBackgroundColor or widget.bgBackgroundColor

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

function Widget.wrap_display(fn)
  return function(self, final)
    local col, row
    if final == nil then
      final = true
    end
    if final then
      col, row = self.term.getCursorPos()
      local widget = self
      while widget.window == nil do
        widget = widget.outside
      end
      window = widget.window
      window.setVisible(false)
    end
    fn(self, final)
    if final then
      self.term.setCursorPos(col, row)
      window.setVisible(true)
    end
  end
end

function Widget:render()
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

Widget.display = Widget.wrap_display(Widget.render)

function Widget:set_focus(widget)
  if widget == nil and self.defer then
    self.focus = self.defer
  else
    self.focus = widget
  end
  if self.outside then
    self.outside:set_focus(self.defer or self)
  end
end

function Widget:display_focus()
  if type(self.focus) == "table" then
    self.focus:display_focus()
  else
    term.setCursorBlink(false)
  end
end

function Widget:after(name, fn)
  -- beware of infinte recursion
  local method = self[name]
  function after_fn(self, ...)
    local results = {method(self, unpack(arg))}
    for i, val in ipairs(results) do
      table.insert(arg, val)
    end
    return fn(self, unpack(arg))
  end
  self[name] = after_fn
end

function Widget:before(name, fn)
  -- beware of infinte recursion
  local method = self[name]
  function before_fn(self, ...)
    local results = {method(self, unpack(arg))}
    if #results == 0 then
      results = arg
    end
    return fn(self, unpack(results))
  end
  self[name] = before_fn
end

function Widget:debug(msg)
  if self.debugTerm then
    local oldTerm = term.redirect(self.debugTerm)
    print(msg)
    term.redirect(oldTerm)
  elseif self.outside then
    self.outside:debug(msg)
  end
end

function Widget:run(term, debugTerm)
  self.debugTerm = debugTerm
  if self.debugTerm then
    debugTerm.clear()
    debugTerm.setCursorPos(1, 1)
  end
  self.running = true
  local cols, rows = term.getSize()
  self.window = window.create(term.current(), 1, 1, cols, rows)
  self:resize(1, 1, cols, rows, self.window)
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
      -- look for listeners on current widget
      local fns = widget["capture_" .. event.name]
      if fns ~= nil then
        if type(fns) == "function" then
          fns = {fns}
        end
        for _, fn in ipairs(fns) do
          local result = fn(widget, unpack(event))
          if result == false then
            propagate = false
            break
          end
        end
        if not propagate then
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
        local fns = widget[event.name]
        if fns ~= nil then
          if type(fns) == "function" then
            fns = {fns}
          end
          local final_result = nil
          for _, fn in ipairs(fns) do
            local result = fn(widget, unpack(event))
            if result ~= nil then
              final_result = result
            end
          end
          if final_result == false then
            propagate = false
          end
          if not propagate then
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

setmetatable(Widget, {
  __index = Widget,
  __call = Widget.create
})

-- Base Class for all widgets that contain widgets ----------------------------
Container = {type="container"}
Container.__index = Container

function Container:create(opt)
  local container = Widget.create(self, opt)
  setmetatable(container, self)

  -- set container default properties
  container.spacing = opt.spacing or 0
  container.title = opt.title
  local focus
  container.inside = {}
  if type(opt.inside) == "table" then
    for i, innerWidget in ipairs(opt.inside) do
      innerWidget.outside = container
      table.insert(container.inside, innerWidget)
      if innerWidget.focus ~= nil then
        focus = innerWidget
      end
    end
  end
  if focus ~= nil then
    container.focus = focus
  elseif opt.focus == true then
    container.focus = true
  end

  return container
end

function Container:add(widget)
  widget.outside = self
  table.insert(self.inside, widget)
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

function Container:render()
  Widget.render(self)

  -- display inside widgets
  if self.inside then
    for i, widget in ipairs(self.inside) do
      if widget.visible and widget.display then
        widget:display(false)
      end
    end
  end
end

Container.display = Widget.wrap_display(Container.render)

-- Tab, container that has multiple panels controlled by buttons -------------------------
Tab = {type="tab"}
Tab.__index = Tab

function Tab:create(opt)
  local tab = Container.create(self, opt)

  -- set container default properties
  tab.tabPanel = Panel{}
  tab:add(tab.tabPanel)
  tab.widgets = {}
  for i, tabPair in ipairs(opt.tabs) do
    tab:add_tab(tabPair[1], tabPair[2])
  end
  tab.focus.visible = true

  return tab
end

function Tab:add_tab(name, widget)
  local button = Button{side="left", size=#name+4, text="/ "..name.." \\"}
  self.tabPanel:add(button)
  self.widgets[name] = widget
  self:add(widget)
  widget.visible = false
  if self.focus == nil or widget.focus == true then
    self.focus = widget
  end
  local tab = self
  button.mouse_click = function()
    for btn, widget in pairs(self.widgets) do
      if btn == name then
        if widget.visible then
          return -- already visible, don't render
        end
        widget.visible = true
      else
        widget.visible = false
      end
    end
    tab:display()
  end
end

function Tab:resize(left, top, cols, rows, term)
  left, top, cols, rows = Container.resize(self, left, top, cols, rows, term)

  -- size tab buttons on top with height 1
  self.tabPanel:resize(left, top, cols, 1, term)
  -- loop through widgets allocating same space for each minus tab button row
  top = top + 1
  rows = rows - 1
  for name, widget in pairs(self.widgets) do
    widget:resize(left, top, cols, rows, term)
  end
end

setmetatable(Tab, {
  __index = Container,
  __call = Tab.create
})

-- Container that allows for positioning on edges -----------------------------
Panel = {type="panel"}
Panel.__index = Panel

function Panel:create(opt)
  local panel = Container.create(self, opt)

  -- set container default properties
  panel.title = opt.title

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

function Panel:render()
  Container.render(self)
  -- display title
  if self.title and self.padding > 0 then
    local left = math.max(0, math.min(2, self.cols - self.title:len()))
    self.term.setTextColor(self.borderTextColor)
    self.term.setBackgroundColor(self.borderBackgroundColor)
    self.term.setCursorPos(self.left + left, self.top)
    self.term.write(self.title:sub(1, self.cols))
  end
end

Panel.display = Widget.wrap_display(Panel.render)

setmetatable(Panel, {
  __index = Container,
  __call = Panel.create
})

-- Container that allows for positioning in a grid ----------------------------
Grid = {type="grid"}
Grid.__index = Grid

function Grid:create(opt)
  local grid = Container.create(self, opt)

  -- set container default properties
  grid.title = opt.title
  grid.grid_rows = opt.grid_rows or 1
  grid.grid_cols = opt.grid_cols or 1

  return grid
end

function Grid:resize(left, top, cols, rows, term)
  left, top, cols, rows = Container.resize(self, left, top, cols, rows, term)
  -- calc grid spaces
  local grid_row_size = math.floor((rows - self.spacing * (self.grid_rows - 1))/self.grid_rows)
  local grid_col_size = math.floor((cols - self.spacing * (self.grid_cols - 1))/self.grid_cols)
  -- center grid spaces in left over space
  top = top + math.floor((rows - ((grid_row_size + self.spacing) * self.grid_rows - self.spacing)) / 2)
  left = left + math.floor((cols - ((grid_col_size + self.spacing) * self.grid_cols - self.spacing)) / 2)
  -- fill in grid spaces
  local grid_row = 1
  local grid_col = 1
  local grid = {} -- available spaces
  for row = 1, self.grid_rows do
    grid[row] = {}
    for col = 1, self.grid_cols do
      grid[row][col] = true
    end
  end
  if self.inside then
    for i, widget in ipairs(self.inside) do
      -- use config or find next free grid space
      if widget.grid_col and widget.grid_row then
        grid_col = widget.grid_col
        grid_row = widget.grid_row
      else
        grid_col = 1
        grid_row = 1
        while true do
          if grid[grid_row] and grid[grid_row][grid_col] then
            break
          else
            grid_col = grid_col + 1
            if grid_col > self.grid_cols then
              grid_col = 1
              grid_row = grid_row + 1
              if grid_row > self.grid_rows then
                error("grid is not large enough: "..self.name)
              end
            end
          end
        end
      end
      -- ensure widget has room to fit
      for row = grid_row, grid_row + widget.rowSpan - 1 do
        for col = grid_col, grid_col + widget.colSpan - 1 do
          if grid[row] and grid[row][col] then
            grid[row][col] = false
          else
            error("widget does not fit in grid: "..self.name.." "..widget.name)
          end
        end
      end
      widget:resize(left + (grid_col - 1) * (grid_col_size + self.spacing),
                    top + (grid_row - 1) * (grid_row_size + self.spacing),
                    (grid_col_size + self.spacing) * widget.colSpan - self.spacing,
                    (grid_row_size + self.spacing) * widget.rowSpan - self.spacing,
                    term)
    end
  end
end

setmetatable(Grid, {
  __index = Container,
  __call = Grid.create
})

-- Scroll widget ----------------------------------------
Scroll = {type="scroll"}
Scroll.__index = Scroll

function Scroll:create(opt)
  local scroll = Widget.create(self, opt)

  scroll.type = opt.type or "horz"
  scroll.min = opt.min or 0
  scroll.max = opt.max or 9
  scroll.value = opt.value or scroll.min
  scroll.range = opt.range or 0

  return scroll
end

function Scroll:update()
  local length
  if self.type == "vert" then
    length = self.rows - self.padding * 2
  else
    length = self.cols - self.padding * 2
  end
  self.size = math.max(1, math.floor(0.5 + (length - 2) * math.max(self.range, 1) / (self.max - self.min + 1)))
end

function Scroll:resize(left, top, cols, rows, term)
  left, top, cols, rows = Widget.resize(self, left, top, cols, rows, term)
  self:update()
end

function Scroll:render()
  Widget.render(self)
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local top = self.top + self.padding
  local left = self.left + self.padding
  self.term.setTextColor(self.textColor)
  self.term.setBackgroundColor(self.backgroundColor)
  if self.type == "vert" then
    local start = math.floor((rows - 2 - self.size) * (self.value - self.min) / ((self.max - self.range + 1) - self.min))
    for row = 1, rows do
      self.term.setCursorPos(left, top + row - 1)
      for col = 1, cols do
        if row == 1 then
          self.term.write("^")
        elseif row == rows then
          self.term.write("v")
        elseif (row >= start + 2) and (row < (start + 2 + self.size)) then
          self.term.write("=")
        else
          self.term.write("|")
        end
      end
    end
  else
    local start = math.floor((cols - 2 - self.size) * (self.value - self.min) / ((self.max - self.range + 1) - self.min))
    for row = 1, rows do
      self.term.setCursorPos(left, top + row - 1)
      for col = 1, cols do
        if col == 1 then
          self.term.write("<")
        elseif col == cols then
          self.term.write(">")
        elseif (col >= start + 2) and (col < (start + 2 + self.size)) then
          self.term.write("=")
        else
          self.term.write("-")
        end
      end
    end
  end
end

Scroll.display = Widget.wrap_display(Scroll.render)

function Scroll:inc(amount)
  self.value = self.value + amount
  if self.value > (self.max - self.range + 1) then
    self.value = (self.max - self.range + 1)
  end
  self:display()
end

function Scroll:dec(amount)
  self.value = self.value - amount
  if self.value < self.min then
    self.value = self.min
  end
  self:display()
end

function Scroll:set(amount)
  self.value = amount
  if self.value < self.min then
    self.value = self.min
  elseif self.value > (self.max - self.range + 1) then
    self.value = (self.max - self.range + 1)
  end
  self:display()
end

function Scroll:mouse_click(btn, col, row)
  local propagate = true
  self:set_focus()
  if self.type == "vert" then
    if row == self.top + self.padding then
      self:dec(1)
      propagate = false
    elseif row == self.top + self.rows - self.padding - 1 then
      self:inc(1)
      propagate = false
    end
  else
    if col == self.left + self.padding then
      self:dec(1)
      propagate = false
    elseif col == self.left + self.cols - self.padding - 1 then
      self:inc(1)
      propagate = false
    end
  end
  self:display_focus()  
  return propagate
end

setmetatable(Scroll, {
  __index = Widget,
  __call = Scroll.create
})

-- Text widget, text only ------------------------------
Text = {type="text"}
Text.__index = Text

function Text:create(opt)
  local text = Widget.create(self, opt)

  text.focus = opt.focus or nil
  text.align = opt.align or "center" -- left, right, center
  text.valign = opt.valign or "middle" -- top, middle, bottom
  text.scroll = opt.scroll or "none" -- none, vert, horz, both, auto
  text.value = split_lines(opt.value)
  return text
end

function Text:scroll_update(max_cols)
  -- max_cols passed in to increase by 1 to make room for cursor
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local top = self.top + self.padding
  local left = self.left + self.padding

  -- calc scroll bars
  local vscroll = self.scroll == "both" or self.scroll == "vert"
    or (self.scroll == "auto" and #self.value > rows)
  max_cols = max_cols or 0
  local max_rows = #self.value
  if self.scroll == "auto" then
    for i, val in ipairs(self.value) do
      if #val > max_cols then
        max_cols = #val
      end
    end
  end
  local hscroll = self.scroll == "both" or self.scroll == "horz"
    or (self.scroll == "auto" and max_cols > cols)

  -- create or hide scroll bars
  local ascroll = 0
  if vscroll and hscroll then
    ascroll = 1
  end
  if vscroll then
    if self.vscroll == nil then
      self:debug("create vscroll")
      self.vscroll = Scroll{min = 1, max = max_rows, range = rows - ascroll, type = "vert"}
      self.vscroll.outside = self.outside
      self.vscroll.defer = self
      self.vscroll:resize(left + cols - 1, top, 1, rows - ascroll, self.term)
    else
      self.vscroll.max = max_rows
      self.vscroll:update()
    end
  end
  if hscroll then
    if self.hscroll == nil then
      self:debug("create hscroll")
      self.hscroll = Scroll{min = 1, max = max_cols, range = cols - ascroll, type = "horz"}
      self.hscroll.outside = self.outside
      self.hscroll.defer = self
      self.hscroll:resize(left, top + rows - 1, cols - ascroll, 1, self.term)
    else
      self.hscroll.max = max_cols
      self.hscroll:update()
    end
  end
  return hscroll, vscroll, max_cols, max_rows
end

function Text:render()
  Widget.render(self)
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local top = self.top + self.padding
  local left = self.left + self.padding

  if type(self.value) == "string" then
    self.value = split_lines(self.value)
  end

  local hscroll, vscroll, max_cols = self:scroll_update()

  -- render scroll bars
  if vscroll and self.vscroll then
    self.vscroll:render()
    cols = cols - 1
  end
  if hscroll and self.hscroll then
    self.hscroll:render()
    rows = rows - 1
  end

  -- render text
  if self.valign == "top" then
  elseif self.valign == "bottom" then
    top = math.max(top, top + rows - #self.value)
  else -- default to middle
    top = math.max(top, top + math.floor((rows - #self.value) / 2))
  end
  self.term.setTextColor(self.textColor)
  self.term.setBackgroundColor(self.backgroundColor)
  local vstart = 1
  if self.vscroll then
    vstart = self.vscroll.value
  end
  local hstart = 1
  if self.hscroll then
    hstart = self.hscroll.value
  end
  for i = vstart, vstart + rows - 1 do
    local val = self.value[i] or ""
    left = self.left + self.padding
    if self.align == "left" then
    elseif self.align == "right" then
      left = math.max(left, left + cols - #val)
    else -- default to center
      left = math.max(left, left + math.floor((cols - #val)/2))
    end
    self.term.setCursorPos(left, top + i - vstart)
    self.term.write(val:sub(hstart, hstart + cols - 1))
  end
end

Text.display = Widget.wrap_display(Text.render)

function Text:set(str)
  self.value = split_lines(str)
  self:display()
end

function Text:append(str)
  local last = #self.value
  str = split_lines(str)
  if last == 0 then
    table.insert(self.value, str[1])
  else
    self.value[last] = self.value[last] .. str[1]
  end
  if #str > 1 then
    local i
    for i = 2, #str do
        table.insert(self.value, str[i])
    end
  end
  self:display()
end

function Text:append_line(str)
  str = split_lines(str)
  local i
  for i = 1, #str do
    table.insert(self.value, str[i])
  end
  self:display()
end

function Text:mouse_click(btn, col, row)
  local propagate = true
  if self.vscroll then
    propagate = self.vscroll:mouse_click(btn, col, row)
  end
  if self.hscroll then
    propagate = self.hscroll:mouse_click(btn, col, row)
  end
  self:display()
  return propagate
end

setmetatable(Text, {
  __index = Widget,
  __call = Text.create
})

-- Edit widget ----------------------------------------------------------------
Edit = {type="edit"}
Edit.__index = Edit

function Edit:create(opt)
  opt.align = opt.align or "left"
  opt.valign = opt.valign or "top"
  opt.scroll = opt.scroll or "auto"
  local edit = Text.create(self, opt)

  edit.col = opt.col or #edit.value[#edit.value] + 1
  edit.row = opt.row or #edit.value

  return edit
end

function Edit:display_focus()
  local left = self.left + self.padding + self.col - 1
  local top = self.top + self.padding + self.row - 1
  if self.hscroll then
    left = left - self.hscroll.value + 1
  end
  if self.vscroll then
    top = top - self.vscroll.value + 1
  end
  local cursor_visible = (left < self.left + self.cols - 1) and (top < self.top + self.rows - 1)
  self.term.setCursorPos(left, top)
  self.term.setCursorBlink(cursor_visible)
end

function Edit:mouse_click(btn, col, row)
  self:set_focus()
  Text.mouse_click(self, btn, col, row)
  self:display()
  self:display_focus()
end

function Edit:scroll_update(max_cols)
  return Text.scroll_update(self, max_cols or self.col)
end

function Edit:get_size()
  local cols = 0
  for i, val in ipairs(self.value) do
    cols = math.max(#val, cols)
  end
  return cols, #self.value
end

function Edit:scroll_check()
  local hscroll, vscroll, cols, rows = self:scroll_update()
  local changed = false
  if hscroll and self.hscroll then
    if self.hscroll.value + self.hscroll.range - 1 > cols then
      self.hscroll.value = cols - self.hscroll.range + 1
      changed = true
    end
    if self.col < self.hscroll.value then
      self.hscroll:set(self.col)
      changed = true
    elseif self.col > self.hscroll.value + self.hscroll.range - 1 then
      self.hscroll:set(self.col - self.hscroll.range + 1)
      changed = true
    end
  elseif self.hscroll then
    if self.hscroll.value ~= 1 then
      self.hscroll.value = 1
      changed = true
    end
  end
  if vscroll and self.vscroll then
    if self.vscroll.value + self.vscroll.range - 1 > rows then
      self.vscroll.value = rows - self.vscroll.range + 1
      changed = true
    end
    if self.row < self.vscroll.value then
      self.vscroll:set(self.row)
      changed = true
    elseif self.row > self.vscroll.value + self.vscroll.range - 1 then
      self.vscroll:set(self.row - self.vscroll.range + 1)
      changed = true
    end
  elseif self.vscroll then
    if self.vscroll.value ~= 1 then
      self.vscroll.value = 1
      changed = true
    end
  end
  return changed
end

function Edit:char(char)
  self:insert(char)
  self:scroll_check()
  self:display()
  self:display_focus()
  return false
end

function Edit:insert(str)
  local lines = split_lines(str)
  if #lines == 1 then
    self.value[self.row] = self.value[self.row]:sub(1, self.col - 1) .. str .. self.value[self.row]:sub(self.col)
    self.col = self.col + #str
  else
    local trailing = self.value[self.row]:sub(self.col)
    self.value[self.row] = self.value[self.row]:sub(1, self.col - 1) .. lines[1]
    for i = 2, #lines do
      self.row = self.row + 1
      table.insert(self.value, self.row, lines[i])
    end
    self.value[self.row] = self.value[self.row] .. trailing
    self.col = #lines[#lines] + 1
  end
end

function Edit:del_sel(sel)
  self.value[sel.row1] = self.value[sel.row1]:sub(1, sel.col1) .. self.value[sel.row2]:sub(sel.col2 + 1)
  for i = sel.row2, sel.row1 + 1, -1 do
    table.remove(self.value, i)
  end
  self.col = sel.col1 + 1
  self.row = sel.row1
end

function Edit:key(key)
  if key == keys.delete then
    local sel = {col1=self.col-1, row1=self.row, col2=self.col, row2=self.row}
    if self.row < #self.value and self.col > #self.value[self.row] then
      sel.row2 = self.row + 1
      sel.col2 = 0
    end
    self:del_sel(sel)
    self:scroll_check()
    self:display()
    self:display_focus()
  elseif key == keys.backspace then
    local sel = {col1=self.col-2, row1=self.row, col2=self.col-1, row2=self.row}
    if sel.col1 < 0 then
      if self.row > 1 then
        sel.row1 = self.row - 1
        sel.col1 = #self.value[sel.row1]
      else
        return false
      end
    end
    self:del_sel(sel)
    self:scroll_check()
    self:display()
    self:display_focus()
  elseif key == keys.left then
    if self.col == 1 then
      if self.row > 1 then
        self.row = self.row - 1
        self.col = #self.value[self.row] + 1
      end
    else
      self.col = self.col - 1
    end
    if self:scroll_check() then
      self:display()
    end
    self:display_focus()
  elseif key == keys.right then
    if self.col > #self.value[self.row] then
      if self.row < #self.value then
        self.row = self.row + 1
        self.col = 1
      end
    else
      self.col = self.col + 1
    end
    if self:scroll_check() then
      self:display()
    end
    self:display_focus()
  elseif key == keys.up then
    if self.row > 1 then
      self.row = self.row - 1
      self.col = math.min(self.col, #self.value[self.row] + 1)
    end
    if self:scroll_check() then
      self:display()
    end
    self:display_focus()
  elseif key == keys.down then
    if self.row < #self.value then
      self.row = self.row + 1
      self.col = math.min(self.col, #self.value[self.row] + 1)
    end
    if self:scroll_check() then
      self:display()
    end
    self:display_focus()
  elseif key == keys.home then
    self.col = 1
    if self:scroll_check() then
      self:display()
    end
    self:display_focus()
  elseif key == keys["end"] then
    self.col = #self.value[self.row] + 1
    if self:scroll_check() then
      self:display()
    end
    self:display_focus()
  elseif key == keys.enter then
    self:insert("\n")
    self:scroll_check()    
    self:display()
    self:display_focus()
  else
    return true
  end
  return false
end

setmetatable(Edit, {
  __index = Text,
  __call = Edit.create
})

-- Spinner widget, number with buttons to increase or decrease value ------
Spinner = {type="spinner"}
Spinner.__index = Spinner

function Spinner:create(opt)
  local spinner = Widget.create(self, opt)

  spinner.focus = opt.focus or nil
  spinner.min = math.floor(tonumber(opt.min or 0))
  spinner.max = math.floor(tonumber(opt.max or 9))
  spinner.value = math.floor(tonumber(opt.value or spinner.min))

  return spinner
end

function Spinner:render()
  Widget.render(self)
  local rows = self.rows - self.padding * 2
  local cols = self.cols - self.padding * 2
  local text = tostring(self.value):sub(1, cols - 2)
  local top = self.top + self.padding + math.floor((rows - 1) / 2)
  local left = self.left + self.padding + math.floor((cols - text:len())/2)
  self.term.setTextColor(self.textColor)
  self.term.setBackgroundColor(self.backgroundColor)
  if self.value > self.min then
    self.term.setCursorPos(self.left + self.padding, top)
    self.term.write("<")
  end
  self.term.setCursorPos(left, top)
  self.term.write(text:sub(1, cols))
  if self.value < self.max then
    self.term.setCursorPos(self.left + self.cols - self.padding - 1, top)
    self.term.write(">")
  end
end

Spinner.display = Widget.wrap_display(Spinner.render)

function Spinner:inc(amount)
  self.value = self.value + amount
  if self.value > self.max then
    self.value = self.max
  end
  self:display()
end

function Spinner:dec(amount)
  self.value = self.value - amount
  if self.value < self.min then
    self.value = self.min
  end
  self:display()
end

function Spinner:set(amount)
  self.value = amount
  if self.value < self.min then
    self.value = self.min
  elseif self.value > self.max then
    self.value = self.max
  end
  self:display()
end

function Spinner:mouse_click(btn, col, row)
  self:set_focus()
  if col == self.left + self.padding then
    self:debug("dec")
    self:dec(1)
  elseif col == self.left + self.cols - self.padding - 1 then
    self:debug("inc")
    self:inc(1)
  end
  self:debug(string.format("%s : %s , %s", btn, col, row))
  self:display_focus()  
end

setmetatable(Spinner, {
  __index = Widget,
  __call = Spinner.create
})

-- Button widget, rotates between states on click -----------------------------
Button = {type="button"}
Button.__index = Button

function Button:create(opt)
  local button = Widget.create(self, opt)

  button.focus = opt.focus or nil
  if type(opt.text) == "table" then
    button.text = opt.text
  else
    button.text = {opt.text}
  end
  button.value = opt.value or 1

  return button
end

function Button:render()
  Widget.render(self)
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

Button.display = Widget.wrap_display(Button.render)

function Button:mouse_click()
  self.value = self.value + 1
  if self.value > #self.text then
    self.value = 1
  end
  self:set_focus()
  self:display()
  self:display_focus()
end

setmetatable(Button, {
  __index = Widget,
  __call = Button.create
})

-- Event listener -------------------------------------------------------------
function listen(widget, event, fn, capture, prepend)
  capture = type(capture) == "boolean" and capture or false
  prepend = type(prepend) == "boolean" and prepend or false
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
    if not widget[event] then
      widget[event] = {fn}
    else
      if type(widget[event]) == "function" then
        widget[event] = {widget[event]}
      end
      if prepend then
        table.insert(widget[event], 1, fn)
      else
        table.insert(widget[event], fn)
      end
    end
  else
    error("listener not attached, "..tostring(widget))
  end
end
