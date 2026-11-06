-- WORKING Meadows Installer (self-contained: no MineOS libraries, images or Files.cfg)
local component, computer = component, computer
local gpu = component.proxy(component.list("gpu")() or error("No GPU"))
local eepromAddr = component.list("eeprom")() or error("No EEPROM")
gpu.bind(component.list("screen")() or error("No screen"))
pcall(gpu.setDepth, gpu.maxDepth())
do local mw, mh = gpu.maxResolution(); pcall(gpu.setResolution, math.min(mw, 80), math.min(mh, 25)) end
local W, H = gpu.getResolution()

local C = {bg = 0x0E1424, panel = 0x151B33, side = 0x1B2340, accent = 0x00C2FF,
           text = 0xE6EDF7, dim = 0x7D8AA8, btn = 0x2F3C6B, red = 0xFF5C7A, green = 0x7CFFB2}

----------------------------------------------------------------------
-- Embedded Meadows system files
----------------------------------------------------------------------
local BOOT = [==[
local c, k = component, computer
local st = "start"
local function die(m)
  pcall(function()
    local g = c.proxy(c.list("gpu")())
    g.bind(c.list("screen")())
    local w, h = g.getResolution()
    g.setBackground(0x550000); g.setForeground(0xFFFFFF); g.fill(1, 1, w, h, " ")
    local y = 1
    for l in tostring(m):gmatch("[^\n]+") do
      g.set(1, y, l:sub(1, w)); y = y + 1
      if y >= h then break end
    end
    g.set(1, h, "Meadows boot failed. Press a key to retry.")
  end)
  repeat local e = k.pullSignal() until e == "key_down"
  k.shutdown(true)
end
local ok, err = xpcall(function()
  st = "eeprom"
  local e = c.list("eeprom")()
  st = "getData"
  local a = c.invoke(e, "getData")
  st = "proxy"
  local f = assert(c.proxy(a), "bad boot address: " .. tostring(a))
  st = "open"
  local h = assert(f.open("/init.lua", "rb"))
  st = "read"
  local d, s = "", nil
  repeat s = f.read(h, math.huge) d = d .. (s or "") until not s
  f.close(h)
  st = "load"
  if k.setBootAddress then k.setBootAddress(a) end
  local fn = assert(load(d, "=init"))
  st = "run"
  fn()
end, function(m)
  return "[stage: " .. st .. "] " .. tostring(m) .. "\n" .. ((debug and debug.traceback) and debug.traceback() or "")
end)
if not ok then die(err) end
]==]

local INIT = [==[
local component, computer = component, computer
local gpu = component.proxy(component.list("gpu")())
gpu.bind(component.list("screen")())
pcall(gpu.setDepth, gpu.maxDepth())
do local mw, mh = gpu.maxResolution(); pcall(gpu.setResolution, math.min(mw, 100), math.min(mh, 30)) end
local W, H = gpu.getResolution()

local user = "User"
pcall(function()
  local fs = component.proxy(computer.getBootAddress())
  local h = fs.open("/meadows/user.cfg", "rb")
  local d = fs.read(h, 64); fs.close(h)
  if d and #d > 0 then user = d end
end)

local C = {bg = 0x0E1424, task = 0x1B2340, accent = 0x00C2FF, text = 0xE6EDF7,
           dim = 0x7D8AA8, win = 0x202A4A, title = 0x2F3C6B, red = 0xFF5C7A}

local function rect(x, y, w, h, c) gpu.setBackground(c); gpu.fill(x, y, w, h, " ") end
local function put(x, y, s, fg, bg) gpu.setBackground(bg); gpu.setForeground(fg); gpu.set(x, y, s) end

----------------------------------------------------------------------
-- Apps
----------------------------------------------------------------------
local function newAbout()
  return {title = "About Meadows", w = 40, h = 9, draw = function(s)
    put(s.x + 2, s.y + 2, "Meadows 1.0", C.accent, C.win)
    put(s.x + 2, s.y + 4, "A tiny desktop OS for OpenComputers.", C.text, C.win)
    put(s.x + 2, s.y + 5, "Signed in as: " .. user, C.dim, C.win)
    put(s.x + 2, s.y + 6, "Free RAM: " .. math.floor(computer.freeMemory() / 1024) .. " KB", C.dim, C.win)
  end}
end

local function newCalc()
  local disp, acc, op, fresh = "0", nil, nil, true
  local keys = {"7","8","9","/","4","5","6","*","1","2","3","-","C","0","=","+"}
  local function fmt(n) return string.format("%.10g", n) end
  local function press(k)
    if k:match("%d") then
      if fresh or disp == "0" or disp == "Error" then disp = k; fresh = false
      elseif #disp < 12 then disp = disp .. k end
    elseif k == "C" then disp, acc, op, fresh = "0", nil, nil, true
    elseif disp ~= "Error" then
      local b = tonumber(disp)
      if acc and op and not fresh then
        if op == "+" then acc = acc + b elseif op == "-" then acc = acc - b
        elseif op == "*" then acc = acc * b
        elseif b == 0 then disp, acc, op, fresh = "Error", nil, nil, true; return
        else acc = acc / b end
        disp = fmt(acc)
      else acc = b end
      if k == "=" then acc, op = nil, nil else op = k end
      fresh = true
    end
  end
  return {title = "Calculator", w = 26, h = 16, draw = function(s)
    rect(s.x + 2, s.y + 2, 22, 1, C.bg)
    put(s.x + 24 - #disp, s.y + 2, disp, C.accent, C.bg)
    for i, k in ipairs(keys) do
      local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
      local bx, by = s.x + 2 + col * 6, s.y + 4 + row * 3
      local isOp = k:match("%d") == nil
      rect(bx, by, 5, 2, isOp and C.accent or C.title)
      put(bx + 2, by, k, isOp and C.bg or C.text, isOp and C.accent or C.title)
    end
  end, onTouch = function(s, x, y)
    local rx, ry = x - (s.x + 2), y - (s.y + 4)
    if rx < 0 or ry < 0 then return end
    local col, row = math.floor(rx / 6), math.floor(ry / 3)
    if col < 4 and row < 4 and rx % 6 < 5 and ry % 3 < 2 then press(keys[row * 4 + col + 1]) end
  end}
end

local function newNotes()
  local lines = {""}
  return {title = "Notes", w = 46, h = 16, draw = function(s)
    rect(s.x + 1, s.y + 1, s.w - 2, s.h - 2, C.bg)
    local first = math.max(1, #lines - (s.h - 3))
    for i = first, #lines do
      put(s.x + 2, s.y + 1 + (i - first), lines[i] .. (i == #lines and "_" or ""), C.text, C.bg)
    end
  end, onKey = function(s, char, code)
    local l = lines[#lines]
    if code == 14 then
      if #l > 0 then lines[#lines] = l:sub(1, -2) elseif #lines > 1 then table.remove(lines) end
    elseif code == 28 then lines[#lines + 1] = ""
    elseif char >= 32 and char < 127 and #l < s.w - 5 then lines[#lines] = l .. string.char(char) end
  end}
end

----------------------------------------------------------------------
-- Desktop shell
----------------------------------------------------------------------
local icons = {{"Calc", newCalc, 0x00C2FF}, {"Notes", newNotes, 0xFFC857}, {"About", newAbout, 0x7CFFB2}}
local menu = {
  {"Calculator", newCalc}, {"Notes", newNotes}, {"About", newAbout},
  {"Reboot", function() computer.shutdown(true) end},
  {"Shut down", function() computer.shutdown() end},
}
local win, menuOpen, drag

local function open(fn)
  win = fn(); win.x = math.floor((W - win.w) / 2); win.y = math.max(1, math.floor((H - win.h) / 2))
end

local function render()
  rect(1, 1, W, H - 1, C.bg)
  put(W - 8, H - 2, "MEADOWS", C.title, C.bg)
  for i, ic in ipairs(icons) do
    local y = 2 + (i - 1) * 5
    rect(3, y, 8, 3, ic[3]); put(6, y + 1, ic[1]:sub(1, 1), C.bg, ic[3]); put(3, y + 3, ic[1], C.text, C.bg)
  end
  if win then
    rect(win.x, win.y, win.w, win.h, C.win)
    rect(win.x, win.y, win.w, 1, C.title)
    put(win.x + 1, win.y, win.title, C.text, C.title)
    put(win.x + win.w - 2, win.y, "x", C.red, C.title)
    win:draw()
  end
  rect(1, H, W, 1, C.task)
  put(1, H, "  Start  ", C.bg, C.accent)
  if win then put(12, H, win.title, C.text, C.task) end
  local ok, t = pcall(os.date, "%H:%M"); if not ok then t = "--:--" end
  put(W - #t, H, t, C.dim, C.task)
  if menuOpen then
    local my = H - #menu
    rect(1, my, 22, #menu, C.task)
    for i, m in ipairs(menu) do put(3, my + i - 1, m[1], C.text, C.task) end
  end
end

local function main()
render()
while true do
  local e, _, a, b = computer.pullSignal(5)
  if e == "touch" then
    local x, y = a, b
    if menuOpen then
      local my = H - #menu
      menuOpen = false
      if x <= 22 and y >= my and y < H then
        local m = menu[y - my + 1]
        if m then
          if m[1] == "Reboot" or m[1] == "Shut down" then m[2]() else open(m[2]) end
        end
      end
    elseif y == H and x <= 9 then menuOpen = true
    elseif win and x >= win.x and x < win.x + win.w and y >= win.y and y < win.y + win.h then
      if y == win.y then
        if x >= win.x + win.w - 2 then win = nil else drag = {x - win.x, y - win.y} end
      elseif win.onTouch then win:onTouch(x, y) end
    else
      for i, ic in ipairs(icons) do
        local iy = 2 + (i - 1) * 5
        if x >= 3 and x <= 10 and y >= iy and y <= iy + 3 then open(ic[2]) end
      end
    end
  elseif e == "drag" and drag and win then
    win.x = math.max(1, math.min(W - win.w + 1, a - drag[1]))
    win.y = math.max(1, math.min(H - win.h, b - drag[2]))
  elseif e == "drop" then drag = nil
  elseif e == "key_down" and win and win.onKey then win:onKey(a, b) end
  render()
end
end
local ok, err = xpcall(main, function(m)
  return tostring(m) .. "\n" .. ((debug and debug.traceback) and debug.traceback() or "")
end)
rect(1, 1, W, H, 0x550000)
local y = 1
for line in tostring(err):gmatch("[^\n]+") do
  put(1, y, line:sub(1, W), 0xFFFFFF, 0x550000); y = y + 1
  if y > H then break end
end
put(1, H, "Meadows crashed. Press any key to reboot.", 0xFFFF00, 0x550000)
repeat local e = computer.pullSignal() until e == "key_down"
computer.shutdown(true)
]==]

----------------------------------------------------------------------
-- Installer UI
----------------------------------------------------------------------
local PW, PH = 62, 19
local px, py = math.floor((W - PW) / 2) + 1, math.floor((H - PH) / 2) + 1
local steps = {"Welcome", "Disk", "Account", "Confirm", "Install", "Finish"}

local function rect(x, y, w, h, c) gpu.setBackground(c); gpu.fill(x, y, w, h, " ") end
local function put(x, y, s, fg, bg) gpu.setBackground(bg or C.panel); gpu.setForeground(fg or C.text); gpu.set(x, y, s) end

local function frame(step)
  rect(1, 1, W, H, C.bg)
  rect(px, py, PW, PH, C.panel)
  rect(px, py, 18, PH, C.side)
  put(px + 2, py + 1, "MEADOWS", C.accent, C.side)
  for i, name in ipairs(steps) do
    local on = i == step
    put(px + 2, py + 3 + i * 2, (on and "> " or "  ") .. name, on and C.text or C.dim, C.side)
  end
end

local function button(x, y, label, primary)
  local w = #label + 4
  rect(x, y, w, 1, primary and C.accent or C.btn)
  put(x + 2, y, label, primary and C.bg or C.text, primary and C.accent or C.btn)
  return {x = x, y = y, w = w}
end
local function hit(b, x, y) return b and x >= b.x and x < b.x + b.w and y == b.y end

local function wait(handler)
  while true do
    local e, _, a, b, c = computer.pullSignal()
    local r = handler(e, a, b, c)
    if r ~= nil then return r end
  end
end

local function title(s, sub)
  put(px + 21, py + 1, s, C.text); if sub then put(px + 21, py + 3, sub, C.dim) end
end

local selected, username = nil, "Player"

local function welcome()
  frame(1); title("Welcome to Meadows")
  put(px + 21, py + 4, "A fresh desktop OS for OpenComputers.", C.dim)
  put(px + 21, py + 6, "This installer will:", C.text)
  put(px + 23, py + 7, "- erase the disk you choose", C.dim)
  put(px + 23, py + 8, "- install the Meadows desktop", C.dim)
  put(px + 23, py + 9, "- flash this computer's EEPROM", C.dim)
  local go = button(px + PW - 16, py + PH - 2, "Start", true)
  local quit = button(px + 21, py + PH - 2, "Shut down")
  return wait(function(e, x, y)
    if e == "touch" then
      if hit(go, x, y) then return 2 elseif hit(quit, x, y) then computer.shutdown() end
    end
  end)
end

local function diskStep()
  frame(2); title("Choose a disk", "WARNING: everything on it will be erased.")
  local list = {}
  for addr in component.list("filesystem") do
    local p = component.proxy(addr)
    if not p.isReadOnly() and p.spaceTotal() >= 512 * 1024 and addr ~= (computer.tmpAddress and computer.tmpAddress()) then
      list[#list + 1] = p
    end
  end
  if #list == 0 then put(px + 21, py + 6, "No writable disk found.", C.red) end
  local function draw()
    for i, p in ipairs(list) do
      if i > 5 then break end
      local y = py + 5 + (i - 1) * 2
      local on = selected == p
      rect(px + 21, y, 38, 1, on and C.accent or C.btn)
      local line = (p.getLabel() or p.address:sub(1, 8)) .. "  " ..
        math.floor(p.spaceTotal() / 1024) .. " KB"
      put(px + 22, y, line, on and C.bg or C.text, on and C.accent or C.btn)
    end
    rect(px + PW - 16, py + PH - 2, 14, 1, C.panel)
    if selected then button(px + PW - 16, py + PH - 2, "Next", true) end
  end
  draw()
  local back = button(px + 21, py + PH - 2, "Back")
  return wait(function(e, x, y)
    if e ~= "touch" then return end
    if hit(back, x, y) then return 1 end
    if selected and x >= px + PW - 16 and y == py + PH - 2 then return 3 end
    for i, p in ipairs(list) do
      if i <= 5 and y == py + 5 + (i - 1) * 2 and x >= px + 21 and x < px + 59 then
        selected = p; draw()
      end
    end
  end)
end

local function accountStep()
  frame(3); title("Create your account", "Pick a username (letters, numbers, _).")
  local function draw()
    rect(px + 21, py + 6, 30, 1, C.btn)
    put(px + 22, py + 6, username .. "_", C.text, C.btn)
  end
  draw()
  local back = button(px + 21, py + PH - 2, "Back")
  local nxt = button(px + PW - 16, py + PH - 2, "Next", true)
  return wait(function(e, a, b)
    if e == "touch" then
      if hit(back, a, b) then return 2 elseif hit(nxt, a, b) and #username > 0 then return 4 end
    elseif e == "key_down" then
      if b == 14 then username = username:sub(1, -2)
      elseif b == 28 and #username > 0 then return 4
      elseif a < 127 and string.char(a):match("[%w_]") and #username < 16 then username = username .. string.char(a) end
      draw()
    end
  end)
end

local function confirmStep()
  frame(4); title("Ready to install")
  put(px + 21, py + 4, "User:  " .. username, C.text)
  put(px + 21, py + 5, "Disk:  " .. (selected.getLabel() or selected.address:sub(1, 8)), C.text)
  put(px + 21, py + 7, "All data on this disk will be lost.", C.red)
  local back = button(px + 21, py + PH - 2, "Back")
  local go = button(px + PW - 22, py + PH - 2, "Erase & install", true)
  return wait(function(e, x, y)
    if e == "touch" then
      if hit(back, x, y) then return 3 elseif hit(go, x, y) then return 5 end
    end
  end)
end

local function write(fs, path, data)
  local h = assert(fs.open(path, "wb"))
  for i = 1, #data, 2048 do fs.write(h, data:sub(i, i + 2047)) end
  fs.close(h)
end

local function installStep()
  frame(5); title("Installing...")
  local function bar(v, msg)
    rect(px + 21, py + 8, 38, 1, C.btn)
    rect(px + 21, py + 8, math.floor(38 * v), 1, C.accent)
    rect(px + 21, py + 10, 38, 1, C.panel)
    put(px + 21, py + 10, msg, C.dim)
  end
  bar(0, "Erasing disk")
  local fs = selected
  for _, name in ipairs(fs.list("/")) do fs.remove("/" .. name) end
  bar(0.25, "Writing system files")
  fs.makeDirectory("/meadows")
  write(fs, "/meadows/user.cfg", username)
  bar(0.5, "Writing init.lua")
  write(fs, "/init.lua", INIT)
  bar(0.75, "Flashing EEPROM")
  component.invoke(eepromAddr, "set", BOOT)
  component.invoke(eepromAddr, "setLabel", "Meadows EFI")
  component.invoke(eepromAddr, "setData", fs.address)
  if not fs.getLabel() then pcall(fs.setLabel, "Meadows HDD") end
  bar(1, "Done")
  computer.pullSignal(0.5)
  return 6
end

local function finishStep()
  frame(6); title("Meadows is installed", "Welcome, " .. username .. "!")
  put(px + 21, py + 6, "Reboot to start your new desktop.", C.green)
  local go = button(px + PW - 16, py + PH - 2, "Reboot", true)
  wait(function(e, x, y) if e == "touch" and hit(go, x, y) then computer.shutdown(true) end end)
end

local fns = {welcome, diskStep, accountStep, confirmStep, installStep, finishStep}
local ok, err = xpcall(function()
  local step = 1
  while true do step = fns[step]() or step end
end, function(m)
  return tostring(m) .. "\n" .. ((debug and debug.traceback) and debug.traceback() or "")
end)
rect(1, 1, W, H, 0x550000)
local y = 1
for line in tostring(err):gmatch("[^\n]+") do
  put(1, y, line:sub(1, W), 0xFFFFFF, 0x550000); y = y + 1
  if y > H then break end
end
put(1, H, "Installer crashed. Press any key to reboot.", 0xFFFF00, 0x550000)
repeat local e = computer.pullSignal() until e == "key_down"
computer.shutdown(true)
