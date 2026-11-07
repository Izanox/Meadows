-- =========================================================
-- CHANGE 5.0
-- MEADOWS OS 2.0 - FOREST EDITION
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
  error("Meadows 2.0: GPU or screen not found.")
end

local gpu = component.proxy(gpuAddress)
local okBind, bindErr = pcall(gpu.bind, screenAddress)
if not okBind then error("Meadows 2.0: Could not bind screen: " .. tostring(bindErr)) end

local W, H = gpu.getResolution()
if W < 50 or H < 20 then
  error("Meadows 2.0 requires a screen of at least 50x20.")
end
pcall(gpu.setDepth, 8)

local VERSION = "2.0"
local OS_NAME = "Meadows"
local MAX_WINDOWS = 2
local C = {
  bg = 0x08130E, desktop = 0x10271B, desktop2 = 0x183A28,
  panel = 0x14251C, panel2 = 0x20382B, window = 0x17271E,
  title = 0x294B38, accent = 0x72D69A, accent2 = 0x285C3D,
  text = 0xE8F5EC, muted = 0x9BB5A3, border = 0x42634C,
  close = 0xD94F55, white = 0xFFFFFF, black = 0x000000,
  select = 0x285C3D, input = 0x0C1911
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

local function clockText()
  if os and os.date then
    local ok, value = pcall(os.date, "%H:%M")
    if ok and value then return tostring(value) end
  end
  local t = math.floor(computer.uptime())
  return string.format("%02d:%02d", math.floor(t / 3600) % 24, math.floor(t / 60) % 60)
end

local function dateText()
  if os and os.date then
    local ok, value = pcall(os.date, "%d/%m/%Y")
    if ok and value then return tostring(value) end
  end
  return "OpenComputers"
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
  data = tostring(data or "")
  local ok, handle = pcall(fs.open, path, "w")
  if not ok or not handle then return false, "Could not open file for writing." end
  local writeOK, result = pcall(fs.write, handle, data)
  local closeOK, closeResult = pcall(fs.close, handle)
  if not writeOK or result == false or not closeOK or closeResult == false then
    return false, "Could not write file."
  end
  if fsRead(fs, path) ~= data then return false, "Storage verification failed." end
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
if #drives == 0 then error("Meadows 2.0: No writable filesystem found.") end

local function chooseStorage()
  local choice, scroll = 1, 0
  while true do
    clear(C.bg)
    center(2, "MEADOWS 2.0 INSTALLATION", C.accent)
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
local config = {
  computerName = "Meadows-PC", wallpaper = 1, username = "",
  displayName = "", setupComplete = false, version = VERSION
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
    "setupComplete=" .. tostring(config.setupComplete),
    "version=" .. cleanValue(config.version)
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
      elseif key == "setupComplete" then config.setupComplete = value == "true"
      elseif key == "version" then config.version = value end
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
local function inputDialog(title, prompt, initial)
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
    local shown = value
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
    center(3, "WELCOME TO MEADOWS 2.0", C.accent)
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

local function setupWizard()
  if not termsScreen() then error("Meadows setup was declined.") end
  config.computerName = cleanValue(inputDialog("COMPUTER NAME", "Name this computer:", config.computerName) or "Meadows-PC")
  local display = inputDialog("CREATE ACCOUNT", "Enter your display name:", "") or "User"
  local username = cleanValue(inputDialog("CREATE ACCOUNT", "Choose a username:", "user") or "user")
  local password = inputDialog("CREATE PASSWORD", "Enter a password (can be blank):", "") or ""
  accounts = {{username = username, displayName = cleanValue(display), passwordHash = hashPassword(password)}}
  config.username = username
  config.displayName = cleanValue(display)
  config.setupComplete = true
  config.version = VERSION
  if not saveConfig() or not saveAccounts() then error("Meadows: Could not save setup.") end
  messageDialog("SETUP COMPLETE", "Welcome to Meadows 2.0!")
end

if not config.setupComplete or #accounts == 0 then setupWizard() end

local function loginScreen()
  while true do
    clear(C.bg)
    center(3, "MEADOWS 2.0", C.accent)
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
            local pw = inputDialog("SIGN IN", "Password for " .. accounts[i].username .. ":", "")
            if pw ~= nil and verifyPassword(pw, accounts[i].passwordHash) then return accounts[i] end
            messageDialog("SIGN IN FAILED", "Incorrect password.")
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
  local ok, iterator = pcall(filesystem.list, path)
  if not ok or not iterator then return {} end
  local result = {}
  while true do
    local readOK, entry = pcall(iterator)
    if not readOK or not entry then break end
    entry = tostring(entry):gsub("/$", "")
    if entry ~= "" then result[#result + 1] = entry end
  end
  table.sort(result, function(a, b) return a:lower() < b:lower() end)
  return result
end

local function copyFile(source, destination)
  source, destination = normalizePath(source), normalizePath(destination)
  if filesystem.isDirectory(source) then return false, "Folder copy is not supported yet." end
  local data = readFile(source)
  if data == nil then return false, "Could not read source file." end
  return writeFile(destination, data)
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
  put(W - 11, H - 1, dateText():sub(1, 10), C.muted, C.panel)
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
  if app == "files" then win.title = "File Explorer"; win.state.path = "/"; win.state.selected = nil; win.state.scroll = 0; win.state.clipboard = nil; win.state.clipMode = nil
  elseif app == "notes" then win.title = "Meadows Notes"; win.state.text = loadNotes(); win.state.cursor = textLen(loadNotes()) + 1; win.state.scroll = 0; win.state.dirty = false
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
  if win.app == "notes" then
    local s = win.state
    put(x + 2, y + 2, "NOTES  |  Ctrl+S to save", C.accent, C.window)
    local lines = {}
    for line in (s.text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local bodyH = h - 6
    local start = math.max(1, s.scroll + 1)
    for i = 1, bodyH do
      local line = lines[start + i - 1]
      if line then put(x + 2, y + 3 + i - 1, line:sub(1, w - 5), C.text, C.window) end
    end
    put(x + 2, y + h - 2, s.dirty and "* Unsaved changes" or "Saved", s.dirty and C.accent or C.muted, C.window)
    if active and math.floor(computer.uptime() * 2) % 2 == 0 then
      local cursorX = math.min(x + w - 3, x + 2 + textLen(s.text))
      put(cursorX, y + h - 2, "|", C.accent, C.window)
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
    put(x + 2, y + 2, "Location: " .. s.path, C.accent, C.window)
    local tools = {"Up", "NewFolder", "NewFile", "Open", "Rename", "Copy", "Cut", "Paste", "Delete"}
    local bx = x + 2
    local by = y + 4
    s.buttons = {}
    for i = 1, #tools do
      local label = tools[i]
      local width = #label + 2
      if bx + width > x + w - 2 then bx = x + 2; by = by + 2 end
      button(bx, by, width, label, false)
      s.buttons[#s.buttons + 1] = {label = label, x = bx, y = by, w = width}
      bx = bx + width + 1
    end
    local listY = by + 2
    s.listY = listY
    put(x + 2, listY - 1, "NAME", C.accent, C.window)
    local entries = listDirectory(s.path)
    s.entries = entries
    local visible = math.max(1, y + h - 3 - listY)
    s.visible = visible
    for i = 1, visible do
      local index = i + s.scroll
      local entry = entries[index]
      if entry then
        local full = pathJoin(s.path, entry)
        local folder = filesystem.isDirectory(full)
        local row = listY + i - 1
        local selected = s.selected == entry
        if selected then rect(x + 1, row, w - 2, 1, C.select) end
        put(x + 2, row, (folder and "[DIR] " or "      ") .. entry, C.white, selected and C.select or C.window)
      end
    end
    put(x + 2, y + h - 2, s.selected and ("Selected: " .. s.selected) or "Select an item", C.muted, C.window)
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
    center(y + 5, clockText(), C.accent, C.window)
    center(y + 8, dateText(), C.text, C.window)
    center(y + 11, "System clock provided by OpenComputers.", C.muted, C.window)
  elseif win.app == "about" then
    center(y + 4, "MEADOWS OS 2.0", C.accent, C.window)
    center(y + 6, "Forest Edition", C.white, C.window)
    center(y + 8, "A desktop environment for OpenComputers.", C.text, C.window)
    center(y + 10, "Persistent storage | Window manager | Apps", C.muted, C.window)
    center(y + 12, "Thank you for using Meadows!", C.accent, C.window)
  end
end

local function drawStartMenu()
  local mw, mh = math.min(36, W - 6), math.min(17, H - 6)
  local x, y = math.floor((W - mw) / 2), H - mh - 3
  rect(x, y, mw, mh, C.window)
  rect(x, y, mw, 1, C.title)
  put(x + 2, y, "MEADOWS 2.0", C.white, C.title)
  local entries = {
    {"File Explorer", "files"}, {"Notes", "notes"}, {"Terminal", "terminal"},
    {"Settings", "settings"}, {"System Monitor", "monitor"},
    {"Calendar & Clock", "clock"}, {"About Meadows", "about"}, {"Power Off", "power"}
  }
  for i = 1, #entries do
    local row = y + 2 + (i - 1) * 2
    if row < y + mh - 1 then button(x + 2, row, mw - 4, entries[i][1], false) end
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
        out(ok and result ~= false and "Directory created." or "Could not create directory.")
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

local function handleWindowKey(win, char, code, ctrl, alt)
  local s = win.state
  if alt and code == 62 then closeWindow(win.id); return end -- Alt+F4
  if code == 62 then closeWindow(win.id); return end -- F4 fallback on keyboards without modifier state
  if code == 1 then
    closeWindow(win.id)
    return
  end
  if win.app == "notes" then
    if ctrl and (char == 19 or code == 31) then
      if saveNotes(s.text) then s.dirty = false end
    elseif code == 14 then
      s.text = backspace(s.text); s.cursor = textLen(s.text) + 1; s.dirty = true
      if saveNotes(s.text) then s.dirty = false end
    elseif code == 28 then
      s.text = s.text .. "\n"; s.cursor = textLen(s.text) + 1; s.dirty = true
      if saveNotes(s.text) then s.dirty = false end
    else
      local ch = charFromCode(char)
      if ch ~= "" and textLen(s.text) < 6000 then
        s.text = s.text .. ch; s.cursor = textLen(s.text) + 1; s.dirty = true
        if saveNotes(s.text) then s.dirty = false end
      end
    end
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
        if not filesystem.exists(target) and not filesystem.isDirectory(s.clipboard) then
          local copied = copyFile(s.clipboard, target)
          if copied and s.clipMode == "Cut" then pcall(filesystem.remove, s.clipboard); s.clipboard = nil; s.clipMode = nil end
        end
      end
    elseif code == 14 then
      s.path = parentPath(s.path); s.selected = nil; s.scroll = 0
    elseif code == 200 then s.scroll = math.max(0, s.scroll - 1)
    elseif code == 208 then s.scroll = math.min(math.max(0, #(s.entries or {}) - (s.visible or 1)), s.scroll + 1)
    elseif code == 28 and s.selected then
      local target = pathJoin(s.path, s.selected)
      if filesystem.isDirectory(target) then s.path = target; s.selected = nil; s.scroll = 0
      else
        local content = readFile(target) or ""
        messageDialog(baseName(target), content:sub(1, W * 5))
      end
    end
  end
end

local function appTouch(win, tx, ty)
  local x, y, w, h = windowRect(win)
  local s = win.state
  if win.app == "notes" then
    if hit(tx, ty, x + 1, y + 2, w - 2, h - 4) then
      -- Notes is keyboard-editable while focused; tapping the text area places focus.
      focused = win.id
    end
  elseif win.app == "terminal" then
    if hit(tx, ty, x + 1, y + h - 2, w - 2, 1) then focused = win.id end
  elseif win.app == "files" then
    for i = 1, #(s.buttons or {}) do
      local b = s.buttons[i]
      if hit(tx, ty, b.x, b.y, b.w, 1) then
        local action = b.label
        if action == "Up" then s.path = parentPath(s.path); s.selected = nil; s.scroll = 0
        elseif action == "NewFolder" then
          local name = safeName(inputDialog("NEW FOLDER", "Folder name:", "New Folder"))
          if name then
            local ok, result = pcall(filesystem.makeDirectory, pathJoin(s.path, name))
            if not ok or result == false then messageDialog("ERROR", "Could not create folder.") end
          end
        elseif action == "NewFile" then
          local name = safeName(inputDialog("NEW FILE", "File name:", "New File.txt"))
          if name then
            local target = pathJoin(s.path, name)
            if filesystem.exists(target) then messageDialog("ERROR", "That item already exists.")
            else writeFile(target, "") end
          end
        elseif action == "Open" and s.selected then
          local target = pathJoin(s.path, s.selected)
          if filesystem.isDirectory(target) then s.path = target; s.selected = nil; s.scroll = 0
          else
            local data = readFile(target) or ""
            messageDialog(baseName(target), data:sub(1, W * 5))
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
          elseif filesystem.isDirectory(s.clipboard) then messageDialog("ERROR", "Folder copy is not supported.")
          else
            local ok, err = copyFile(s.clipboard, target)
            if ok and s.clipMode == "Cut" then
              pcall(filesystem.remove, s.clipboard); s.clipboard = nil; s.clipMode = nil
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
    if s.listY and ty >= s.listY and ty < s.listY + (s.visible or 0) then
      local index = ty - s.listY + 1 + s.scroll
      local entry = s.entries[index]
      if entry then
        if s.selected == entry then
          local target = pathJoin(s.path, entry)
          if filesystem.isDirectory(target) then s.path = target; s.selected = nil; s.scroll = 0
          else
            local data = readFile(target) or ""
            messageDialog(baseName(target), data:sub(1, W * 5))
          end
        else s.selected = entry end
      end
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
            if win.app == "notes" and win.state.dirty then
              if confirmDialog("UNSAVED NOTES", "Save changes before closing?") then saveNotes(win.state.text) end
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
  while true do
    drawAll()
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
              local row = my + 2 + (i - 1) * 2
              if hit(tx, ty, mx + 2, row, mw - 4, 1) then
                local app = entries[i][2]
                startOpen = false
                if app == "power" then
                  if confirmDialog("POWER OFF", "Shut down Meadows OS?") then computer.shutdown() end
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
      if computer.getKeyboards then
        -- Modifier state is not consistently exposed by all OpenComputers versions.
        ctrl = false; alt = false
      end
      if code == 1 and startOpen then startOpen = false
      elseif focused then
        local _, win = findWindow(focused)
        if win then handleWindowKey(win, ch, code, ctrl, alt) end
      end
    end
  end
end

-- ------------------------- Final boot -------------------------
clear(C.bg)
center(math.floor(H / 2) - 1, "MEADOWS OS 2.0", C.accent)
center(math.floor(H / 2) + 1, "Preparing Forest Desktop...", C.white)
computer.pullSignal(0.45)
desktopLoop()
