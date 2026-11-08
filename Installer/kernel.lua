-- =========================================================
-- CHANGE 1.0
-- MEADOWS OS 3.0 - FOREST EDITION
-- Native OpenComputers BIOS kernel
-- =========================================================
-- Install as the kernel loaded by your EEPROM.
-- User data is stored on the selected writable filesystem in /.meadows.
-- Written for OpenComputers Lua; static review only, not runtime-tested.
--
-- Controls:
--   Touch: select and operate controls; drag title bars; resize bottom-right.
--   Keyboard: type in focused fields/terminal/notes.
--   Esc: close menus or the focused window.
--   Ctrl+C / Ctrl+X / Ctrl+V: file operations when Explorer is focused.
--   Alt+F4: close focused window.
--
-- IMPORTANT: Back up your world and existing Meadows data before testing.
-- =========================================================

local component = component
local computer = computer
local unicode = unicode

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()
if not gpuAddress or not screenAddress then
  error("Meadows 3.0: GPU or screen not found.")
end

local gpu = component.proxy(gpuAddress)
local okBind, bindErr = pcall(gpu.bind, screenAddress)
if not okBind then error("Meadows 3.0: Could not bind screen: " .. tostring(bindErr)) end

local W, H = gpu.getResolution()
if W < 50 or H < 20 then
  error("Meadows 3.0 requires a screen of at least 50x20.")
end
pcall(gpu.setDepth, 8)

local VERSION = "3.0"
local OS_NAME = "Meadows"
local MAX_WINDOWS = 4
local C = {
  bg = 0x08130E, desktop = 0x10271B, desktop2 = 0x183A28,
  panel = 0x14251C, panel2 = 0x20382B, window = 0x17271E,
  title = 0x294B38, accent = 0x72D69A, accent2 = 0x285C3D,
  text = 0xE8F5EC, muted = 0x9BB5A3, border = 0x42634C,
  close = 0xD94F55, white = 0xFFFFFF, black = 0x000000,
  select = 0x285C3D, input = 0x0C1911,

  editorBg = 0x101C15,
  editorMuted = 0x8FA99A,
  editorText = 0xDCEBE0,
  fileText = 0xDCEBE0
}

local DATA_DIR = "/.meadows"
local CONFIG_FILE = DATA_DIR .. "/system.cfg"
local ACCOUNTS_FILE = DATA_DIR .. "/accounts.db"
local NOTES_FILE = DATA_DIR .. "/notes.txt"
local STORAGE_ID_FILE = DATA_DIR .. "/storage.id"

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function rect(x, y, w, h, color)
  x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
  if x < 1 then w, x = w - 1 + x, 1 end
  if y < 1 then h, y = h - 1 + y, 1 end
  if x + w - 1 > W then w = W - x + 1 end
  if y + h - 1 > H then h = H - y + 1 end
  if w <= 0 or h <= 0 then return end
  gpu.setBackground(color or C.bg)
  gpu.fill(x, y, w, h, " ")
end

local function put(x, y, value, fg, bg)
  value = tostring(value or "")
  x, y = math.floor(x), math.floor(y)
  if y < 1 or y > H or x > W then return end
  if x < 1 then value, x = value:sub(2 - x), 1 end
  if x + #value - 1 > W then value = value:sub(1, W - x + 1) end
  if #value == 0 then return end
  gpu.setForeground(fg or C.text)
  gpu.setBackground(bg or C.bg)
  gpu.set(x, y, value)
end

local function center(y, value, fg, bg)
  value = tostring(value or "")
  put(math.floor((W - #value) / 2) + 1, y, value, fg, bg)
end

local function hit(x, y, bx, by, bw, bh)
  return x and y and x >= bx and x < bx + bw and y >= by and y < by + bh
end

local function button(x, y, w, label, active, color)
  local surface = color or (active and C.accent2 or C.panel2)
  rect(x, y, w, 1, surface)
  local s = tostring(label or "")
  local tx = x + math.max(0, math.floor((w - #s) / 2))
  put(tx, y, s:sub(1, w), C.white, surface)
end

local config

local function virtualTimestamp()
  local now = os and os.time and os.time() or 0
  return now + (tonumber(config and config.clockShift) or 0) +
    (tonumber(config and config.utcOffset) or 0) * 60
end

local function clockText()
  if os and os.date then
    local ok, value = pcall(os.date, "!%H:%M:%S", virtualTimestamp())
    if ok and value then return tostring(value) end
  end
  local t = math.floor(computer.uptime())
  return string.format("%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60)
end

local function dateText()
  if os and os.date then
    local ok, value = pcall(os.date, "!%Y-%m-%d", virtualTimestamp())
    if ok and value then return tostring(value) end
  end
  return "OpenComputers"
end

local function utcLabel()
  local offset = tonumber(config and config.utcOffset) or 0
  local sign = offset < 0 and "-" or "+"
  offset = math.abs(offset)
  return "UTC" .. sign .. string.format("%02d:%02d", math.floor(offset / 60), offset % 60)
end

local function clear(color)
  rect(1, 1, W, H, color or C.bg)
end

local function charFromCode(code)
  if not code or code <= 0 then return "" end
  if unicode and unicode.char then
    local ok, value = pcall(unicode.char, code)
    if ok and value then return value end
  end
  if code >= 32 and code <= 255 then
    local ok, value = pcall(string.char, code)
    if ok then return value end
  end
  return ""
end

local function textLen(s)
  if unicode and unicode.len then
    local ok, n = pcall(unicode.len, tostring(s or ""))
    if ok and n then return n end
  end
  return #(tostring(s or ""))
end

local function textSub(s, i, j)
  if unicode and unicode.sub then
    local ok, v = pcall(unicode.sub, s, i, j)
    if ok then return v end
  end
  return tostring(s or ""):sub(i, j)
end

local function appendChar(s, ch)
  return tostring(s or "") .. tostring(ch or "")
end

local function backspace(s)
  s = tostring(s or "")
  if unicode and unicode.sub and unicode.len then
    local n = unicode.len(s)
    return unicode.sub(s, 1, math.max(0, n - 1))
  end
  return s:sub(1, -2)
end

local function bootSplash()
  local frames = {"|", "/", "-", "\\"}
  local logo = {
    "  __  __",
    " |  \\/  |",
    " | |\\/| |",
    " |_|  |_|"
  }
  for frame = 1, 24 do
    clear(C.bg)
    local top = math.max(2, math.floor(H / 2) - 8)
    for i = 1, #logo do center(top + i - 1, logo[i], C.accent) end
    center(top + 5, "MEADOWS", C.white)
    center(top + 7, "FOREST EDITION", C.accent)
    center(H - 4, "Starting Meadows " .. frames[(frame - 1) % #frames + 1], C.muted)
    center(H - 2, "VERSION " .. VERSION, C.muted)
    computer.pullSignal(0.09)
  end
end

-- ------------------------- Storage discovery -------------------------
local function fsExists(fs, path)
  local ok, value = pcall(fs.exists, path)
  return ok and value == true
end

local function fsRead(fs, path)
  local ok, handle = pcall(fs.open, path, "r")
  if not ok or not handle then return nil end
  local chunks = {}
  while true do
    local readOK, data = pcall(fs.read, handle, 4096)
    if not readOK or not data or #data == 0 then break end
    chunks[#chunks + 1] = data
  end
  pcall(fs.close, handle)
  return table.concat(chunks)
end

local function fsWrite(fs, path, data)
  path = tostring(path or "")
  data = tostring(data or "")
  local ok, handle, openReason = pcall(fs.open, path, "w")
  if not ok or not handle then
    return false, "Could not open '" .. path .. "' for writing: " .. tostring(openReason or handle or "unknown storage error")
  end
  local writeOK, writeReason = true, nil
  local offset = 1
  while offset <= #data do
    local chunk = data:sub(offset, offset + 4095)
    local callOK, result, reason = pcall(fs.write, handle, chunk)
    if not callOK or result == false then
      writeOK, writeReason = false, reason or result or "write failed"
      break
    end
    offset = offset + #chunk
  end
  local closeOK, closeResult, closeReason = pcall(fs.close, handle)
  if not writeOK or not closeOK or closeResult == false then
    return false, "Could not write '" .. path .. "': " .. tostring(writeReason or closeReason or "storage error")
  end
  local saved = fsRead(fs, path)
  if saved ~= data then return false, "Storage verification failed for '" .. path .. "'." end
  return true
end

bootSplash()

local drives = {}
for address in component.list("filesystem") do
  local proxyOK, fs = pcall(component.proxy, address)
  if proxyOK and fs then
    local readOnly = true
    if fs.isReadOnly then
      local ok, value = pcall(fs.isReadOnly)
      if ok then readOnly = value == true end
    end
    if not readOnly then
      local total, used, label = 0, 0, "Unnamed"
      if fs.spaceTotal then local ok, v = pcall(fs.spaceTotal); if ok then total = tonumber(v) or 0 end end
      if fs.spaceUsed then local ok, v = pcall(fs.spaceUsed); if ok then used = tonumber(v) or 0 end end
      if fs.getLabel then local ok, v = pcall(fs.getLabel); if ok and v and v ~= "" then label = tostring(v) end end
      drives[#drives + 1] = {address = address, fs = fs, label = label, total = total, used = used}
    end
  end
end
if #drives == 0 then error("Meadows 3.0: No writable filesystem found.") end

local function chooseStorage()
  local choice, scroll = 1, 0
  while true do
    clear(C.bg)
    center(2, "MEADOWS 3.0 INSTALLATION", C.accent)
    center(4, "Choose the writable drive for system data.", C.white)
    local visible = math.max(1, H - 10)
    if choice > scroll + visible then scroll = choice - visible end
    if choice <= scroll then scroll = choice - 1 end
    for row = 1, visible do
      local i = row + scroll
      local disk = drives[i]
      if disk then
        local y = 6 + row
        if i == choice then rect(3, y, W - 6, 1, C.select) end
        local free = math.max(0, disk.total - disk.used)
        local capacity = disk.total > 0 and (math.floor(free / 1024) .. " KB free") or "Capacity unknown"
        put(5, y, i .. ". " .. disk.label .. " | " .. capacity, C.white, i == choice and C.select or C.bg)
      end
    end
    center(H - 2, "Tap a drive or use Up/Down and Enter.", C.muted)
    local sig, addr, ch, code = computer.pullSignal()
    if sig == "touch" then
      local x, y = tonumber(ch), tonumber(code)
      if x and y then
        for row = 1, visible do
          local i = row + scroll
          if drives[i] and y == 6 + row and x >= 3 and x <= W - 3 then return drives[i] end
        end
      end
    elseif sig == "key_down" then
      if code == 200 then choice = math.max(1, choice - 1)
      elseif code == 208 then choice = math.min(#drives, choice + 1)
      elseif code == 28 or ch == 13 then return drives[choice] end
    end
  end
end

local selectedDisk
for i = 1, #drives do
  local disk = drives[i]
  if fsExists(disk.fs, DATA_DIR) and fsExists(disk.fs, STORAGE_ID_FILE) then
    local saved = fsRead(disk.fs, STORAGE_ID_FILE)
    if saved and saved:gsub("%s+", "") == disk.address then selectedDisk = disk; break end
  end
end
if not selectedDisk then selectedDisk = chooseStorage() end
if not selectedDisk then error("Meadows: No installation drive selected.") end

local filesystem = selectedDisk.fs
local STORAGE_ADDRESS = selectedDisk.address
if filesystem.setLabel then pcall(filesystem.setLabel, "Meadows") end
if not fsExists(filesystem, DATA_DIR) then
  local ok, result = pcall(filesystem.makeDirectory, DATA_DIR)
  if not ok or result == false or not fsExists(filesystem, DATA_DIR) then
    error("Meadows: Could not create system directory.")
  end
end
local storageOK = fsWrite(filesystem, DATA_DIR .. "/storage-test.tmp", "MEADOWS STORAGE TEST")
if not storageOK then error("Meadows: Storage write test failed.") end
pcall(filesystem.remove, DATA_DIR .. "/storage-test.tmp")
local identityOK = fsWrite(filesystem, STORAGE_ID_FILE, STORAGE_ADDRESS)
if not identityOK then error("Meadows: Could not save drive identity.") end

local function readFile(path) return fsRead(filesystem, path) end
local function writeFile(path, data) return fsWrite(filesystem, path, data) end

-- ------------------------- Configuration and accounts -------------------------
config = {
  computerName = "Meadows-PC", wallpaper = 1, username = "",
  displayName = "", adminName = "", setupComplete = false, setupVersion = 0, passwordEnabled = true, version = VERSION,
  clockShift = 0, utcOffset = 0
}

local function cleanValue(value)
  value = tostring(value or "")
  value = value:gsub("[\r\n]", ""):gsub("|", ""):gsub("=", "")
  return value
end

local function saveConfig()
  local lines = {
    "computerName=" .. cleanValue(config.computerName),
    "wallpaper=" .. cleanValue(config.wallpaper),
    "username=" .. cleanValue(config.username),
    "displayName=" .. cleanValue(config.displayName),
    "adminName=" .. cleanValue(config.adminName),
    "passwordEnabled=" .. tostring(config.passwordEnabled ~= false),
    "setupVersion=" .. tostring(tonumber(config.setupVersion) or 0),
    "setupComplete=" .. tostring(config.setupComplete),
    "version=" .. cleanValue(config.version),
    "clockShift=" .. tostring(tonumber(config.clockShift) or 0),
    "utcOffset=" .. tostring(tonumber(config.utcOffset) or 0)
  }
  return writeFile(CONFIG_FILE, table.concat(lines, "\n"))
end

local function loadConfig()
  local data = readFile(CONFIG_FILE)
  if not data then return end
  for line in data:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key and value then
      if key == "computerName" then config.computerName = value
      elseif key == "wallpaper" then config.wallpaper = tonumber(value) or 1
      elseif key == "username" then config.username = value
      elseif key == "displayName" then config.displayName = value
      elseif key == "adminName" then config.adminName = value
      elseif key == "passwordEnabled" then config.passwordEnabled = value == "true"
      elseif key == "setupVersion" then config.setupVersion = tonumber(value) or 0
      elseif key == "setupComplete" then config.setupComplete = value == "true"
      elseif key == "version" then config.version = value
      elseif key == "clockShift" then config.clockShift = tonumber(value) or 0
      elseif key == "utcOffset" then config.utcOffset = clamp(tonumber(value) or 0, -720, 840) end
    end
  end
end
loadConfig()

local function hashPassword(password)
  local hash = 5381
  password = tostring(password or "")
  for i = 1, #password do hash = (hash * 33 + password:byte(i)) % 2147483647 end
  return tostring(hash)
end

local function verifyPassword(password, savedHash)
  return hashPassword(password) == tostring(savedHash or "")
end

local accounts = {}
local function saveAccounts()
  local lines = {}
  for i = 1, #accounts do
    local a = accounts[i]
    lines[#lines + 1] = table.concat({
      cleanValue(a.username), cleanValue(a.displayName), cleanValue(a.passwordHash)
    }, "|")
  end
  return writeFile(ACCOUNTS_FILE, table.concat(lines, "\n"))
end

local function loadAccounts()
  accounts = {}
  local data = readFile(ACCOUNTS_FILE)
  if not data then return end
  for line in data:gmatch("[^\r\n]+") do
    local u, d, p = line:match("^([^|]*)|([^|]*)|([^|]*)$")
    if u and u ~= "" then
      accounts[#accounts + 1] = {username = u, displayName = d or u, passwordHash = p or ""}
    end
  end
end
loadAccounts()

-- ------------------------- Input and message dialogs -------------------------
local function inputDialog(title, prompt, initial, masked, digitsOnly)
  local value = tostring(initial or "")
  local cursor = #value + 1
  local blink = true
  local lastBlink = computer.uptime()
  while true do
    clear(C.bg)
    local boxY = math.floor(H / 2) - 5
    rect(3, boxY, W - 6, 11, C.window)
    rect(3, boxY, W - 6, 1, C.title)
    center(boxY, title, C.white, C.title)
    center(boxY + 2, prompt, C.text, C.window)
    rect(6, boxY + 5, W - 12, 1, C.input)
    local shown = masked and string.rep("*", #value) or value
    local maxChars = W - 16
    if textLen(shown) > maxChars then shown = textSub(shown, textLen(shown) - maxChars + 1, -1) end
    put(7, boxY + 5, shown, C.white, C.input)
    if blink then
      local cx = math.min(W - 7, 7 + textLen(shown))
      put(cx, boxY + 5, "|", C.accent, C.input)
    end
    button(math.floor(W / 2) - 12, boxY + 8, 10, "OK", true)
    button(math.floor(W / 2) + 2, boxY + 8, 10, "Cancel", false)
    local sig, addr, ch, code = computer.pullSignal(0.15)
    local now = computer.uptime()
    if now - lastBlink >= 0.45 then blink = not blink; lastBlink = now end
    if sig == "touch" then
      local x, y = tonumber(ch), tonumber(code)
      if x and y and y == boxY + 8 then
        if hit(x, y, math.floor(W / 2) - 12, y, 10, 1) then return value end
        if hit(x, y, math.floor(W / 2) + 2, y, 10, 1) then return nil end
      end
    elseif sig == "key_down" then
      if code == 28 or ch == 13 then return value
      elseif code == 1 then return nil
      elseif code == 14 then value = backspace(value)
      else
        local c = charFromCode(ch)
        if digitsOnly and not c:match("^%d$") then c = "" end
        if c ~= "" and textLen(value) < 120 then value = appendChar(value, c) end
      end
    end
  end
end

local function messageDialog(title, message)
  clear(C.bg)
  local y = math.floor(H / 2) - 3
  rect(3, y, W - 6, 7, C.window)
  rect(3, y, W - 6, 1, C.title)
  center(y, title, C.white, C.title)
  center(y + 2, message, C.text, C.window)
  center(y + 4, "Touch or press any key", C.muted, C.window)
  while true do
    local sig = computer.pullSignal()
    if sig == "touch" or sig == "key_down" then return end
  end
end

local function confirmDialog(title, message)
  while true do
    clear(C.bg)
    local y = math.floor(H / 2) - 3
    rect(3, y, W - 6, 7, C.window)
    rect(3, y, W - 6, 1, C.title)
    center(y, title, C.white, C.title)
    center(y + 2, message, C.text, C.window)
    button(math.floor(W / 2) - 12, y + 4, 10, "Yes", true)
    button(math.floor(W / 2) + 2, y + 4, 10, "No", false)
    local sig, addr, ch, code = computer.pullSignal()
    if sig == "touch" then
      local x, yy = tonumber(ch), tonumber(code)
      if x and yy then
        if hit(x, yy, math.floor(W / 2) - 12, y + 4, 10, 1) then return true end
        if hit(x, yy, math.floor(W / 2) + 2, y + 4, 10, 1) then return false end
      end
    elseif sig == "key_down" then
      if code == 28 then return true elseif code == 1 then return false end
    end
  end
end

local function termsScreen()
  while true do
    clear(C.bg)
    center(3, "WELCOME TO MEADOWS 3.0", C.accent)
    center(6, "Your files and settings are stored on the selected drive.", C.text)
    center(8, "Back up important files regularly.", C.text)
    center(10, "An independent OpenComputers desktop environment.", C.muted)
    button(math.floor(W / 2) - 13, H - 4, 11, "Accept", true)
    button(math.floor(W / 2) + 2, H - 4, 11, "Decline", false)
    local sig, addr, ch, code = computer.pullSignal()
    if sig == "touch" then
      local x, y = tonumber(ch), tonumber(code)
      if x and y and y == H - 4 then
        if hit(x, y, math.floor(W / 2) - 13, y, 11, 1) then return true end
        if hit(x, y, math.floor(W / 2) + 2, y, 11, 1) then return false end
      end
    elseif sig == "key_down" then
      if code == 28 then return true elseif code == 1 then return false end
    end
  end
end

local function requiredInput(title, prompt, initial)
  while true do
    local value = inputDialog(title, prompt, initial)
    if value == nil then
      messageDialog("REQUIRED FIELD", "This field cannot be left blank.")
    else
      value = cleanValue(value):gsub("^%s+", ""):gsub("%s+$", "")
      if value ~= "" then return value end
      messageDialog("REQUIRED FIELD", "You must type something here.")
    end
    initial = ""
  end
end

local function setupWizard()
  if not termsScreen() then error("Meadows setup was declined.") end
  config.computerName = requiredInput("COMPUTER NAME", "Name this computer:", config.computerName)
  local display = requiredInput("DISPLAY NAME", "Display name (default: user):", "user")
  local username = requiredInput("USERNAME", "Choose a username:", "user")
  local adminName = requiredInput("ADMIN NAME", "Enter administrator name:", "admin")
  local passwordEnabled = confirmDialog("PASSWORD PROTECTION", "Enable a sign-in PIN? Yes = enabled, No = disabled")
  local passwordHash = ""
  if passwordEnabled then
    while true do
      local pin = inputDialog("CREATE PIN", "Enter a numeric PIN (at least 4 digits):", "", true, true)
      if pin and pin:match("^%d%d%d%d+$") then
        passwordHash = hashPassword(pin)
        break
      end
      messageDialog("INVALID PIN", "PIN must contain at least 4 digits (0-9).")
    end
  end
  config.username = username
  config.displayName = display
  config.adminName = adminName
  config.passwordEnabled = passwordEnabled
  accounts = {{username = username, displayName = display, passwordHash = passwordHash}}
  config.setupComplete = true
  config.setupVersion = 2
  config.version = VERSION
  if not saveConfig() or not saveAccounts() then error("Meadows: Could not save setup.") end
  messageDialog("SETUP COMPLETE", "Welcome to Meadows 3.0!")
end

if not config.setupComplete or #accounts == 0 or (tonumber(config.setupVersion) or 0) < 2 then setupWizard() end

local function loginScreen()
  while true do
    clear(C.bg)
    center(3, "MEADOWS 3.0", C.accent)
    center(5, "Welcome back to " .. tostring(config.computerName), C.white)
    for i = 1, #accounts do
      button(math.floor(W / 2) - 17, 8 + (i - 1) * 2, 34,
        accounts[i].displayName .. " (" .. accounts[i].username .. ")", false)
    end
    local sig, addr, ch, code = computer.pullSignal()
    if sig == "touch" then
      local x, y = tonumber(ch), tonumber(code)
      if x and y then
        for i = 1, #accounts do
          local row = 8 + (i - 1) * 2
          if hit(x, y, math.floor(W / 2) - 17, row, 34, 1) then
            if not accounts[i].passwordHash or accounts[i].passwordHash == "" then return accounts[i] end
            local pw = inputDialog("SIGN IN", "Enter PIN for " .. accounts[i].username .. ":", "", true, true)
            if pw ~= nil and verifyPassword(pw, accounts[i].passwordHash) then return accounts[i] end
            messageDialog("SIGN IN FAILED", "Incorrect PIN.")
          end
        end
      end
    elseif sig == "key_down" and code == 1 then
      return nil
    end
  end
end

local currentAccount = loginScreen()
if not currentAccount then error("Meadows: Login cancelled.") end
config.username = currentAccount.username
config.displayName = currentAccount.displayName
saveConfig()

-- ------------------------- Path and filesystem helpers -------------------------
local function pathJoin(a, b)
  if a == "/" then return "/" .. b end
  return a .. "/" .. b
end

local function normalizePath(path)
  path = tostring(path or "/"):gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  path = path:gsub("/+", "/")
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." and part ~= "" then parts[#parts + 1] = part end
  end
  return "/" .. table.concat(parts, "/")
end

local function parentPath(path)
  path = normalizePath(path)
  if path == "/" then return "/" end
  local p = path:match("^(.*)/[^/]+$")
  if not p or p == "" then return "/" end
  return p
end

local function baseName(path)
  path = normalizePath(path)
  if path == "/" then return "/" end
  return path:match("([^/]+)$") or path
end

local function safeName(name)
  name = tostring(name or ""):gsub("[/\\:*?\"<>|]", "")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or name == "." or name == ".." then return nil end
  return name
end

local function isProtectedPath(path)
  path = normalizePath(path)
  return path == DATA_DIR or path:sub(1, #DATA_DIR + 1) == DATA_DIR .. "/"
end

local function listDirectory(path)
  path = normalizePath(path)

  -- OpenComputers normally returns an iterator from filesystem.list().
  -- Some filesystem wrappers return a table instead. Support both forms.
  local callOK, listing, listReason = pcall(filesystem.list, path)
  if not callOK then
    return {}, "Directory listing failed: " .. tostring(listing)
  end
  if listing == nil then
    return {}, "Directory listing failed: " .. tostring(listReason or "no result returned")
  end

  local rawEntries = {}
  local function addEntry(value)
    if type(value) == "string" and value ~= "" then
      rawEntries[#rawEntries + 1] = value
    end
  end

  if type(listing) == "function" then
    while true do
      local readOK, entry = pcall(listing)
      if not readOK then
        return {}, "Directory read failed: " .. tostring(entry)
      end
      if entry == nil then break end
      addEntry(entry)
    end
  elseif type(listing) == "table" then
    -- Array-style results are the common table form. Also accept maps
    -- such as { ["folder/"] = true } without adding non-string metadata.
    for _, entry in ipairs(listing) do addEntry(entry) end
    for key, value in pairs(listing) do
      if type(key) == "string" and value == true then addEntry(key) end
    end
  else
    return {}, "Unsupported directory listing result: " .. type(listing)
  end

  local result, seen = {}, {}
  for i = 1, #rawEntries do
    local entry = tostring(rawEntries[i]):gsub("\\", "/"):gsub("/+$", "")
    entry = entry:gsub("^/+", "")
    local prefix = path == "/" and "" or (path:gsub("/$", "") .. "/")
    if prefix ~= "" and entry:sub(1, #prefix) == prefix then
      entry = entry:sub(#prefix + 1)
    end
    if entry ~= "" and not entry:find("/", 1, true) and not seen[entry] then
      result[#result + 1] = entry
      seen[entry] = true
    end
  end

  table.sort(result, function(a, b)
    local da, db = false, false
    pcall(function() da = filesystem.isDirectory(pathJoin(path, a)) end)
    pcall(function() db = filesystem.isDirectory(pathJoin(path, b)) end)
    if da ~= db then return da end
    return a:lower() < b:lower()
  end)
  return result
end

local function copyFile(source, destination)
  source, destination = normalizePath(source), normalizePath(destination)
  if filesystem.isDirectory(source) then return false, "Source is a folder." end
  local data = readFile(source)
  if data == nil then return false, "Could not read source file." end
  return writeFile(destination, data)
end

local function copyPath(source, destination)
  source, destination = normalizePath(source), normalizePath(destination)
  if filesystem.exists(destination) then return false, "Destination already exists." end
  if filesystem.isDirectory(source) then
    local ok, result = pcall(filesystem.makeDirectory, destination)
    if not ok or result == false or not filesystem.exists(destination) then return false, "Could not create destination folder." end
    local entries = listDirectory(source)
    for i = 1, #entries do
      local childOK, childErr = copyPath(pathJoin(source, entries[i]), pathJoin(destination, entries[i]))
      if not childOK then return false, childErr end
    end
    return true
  end
  return copyFile(source, destination)
end

local function deletePath(path)
  path = normalizePath(path)
  if path == "/" or isProtectedPath(path) then return false, "Protected system path." end
  if not filesystem.exists(path) then return false, "Path does not exist." end
  if filesystem.isDirectory(path) then
    local entries = listDirectory(path)
    for i = 1, #entries do
      local ok, err = deletePath(pathJoin(path, entries[i]))
      if not ok then return false, err end
    end
  end
  local ok, result = pcall(filesystem.remove, path)
  if not ok or result == false then return false, "Could not delete item." end
  return true
end

-- Notes persistence (defined explicitly; fixes the missing-function bug).
local function loadNotes()
  return readFile(NOTES_FILE) or ""
end

local function saveNotes(value)
  local ok, err = writeFile(NOTES_FILE, tostring(value or ""))
  if not ok then messageDialog("NOTES ERROR", tostring(err or "Could not save notes.")) end
  return ok
end

-- ------------------------- Theme, desktop and taskbar -------------------------
local wallpapers = {
  {name = "Forest", top = 0x10271B, bottom = 0x07130D},
  {name = "Meadow", top = 0x244C35, bottom = 0x102719},
  {name = "Night", top = 0x101B32, bottom = 0x080D19},
  {name = "Emerald", top = 0x07523E, bottom = 0x09251D}
}

local function drawWallpaper()
  local wp = wallpapers[config.wallpaper] or wallpapers[1]
  rect(1, 1, W, H, wp.bottom)
  for i = 1, 9 do
    local x = math.floor((W / 9) * (i - 1)) + 1
    local hh = math.floor(H * (0.20 + ((i * 7) % 5) * 0.045))
    rect(x, H - hh - 2, math.max(2, math.floor(W / 18)), hh, wp.top)
  end
end

local desktopIcons = {
  {name = "Files", app = "files", symbol = "[F]"},
  {name = "Notes", app = "notes", symbol = "[N]"},
  {name = "Settings", app = "settings", symbol = "[S]"},
  {name = "Terminal", app = "terminal", symbol = "[>]"},
  {name = "Monitor", app = "monitor", symbol = "[M]"},
  {name = "About", app = "about", symbol = "[i]"}
}

local windows = {}
local focused = nil

local function drawDesktop()
  drawWallpaper()
  center(2, config.computerName, C.accent)
  for i = 1, #desktopIcons do
    local icon = desktopIcons[i]
    local x = 3
    local y = 4 + (i - 1) * 3
    put(x, y, icon.symbol, C.accent, C.desktop)
    put(x, y + 1, icon.name, C.white, C.desktop)
  end
  rect(1, H - 2, W, 2, C.panel)
  local taskItems = {"Start", "Files", "Notes", "Terminal"}
  local total = 0
  for i = 1, #taskItems do total = total + #taskItems[i] + 3 end
  local x = math.max(2, math.floor((W - total) / 2))
  button(x, H - 2, #taskItems[1] + 2, taskItems[1], false); x = x + #taskItems[1] + 3
  for i = 2, #taskItems do
    local name = taskItems[i]
    local running = false
    for j = 1, #windows do if windows[j].app == name:lower() then running = true end end
    button(x, H - 2, #name + 2, name, running); x = x + #name + 3
  end
  put(W - 8, H - 2, clockText(), C.white, C.panel)
  put(W - 11, H - 1, dateText():sub(6, 10), C.muted, C.panel)
end

-- ------------------------- Window manager -------------------------
local nextWindowId = 1
local startOpen = false
local contextMenu = nil

local function findWindow(id)
  for i = 1, #windows do if windows[i].id == id then return i, windows[i] end end
  return nil, nil
end

local function closeWindow(id)
  local index = findWindow(id)
  if index then table.remove(windows, index) end
  if focused == id then focused = windows[#windows] and windows[#windows].id or nil end
end

local function focusWindow(id)
  local index, win = findWindow(id)
  if not index then return end
  table.remove(windows, index)
  windows[#windows + 1] = win
  focused = id
end

local function openWindow(app)
  for i = 1, #windows do
    if windows[i].app == app then
      windows[i].minimized = false
      focusWindow(windows[i].id)
      return true
    end
  end
  if #windows >= MAX_WINDOWS then
    messageDialog("WINDOW LIMIT", "Close or minimize a window before opening another.")
    return false
  end
  local win = {
    id = nextWindowId, app = app, title = app, x = 5 + (#windows * 3),
    y = 4 + (#windows * 2), w = math.min(W - 10, 66), h = math.min(H - 9, 30),
    minW = 38, minH = 12, minimized = false, maximized = false,
    restore = nil, state = {}
  }
  if win.w < 38 then win.w = W - 4 end
  if win.h < 12 then win.h = H - 5 end
  if app == "files" then win.title = "File Explorer"; win.state.path = "/"; win.state.selected = nil; win.state.scroll = 0; win.state.clipboard = nil; win.state.clipMode = nil; win.state.history = {"/"}; win.state.historyIndex = 1; win.state.gridMode = false; win.state.sidebar = 16
  elseif app == "notes" then win.title = "Meadows Notes"; win.state.text = loadNotes(); win.state.cursor = textLen(loadNotes()) + 1; win.state.scroll = 0; win.state.dirty = false
  elseif app == "editor" then win.title = "Text Editor"; win.state.path = "/"; win.state.text = ""; win.state.cursor = 1; win.state.scroll = 0; win.state.dirty = false
  elseif app == "picture" then win.title = "Picture Viewer"; win.state.path = ""; win.state.picture = nil
  elseif app == "terminal" then win.title = "Meadows Terminal"; win.state.path = "/"; win.state.history = {"Meadows Terminal " .. VERSION}; win.state.command = ""; win.state.cursor = 1; win.state.scroll = 0
  elseif app == "settings" then win.title = "Settings"
  elseif app == "monitor" then win.title = "System Monitor"
  elseif app == "clock" then win.title = "Calendar & Clock"
  elseif app == "about" then win.title = "About Meadows" end
  nextWindowId = nextWindowId + 1
  windows[#windows + 1] = win
  focused = win.id
  return true
end

local function windowRect(win)
  if win.maximized then return 2, 2, W - 4, H - 5 end
  return win.x, win.y, win.w, win.h
end

local function centerInWindow(x, y, w, value, fg, bg)
  value = tostring(value or "")
  local tx = x + math.max(1, math.floor((w - textLen(value)) / 2))
  put(tx, y, value, fg, bg)
end

local function splitLines(value)
  local lines = {}
  for line in (tostring(value or "") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if #lines == 0 then lines[1] = "" end
  return lines
end

local function editorCursorPosition(value, cursor)
  local before = textSub(value, 1, math.max(0, (cursor or 1) - 1))
  local line = 1
  for _ in before:gmatch("\n") do line = line + 1 end
  local last = before:match("([^\n]*)$") or ""
  return line, textLen(last)
end

local function saveDocument(win)
  local ok, err = writeFile(win.state.path, win.state.text)
  if ok then win.state.dirty = false
  else messageDialog("SAVE ERROR", tostring(err or "Could not save file.")) end
  return ok
end

local function openFileInEditor(path)
  path = normalizePath(path)
  local ext = (baseName(path):match("%.([^%.]+)$") or ""):lower()
  if ext == "pic" then
    if openWindow("picture") then
      local _, picWin = findWindow(focused)
      if picWin then
        picWin.state.path = path
        local ok, imageLib = pcall(require, "image")
        if ok and imageLib and imageLib.load then
          local loaded, result, reason = pcall(imageLib.load, path)
          if loaded and result then picWin.state.picture = result
          else picWin.state.error = tostring(reason or result or "Image load failed.") end
        else
          picWin.state.error = "MineOS image library is missing (install /lib/image.lua)."
        end
      end
    end
  else
    if openWindow("editor") then
      local _, editWin = findWindow(focused)
      if editWin then
        editWin.title = "Text Editor - " .. baseName(path)
        editWin.state.path = path
        editWin.state.text = readFile(path) or ""
        editWin.state.cursor = textLen(editWin.state.text) + 1
        editWin.state.scroll = 0
        editWin.state.dirty = false
      end
    end
  end
end

local function drawWindow(win, active)
  if win.minimized then return end
  local x, y, w, h = windowRect(win)
  rect(x + 1, y + 1, w, h, C.black)
  rect(x, y, w, h, C.window)
  rect(x, y, w, 1, active and C.title or C.panel2)
  -- top-right window controls: minimize, maximize/restore, close
  local closeX = x + w - 4
  local maxX = x + w - 8
  local minX = x + w - 12
  put(x + 2, y, win.title, C.white, active and C.title or C.panel2)
  button(minX, y, 3, "_", false, C.panel2)
  button(maxX, y, 3, win.maximized and "[]" or "[]", false, C.panel2)
  button(closeX, y, 3, "X", false, C.close)
  rect(x, y + h - 1, w, 1, C.border)

  if win.app == "editor" or win.app == "notes" then
    local s = win.state
    local editorBg = C.editorBg

    -- Dark, comfortable editing surface
    rect(x + 1, y + 2, w - 2, h - 4, editorBg)

    put(x + 2, y + 2,
      win.app == "notes" and "NOTES" or ("EDITING  /  " .. baseName(s.path)),
      C.accent, editorBg)

    put(x + 2, y + 3,
      "Ctrl+S Save   |   Arrows Move   |   Enter New Line",
      C.editorMuted, editorBg)

    local lines = splitLines(s.text)
    local bodyH = math.max(1, h - 7)
    local currentLine, currentCol = editorCursorPosition(s.text, s.cursor)

    if currentLine <= s.scroll then
      s.scroll = currentLine - 1
    end

    if currentLine > s.scroll + bodyH then
      s.scroll = currentLine - bodyH
    end

    -- Comfortable document text
    for i = 1, bodyH do
      local line = lines[s.scroll + i]
      if line then
        put(x + 2, y + 4 + i - 1,
          textSub(line, 1, w - 5),
          C.editorText, editorBg)
      end
    end

    -- Cursor
    if active and currentLine > s.scroll
      and currentLine <= s.scroll + bodyH
      and math.floor(computer.uptime() * 2) % 2 == 0 then

      local cx = math.min(x + w - 3, x + 2 + currentCol)

      put(cx, y + 4 + currentLine - s.scroll - 1,
        "|", C.accent, editorBg)
    end

    -- Status bar
    rect(x + 1, y + h - 2, w - 2, 1, C.panel)

    put(x + 2, y + h - 2,
      s.dirty and "* Unsaved changes" or "Saved",
      s.dirty and C.accent or C.editorMuted,
      C.panel)

    put(x + w - 17, y + h - 2,
      "Ln " .. tostring(currentLine),
      C.editorMuted, C.panel)
  elseif win.app == "picture" then
    local s = win.state
    put(x + 2, y + 2, "PICTURE VIEWER: " .. tostring(s.path or ""), C.accent, C.window)
    if s.error then
      put(x + 2, y + 4, s.error, C.text, C.window)
      put(x + 2, y + 6, "Install the MineOS image library to view .pic files.", C.muted, C.window)
    elseif s.picture then
      local pic = s.picture
      local iw, ih = tonumber(pic[1]) or 0, tonumber(pic[2]) or 0
      local maxW, maxH = w - 4, h - 5
      local scale = math.max(1, math.ceil(math.max(iw / maxW, ih / maxH)))
      local drawW, drawH = math.min(maxW, math.floor(iw / scale)), math.min(maxH, math.floor(ih / scale))
      local ox, oy = x + 2 + math.floor((maxW - drawW) / 2), y + 4
      for py = 1, drawH do
        for px = 1, drawW do
          local sx, sy = (px - 1) * scale + 1, (py - 1) * scale + 1
          local idx = 3 + ((sy - 1) * iw + (sx - 1)) * 4
          local bg, fg, alpha, symbol = pic[idx], pic[idx + 1], pic[idx + 2], pic[idx + 3]
          if bg and fg and symbol and (tonumber(alpha) or 0) < 255 then
            gpu.setBackground(bg); gpu.setForeground(fg)
            gpu.set(ox + px - 1, oy + py - 1, tostring(symbol))
          end
        end
      end
    end
  elseif win.app == "terminal" then
    local s = win.state
    put(x + 2, y + 2, "Meadows Shell  |  Type help for commands", C.accent, C.window)
    local bodyH = h - 6
    local first = math.max(1, #s.history - bodyH + 1)
    for i = first, #s.history do
      put(x + 2, y + 3 + i - first, s.history[i], C.text, C.window)
    end
    local prompt = s.path .. "> " .. s.command
    put(x + 2, y + h - 2, prompt:sub(1, w - 5), C.white, C.input)
    local cursorX = math.min(x + w - 3, x + 2 + #s.path + 2 + textLen(s.command))
    if active and math.floor(computer.uptime() * 2) % 2 == 0 then put(cursorX, y + h - 2, "|", C.accent, C.input) end

  elseif win.app == "files" then
    local s = win.state

    -- Layout
    local sideW = math.min(15, math.max(12, math.floor(w * 0.25)))
    local mainX = x + sideW + 2
    local mainW = w - sideW - 3

    -- Sidebar
    rect(x + 1, y + 1, sideW, h - 2, C.panel)
    put(x + 2, y + 2, "LOCATIONS", C.accent, C.panel)

    local favs = {
      {"Home", "/home"},
      {"Desktop", "/home/desktop"},
      {"Applications", "/apps"},
      {"Programs", "/usr"},
      {"Temporary", "/tmp"},
      {"Root", "/"}
    }

    s.sidebarRows = {}

    for i = 1, #favs do
      local path = favs[i][2]
      local ok, exists = pcall(filesystem.exists, path)
      local isDir = false

      if ok and exists then
        pcall(function()
          isDir = filesystem.isDirectory(path)
        end)
      end

      if isDir then
        local row = y + 4 + #s.sidebarRows
        if row < y + h - 3 then
          local selected = s.path == path

          if selected then
            rect(x + 1, row, sideW, 1, C.select)
          end

          put(x + 2, row,
            (selected and "> " or "  ") .. favs[i][1],
            selected and C.white or C.fileText,
            selected and C.select or C.panel)

          s.sidebarRows[#s.sidebarRows + 1] = {
            x = x + 1,
            y = row,
            w = sideW,
            path = path,
            enabled = true
          }
        end
      end
    end

    -- Navigation and address bar
    rect(mainX, y + 1, mainW, 3, C.window)

    put(mainX + 1, y + 2, "<", C.accent, C.window)
    put(mainX + 4, y + 2, ">", C.accent, C.window)
    put(mainX + 7, y + 2, "^", C.accent, C.window)

    put(mainX + 10, y + 2, "LOCATION", C.editorMuted, C.window)
    put(mainX + 20, y + 2,
      textSub(s.path, 1, math.max(1, mainW - 22)),
      C.accent, C.window)

    s.nav = {
      back = {x = mainX + 1, y = y + 2},
      forward = {x = mainX + 4, y = y + 2},
      up = {x = mainX + 7, y = y + 2}
    }

    -- Clean two-row toolbar
    local toolbarRows = {
      {
        {"New Folder", 11},
        {"New File", 10},
        {"Open", 6},
        {"Rename", 8}
      },
      {
        {"Copy", 6},
        {"Cut", 5},
        {"Paste", 7},
        {"Delete", 8},
        {s.gridMode and "List View" or "Grid View", 11}
      }
    }

    s.buttons = {}

    for rowIndex = 1, #toolbarRows do
      local bx = mainX
      local by = y + 4 + (rowIndex - 1) * 2

      for i = 1, #toolbarRows[rowIndex] do
        local label = toolbarRows[rowIndex][i][1]
        local width = toolbarRows[rowIndex][i][2]

        button(bx, by, width, label, false)

        s.buttons[#s.buttons + 1] = {
          label = label,
          x = bx,
          y = by,
          w = width
        }

        bx = bx + width + 1
      end
    end

    -- File list header
    local listY = y + 8
    s.listY = listY

    rect(mainX - 1, listY - 1, mainW, 1, C.panel2)

    put(mainX, listY - 1, "NAME", C.accent, C.panel2)
    put(mainX + mainW - 6, listY - 1, "TYPE", C.accent, C.panel2)

    -- Directory contents
    local entries, listError = listDirectory(s.path)
    s.entries = entries

    local visible = math.max(1, y + h - 3 - listY)
    s.visible = visible
    s.gridCells = {}

    if s.gridMode then
      local columns = math.max(1, math.floor(mainW / 16))
      local rows = math.max(1, math.floor(visible / 2))
      local capacity = columns * rows
      local cellW = math.floor(mainW / columns)

      for i = 1, math.min(capacity, #entries - s.scroll) do
        local index = i + s.scroll
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)

        local cx = mainX + col * cellW
        local cy = listY + row * 2
        local entry = entries[index]
        local full = pathJoin(s.path, entry)

        local folder = false
        pcall(function()
          folder = filesystem.isDirectory(full)
        end)

        local selected = s.selected == entry
        local cellWidth = cellW - 1

        if selected then
          rect(cx - 1, cy, cellWidth, 2, C.select)
        end

        put(cx, cy,
          folder and "[DIR]" or "[FILE]",
          C.accent,
          selected and C.select or C.window)

        put(cx, cy + 1,
          textSub(entry, 1, math.max(1, cellWidth - 1)),
          C.fileText,
          selected and C.select or C.window)

        s.gridCells[#s.gridCells + 1] = {
          x = cx - 1,
          y = cy,
          w = cellWidth,
          h = 2,
          name = entry
        }
      end

    else
      -- Clean, readable file rows
      for i = 1, visible do
        local index = i + s.scroll
        local entry = entries[index]

        if entry then
          local full = pathJoin(s.path, entry)

          local folder = false
          pcall(function()
            folder = filesystem.isDirectory(full)
          end)

          local row = listY + i - 1
          local selected = s.selected == entry

          if selected then
            rect(mainX - 1, row, mainW, 1, C.select)
          end

          local displayName = (folder and "> " or "  ") .. entry

          put(mainX, row,
            textSub(displayName, 1, math.max(1, mainW - 8)),
            selected and C.white or C.fileText,
            selected and C.select or C.window)

          put(mainX + mainW - 6, row,
            folder and "DIR" or "FILE",
            folder and C.accent or C.editorMuted,
            selected and C.select or C.window)
        end
      end
    end

    -- Empty directory / error state
    if #entries == 0 then
      put(mainX + 1, listY + 1,
        listError and "Unable to open this location." or "This folder is empty.",
        listError and C.close or C.editorMuted,
        C.window)

      if listError then
        put(mainX + 1, listY + 2,
          tostring(listError),
          C.editorMuted,
          C.window)
      end
    end

    -- Bottom information bar
    rect(mainX - 1, y + h - 2, mainW, 1, C.panel)

    local info = s.selected and
      ("Selected: " .. s.selected) or
      (tostring(#entries) .. " items")

    put(mainX, y + h - 2,
      textSub(info, 1, mainW - 2),
      C.editorMuted,
      C.panel)
  elseif win.app == "settings" then
    put(x + 2, y + 2, "PERSONALIZATION", C.accent, C.window)
    for i = 1, #wallpapers do
      local row = y + 4 + (i - 1) * 2
      button(x + 2, row, 24, wallpapers[i].name .. (config.wallpaper == i and " *" or ""), config.wallpaper == i)
    end
    put(x + 2, y + 14, "SYSTEM", C.accent, C.window)
    put(x + 2, y + 16, "Computer: " .. config.computerName, C.text, C.window)
    put(x + 2, y + 17, "User: " .. config.username, C.text, C.window)
    put(x + 2, y + 18, "Storage: " .. tostring(selectedDisk.label), C.text, C.window)
  elseif win.app == "monitor" then
    local total, used = 0, 0
    if filesystem.spaceTotal then pcall(function() total = filesystem.spaceTotal() or 0 end) end
    if filesystem.spaceUsed then pcall(function() used = filesystem.spaceUsed() or 0 end) end
    put(x + 2, y + 2, "SYSTEM MONITOR", C.accent, C.window)
    put(x + 2, y + 4, "Uptime: " .. math.floor(computer.uptime()) .. " seconds", C.text, C.window)
    put(x + 2, y + 6, "Computer: " .. config.computerName, C.text, C.window)
    put(x + 2, y + 8, "CPU architecture: " .. tostring(computer.getArchitecture and computer.getArchitecture() or "Unknown"), C.text, C.window)
    put(x + 2, y + 10, "Memory free: " .. tostring(computer.freeMemory()) .. " bytes", C.text, C.window)
    put(x + 2, y + 12, "Memory total: " .. tostring(computer.totalMemory()) .. " bytes", C.text, C.window)
    put(x + 2, y + 14, "Disk used: " .. tostring(used) .. " / " .. tostring(total), C.text, C.window)
    put(x + 2, y + 16, "Refresh by clicking inside this window.", C.muted, C.window)
  elseif win.app == "clock" then
    centerInWindow(x, y + 3, w, clockText(), C.accent, C.window)
    centerInWindow(x, y + 5, w, dateText() .. "  " .. utcLabel(), C.text, C.window)
    put(x + 2, y + 8, "Change date: set the Meadows display calendar", C.muted, C.window)
    button(x + 2, y + 10, 18, "Set Date", false)
    button(x + 22, y + 10, 18, "Set Time", false)
    button(x + 2, y + 12, w - 4, "Set UTC Offset / World Time", false)
    put(x + 2, y + 13, "Virtual clock; hardware time unchanged.", C.muted, C.window)
  elseif win.app == "about" then
    centerInWindow(x, y + 4, w, "MEADOWS OS 3.0", C.accent, C.window)
    centerInWindow(x, y + 6, w, "Forest Edition", C.white, C.window)
    centerInWindow(x, y + 8, w, "A desktop for OpenComputers.", C.text, C.window)
    centerInWindow(x, y + 10, w, "Storage | Windows | Apps", C.muted, C.window)
    centerInWindow(x, y + 12, w, "Thank you for using Meadows!", C.accent, C.window)
  end
end

local function drawStartMenu()
  local mw, mh = math.min(38, W - 4), math.min(14, H - 4)
  local x, y = math.max(1, math.floor((W - mw) / 2)), math.max(1, H - mh - 2)
  rect(x, y, mw, mh, C.window)
  rect(x, y, mw, 1, C.title)
  put(x + 2, y, "MEADOWS 3.0", C.white, C.title)
  local entries = {
    {"File Explorer", "files"}, {"Notes", "notes"}, {"Terminal", "terminal"},
    {"Settings", "settings"}, {"System Monitor", "monitor"},
    {"Calendar & Clock", "clock"}, {"About Meadows", "about"},
    {"Log Out", "logout"}, {"Restart", "restart"}, {"Shut Down", "shutdown"}
  }
  for i = 1, #entries do
    local row = y + 2 + (i - 1)
    if row < y + mh then button(x + 1, row, mw - 2, entries[i][1], false) end
  end
  return x, y, mw, mh, entries
end

-- ------------------------- Terminal command processor -------------------------
local function terminalCommand(win, command)
  local s = win.state
  local args = {}
  for word in tostring(command or ""):gmatch("%S+") do args[#args + 1] = word end
  local cmd = args[1]
  if not cmd then return end
  local function out(v) s.history[#s.history + 1] = tostring(v) end
  if cmd == "help" then
    out("help clear ls pwd cd mkdir touch cat rm whoami hostname version date reboot shutdown")
  elseif cmd == "clear" then s.history = {}
  elseif cmd == "pwd" then out(s.path)
  elseif cmd == "whoami" then out(config.username)
  elseif cmd == "hostname" then out(config.computerName)
  elseif cmd == "version" then out("Meadows OS " .. VERSION)
  elseif cmd == "date" then out(dateText() .. " " .. clockText())
  elseif cmd == "ls" then
    local entries = listDirectory(s.path)
    if #entries == 0 then out("(empty)") end
    for i = 1, #entries do out(entries[i]) end
  elseif cmd == "cd" then
    local target = args[2] or "/"
    if target == ".." then s.path = parentPath(s.path)
    else
      if target:sub(1, 1) ~= "/" then target = pathJoin(s.path, target) end
      target = normalizePath(target)
      if filesystem.exists(target) and filesystem.isDirectory(target) then s.path = target else out("Directory not found.") end
    end
  elseif cmd == "mkdir" or cmd == "touch" then
    local name = safeName(args[2])
    if not name then out("Usage: " .. cmd .. " name")
    else
      local target = pathJoin(s.path, name)
      if filesystem.exists(target) then out("Already exists.")
      elseif cmd == "mkdir" then
        local ok, result = pcall(filesystem.makeDirectory, target)
        out(ok and result ~= false and filesystem.exists(target) and filesystem.isDirectory(target) and "Directory created." or "Could not create directory.")
      else
        local ok = writeFile(target, "")
        out(ok and "File created." or "Could not create file.")
      end
    end
  elseif cmd == "cat" then
    local name = args[2]
    if not name then out("Usage: cat filename")
    else
      local data = readFile(normalizePath(pathJoin(s.path, name)))
      if data == nil then out("Could not read file.")
      else for line in (data .. "\n"):gmatch("(.-)\n") do out(line) end end
    end
  elseif cmd == "rm" then
    local name = args[2]
    if not name then out("Usage: rm filename")
    else
      local target = normalizePath(pathJoin(s.path, name))
      if isProtectedPath(target) then out("Protected system path.")
      else
        local ok, err = deletePath(target)
        out(ok and "Deleted." or tostring(err))
      end
    end
  elseif cmd == "reboot" then
    computer.shutdown(true)
  elseif cmd == "shutdown" then
    computer.shutdown()
  else
    out("Unknown command: " .. tostring(cmd))
    out("Type help for commands.")
  end
  while #s.history > 300 do table.remove(s.history, 1) end
end

-- ------------------------- Application input handling -------------------------
local function insertText(s, ch, field)
  local value = s[field] or ""
  local cursor = s.cursor or (textLen(value) + 1)
  local left = textSub(value, 1, cursor - 1)
  local right = textSub(value, cursor, -1)
  s[field] = left .. ch .. right
  s.cursor = cursor + textLen(ch)
end

local function moveEditorCursor(s, direction)
  local value, cursor = s.text or "", s.cursor or 1
  local line, col = editorCursorPosition(value, cursor)
  local lines = splitLines(value)
  if direction == "left" then cursor = math.max(1, cursor - 1)
  elseif direction == "right" then cursor = math.min(textLen(value) + 1, cursor + 1)
  elseif direction == "home" then cursor = cursor - col
  elseif direction == "end" then cursor = cursor + (textLen(lines[line] or "") - col)
  elseif direction == "up" or direction == "down" then
    local targetLine = clamp(line + (direction == "up" and -1 or 1), 1, #lines)
    local targetCol = math.min(col, textLen(lines[targetLine] or ""))
    local n = 1
    for i = 1, targetLine - 1 do n = n + textLen(lines[i]) + 1 end
    cursor = n + targetCol
  end
  s.cursor = cursor
end

local function editTextKey(win, char, code, ctrl)
  local s = win.state
  if char == 19 or (ctrl and code == 31) then
    if win.app == "notes" then
      if saveNotes(s.text) then s.dirty = false end
    else saveDocument(win) end
    return
  end
  if code == 203 then moveEditorCursor(s, "left")
  elseif code == 205 then moveEditorCursor(s, "right")
  elseif code == 200 then moveEditorCursor(s, "up")
  elseif code == 208 then moveEditorCursor(s, "down")
  elseif code == 199 then moveEditorCursor(s, "home")
  elseif code == 207 then moveEditorCursor(s, "end")
  elseif code == 14 then
    if s.cursor > 1 then
      local left = textSub(s.text, 1, s.cursor - 2)
      local right = textSub(s.text, s.cursor, -1)
      s.text = left .. right; s.cursor = s.cursor - 1
    end
  elseif code == 211 then
    local left = textSub(s.text, 1, s.cursor - 1)
    local right = textSub(s.text, s.cursor + 1, -1)
    s.text = left .. right
  elseif code == 28 then
    insertText(s, "\n", "text")
  else
    local ch = charFromCode(char)
    if ch ~= "" and textLen(s.text) < 24000 then insertText(s, ch, "text") end
  end
  s.dirty = true
  if win.app == "notes" then
    if saveNotes(s.text) then s.dirty = false end
  end
  -- Text files are saved with Ctrl+S or when their editor window is closed.
  -- Avoid writing to disk on every keystroke; this caused visible lag on OC drives.
end

local explorerNavigate
local function handleWindowKey(win, char, code, ctrl, alt)
  local s = win.state
  if alt and code == 62 then
    if win.app == "editor" and s.dirty then saveDocument(win) end
    closeWindow(win.id); return
  end -- Alt+F4
  if code == 62 then
    if win.app == "editor" and s.dirty then saveDocument(win) end
    closeWindow(win.id); return
  end -- F4 fallback on keyboards without modifier state
  if code == 1 then
    if win.app == "editor" and s.dirty then saveDocument(win) end
    closeWindow(win.id)
    return
  end
  if win.app == "notes" or win.app == "editor" then
    editTextKey(win, char, code, ctrl)
  elseif win.app == "terminal" then
    if code == 14 then
      s.command = backspace(s.command); s.cursor = textLen(s.command) + 1
    elseif code == 28 then
      local cmd = s.command
      s.history[#s.history + 1] = s.path .. "> " .. cmd
      s.command = ""
      terminalCommand(win, cmd)
    else
      local ch = charFromCode(char)
      if ch ~= "" and textLen(s.command) < 160 then
        s.command = s.command .. ch; s.cursor = textLen(s.command) + 1
      end
    end
  elseif win.app == "files" then
    -- OpenComputers reports Ctrl-letter combinations as control character codes.
    if char == 3 or char == 24 then
      if s.selected then s.clipboard = pathJoin(s.path, s.selected); s.clipMode = (char == 3 and "Copy" or "Cut") end
    elseif char == 22 then
      if s.clipboard then
        local target = pathJoin(s.path, baseName(s.clipboard))
        if not filesystem.exists(target) then
          local copied = copyPath(s.clipboard, target)
          if copied and s.clipMode == "Cut" then
            local removed = deletePath(s.clipboard)
            if removed then s.clipboard = nil; s.clipMode = nil end
          end
        end
      end
    elseif code == 14 then
      explorerNavigate(s, parentPath(s.path))
    elseif code == 200 then s.scroll = math.max(0, s.scroll - 1)
    elseif code == 208 then s.scroll = math.min(math.max(0, #(s.entries or {}) - (s.visible or 1)), s.scroll + 1)
    elseif code == 28 and s.selected then
      local target = pathJoin(s.path, s.selected)
      if filesystem.isDirectory(target) then explorerNavigate(s, target)
      else
        openFileInEditor(target)
      end
    end
  end
end

explorerNavigate = function(state, path, addHistory)
  path = normalizePath(path)
  if not filesystem.exists(path) or not filesystem.isDirectory(path) then return false end
  state.path, state.selected, state.scroll = path, nil, 0
  if addHistory ~= false then
    local history = state.history or {"/"}
    local index = state.historyIndex or #history
    for i = #history, index + 1, -1 do history[i] = nil end
    if history[#history] ~= path then history[#history + 1] = path end
    state.history, state.historyIndex = history, #history
  end
  return true
end

local function appTouch(win, tx, ty)
  local x, y, w, h = windowRect(win)
  local s = win.state
  if win.app == "notes" or win.app == "editor" then
    if hit(tx, ty, x + 1, y + 2, w - 2, h - 4) then
      focused = win.id
      if ty >= y + 4 and ty < y + h - 2 then
        local lines = splitLines(s.text)
        local targetLine = clamp(ty - (y + 4) + 1 + s.scroll, 1, #lines)
        local targetCol = clamp(tx - (x + 2), 0, textLen(lines[targetLine] or ""))
        local cursor = 1
        for i = 1, targetLine - 1 do cursor = cursor + textLen(lines[i]) + 1 end
        s.cursor = cursor + targetCol
      end
    end
  elseif win.app == "terminal" then
    if hit(tx, ty, x + 1, y + h - 2, w - 2, 1) then focused = win.id end
  elseif win.app == "files" then
    for i = 1, #(s.sidebarRows or {}) do
      local item = s.sidebarRows[i]
      if item.enabled and hit(tx, ty, item.x, item.y, item.w, 1) then
        if explorerNavigate(s, item.path) then return end
      end
    end
    if s.nav then
      if hit(tx, ty, s.nav.back.x, s.nav.back.y, 1, 1) then
        if (s.historyIndex or 1) > 1 then s.historyIndex = s.historyIndex - 1; explorerNavigate(s, s.history[s.historyIndex], false) end
        return
      elseif hit(tx, ty, s.nav.forward.x, s.nav.forward.y, 1, 1) then
        if (s.historyIndex or 1) < #(s.history or {}) then s.historyIndex = s.historyIndex + 1; explorerNavigate(s, s.history[s.historyIndex], false) end
        return
      elseif hit(tx, ty, s.nav.up.x, s.nav.up.y, 1, 1) then
        explorerNavigate(s, parentPath(s.path)); return
      end
    end
    for i = 1, #(s.buttons or {}) do
      local b = s.buttons[i]
      if hit(tx, ty, b.x, b.y, b.w, 1) then
        local action = b.label
        if action == "Up" then explorerNavigate(s, parentPath(s.path))
        elseif action == "Grid View" or action == "List View" then s.gridMode = not s.gridMode
        elseif action == "New Folder" then
          local entered = inputDialog("NEW FOLDER", "Folder name:", "New Folder")
          local name = safeName(entered)
          if entered ~= nil then
            if not name then messageDialog("ERROR", "Enter a valid folder name.")
            else
              local target = pathJoin(s.path, name)
              if filesystem.exists(target) then messageDialog("ERROR", "That item already exists.")
              else
                local ok, result, reason = pcall(filesystem.makeDirectory, target)
                local exists, isDir = false, false
                pcall(function() exists = filesystem.exists(target); isDir = exists and filesystem.isDirectory(target) end)
                if not ok or result == false or not exists or not isDir then
                  messageDialog("FOLDER ERROR", "Could not create: " .. tostring(reason or result or "storage rejected the request"))
                else
                  s.selected = name
                  s.scroll = 0
                end
              end
            end
          end
        elseif action == "New File" then
          local entered = inputDialog("NEW FILE", "File name (press Enter to confirm):", "New File.txt")
          if entered ~= nil then
            local name = safeName(entered)
            if not name then
              messageDialog("FILE NAME", "Enter a valid file name.")
            else
              local target = normalizePath(pathJoin(s.path, name))
              local existsOK, exists = pcall(filesystem.exists, target)
              if not existsOK then
                messageDialog("STORAGE ERROR", "Could not check the destination: " .. tostring(exists))
              elseif exists then
                messageDialog("FILE EXISTS", "That item already exists.")
              else
                local created, createError = writeFile(target, "")
                if not created then
                  messageDialog("FILE ERROR", tostring(createError or "Could not create file."))
                elseif not filesystem.exists(target) then
                  messageDialog("FILE ERROR", "Storage did not create the file.")
                else
                  s.selected = name
                  s.scroll = 0
                  openFileInEditor(target)
                end
              end
            end
          end
        elseif action == "Open" and s.selected then
          local target = pathJoin(s.path, s.selected)
          if filesystem.isDirectory(target) then explorerNavigate(s, target)
          else
            openFileInEditor(target)
          end
        elseif action == "Rename" and s.selected then
          local newName = safeName(inputDialog("RENAME", "New name:", s.selected))
          if newName then
            local old = pathJoin(s.path, s.selected)
            local new = pathJoin(s.path, newName)
            if not isProtectedPath(old) and not filesystem.exists(new) then
              local ok, result = pcall(filesystem.rename, old, new)
              if ok and result ~= false then s.selected = newName else messageDialog("ERROR", "Rename failed.") end
            else messageDialog("ERROR", "Invalid destination.") end
          end
        elseif (action == "Copy" or action == "Cut") and s.selected then
          s.clipboard = pathJoin(s.path, s.selected); s.clipMode = action
        elseif action == "Paste" and s.clipboard then
          local target = pathJoin(s.path, baseName(s.clipboard))
          if filesystem.exists(target) then messageDialog("ERROR", "Destination already exists.")
          else
            local ok, err = copyPath(s.clipboard, target)
            if ok and s.clipMode == "Cut" then
              local removed, removeErr = deletePath(s.clipboard)
              if removed then s.clipboard = nil; s.clipMode = nil else messageDialog("MOVE ERROR", tostring(removeErr)) end
            elseif not ok then messageDialog("ERROR", tostring(err)) end
          end
        elseif action == "Delete" and s.selected then
          if confirmDialog("DELETE ITEM", "Delete " .. s.selected .. "?") then
            local ok, err = deletePath(pathJoin(s.path, s.selected))
            if ok then s.selected = nil else messageDialog("ERROR", tostring(err)) end
          end
        end
        return
      end
    end
    if s.gridMode then
      for i = 1, #(s.gridCells or {}) do
        local cell = s.gridCells[i]
        if hit(tx, ty, cell.x, cell.y, cell.w, cell.h) then
          local entry = cell.name
          if s.selected == entry then
            local target = pathJoin(s.path, entry)
            if filesystem.isDirectory(target) then explorerNavigate(s, target) else openFileInEditor(target) end
          else s.selected = entry end
          return
        end
      end
    end
    if not s.gridMode and s.listY and ty >= s.listY and ty < s.listY + (s.visible or 0) then
      local index = ty - s.listY + 1 + s.scroll
      local entry = s.entries[index]
      if entry then
        if s.selected == entry then
          local target = pathJoin(s.path, entry)
          if filesystem.isDirectory(target) then explorerNavigate(s, target)
          else
            openFileInEditor(target)
          end
        else s.selected = entry end
      end
    end
  elseif win.app == "clock" then
    if hit(tx, ty, x + 2, y + 10, 18, 1) then
      local dateValue = inputDialog("SET DATE", "Enter date YYYY-MM-DD:", dateText())
      local yy, mm, dd
      if dateValue then yy, mm, dd = dateValue:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$") end
      if yy then
        local old = os.time()
        local t = {year=tonumber(yy), month=tonumber(mm), day=tonumber(dd), hour=0, min=0, sec=0}
        local ok, target = pcall(os.time, t)
        if ok and target then
          local utc = os.difftime(os.time(os.date("!*t", target)), target)
          config.clockShift = target - utc - (tonumber(config.utcOffset) or 0) * 60 - old
          saveConfig()
        else messageDialog("DATE ERROR", "Invalid date.") end
      else messageDialog("DATE ERROR", "Use YYYY-MM-DD.") end
    elseif hit(tx, ty, x + 22, y + 10, 18, 1) then
      local timeValue = inputDialog("SET TIME", "Enter time HH:MM:SS:", clockText())
      local hh, mi, ss
      if timeValue then hh, mi, ss = timeValue:match("^(%d%d):(%d%d):(%d%d)$") end
      if hh and tonumber(hh) < 24 and tonumber(mi) < 60 and tonumber(ss) < 60 then
        local current = os.date("!*t", virtualTimestamp())
        local targetTable = {year=current.year, month=current.month, day=current.day, hour=tonumber(hh), min=tonumber(mi), sec=tonumber(ss)}
        local target = os.time(targetTable)
        local utc = os.difftime(os.time(os.date("!*t", target)), target)
        config.clockShift = target - utc - (tonumber(config.utcOffset) or 0) * 60 - os.time()
        saveConfig()
      else messageDialog("TIME ERROR", "Use a valid HH:MM:SS time.") end
    elseif hit(tx, ty, x + 2, y + 12, w - 4, 1) then
      local zone = inputDialog("UTC OFFSET", "Enter offset minutes (e.g. 330 for UTC+5:30):", tostring(config.utcOffset or 0))
      local n = tonumber(zone)
      if n and n >= -720 and n <= 840 then
        config.utcOffset = math.floor(n)
        saveConfig()
      else messageDialog("TIME ZONE", "Offset must be -720 to +840 minutes.") end
    end
  elseif win.app == "settings" then
    for i = 1, #wallpapers do
      if hit(tx, ty, x + 2, y + 4 + (i - 1) * 2, 24, 1) then
        config.wallpaper = i; saveConfig()
      end
    end
  end
end

-- ------------------------- Window drawing and interaction -------------------------
local function drawAll()
  drawDesktop()
  for i = 1, #windows do drawWindow(windows[i], windows[i].id == focused) end
  if startOpen then drawStartMenu() end
  if contextMenu then
    rect(contextMenu.x, contextMenu.y, contextMenu.w, contextMenu.h, C.window)
    rect(contextMenu.x, contextMenu.y, contextMenu.w, 1, C.title)
    put(contextMenu.x + 1, contextMenu.y, "DESKTOP", C.white, C.title)
    button(contextMenu.x + 1, contextMenu.y + 2, contextMenu.w - 2, "Refresh", false)
    button(contextMenu.x + 1, contextMenu.y + 4, contextMenu.w - 2, "New Folder", false)
    button(contextMenu.x + 1, contextMenu.y + 6, contextMenu.w - 2, "Settings", false)
  end
end

local function taskbarAction(x, y)
  if y ~= H - 2 then return false end
  local names = {"Start", "Files", "Notes", "Terminal"}
  local total = 0
  for i = 1, #names do total = total + #names[i] + 3 end
  local bx = math.max(2, math.floor((W - total) / 2))
  for i = 1, #names do
    local ww = #names[i] + 2
    if hit(x, y, bx, y, ww, 1) then
      if i == 1 then startOpen = not startOpen else openWindow(names[i]:lower()) end
      return true
    end
    bx = bx + ww + 1
  end
  -- minimized windows are represented by taskbar buttons in the right half
  return false
end

local function handleWindowTouch(tx, ty)
  for i = #windows, 1, -1 do
    local win = windows[i]
    if not win.minimized then
      local x, y, w, h = windowRect(win)
      if hit(tx, ty, x, y, w, h) then
        focusWindow(win.id)
        x, y, w, h = windowRect(win)
        local closeX, maxX, minX = x + w - 4, x + w - 8, x + w - 12
        if ty == y then
          if hit(tx, ty, closeX, y, 3, 1) then
            if (win.app == "notes" or win.app == "editor") and win.state.dirty then
              if confirmDialog("UNSAVED CHANGES", "Save changes before closing?") then
                if win.app == "notes" then saveNotes(win.state.text) else saveDocument(win) end
              end
            end
            closeWindow(win.id); return true
          elseif hit(tx, ty, maxX, y, 3, 1) then
            if win.maximized then
              win.maximized = false
              if win.restore then win.x, win.y, win.w, win.h = win.restore.x, win.restore.y, win.restore.w, win.restore.h end
            else
              win.restore = {x = win.x, y = win.y, w = win.w, h = win.h}
              win.maximized = true
            end
            return true
          elseif hit(tx, ty, minX, y, 3, 1) then win.minimized = true; return true
          else
            win.drag = {dx = tx - x, dy = ty - y}
            return true
          end
        end
        if not win.maximized and tx >= x + w - 2 and ty >= y + h - 2 then
          win.resize = true
          return true
        end
        appTouch(win, tx, ty)
        return true
      end
    end
  end
  return false
end

local function restoreMinimizedAtTaskbar(x, y)
  if y ~= H - 2 then return false end
  local px = math.floor(W / 2) + 12
  for i = 1, #windows do
    local win = windows[i]
    if win.minimized then
      if hit(x, y, px, y, 9, 1) then win.minimized = false; focusWindow(win.id); return true end
      px = px + 10
    end
  end
  return false
end

-- ------------------------- Main desktop loop -------------------------
local function desktopLoop()
  drawAll()

  while true do
    local sig, addr, ch, code, player = computer.pullSignal(0.15)
    if sig == "touch" then
      local tx, ty = tonumber(ch), tonumber(code)
      if tx and ty then
        if contextMenu then
          if hit(tx, ty, contextMenu.x + 1, contextMenu.y + 2, contextMenu.w - 2, 1) then
            contextMenu = nil
          elseif hit(tx, ty, contextMenu.x + 1, contextMenu.y + 4, contextMenu.w - 2, 1) then
            local name = safeName(inputDialog("NEW FOLDER", "Create folder on root:", "New Folder"))
            if name then pcall(filesystem.makeDirectory, "/" .. name) end
            contextMenu = nil
          elseif hit(tx, ty, contextMenu.x + 1, contextMenu.y + 6, contextMenu.w - 2, 1) then
            openWindow("settings"); contextMenu = nil
          else contextMenu = nil end
        elseif startOpen then
          local mx, my, mw, mh, entries = drawStartMenu()
          if hit(tx, ty, mx, my, mw, mh) then
            for i = 1, #entries do
              local row = my + 2 + (i - 1)
              if hit(tx, ty, mx + 1, row, mw - 2, 1) then
                local app = entries[i][2]
                startOpen = false
                if app == "shutdown" then
                  if confirmDialog("SHUT DOWN", "Turn off this computer?") then computer.shutdown() end
                elseif app == "restart" then
                  if confirmDialog("RESTART", "Restart this computer?") then computer.shutdown(true) end
                elseif app == "logout" then
                  if confirmDialog("LOG OUT", "Return to the sign-in screen?") then
                    for wi = 1, #windows do
                      local pending = windows[wi]
                      if pending.state and pending.state.dirty then
                        if pending.app == "notes" then saveNotes(pending.state.text)
                        elseif pending.app == "editor" then saveDocument(pending) end
                      end
                    end
                    windows = {}; focused = nil
                    currentAccount = loginScreen()
                    if not currentAccount then computer.shutdown() end
                    config.username = currentAccount.username
                    config.displayName = currentAccount.displayName
                    saveConfig()
                  end
                else openWindow(app) end
                break
              end
            end
          else startOpen = false end
        elseif taskbarAction(tx, ty) then
          -- handled
        elseif restoreMinimizedAtTaskbar(tx, ty) then
          -- handled
        elseif handleWindowTouch(tx, ty) then
          -- handled
        elseif ty >= 3 and ty < H - 3 then
          local iconIndex = math.floor((ty - 4) / 3) + 1
          local icon = desktopIcons[iconIndex]
          if icon and tx >= 2 and tx <= 18 then
            openWindow(icon.app)
          end
        else
          -- Right-click is button 2 in OpenComputers touch events.
          if player == 2 then contextMenu = {x = clamp(tx, 1, W - 18), y = clamp(ty, 1, H - 9), w = 18, h = 8} end
        end
      end
    elseif sig == "drag" then
      local tx, ty = tonumber(ch), tonumber(code)
      if tx and ty and focused then
        local _, win = findWindow(focused)
        if win and win.drag and not win.maximized then
          win.x = clamp(tx - win.drag.dx, 1, W - win.w + 1)
          win.y = clamp(ty - win.drag.dy, 2, H - win.h - 2)
        elseif win and win.resize and not win.maximized then
          win.w = clamp(tx - win.x + 1, win.minW, W - win.x + 1)
          win.h = clamp(ty - win.y + 1, win.minH, H - win.y - 2)
        end
      end
    elseif sig == "drop" then
      if focused then
        local _, win = findWindow(focused)
        if win then win.drag = nil; win.resize = nil end
      end
    elseif sig == "key_down" then
      local ctrl = false
      local alt = false

      if code == 1 and startOpen then
        startOpen = false
      elseif focused then
        local _, win = findWindow(focused)
        if win then
          handleWindowKey(win, ch, code, ctrl, alt)
        end
      end
    end

    if sig then
      drawAll()
    end
  end
end

-- ------------------------- Final boot -------------------------
clear(C.bg)
center(math.floor(H / 2) - 1, "MEADOWS OS 3.0", C.accent)
center(math.floor(H / 2) + 1, "Preparing Forest Desktop...", C.white)
computer.pullSignal(0.45)
desktopLoop()
