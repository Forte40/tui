loadfile("tui")()

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
      self.display = math.pow(self.display, self.lastnum)
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
      self.display = math.pow(self.num, self.display)
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
    Button{name="close", text="X"},
    Button{name="number_field", text="0", colSpan=5},
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

    Button{name="power", text="^", bgChar="."},
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
  calc:number(self.data)
end
for num = 0, 9 do
  listen("number"..tostring(num), "mouse_click", numberClick)
end

function decimal:mouse_click()
  calc:decimal()
end

function opClick(self)
  calc:operation(self.text[self.value])
end
for _, op in ipairs({"add", "subtract", "multiply", "divide", "power"}) do
  listen(op, "mouse_click", opClick)
end

function reciprocal:mouse_click()
  calc:reciprocal()
end

function equal:mouse_click()
  calc:equal()
end

function clear:mouse_click()
  calc:clear()
end

function store:mouse_click()
  calc:store()
end

function recall:mouse_click()
  calc:recall()
end

function close:mouse_click()
  self:stop()
end

function calculator:mouse_click()
  number_field.text[1] = tostring(calc.display)
  number_field:display()
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
  number_field.text[1] = tostring(calc.display)
  number_field:display()
end

function calculator:key(key)
  if key == keys.enter then
    calc:equal()
  elseif key == keys.delete then
    calc:clear()
  end
  number_field.text[1] = tostring(calc.display)
  number_field:display()
end

calculator:run(term)
