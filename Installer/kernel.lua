-- =========================================================
-- CHANGE 1.0
-- MEADOWS OS 1.2 - FOREST EDITION (TOUCH UI UPDATE)
-- Native OpenComputers BIOS kernel
-- =========================================================
-- Install this file as the kernel loaded by your EEPROM.
-- The selected writable filesystem stores all user data in /.meadows.
-- Tested by static review only; test in a copied world first.

local component = component
local computer = computer
local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()

if not gpuAddress or not screenAddress then
    error("Meadows: GPU or screen not found.")
end

local gpu = component.proxy(gpuAddress)
local okBind, bindError = pcall(gpu.bind, screenAddress)
if not okBind then error("Meadows: Could not bind screen: " .. tostring(bindError)) end

local W, H = gpu.getResolution()
if W < 40 or H < 16 then error("Meadows: Screen must be at least 40x16.") end
pcall(gpu.setDepth, 8)

local VERSION = "1.2"
local OS_NAME = "Meadows"
local MAX_WINDOWS = 2
local C = {
    background = 0x0B1511, desktop = 0x102019, panel = 0x172820,
    panel2 = 0x20382B, window = 0x192B22, titlebar = 0x294B38,
    accent = 0x72D69A, accentDark = 0x285C3D, text = 0xE8F5EC,
    muted = 0x9BB5A3, close = 0xE36F70, white = 0xFFFFFF,
    border = 0x365643, selected = 0x285C3D
}

local DATA_DIR = "/.meadows"
local CONFIG_FILE = DATA_DIR .. "/system.cfg"
local ACCOUNTS_FILE = DATA_DIR .. "/accounts.db"
local NOTES_FILE = DATA_DIR .. "/notes.txt"
local STORAGE_ID_FILE = DATA_DIR .. "/storage.id"

-- ------------------------- Graphics ----------------------
local function rect(x, y, w, h, color)
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    if x < 1 then w, x = w - 1 + x, 1 end
    if y < 1 then h, y = h - 1 + y, 1 end
    if x + w - 1 > W then w = W - x + 1 end
    if y + h - 1 > H then h = H - y + 1 end
    if w <= 0 or h <= 0 then return end
    gpu.setBackground(color)
    gpu.fill(x, y, w, h, " ")
end

local function put(x, y, value, color)
    value = tostring(value or "")
    x, y = math.floor(x), math.floor(y)
    if y < 1 or y > H or x > W then return end
    if x < 1 then value, x = value:sub(2 - x), 1 end
    if x + #value - 1 > W then value = value:sub(1, W - x + 1) end
    if #value == 0 then return end
    gpu.setForeground(color or C.text)
    gpu.set(x, y, value)
end

local function center(y, value, color)
    value = tostring(value or "")
    put(math.floor((W - #value) / 2) + 1, y, value, color)
end

-- Touch-friendly controls. Labels remain readable; selection is shown by
-- changing the button surface, never by painting over the text.
local function drawButton(x, y, w, label, selected)
    rect(x, y, w, 1, selected and C.accentDark or C.panel2)
    local text = tostring(label or "")
    local tx = x + math.max(0, math.floor((w - #text) / 2))
    put(tx, y, text:sub(1, w), C.white)
end

local function hit(x, y, bx, by, bw, bh)
    return x and y and x >= bx and x < bx + bw and y >= by and y < by + bh
end

local function clockText()
    if os and os.date then
        local ok, value = pcall(os.date, "%H:%M")
        if ok and value then return tostring(value) end
    end
    return string.format("%02d:%02d", math.floor(computer.uptime() / 60) % 24, math.floor(computer.uptime()) % 60)
end

local function clear(color)
    rect(1, 1, W, H, color or C.background)
end

local function waitForKey()
    while true do
        local signal = computer.pullSignal()
        if signal == "key_down" then return end
    end
end

local function keyEvent()
    while true do
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then return char, code end
    end
end

local function bootSplash()
    local frames = {"|", "/", "-", "\\"}
    for frame = 1, 20 do
        clear(C.background)
        local logoX, logoY = math.floor(W / 2) - 4, math.floor(H / 2) - 4
        rect(logoX, logoY, 3, 2, C.accentDark)
        rect(logoX + 4, logoY, 3, 2, C.accentDark)
        rect(logoX, logoY + 3, 3, 2, C.accent)
        rect(logoX + 4, logoY + 3, 3, 2, C.accent)
        center(logoY + 6, "MEADOWS", C.white)
        center(logoY + 8, "FOREST EDITION", C.accent)
        center(H - 3, "Starting Meadows EFI " .. frames[(frame - 1) % #frames + 1], C.muted)
        center(H - 1, "VERSION " .. VERSION, C.muted)
        computer.pullSignal(0.10)
    end
end

bootSplash()

-- ------------------------- Filesystem --------------------
local function fsExists(fs, path)
    local ok, result = pcall(fs.exists, path)
    return ok and result == true
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
if #drives == 0 then error("Meadows: No writable filesystem found.") end

local function chooseStorage()
    local choice, scroll = 1, 0
    while true do
        clear(C.background)
        center(2, "MEADOWS INSTALLATION", C.accent)
        center(4, "Choose the drive used for Meadows data.", C.white)
        local visible = math.max(1, H - 10)
        if choice > scroll + visible then scroll = choice - visible end
        if choice <= scroll then scroll = choice - 1 end
        for row = 1, visible do
            local i = row + scroll
            local disk = drives[i]
            if disk then
                local y = 6 + row
                if i == choice then rect(3, y, W - 6, 1, C.selected) end
                local free = math.max(0, disk.total - disk.used)
                local capacity = disk.total > 0 and (math.floor(free / 1024) .. " KB free") or "Capacity unknown"
                put(5, y, tostring(i) .. ". " .. disk.label .. " | " .. capacity, C.white)
            end
        end
        put(4, H - 2, "Tap a drive to select and install Meadows.", C.accent)
        local signal, address, char, code = computer.pullSignal()
        if signal == "touch" then
            local tx, ty = tonumber(char), tonumber(code)
            if tx and ty then
                for row = 1, visible do
                    local i = row + scroll
                    if drives[i] and ty == 6 + row and tx >= 3 and tx <= W - 3 then return drives[i] end
                end
            end
        elseif signal == "key_down" then
            if code == 200 then choice = math.max(1, choice - 1)
            elseif code == 208 then choice = math.min(#drives, choice + 1)
            elseif code == 28 or char == 13 then return drives[choice] end
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
local testOK = fsWrite(filesystem, DATA_DIR .. "/storage-test.tmp", "MEADOWS STORAGE TEST")
if not testOK then error("Meadows: Storage write test failed.") end
pcall(filesystem.remove, DATA_DIR .. "/storage-test.tmp")
local identityOK = fsWrite(filesystem, STORAGE_ID_FILE, STORAGE_ADDRESS)
if not identityOK then error("Meadows: Could not save drive identity.") end

local function readFile(path) return fsRead(filesystem, path) end
local function writeFile(path, data) return fsWrite(filesystem, path, data) end

-- ------------------------- Configuration ------------------
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

-- Prototype hash only; not cryptographic password storage.
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
-- =========================================================
-- PART 2: ACCOUNTS, SETUP, LOGIN AND FILESYSTEM UTILITIES
-- =========================================================

local function saveAccounts()
    local lines = {}
    for i = 1, #accounts do
        local account = accounts[i]
        lines[#lines + 1] = table.concat({
            cleanValue(account.username),
            cleanValue(account.displayName),
            cleanValue(account.passwordHash)
        }, "|")
    end
    return writeFile(ACCOUNTS_FILE, table.concat(lines, "\n"))
end

local function loadAccounts()
    accounts = {}
    local data = readFile(ACCOUNTS_FILE)
    if not data then return end

    for line in data:gmatch("[^\r\n]+") do
        local username, displayName, passwordHash =
            line:match("^([^|]*)|([^|]*)|([^|]*)$")

        if username and username ~= "" then
            accounts[#accounts + 1] = {
                username = username,
                displayName = displayName,
                passwordHash = passwordHash or ""
            }
        end
    end
end

loadAccounts()

-- ------------------------- Input Dialog ------------------

local function inputDialog(title, prompt, initial)
    local value = tostring(initial or "")

    while true do
        clear(C.background)
        rect(3, math.floor(H / 2) - 4, W - 6, 9, C.window)

        center(math.floor(H / 2) - 3, title, C.accent)
        center(math.floor(H / 2) - 1, prompt, C.white)

        rect(6, math.floor(H / 2) + 1, W - 12, 1, C.panel2)
        put(7, math.floor(H / 2) + 1, value, C.white)

        drawButton(math.floor(W / 2) - 12, math.floor(H / 2) + 3, 10, "OK", true)
        drawButton(math.floor(W / 2) + 2, math.floor(H / 2) + 3, 10, "Cancel", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)
            if x and y and y == math.floor(H / 2) + 3 then
                if hit(x, y, math.floor(W / 2) - 12, y, 10, 1) then
                    return value
                end
                if hit(x, y, math.floor(W / 2) + 2, y, 10, 1) then
                    return nil
                end
            end

        elseif signal == "key_down" then
            if code == 28 or char == 13 then
                return value
            elseif code == 1 then
                return nil
            elseif code == 14 then
                value = value:sub(1, -2)
            elseif char and char > 0 then
                local ok, character = pcall(string.char, char)
                if ok and character and #value < 64 then
                    value = value .. character
                end
            end
        end
    end
end

-- ------------------------- Message Dialog ----------------

local function messageDialog(title, message)
    clear(C.background)
    rect(3, math.floor(H / 2) - 3, W - 6, 7, C.window)

    center(math.floor(H / 2) - 2, title, C.accent)
    center(math.floor(H / 2), message, C.white)
    center(math.floor(H / 2) + 2, "Touch anywhere or press a key", C.muted)

    while true do
        local signal = computer.pullSignal()
        if signal == "touch" or signal == "key_down" then
            return
        end
    end
end

-- ------------------------- Confirmation Dialog -----------

local function confirmDialog(title, message)
    while true do
        clear(C.background)
        rect(3, math.floor(H / 2) - 3, W - 6, 7, C.window)

        center(math.floor(H / 2) - 2, title, C.accent)
        center(math.floor(H / 2), message, C.white)

        drawButton(math.floor(W / 2) - 12, math.floor(H / 2) + 2, 10, "Yes", true)
        drawButton(math.floor(W / 2) + 2, math.floor(H / 2) + 2, 10, "No", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                if hit(x, y, math.floor(W / 2) - 12,
                    math.floor(H / 2) + 2, 10, 1) then
                    return true
                end

                if hit(x, y, math.floor(W / 2) + 2,
                    math.floor(H / 2) + 2, 10, 1) then
                    return false
                end
            end

        elseif signal == "key_down" then
            if code == 28 then return true end
            if code == 1 then return false end
        end
    end
end

-- ------------------------- Setup Terms -------------------

local function termsScreen()
    while true do
        clear(C.background)

        center(2, "WELCOME TO MEADOWS OS", C.accent)
        center(4, "FOREST EDITION - VERSION " .. VERSION, C.white)

        center(7, "Your settings and files are stored on the selected drive.", C.text)
        center(9, "Back up important files regularly.", C.text)
        center(11, "An independent OpenComputers desktop environment.", C.muted)

        drawButton(math.floor(W / 2) - 13, H - 4, 11, "Accept", true)
        drawButton(math.floor(W / 2) + 2, H - 4, 11, "Decline", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y and y == H - 4 then
                if hit(x, y, math.floor(W / 2) - 13, y, 11, 1) then
                    return true
                end

                if hit(x, y, math.floor(W / 2) + 2, y, 11, 1) then
                    return false
                end
            end

        elseif signal == "key_down" then
            if code == 28 then return true end
            if code == 1 then return false end
        end
    end
end

-- ------------------------- Setup Wizard ------------------

local function setupWizard()
    if not termsScreen() then
        error("Meadows setup was declined.")
    end

    local computerName = inputDialog(
        "COMPUTER NAME",
        "Enter a name for this computer:",
        config.computerName
    )

    if not computerName or computerName == "" then
        computerName = "Meadows-PC"
    end

    config.computerName = cleanValue(computerName)

    local displayName = inputDialog(
        "CREATE ACCOUNT",
        "Enter your display name:",
        ""
    )

    if not displayName or displayName == "" then
        displayName = "User"
    end

    local username = inputDialog(
        "CREATE ACCOUNT",
        "Choose a username:",
        "user"
    )

    if not username or username == "" then
        username = "user"
    end

    username = cleanValue(username)

    local password = inputDialog(
        "CREATE PASSWORD",
        "Enter a password:",
        ""
    )

    if password == nil then password = "" end

    accounts = {
        {
            username = username,
            displayName = cleanValue(displayName),
            passwordHash = hashPassword(password)
        }
    }

    config.username = username
    config.displayName = cleanValue(displayName)
    config.setupComplete = true
    config.version = VERSION

    local configOK = saveConfig()
    local accountsOK = saveAccounts()

    if not configOK or not accountsOK then
        error("Meadows: Could not save setup to the selected drive.")
    end

    messageDialog("SETUP COMPLETE", "Welcome to Meadows OS!")
end

if not config.setupComplete or #accounts == 0 then
    setupWizard()
end

-- ------------------------- Login Screen ------------------

local function loginScreen()
    while true do
        clear(C.background)

        center(3, "MEADOWS OS", C.accent)
        center(5, "Welcome back to " .. tostring(config.computerName), C.white)
        center(7, "Select your account to sign in.", C.muted)

        for i = 1, #accounts do
            local y = 9 + (i - 1) * 2
            local label = accounts[i].displayName ..
                " (" .. accounts[i].username .. ")"

            drawButton(math.floor(W / 2) - 15, y, 30, label, false)
        end

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                for i = 1, #accounts do
                    local row = 9 + (i - 1) * 2

                    if hit(x, y, math.floor(W / 2) - 15, row, 30, 1) then
                        local password = inputDialog(
                            "SIGN IN",
                            "Password for " .. accounts[i].username .. ":",
                            ""
                        )

                        if password ~= nil and
                            verifyPassword(password, accounts[i].passwordHash) then
                            return accounts[i]
                        end

                        messageDialog("SIGN IN FAILED", "Incorrect password.")
                    end
                end
            end

        elseif signal == "key_down" and code == 1 then
            return nil
        end
    end
end

local currentAccount = loginScreen()

if not currentAccount then
    error("Meadows: Login cancelled.")
end

config.username = currentAccount.username
config.displayName = currentAccount.displayName
saveConfig()

-- ------------------------- Filesystem Utilities ----------

local function pathJoin(a, b)
    if a == "/" then return "/" .. b end
    return a .. "/" .. b
end

local function normalizePath(path)
    path = tostring(path or "/")
    path = path:gsub("\\", "/")

    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end

    path = path:gsub("/+", "/")

    if #path > 1 then
        path = path:gsub("/$", "")
    end

    return path
end

local function parentPath(path)
    path = normalizePath(path)

    if path == "/" then return "/" end

    local parent = path:match("^(.*)/[^/]+$")

    if not parent or parent == "" then
        return "/"
    end

    return parent
end

local function baseName(path)
    path = normalizePath(path)

    if path == "/" then return "/" end

    return path:match("([^/]+)$") or path
end

local function safeName(name)
    name = tostring(name or "")
    name = name:gsub("[/\\:*?\"<>|]", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    if name == "" or name == "." or name == ".." then
        return nil
    end

    return name
end

local function isProtectedPath(path)
    path = normalizePath(path)

    return path == DATA_DIR or
        path:sub(1, #DATA_DIR + 1) == DATA_DIR .. "/"
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

        if entry ~= "" then
            result[#result + 1] = entry
        end
    end

    table.sort(result, function(a, b)
        return a:lower() < b:lower()
    end)

    return result
end

local function copyFile(source, destination)
    source = normalizePath(source)
    destination = normalizePath(destination)

    if filesystem.isDirectory(source) then
        return false, "Folder copying is not supported by this operation."
    end

    local data = readFile(source)

    if data == nil then
        return false, "Could not read source file."
    end

    return writeFile(destination, data)
end

local function deletePath(path)
    path = normalizePath(path)

    if path == "/" or isProtectedPath(path) then
        return false, "This system path cannot be deleted."
    end

    if not filesystem.exists(path) then
        return false, "Path does not exist."
    end

    if filesystem.isDirectory(path) then
        local entries = listDirectory(path)

        for i = 1, #entries do
            local child = pathJoin(path, entries[i])
            local ok, err = deletePath(child)

            if not ok then return false, err end
        end
    end

    local ok, result = pcall(filesystem.remove, path)

    if not ok or result == false then
        return false, "Could not delete item."
    end

    return true
end
-- =========================================================
-- PART 3: DESKTOP, TASKBAR AND APPLICATIONS
-- =========================================================

-- ------------------------- Wallpapers --------------------

local wallpapers = {
    {name = "Forest", top = 0x10271B, bottom = 0x07130D},
    {name = "Meadow", top = 0x244C35, bottom = 0x102719},
    {name = "Night", top = 0x101B32, bottom = 0x080D19},
    {name = "Emerald", top = 0x07523E, bottom = 0x09251D}
}

local function drawWallpaper()
    local wallpaper = wallpapers[config.wallpaper] or wallpapers[1]
    local top = wallpaper.top
    local bottom = wallpaper.bottom

    rect(1, 1, W, H, bottom)

    -- Decorative forest shapes
    for i = 1, 8 do
        local x = math.floor((W / 8) * (i - 1)) + 1
        local height = math.floor(H * (0.25 + ((i * 7) % 5) * 0.04))
        rect(x, H - height - 2, math.max(2, math.floor(W / 16)), height, top)
    end

    rect(1, H - 3, W, 3, C.desktop)
end

-- ------------------------- Desktop Icons -----------------

local desktopIcons = {
    {name = "Files", symbol = "[F]", app = "files"},
    {name = "Notes", symbol = "[N]", app = "notes"},
    {name = "Settings", symbol = "[S]", app = "settings"},
    {name = "Terminal", symbol = "[>]", app = "terminal"},
    {name = "About", symbol = "[i]", app = "about"}
}

local function drawDesktopIcons()
    for i = 1, #desktopIcons do
        local icon = desktopIcons[i]
        local x = 3
        local y = 3 + (i - 1) * 4

        put(x, y, icon.symbol, C.accent)
        put(x, y + 1, icon.name, C.white)
    end
end

-- ------------------------- Taskbar -----------------------

local function drawTaskbar()
    local y = H - 2

    rect(1, y, W, 2, C.panel)

    local items = {
        {label = "Start", action = "start"},
        {label = "Files", action = "files"},
        {label = "Notes", action = "notes"},
        {label = "Settings", action = "settings"}
    }

    local totalWidth = 0
    for i = 1, #items do
        totalWidth = totalWidth + #items[i].label + 3
    end

    local startX = math.max(2, math.floor((W - totalWidth) / 2))
    local x = startX

    for i = 1, #items do
        local item = items[i]
        local width = #item.label + 2

        drawButton(x, y, width, item.label, false)
        x = x + width + 1
    end

    local time = clockText()
    put(W - #time - 2, y, time, C.white)

    if os and os.date then
        local ok, date = pcall(os.date, "%d/%m")
        if ok and date then
            put(W - #date - 2, y + 1, date, C.muted)
        end
    end
end

local function drawDesktop()
    drawWallpaper()

    center(2, config.computerName, C.accent)
    drawDesktopIcons()
    drawTaskbar()
end

-- ------------------------- Start Menu --------------------

local function drawStartMenu()
    local menuWidth = math.min(34, W - 4)
    local menuHeight = math.min(15, H - 5)

    local x = math.floor((W - menuWidth) / 2)
    local y = H - menuHeight - 3

    rect(x, y, menuWidth, menuHeight, C.window)
    rect(x, y, menuWidth, 1, C.titlebar)

    put(x + 2, y, "MEADOWS START", C.white)

    local entries = {
        {name = "File Explorer", app = "files"},
        {name = "Notes", app = "notes"},
        {name = "Settings", app = "settings"},
        {name = "Terminal", app = "terminal"},
        {name = "About Meadows", app = "about"},
        {name = "Power Options", app = "power"}
    }

    for i = 1, #entries do
        local row = y + 2 + (i - 1) * 2
        if row < y + menuHeight - 1 then
            drawButton(x + 2, row, menuWidth - 4, entries[i].name, false)
        end
    end

    return x, y, menuWidth, menuHeight, entries
end

-- ------------------------- Text Editor -------------------

local function textEditor(path)
    path = normalizePath(path)

    local contents = readFile(path)
    if contents == nil then
        contents = ""
    end

    local lines = {}
    for line in (contents .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end

    if #lines == 0 then lines[1] = "" end

    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.window)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "NOTEPAD - " .. baseName(path), C.white)

        local visible = H - 9

        for i = 1, visible do
            local line = lines[i] or ""
            put(4, 3 + i, tostring(i) .. ": " .. line, C.text)
        end

        put(4, H - 4, "Touch Add line to append a line.", C.muted)

        drawButton(4, H - 2, 12, "Add line", true)
        drawButton(18, H - 2, 10, "Save", false)
        drawButton(30, H - 2, 10, "Close", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                if hit(x, y, 4, H - 2, 12, 1) then
                    local newLine = inputDialog(
                        "ADD LINE",
                        "Enter text for the new line:",
                        ""
                    )

                    if newLine ~= nil then
                        lines[#lines + 1] = newLine
                    end

                elseif hit(x, y, 18, H - 2, 10, 1) then
                    local ok = writeFile(path, table.concat(lines, "\n"))
                    if ok then
                        messageDialog("SAVED", "File saved successfully.")
                    else
                        messageDialog("ERROR", "Could not save this file.")
                    end

                elseif hit(x, y, 30, H - 2, 10, 1) then
                    if confirmDialog("CLOSE EDITOR", "Close this document?") then
                        return
                    end
                end
            end

        elseif signal == "key_down" and code == 1 then
            return
        end
    end
end

-- ------------------------- File Explorer -----------------

local function fileExplorer()
    local currentPath = "/"
    local selected = nil
    local clipboard = nil
    local clipboardMode = nil
    local lastTouched = nil
    local lastTouchTime = 0
    local scroll = 0

    while true do
        local entries = listDirectory(currentPath)

        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.window)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "FILE EXPLORER", C.white)
        put(4, 4, "Location: " .. currentPath, C.accent)

        local toolbar = {
            {label = "Up", action = "up"},
            {label = "Folder", action = "folder"},
            {label = "File", action = "file"},
            {label = "Open", action = "open"},
            {label = "Rename", action = "rename"},
            {label = "Copy", action = "copy"},
            {label = "Cut", action = "cut"},
            {label = "Paste", action = "paste"},
            {label = "Delete", action = "delete"}
        }

        local x = 4
        local y = 6

        for i = 1, #toolbar do
            local width = #toolbar[i].label + 2

            if x + width >= W - 3 then
                x = 4
                y = y + 2
            end

            drawButton(x, y, width, toolbar[i].label, false)
            toolbar[i].x = x
            toolbar[i].y = y
            toolbar[i].width = width

            x = x + width + 1
        end

        local listStart = y + 2
        local listHeight = H - listStart - 4

        put(4, listStart - 1, "NAME", C.accent)
        put(math.floor(W * 0.65), listStart - 1, "TYPE", C.accent)

        local visible = math.max(1, listHeight)

        if selected and not filesystem.exists(pathJoin(currentPath, selected)) then
            selected = nil
        end

        for i = 1, visible do
            local index = i + scroll
            local entry = entries[index]

            if entry then
                local fullPath = pathJoin(currentPath, entry)
                local isDir = filesystem.isDirectory(fullPath)
                local marker = isDir and "[DIR] " or "      "
                local label = marker .. entry
                local row = listStart + i - 1

                if selected == entry then
                    rect(3, row, W - 6, 1, C.selected)
                end

                put(4, row, label:sub(1, math.floor(W * 0.60)), C.white)
                put(math.floor(W * 0.65), row,
                    isDir and "Folder" or "File", C.muted)
            end
        end

        put(4, H - 3, selected and ("Selected: " .. selected) or "Select an item.", C.accent)
        drawButton(W - 13, H - 2, 10, "Close", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local tx, ty = tonumber(char), tonumber(code)

            if tx and ty then
                if hit(tx, ty, W - 13, H - 2, 10, 1) then
                    return
                end

                local handled = false

                for i = 1, #toolbar do
                    local button = toolbar[i]

                    if hit(tx, ty, button.x, button.y, button.width, 1) then
                        handled = true
                        local action = button.action

                        if action == "up" then
                            currentPath = parentPath(currentPath)
                            selected = nil
                            scroll = 0

                        elseif action == "folder" then
                            local name = safeName(inputDialog(
                                "NEW FOLDER", "Enter folder name:", "New Folder"
                            ))

                            if name then
                                local target = pathJoin(currentPath, name)
                                local ok, result = pcall(filesystem.makeDirectory, target)

                                if not ok or result == false then
                                    messageDialog("ERROR", "Could not create folder.")
                                end
                            end

                        elseif action == "file" then
                            local name = safeName(inputDialog(
                                "NEW FILE", "Enter file name:", "New File.txt"
                            ))

                            if name then
                                local target = pathJoin(currentPath, name)

                                if filesystem.exists(target) then
                                    messageDialog("ERROR", "That item already exists.")
                                else
                                    writeFile(target, "")
                                end
                            end

                        elseif action == "open" then
                            if selected then
                                local target = pathJoin(currentPath, selected)

                                if filesystem.isDirectory(target) then
                                    currentPath = target
                                    selected = nil
                                    scroll = 0
                                else
                                    textEditor(target)
                                end
                            end

                        elseif action == "rename" then
                            if selected then
                                local newName = safeName(inputDialog(
                                    "RENAME", "Enter the new name:", selected
                                ))

                                if newName then
                                    local oldPath = pathJoin(currentPath, selected)
                                    local newPath = pathJoin(currentPath, newName)

                                    if not isProtectedPath(oldPath) and
                                        not filesystem.exists(newPath) then
                                        local ok, result = pcall(filesystem.rename, oldPath, newPath)

                                        if ok and result ~= false then
                                            selected = newName
                                        else
                                            messageDialog("ERROR", "Rename failed.")
                                        end
                                    else
                                        messageDialog("ERROR", "Invalid destination.")
                                    end
                                end
                            end

                        elseif action == "copy" or action == "cut" then
                            if selected then
                                clipboard = pathJoin(currentPath, selected)
                                clipboardMode = action
                            end

                        elseif action == "paste" then
                            if clipboard then
                                local name = baseName(clipboard)
                                local destination = pathJoin(currentPath, name)

                                if filesystem.exists(destination) then
                                    messageDialog("ERROR", "An item with that name exists.")
                                elseif filesystem.isDirectory(clipboard) then
                                    messageDialog("ERROR", "Folder paste is not supported.")
                                else
                                    local ok, err = copyFile(clipboard, destination)

                                    if ok and clipboardMode == "cut" then
                                        pcall(filesystem.remove, clipboard)
                                        clipboard = nil
                                        clipboardMode = nil
                                    elseif not ok then
                                        messageDialog("ERROR", tostring(err))
                                    end
                                end
                            end

                        elseif action == "delete" then
                            if selected then
                                local target = pathJoin(currentPath, selected)

                                if confirmDialog("DELETE ITEM", "Delete " .. selected .. "?") then
                                    local ok, err = deletePath(target)

                                    if ok then
                                        selected = nil
                                    else
                                        messageDialog("ERROR", tostring(err))
                                    end
                                end
                            end
                        end

                        break
                    end
                end

                if not handled and ty >= listStart and ty < listStart + visible then
                    local index = ty - listStart + 1 + scroll
                    local entry = entries[index]

                    if entry then
                        local now = computer.uptime()

                        if selected == entry and lastTouched == entry and
                            now - lastTouchTime < 0.65 then

                            local target = pathJoin(currentPath, entry)

                            if filesystem.isDirectory(target) then
                                currentPath = target
                                selected = nil
                                scroll = 0
                            else
                                textEditor(target)
                            end
                        else
                            selected = entry
                        end

                        lastTouched = entry
                        lastTouchTime = now
                    end
                end
            end

        elseif signal == "key_down" then
            if code == 1 then
                return
            elseif code == 200 then
                scroll = math.max(0, scroll - 1)
            elseif code == 208 then
                scroll = math.min(math.max(0, #entries - visible), scroll + 1)
            end
        end
    end
end

-- ------------------------- Notes Application --------------

local function notesApp()
    local notes = loadNotes()

    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.window)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "MEADOWS NOTES", C.white)

        local lines = {}
        for line in (notes .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line
        end

        local maxLines = H - 9

        for i = 1, math.min(#lines, maxLines) do
            put(4, 3 + i, lines[i], C.text)
        end

        drawButton(4, H - 3, 12, "Add note", true)
        drawButton(18, H - 3, 12, "Edit notes", false)
        drawButton(32, H - 3, 10, "Clear", false)
        drawButton(W - 13, H - 3, 10, "Close", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                if hit(x, y, 4, H - 3, 12, 1) then
                    local note = inputDialog("NEW NOTE", "Enter your note:", "")

                    if note ~= nil then
                        if notes ~= "" then notes = notes .. "\n" end
                        notes = notes .. note
                        saveNotes(notes)
                    end

                elseif hit(x, y, 18, H - 3, 12, 1) then
                    local note = inputDialog(
                        "EDIT NOTES",
                        "Replace all notes with:",
                        notes
                    )

                    if note ~= nil then
                        notes = note
                        saveNotes(notes)
                    end

                elseif hit(x, y, 32, H - 3, 10, 1) then
                    if confirmDialog("CLEAR NOTES", "Delete all saved notes?") then
                        notes = ""
                        saveNotes(notes)
                    end

                elseif hit(x, y, W - 13, H - 3, 10, 1) then
                    return
                end
            end

        elseif signal == "key_down" and code == 1 then
            return
        end
    end
end

-- ------------------------- Settings ----------------------

local function settingsApp()
    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.window)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "MEADOWS SETTINGS", C.white)

        put(4, 5, "PERSONALIZATION", C.accent)

        for i = 1, #wallpapers do
            local y = 7 + (i - 1) * 2
            local selected = config.wallpaper == i

            drawButton(4, y, 25,
                wallpapers[i].name .. (selected and "  *" or ""),
                selected
            )
        end

        put(4, 16, "SYSTEM INFORMATION", C.accent)
        put(4, 18, "OS: Meadows " .. VERSION, C.text)
        put(4, 19, "Computer: " .. config.computerName, C.text)
        put(4, 20, "User: " .. config.username, C.text)

        drawButton(W - 13, H - 3, 10, "Close", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                for i = 1, #wallpapers do
                    local row = 7 + (i - 1) * 2

                    if hit(x, y, 4, row, 25, 1) then
                        config.wallpaper = i
                        saveConfig()
                    end
                end

                if hit(x, y, W - 13, H - 3, 10, 1) then
                    return
                end
            end

        elseif signal == "key_down" and code == 1 then
            return
        end
    end
end
-- =========================================================
-- PART 4: TERMINAL, ABOUT, START MENU AND MAIN DESKTOP
-- =========================================================

-- ------------------------- Terminal ----------------------

local function terminalApp()
    local history = {}
    local currentPath = "/"

    local function addHistory(value)
        history[#history + 1] = tostring(value)
        while #history > H - 9 do
            table.remove(history, 1)
        end
    end

    local function executeCommand(command)
        command = tostring(command or "")
        local args = {}

        for word in command:gmatch("%S+") do
            args[#args + 1] = word
        end

        local cmd = args[1]

        if not cmd then return end

        if cmd == "help" then
            addHistory("Commands:")
            addHistory("help, clear, ls, pwd, cd")
            addHistory("mkdir, touch, cat, rm")
            addHistory("whoami, hostname, version")

        elseif cmd == "clear" then
            history = {}

        elseif cmd == "pwd" then
            addHistory(currentPath)

        elseif cmd == "whoami" then
            addHistory(config.username)

        elseif cmd == "hostname" then
            addHistory(config.computerName)

        elseif cmd == "version" then
            addHistory("Meadows OS " .. VERSION)

        elseif cmd == "ls" then
            local entries = listDirectory(currentPath)
            if #entries == 0 then addHistory("(empty)") end

            for i = 1, #entries do
                addHistory(entries[i])
            end

        elseif cmd == "cd" then
            local target = args[2] or "/"

            if target == ".." then
                currentPath = parentPath(currentPath)
            else
                if target:sub(1, 1) ~= "/" then
                    target = pathJoin(currentPath, target)
                end

                target = normalizePath(target)

                if filesystem.exists(target) and filesystem.isDirectory(target) then
                    currentPath = target
                else
                    addHistory("Directory not found.")
                end
            end

        elseif cmd == "mkdir" then
            local name = safeName(args[2])

            if not name then
                addHistory("Usage: mkdir foldername")
            else
                local path = pathJoin(currentPath, name)
                local ok, result = pcall(filesystem.makeDirectory, path)

                if not ok or result == false then
                    addHistory("Could not create directory.")
                else
                    addHistory("Directory created.")
                end
            end

        elseif cmd == "touch" then
            local name = safeName(args[2])

            if not name then
                addHistory("Usage: touch filename")
            else
                local path = pathJoin(currentPath, name)

                if filesystem.exists(path) then
                    addHistory("File already exists.")
                else
                    local ok = writeFile(path, "")
                    addHistory(ok and "File created." or "Could not create file.")
                end
            end

        elseif cmd == "cat" then
            local name = args[2]

            if not name then
                addHistory("Usage: cat filename")
            else
                local path = normalizePath(pathJoin(currentPath, name))
                local data = readFile(path)

                if data == nil then
                    addHistory("Could not read file.")
                else
                    for line in (data .. "\n"):gmatch("(.-)\n") do
                        addHistory(line)
                    end
                end
            end

        elseif cmd == "rm" then
            local name = args[2]

            if not name then
                addHistory("Usage: rm filename")
            else
                local path = normalizePath(pathJoin(currentPath, name))

                if isProtectedPath(path) then
                    addHistory("Protected system path.")
                elseif confirmDialog("TERMINAL DELETE", "Delete " .. name .. "?") then
                    local ok, err = deletePath(path)
                    addHistory(ok and "Deleted." or tostring(err))
                end
            end

        else
            addHistory("Unknown command: " .. tostring(cmd))
            addHistory("Type help for commands.")
        end
    end

    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.window)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "MEADOWS TERMINAL", C.white)

        local visible = H - 9
        local first = math.max(1, #history - visible + 1)

        for i = first, #history do
            put(4, 3 + i - first, history[i], C.text)
        end

        put(4, H - 4, currentPath .. ">", C.accent)
        drawButton(4, H - 2, 12, "Command", true)
        drawButton(18, H - 2, 10, "Close", false)

        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                if hit(x, y, 4, H - 2, 12, 1) then
                    local command = inputDialog(
                        "TERMINAL COMMAND",
                        "Enter a command:",
                        ""
                    )

                    if command ~= nil then
                        addHistory(currentPath .. "> " .. command)
                        executeCommand(command)
                    end

                elseif hit(x, y, 18, H - 2, 10, 1) then
                    return
                end
            end

        elseif signal == "key_down" and code == 1 then
            return
        end
    end
end

-- ------------------------- About -------------------------

local function aboutApp()
    clear(C.background)

    rect(3, 3, W - 6, H - 6, C.window)
    rect(3, 3, W - 6, 1, C.titlebar)

    center(5, "MEADOWS OS", C.accent)
    center(7, "Forest Edition", C.white)
    center(9, "Version " .. VERSION, C.text)

    center(12, "A desktop environment for OpenComputers.", C.text)
    center(14, "Designed around a peaceful forest theme.", C.muted)
    center(16, "Persistent filesystem installation.", C.muted)

    center(19, "Thank you for using Meadows OS!", C.accent)

    drawButton(math.floor(W / 2) - 5, H - 3, 10, "Close", true)

    while true do
        local signal, address, char, code = computer.pullSignal()

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y and hit(x, y, math.floor(W / 2) - 5, H - 3, 10, 1) then
                return
            end

        elseif signal == "key_down" then
            return
        end
    end
end

-- ------------------------- App Launcher ------------------

local function launchApp(app)
    if app == "files" then
        fileExplorer()

    elseif app == "notes" then
        notesApp()

    elseif app == "settings" then
        settingsApp()

    elseif app == "terminal" then
        terminalApp()

    elseif app == "about" then
        aboutApp()

    elseif app == "power" then
        if confirmDialog("POWER OPTIONS", "Shut down Meadows OS?") then
            clear(C.background)
            center(math.floor(H / 2), "Shutting down Meadows OS...", C.accent)
            computer.shutdown()
            return true
        end
    end

    return false
end

-- ------------------------- Desktop Interaction -----------

local function desktopLoop()
    local startOpen = false
    local lastIcon = nil
    local lastIconTime = 0

    while true do
        drawDesktop()

        local menuX, menuY, menuW, menuH, entries

        if startOpen then
            menuX, menuY, menuW, menuH, entries = drawStartMenu()
        end

        local signal, address, char, code = computer.pullSignal(1)

        if signal == "touch" then
            local x, y = tonumber(char), tonumber(code)

            if x and y then
                local handled = false

                -- Start menu interaction
                if startOpen then
                    if x >= menuX and x < menuX + menuW and
                        y >= menuY and y < menuY + menuH then

                        for i = 1, #entries do
                            local row = menuY + 2 + (i - 1) * 2

                            if hit(x, y, menuX + 2, row, menuW - 4, 1) then
                                local app = entries[i].app
                                startOpen = false

                                local shouldStop = launchApp(app)
                                if shouldStop then return end

                                handled = true
                                break
                            end
                        end

                    else
                        startOpen = false
                        handled = true
                    end
                end

                -- Taskbar interaction
                if not handled and y == H - 2 then
                    local items = {
                        {label = "Start", action = "start"},
                        {label = "Files", action = "files"},
                        {label = "Notes", action = "notes"},
                        {label = "Settings", action = "settings"}
                    }

                    local totalWidth = 0
                    for i = 1, #items do
                        totalWidth = totalWidth + #items[i].label + 3
                    end

                    local tx = math.max(2, math.floor((W - totalWidth) / 2))

                    for i = 1, #items do
                        local item = items[i]
                        local width = #item.label + 2

                        if hit(x, y, tx, y, width, 1) then
                            if item.action == "start" then
                                startOpen = not startOpen
                            else
                                local shouldStop = launchApp(item.action)
                                if shouldStop then return end
                            end

                            handled = true
                            break
                        end

                        tx = tx + width + 1
                    end
                end

                -- Desktop icon interaction
                if not handled then
                    for i = 1, #desktopIcons do
                        local icon = desktopIcons[i]
                        local ix = 3
                        local iy = 3 + (i - 1) * 4

                        if hit(x, y, ix, iy, 12, 2) then
                            local now = computer.uptime()

                            if lastIcon == icon.app and now - lastIconTime < 0.65 then
                                local shouldStop = launchApp(icon.app)
                                if shouldStop then return end
                                lastIcon = nil
                            else
                                lastIcon = icon.app
                            end

                            lastIconTime = now
                            handled = true
                            break
                        end
                    end
                end
            end

        elseif signal == "key_down" then
            -- Escape closes the Start menu.
            if code == 1 then
                if startOpen then
                    startOpen = false
                end
            end
        end
    end
end

-- ------------------------- Final Boot --------------------

clear(C.background)
center(math.floor(H / 2) - 1, "MEADOWS OS", C.accent)
center(math.floor(H / 2) + 1, "Loading desktop...", C.white)
computer.pullSignal(0.5)

desktopLoop()
