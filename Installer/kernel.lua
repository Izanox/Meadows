-- =========================================================
-- CHANGE 5.5
-- MEADOWS OS 1.2 - FOREST EDITION
-- Rebuilt and corrected native OpenComputers BIOS kernel
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
        center(H - 2, "UP/DOWN: Select     ENTER: Confirm", C.accent)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
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
local function saveAccounts()
    local lines = {}
    for i = 1, #accounts do
        local a = accounts[i]
        lines[#lines + 1] = table.concat({cleanValue(a.username), cleanValue(a.displayName), cleanValue(a.passwordHash)}, "|")
    end
    return writeFile(ACCOUNTS_FILE, table.concat(lines, "\n"))
end
local function loadAccounts()
    accounts = {}
    local data = readFile(ACCOUNTS_FILE)
    if not data then return end
    for line in data:gmatch("[^\r\n]+") do
        local username, displayName, passwordHash = line:match("^([^|]+)|([^|]*)|([^|]+)$")
        if username and passwordHash then
            accounts[#accounts + 1] = {username = username, displayName = displayName, passwordHash = passwordHash}
        end
    end
end
loadAccounts()

local function findAccount(username)
    username = tostring(username or ""):lower()
    for i = 1, #accounts do
        if accounts[i].username:lower() == username then return accounts[i], i end
    end
    return nil
end
local function validUsername(username)
    return #username >= 3 and #username <= 16 and username:match("^[a-zA-Z0-9_]+$") ~= nil
end
local function createAccount(username, displayName, password)
    username, displayName, password = tostring(username or ""):lower(), tostring(displayName or ""), tostring(password or "")
    if not validUsername(username) then return false, "Username must be 3-16 letters, numbers or underscores." end
    if findAccount(username) then return false, "That username already exists." end
    if #displayName < 1 or #displayName > 24 then return false, "Display name must be 1-24 characters." end
    if #password < 1 then return false, "Password cannot be empty." end
    accounts[#accounts + 1] = {username = username, displayName = cleanValue(displayName), passwordHash = hashPassword(password)}
    local success, reason = saveAccounts()
    if not success then accounts[#accounts] = nil; return false, reason or "Could not save account." end
    return true
end

-- ------------------------- Dialogs ------------------------
local function inputDialog(title, prompt, secret, initial)
    local value = tostring(initial or "")
    while true do
        clear(C.background)
        rect(3, 3, W - 6, H - 6, C.panel)
        rect(3, 3, W - 6, 1, C.titlebar)
        put(5, 3, title, C.white)
        put(5, 6, prompt, C.muted)
        rect(5, 8, W - 10, 3, C.background)
        local shown = secret and string.rep("*", #value) or value
        local maxChars = W - 13
        if #shown > maxChars then shown = shown:sub(#shown - maxChars + 1) end
        put(6, 9, shown, C.white)
        put(math.min(W - 5, 6 + #shown), 9, "_", C.accent)
        center(H - 5, "ENTER: Confirm", C.accent)
        center(H - 3, "ESC: Cancel", C.muted)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 1 or char == 27 then return nil
            elseif code == 28 or char == 13 then return value
            elseif code == 14 then value = value:sub(1, -2)
            elseif char and char >= 32 and char <= 126 and #value < 96 then value = value .. string.char(char) end
        end
    end
end

local function messageDialog(title, message)
    clear(C.background)
    rect(3, 4, W - 6, H - 8, C.panel)
    rect(3, 4, W - 6, 1, C.titlebar)
    put(5, 4, title, C.white)
    local y = 7
    for line in tostring(message):gmatch("[^\n]+") do
        if y >= H - 5 then break end
        put(5, y, line:sub(1, W - 10), C.text)
        y = y + 1
    end
    center(H - 3, "Press any key to continue", C.accent)
    waitForKey()
end

local function confirmDialog(title, message)
    local selection = 1
    while true do
        clear(C.background)
        rect(4, 5, W - 8, H - 10, C.panel)
        rect(4, 5, W - 8, 1, C.titlebar)
        put(6, 5, title, C.white)
        put(6, 8, tostring(message):sub(1, W - 12), C.text)
        if selection == 1 then rect(6, H - 5, 12, 1, C.accentDark) else rect(22, H - 5, 12, 1, C.accentDark) end
        put(7, H - 5, "Yes", C.white); put(23, H - 5, "No", C.white)
        center(H - 2, "LEFT/RIGHT: Select     ENTER: Confirm", C.muted)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 203 then selection = 1
            elseif code == 205 then selection = 2
            elseif code == 28 then return selection == 1
            elseif code == 1 then return false end
        end
    end
end

-- ------------------------- First-run setup ----------------
local function termsScreen()
    local selection = 1
    while true do
        clear(C.background)
        rect(3, 2, W - 6, H - 4, C.panel)
        rect(3, 2, W - 6, 1, C.titlebar)
        put(5, 2, "MEADOWS TERMS AND CONDITIONS", C.white)
        put(5, 5, "Welcome to Meadows OS.", C.accent)
        put(5, 7, "Please read this playful system agreement:", C.text)
        put(5, 9, "1. Use Meadows responsibly.", C.text)
        put(5, 11, "2. Your files and accounts are stored locally.", C.text)
        put(5, 13, "3. Have fun exploring the Forest Edition.", C.accent)
        if selection == 1 then rect(5, H - 5, 15, 1, C.accentDark) else rect(24, H - 5, 15, 1, C.accentDark) end
        put(6, H - 5, "Accept", C.white); put(25, H - 5, "Decline", C.white)
        center(H - 2, "LEFT/RIGHT: Select     ENTER: Confirm", C.muted)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 203 then selection = 1
            elseif code == 205 then selection = 2
            elseif code == 28 then return selection == 1 end
        end
    end
end

local function setupWizard()
    if not termsScreen() then
        messageDialog("Setup cancelled", "You declined the Meadows terms. Setup cannot continue.")
        computer.shutdown()
        return false
    end
    local computerName = inputDialog("Computer name", "Choose a name for this computer:")
    if not computerName then return false end
    if computerName == "" then computerName = "Meadows-PC" end
    local displayName = inputDialog("Create account", "Enter your display name:")
    if not displayName then return false end
    local username = inputDialog("Create username", "Use 3-16 letters, numbers or underscores:")
    if not username then return false end
    local password = inputDialog("Create password", "Enter your account password:", true)
    if not password then return false end
    local confirmation = inputDialog("Confirm password", "Enter your password again:", true)
    if not confirmation then return false end
    if password ~= confirmation then messageDialog("Password mismatch", "The passwords do not match."); return false end
    local success, reason = createAccount(username, displayName, password)
    if not success then messageDialog("Account error", tostring(reason)); return false end
    config.computerName, config.username, config.displayName = cleanValue(computerName), username:lower(), cleanValue(displayName)
    config.setupComplete = true
    local saved, saveError = saveConfig()
    if not saved then messageDialog("Configuration error", tostring(saveError)); return false end
    messageDialog("Setup complete", "Welcome to Meadows OS, " .. displayName .. "!\n\nYour account has been saved to the selected drive.")
    return true
end

local function loginScreen()
    while true do
        if #accounts == 0 then messageDialog("No accounts", "No accounts were found. Restart setup to create one."); return nil end
        local selected = 1
        while true do
            clear(C.background)
            center(3, "WELCOME BACK", C.accent)
            center(5, config.computerName, C.muted)
            center(7, "Select your account", C.white)
            local visible = math.max(1, H - 11)
            for i = 1, math.min(#accounts, visible) do
                local y = 9 + (i - 1) * 1
                if i == selected then rect(4, y, W - 8, 1, C.accentDark) end
                put(6, y, accounts[i].displayName .. " (" .. accounts[i].username .. ")", C.white)
            end
            center(H - 2, "UP/DOWN: Select     ENTER: Login", C.muted)
            local signal, address, char, code = computer.pullSignal()
            if signal == "key_down" then
                if code == 200 then selected = math.max(1, selected - 1)
                elseif code == 208 then selected = math.min(#accounts, selected + 1)
                elseif code == 28 then
                    local account = accounts[selected]
                    local password = inputDialog("Password", "Enter password for " .. account.displayName .. ":", true)
                    if password and verifyPassword(password, account.passwordHash) then return account end
                    if password then messageDialog("Login failed", "Incorrect password. Please try again.") end
                    break
                elseif code == 1 then break end
            end
        end
    end
end

if not config.setupComplete or #accounts == 0 then
    if not setupWizard() then error("Meadows: Setup did not complete.") end
    loadAccounts()
end
local currentUser = loginScreen()
if not currentUser then error("Meadows: Login failed.") end
config.username, config.displayName = currentUser.username, currentUser.displayName
saveConfig()

-- ------------------------- Paths and file operations -----
local function normalizePath(path)
    path = tostring(path or "/"):gsub("\\", "/")
    local segments = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then if #segments > 0 then segments[#segments] = nil end
        elseif part ~= "." and part ~= "" then segments[#segments + 1] = part end
    end
    if #segments == 0 then return "/" end
    return "/" .. table.concat(segments, "/")
end
local function joinPath(parent, child)
    parent, child = normalizePath(parent), tostring(child or "")
    if child == "" or child == "." or child == ".." or child:find("/", 1, true) or child:find("\\", 1, true) then return nil end
    return normalizePath((parent == "/" and "" or parent) .. "/" .. child)
end
local function isProtectedPath(path)
    path = normalizePath(path)
    return path == DATA_DIR or path:sub(1, #DATA_DIR + 1) == DATA_DIR .. "/"
end
local function safePath(path)
    path = normalizePath(path)
    if isProtectedPath(path) then return nil end
    return path
end
local function parentPath(path)
    path = normalizePath(path)
    if path == "/" then return "/" end
    return path:match("^(.*)/[^/]+$") ~= "" and path:match("^(.*)/[^/]+$") or "/"
end
local function baseName(path)
    path = normalizePath(path)
    return path == "/" and "/" or (path:match("([^/]+)$") or path)
end
local function pathExists(path) return fsExists(filesystem, normalizePath(path)) end
local function isDirectory(path)
    local ok, result = pcall(filesystem.isDirectory, normalizePath(path))
    return ok and result == true
end
local function listDirectory(path)
    local result = {}
    local ok, iterator = pcall(filesystem.list, normalizePath(path))
    if not ok or not iterator then return result end
    while true do
        local success, item = pcall(iterator)
        if not success or not item then break end
        item = tostring(item):gsub("/$", "")
        if item ~= "" and item ~= "." and item ~= ".." then result[#result + 1] = item end
    end
    table.sort(result, function(a, b)
        local pa, pb = joinPath(path, a), joinPath(path, b)
        local da, db = pa and isDirectory(pa) or false, pb and isDirectory(pb) or false
        if da ~= db then return da end
        return a:lower() < b:lower()
    end)
    return result
end
local function createFolder(path)
    path = safePath(path)
    if not path then return false, "Protected system location." end
    if pathExists(path) then return false, "This item already exists." end
    local ok, result = pcall(filesystem.makeDirectory, path)
    if not ok or result == false or not pathExists(path) then return false, "Could not create folder." end
    return true
end
local function createFile(path, content)
    path = safePath(path)
    if not path then return false, "Protected system location." end
    if pathExists(path) then return false, "This item already exists." end
    return fsWrite(filesystem, path, content or "")
end
local function deletePath(path)
    path = safePath(path)
    if not path or path == "/" then return false, "Cannot delete this location." end
    if not pathExists(path) then return false, "Item does not exist." end
    if isDirectory(path) then
        local entries = listDirectory(path)
        for i = 1, #entries do
            local child = joinPath(path, entries[i])
            local success, reason = deletePath(child)
            if not success then return false, reason end
        end
    end
    local ok, result = pcall(filesystem.remove, path)
    if not ok or result == false or pathExists(path) then return false, "Could not delete item." end
    return true
end
local function renamePath(oldPath, newName)
    oldPath = safePath(oldPath)
    newName = tostring(newName or "")
    if not oldPath then return false, "Protected system location." end
    if newName == "" or newName == "." or newName == ".." or newName:find("/", 1, true) or newName:find("\\", 1, true) then return false, "Invalid new name." end
    local destination = joinPath(parentPath(oldPath), newName)
    if not destination then return false, "Invalid destination." end
    if pathExists(destination) then return false, "An item with that name already exists." end
    local ok, result = pcall(filesystem.rename, oldPath, destination)
    if not ok or result == false or not pathExists(destination) then return false, "Rename failed." end
    return true
end
local function copyFile(source, destination)
    source, destination = safePath(source), safePath(destination)
    if not source or not destination then return false, "Protected system location." end
    if not pathExists(source) or isDirectory(source) then return false, "Source is not a regular file." end
    if pathExists(destination) then return false, "Destination already exists." end
    local sourceHandle, destinationHandle
    local ok, reason = pcall(function()
        sourceHandle = assert(filesystem.open(source, "r"))
        destinationHandle = assert(filesystem.open(destination, "w"))
        while true do
            local chunk = filesystem.read(sourceHandle, 4096)
            if not chunk or #chunk == 0 then break end
            local wrote = filesystem.write(destinationHandle, chunk)
            if wrote == false then error("Write failed.") end
        end
    end)
    if sourceHandle then pcall(filesystem.close, sourceHandle) end
    if destinationHandle then pcall(filesystem.close, destinationHandle) end
    if not ok then pcall(filesystem.remove, destination); return false, tostring(reason) end
    return true
end
local function copyPath(source, destination)
    source, destination = safePath(source), safePath(destination)
    if not source or not destination then return false, "Protected system location." end
    if not pathExists(source) then return false, "Source does not exist." end
    if pathExists(destination) then return false, "Destination already exists." end
    if isDirectory(source) then
        if destination:sub(1, #source + 1) == source .. "/" then return false, "Cannot copy a folder into itself." end
        local ok, result = pcall(filesystem.makeDirectory, destination)
        if not ok or result == false then return false, "Could not create destination folder." end
        for _, name in ipairs(listDirectory(source)) do
            local success, reason = copyPath(joinPath(source, name), joinPath(destination, name))
            if not success then deletePath(destination); return false, reason end
        end
        return true
    end
    return copyFile(source, destination)
end
local clipboard, clipboardMode = nil, nil
local function pasteClipboard(currentDirectory)
    if not clipboard then return false, "Clipboard is empty." end
    local destination = joinPath(currentDirectory, baseName(clipboard))
    if not destination then return false, "Invalid destination." end
    if pathExists(destination) then return false, "An item with that name already exists." end
    local success, reason = copyPath(clipboard, destination)
    if not success then return false, reason end
    if clipboardMode == "cut" then
        local removed, removeReason = deletePath(clipboard)
        if not removed then deletePath(destination); return false, "Could not move original: " .. tostring(removeReason) end
    end
    clipboard, clipboardMode = nil, nil
    return true
end

-- ------------------------- Text editor -------------------
local function textEditor(path, initialText)
    local lines = {}
    for line in (tostring(initialText or "") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if #lines == 0 then lines[1] = "" end
    local cursorLine, cursorColumn = 1, 0
    local dirty = false
    local function save()
        local ok, reason = writeFile(path, table.concat(lines, "\n"))
        if ok then dirty = false else messageDialog("Save failed", tostring(reason)) end
        return ok
    end
    while true do
        clear(C.background)
        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)
        put(4, 2, "NOTEPAD - " .. baseName(path) .. (dirty and " *" or ""), C.white)
        local maxLines = math.max(1, H - 9)
        local firstLine = math.max(1, math.min(cursorLine, #lines) - maxLines + 1)
        for i = firstLine, math.min(#lines, firstLine + maxLines - 1) do
            put(4, 4 + i - firstLine, lines[i], C.text)
        end
        local cy = 4 + cursorLine - firstLine
        local cx = math.min(W - 3, 4 + cursorColumn)
        put(cx, cy, "_", C.accent)
        center(H - 3, "CTRL+S: Save     ESC: Close     Arrows: Move", C.accent)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 1 then
                if dirty then
                    if confirmDialog("Unsaved changes", "Save changes before closing?") then save() end
                end
                return
            elseif code == 31 and (char == 115 or char == 83) then save()
            elseif code == 14 then
                if cursorColumn > 0 then
                    local line = lines[cursorLine]
                    lines[cursorLine] = line:sub(1, cursorColumn) .. line:sub(cursorColumn + 2)
                    cursorColumn = cursorColumn - 1; dirty = true
                elseif cursorLine > 1 then
                    local previous = lines[cursorLine - 1]
                    lines[cursorLine - 1] = previous .. lines[cursorLine]
                    cursorColumn = #previous; table.remove(lines, cursorLine); cursorLine = cursorLine - 1; dirty = true
                end
            elseif code == 28 then
                local line = lines[cursorLine]
                lines[cursorLine] = line:sub(1, cursorColumn)
                table.insert(lines, cursorLine + 1, line:sub(cursorColumn + 1))
                cursorLine, cursorColumn, dirty = cursorLine + 1, 0, true
            elseif code == 203 then cursorColumn = math.max(0, cursorColumn - 1)
            elseif code == 205 then cursorColumn = math.min(#lines[cursorLine], cursorColumn + 1)
            elseif code == 200 then cursorLine = math.max(1, cursorLine - 1); cursorColumn = math.min(cursorColumn, #lines[cursorLine])
            elseif code == 208 then cursorLine = math.min(#lines, cursorLine + 1); cursorColumn = math.min(cursorColumn, #lines[cursorLine])
            elseif char and char >= 32 and char <= 126 then
                local line = lines[cursorLine]
                lines[cursorLine] = line:sub(1, cursorColumn) .. string.char(char) .. line:sub(cursorColumn + 1)
                cursorColumn, dirty = cursorColumn + 1, true
            end
        end
    end
end

-- ------------------------- Files app ---------------------
local function filesApp()
    local currentDirectory, selectedIndex, scroll = "/", 1, 0
    while true do
        local entries, rows = listDirectory(currentDirectory), {}
        if currentDirectory ~= "/" then rows[#rows + 1] = {name = "..", path = parentPath(currentDirectory), directory = true, parent = true} end
        for i = 1, #entries do
            local path = joinPath(currentDirectory, entries[i])
            rows[#rows + 1] = {name = entries[i], path = path, directory = path and isDirectory(path) or false, parent = false}
        end
        selectedIndex = math.max(1, math.min(selectedIndex, math.max(1, #rows)))
        clear(C.background)
        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)
        put(4, 2, "FILES", C.white)
        put(4, 4, "Location: " .. currentDirectory, C.accent)
        put(4, 6, "Name", C.muted); put(W - 17, 6, "Type", C.muted)
        local visible = math.max(1, H - 13)
        if selectedIndex > scroll + visible then scroll = selectedIndex - visible end
        if selectedIndex <= scroll then scroll = selectedIndex - 1 end
        for row = 1, visible do
            local index, item = row + scroll, rows[row + scroll]
            if item then
                local y = 7 + row
                if index == selectedIndex then rect(3, y, W - 6, 1, C.selected) end
                local prefix = item.directory and "[DIR]  " or "[FILE] "
                put(4, y, prefix .. item.name, C.text)
                put(W - 17, y, item.directory and "Folder" or "File", C.muted)
            end
        end
        center(H - 5, "ENTER: Open   N: Folder   F: File   R: Rename", C.accent)
        center(H - 3, "C: Copy   X: Cut   V: Paste   D: Delete", C.muted)
        center(H - 2, "ESC: Desktop", C.muted)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 1 then return
            elseif code == 200 then selectedIndex = math.max(1, selectedIndex - 1)
            elseif code == 208 then selectedIndex = math.min(math.max(1, #rows), selectedIndex + 1)
            elseif code == 28 then
                local item = rows[selectedIndex]
                if item then
                    if item.directory then currentDirectory, selectedIndex, scroll = item.path, 1, 0
                    else local content = readFile(item.path); if content ~= nil then textEditor(item.path, content) else messageDialog("Open failed", "Could not read this file.") end end
                end
            elseif char == 110 or char == 78 then
                local name = inputDialog("New folder", "Enter folder name:")
                if name then local dest = joinPath(currentDirectory, name); local ok, reason = dest and createFolder(dest); if not ok then messageDialog("Folder error", tostring(reason or "Invalid name.")) end end
            elseif char == 102 or char == 70 then
                local name = inputDialog("New file", "Enter file name:")
                if name then local dest = joinPath(currentDirectory, name); local ok, reason = dest and createFile(dest, ""); if not ok then messageDialog("File error", tostring(reason or "Invalid name.")) end end
            elseif char == 114 or char == 82 then
                local item = rows[selectedIndex]
                if item and not item.parent then local name = inputDialog("Rename", "Enter the new name:"); if name then local ok, reason = renamePath(item.path, name); if not ok then messageDialog("Rename error", tostring(reason)) end end end
            elseif char == 99 or char == 67 then
                local item = rows[selectedIndex]; if item and not item.parent then clipboard, clipboardMode = item.path, "copy"; messageDialog("Copied", "Selected item is ready to paste.") end
            elseif char == 120 or char == 88 then
                local item = rows[selectedIndex]; if item and not item.parent then clipboard, clipboardMode = item.path, "cut"; messageDialog("Cut", "Selected item will be moved when pasted.") end
            elseif char == 118 or char == 86 then local ok, reason = pasteClipboard(currentDirectory); if not ok then messageDialog("Paste failed", tostring(reason)) end
            elseif char == 100 or char == 68 then
                local item = rows[selectedIndex]
                if item and not item.parent and confirmDialog("Delete item", "Delete " .. item.name .. "?") then local ok, reason = deletePath(item.path); if not ok then messageDialog("Delete failed", tostring(reason)) end; selectedIndex = 1 end
            end
        elseif signal == "touch" then
            -- OpenComputers touch tuple: signal,address,x,y,button,player.
            local tx, ty = tonumber(char), tonumber(code)
            if tx and ty and ty >= 8 and ty <= 7 + visible then
                local index = ty - 7 + scroll
                if rows[index] then
                    if selectedIndex == index then
                        local item = rows[index]
                        if item.directory then currentDirectory, selectedIndex, scroll = item.path, 1, 0
                        else local content = readFile(item.path); if content ~= nil then textEditor(item.path, content) end end
                    else selectedIndex = index end
                end
            end
        end
    end
end

-- ------------------------- Notes app ---------------------
local function notesApp()
    local content = readFile(NOTES_FILE) or ""
    while true do
        clear(C.background)
        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)
        put(4, 2, "MEADOWS NOTES", C.white)
        put(4, 4, "Saved automatically on this Meadows drive.", C.muted)
        local lines, lineNo = {}, 6
        for item in (content .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = item end
        local offset = math.max(1, #lines - (H - 12) + 1)
        for i = offset, #lines do
            if lineNo >= H - 6 then break end
            put(4, lineNo, lines[i], C.text); lineNo = lineNo + 1
        end
        center(H - 4, "A: Add note   E: Edit all notes   C: Clear notes", C.accent)
        center(H - 2, "ESC: Return to desktop", C.muted)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 1 then return
            elseif char == 97 or char == 65 then
                local note = inputDialog("Add note", "Write your note:")
                if note and note ~= "" then
                    if content ~= "" then content = content .. "\n" end
                    content = content .. note
                    local ok, reason = writeFile(NOTES_FILE, content)
                    if not ok then messageDialog("Notes error", tostring(reason)) end
                end
            elseif char == 101 or char == 69 then
                -- Open the full-page editor directly on the persistent notes file.
                textEditor(NOTES_FILE, content)
                content = readFile(NOTES_FILE) or content
            elseif char == 99 or char == 67 then
                if confirmDialog("Clear notes", "Delete all saved notes?") then content = ""; local ok, reason = writeFile(NOTES_FILE, content); if not ok then messageDialog("Notes error", tostring(reason)) end end
            end
        end
    end
end

-- ------------------------- Terminal ----------------------
local function terminalApp()
    local currentDirectory, history = "/", {}
    local function printLine(message, color)
        history[#history + 1] = {text = tostring(message), color = color or C.text}
        while #history > H - 9 do table.remove(history, 1) end
    end
    local function execute(command)
        local args = {}
        for word in command:gmatch("%S+") do args[#args + 1] = word end
        local cmd = args[1]
        if not cmd then return end
        if cmd == "help" then
            for _, line in ipairs({"help, clear, pwd, ls", "cd PATH, mkdir NAME, touch NAME", "cat NAME, rm NAME, rename OLD NEW", "whoami, about, reboot, shutdown"}) do printLine(line) end
        elseif cmd == "clear" then history = {}
        elseif cmd == "pwd" then printLine(currentDirectory)
        elseif cmd == "ls" then
            local entries = listDirectory(currentDirectory)
            if #entries == 0 then printLine("(empty)") end
            for _, name in ipairs(entries) do local p = joinPath(currentDirectory, name); printLine(name .. (p and isDirectory(p) and "/" or "")) end
        elseif cmd == "cd" then
            local target = args[2] or "/"
            local dest = target:sub(1, 1) == "/" and normalizePath(target) or normalizePath(currentDirectory .. "/" .. target)
            if pathExists(dest) and isDirectory(dest) and not isProtectedPath(dest) then currentDirectory = dest else printLine("Directory not found.", C.close) end
        elseif cmd == "mkdir" or cmd == "touch" then
            if not args[2] then printLine("Usage: " .. cmd .. " NAME", C.close)
            else
                local dest = joinPath(currentDirectory, args[2])
                local ok, reason
                if dest then if cmd == "mkdir" then ok, reason = createFolder(dest) else ok, reason = createFile(dest, "") end end
                if ok then printLine("Created.", C.accent) else printLine(reason or "Invalid name.", C.close) end
            end
        elseif cmd == "cat" then
            local dest = args[2] and joinPath(currentDirectory, args[2])
            if dest and pathExists(dest) and not isDirectory(dest) then printLine(readFile(dest) or "") else printLine("File not found.", C.close) end
        elseif cmd == "rm" then
            local dest = args[2] and joinPath(currentDirectory, args[2])
            if dest then local ok, reason = deletePath(dest); printLine(ok and "Deleted." or tostring(reason), ok and C.accent or C.close) else printLine("Usage: rm NAME", C.close) end
        elseif cmd == "rename" then
            local dest = args[2] and joinPath(currentDirectory, args[2])
            if dest and args[3] then local ok, reason = renamePath(dest, args[3]); printLine(ok and "Renamed." or tostring(reason), ok and C.accent or C.close) else printLine("Usage: rename OLD NEW", C.close) end
        elseif cmd == "whoami" then printLine(currentUser.username)
        elseif cmd == "about" then printLine("Meadows OS " .. VERSION .. " - Forest Edition")
        elseif cmd == "reboot" then computer.shutdown(true)
        elseif cmd == "shutdown" then computer.shutdown()
        else printLine("Unknown command: " .. cmd, C.close); printLine("Type help for commands.") end
    end
    while true do
        clear(C.background); rect(2, 2, W - 4, H - 4, C.panel); rect(2, 2, W - 4, 1, C.titlebar)
        put(4, 2, "MEADOWS TERMINAL", C.white)
        for i = 1, #history do put(4, 4 + i, history[i].text, history[i].color) end
        put(4, H - 4, currentDirectory .. " >", C.accent)
        local command = inputDialog("Terminal command", "Enter a command:")
        if command == nil then return elseif command ~= "" then execute(command) end
    end
end

-- ------------------------- Wallpaper / applications -------
local wallpapers = {0x102019, 0x101B30, 0x241B30, 0x202020, 0x0B2528}
local wallpaperNames = {"Forest", "Midnight", "Purple", "Dark", "Ocean"}
local function getWallpaper() return wallpapers[tonumber(config.wallpaper) or 1] or wallpapers[1] end

local apps = {
    {id = "files", name = "Files", icon = "F", run = filesApp},
    {id = "notes", name = "Notes", icon = "N", run = notesApp},
    {id = "terminal", name = "Terminal", icon = "T", run = terminalApp},
    {id = "settings", name = "Settings", icon = "S"},
    {id = "about", name = "About", icon = "?"}
}
local function findApp(id) for i = 1, #apps do if apps[i].id == id then return apps[i] end end end

local function settingsApp()
    local options = {"Computer name", "Change password", "Wallpaper", "Storage information", "System information", "Return to desktop"}
    local selection = 1
    while true do
        clear(C.background); rect(2, 2, W - 4, H - 4, C.panel); rect(2, 2, W - 4, 1, C.titlebar)
        put(4, 2, "MEADOWS SETTINGS", C.white); put(4, 4, "Personalize and manage your system.", C.muted)
        for i = 1, #options do local y = 7 + (i - 1) * 2; if i == selection then rect(3, y, W - 6, 1, C.selected) end; put(5, y, options[i], C.text) end
        center(H - 2, "UP/DOWN: Select     ENTER: Open     ESC: Back", C.muted)
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 1 then return
            elseif code == 200 then selection = math.max(1, selection - 1)
            elseif code == 208 then selection = math.min(#options, selection + 1)
            elseif code == 28 then
                if selection == 1 then
                    local name = inputDialog("Computer name", "Enter your new computer name:", false, config.computerName)
                    if name and name ~= "" then config.computerName = cleanValue(name); local ok, reason = saveConfig(); messageDialog(ok and "Settings saved" or "Save failed", ok and "Computer name updated." or tostring(reason)) end
                elseif selection == 2 then
                    local old = inputDialog("Current password", "Enter your current password:", true)
                    if old then
                        if verifyPassword(old, currentUser.passwordHash) then
                            local new = inputDialog("New password", "Enter your new password:", true)
                            if new and new ~= "" then
                                local confirm = inputDialog("Confirm password", "Enter your new password again:", true)
                                if confirm == new then
                                    local previous = currentUser.passwordHash
                                    currentUser.passwordHash = hashPassword(new)
                                    local ok, reason = saveAccounts()
                                    if ok then messageDialog("Password changed", "Your password has been updated.") else currentUser.passwordHash = previous; messageDialog("Save failed", tostring(reason)) end
                                else messageDialog("Password mismatch", "The new passwords do not match.") end
                            end
                        else messageDialog("Incorrect password", "Your current password was incorrect.") end
                    end
                elseif selection == 3 then
                    local wi = tonumber(config.wallpaper) or 1
                    while true do
                        clear(C.background); center(3, "CHOOSE WALLPAPER", C.accent)
                        for i = 1, #wallpaperNames do local y = 7 + (i - 1) * 2; if i == wi then rect(5, y, W - 10, 1, C.selected) end; put(7, y, wallpaperNames[i], C.white) end
                        center(H - 2, "UP/DOWN: Select     ENTER: Apply     ESC: Back", C.muted)
                        local s, a, ch, co = computer.pullSignal()
                        if s == "key_down" then
                            if co == 1 then break
                            elseif co == 200 then wi = math.max(1, wi - 1)
                            elseif co == 208 then wi = math.min(#wallpaperNames, wi + 1)
                            elseif co == 28 then config.wallpaper = wi; saveConfig(); messageDialog("Wallpaper updated", "Your desktop wallpaper has been changed."); break end
                        end
                    end
                elseif selection == 4 then
                    local free = math.max(0, selectedDisk.total - selectedDisk.used)
                    messageDialog("Storage information", "Drive: " .. selectedDisk.label .. "\nAddress: " .. STORAGE_ADDRESS .. "\nTotal: " .. math.floor(selectedDisk.total / 1024) .. " KB\nUsed: " .. math.floor(selectedDisk.used / 1024) .. " KB\nFree: " .. math.floor(free / 1024) .. " KB")
                elseif selection == 5 then
                    messageDialog("System information", "Operating system: Meadows OS\nVersion: " .. VERSION .. "\nEdition: Forest Edition\nComputer: " .. config.computerName .. "\nUser: " .. currentUser.username .. "\nMaximum open app slots: " .. MAX_WINDOWS)
                elseif selection == 6 then return end
            end
        end
    end
end

local function aboutApp()
    clear(C.background); rect(3, 3, W - 6, H - 6, C.panel); rect(3, 3, W - 6, 1, C.titlebar)
    center(6, "MEADOWS OS", C.accent); center(8, "FOREST EDITION", C.white)
    center(11, "Version " .. VERSION, C.text); center(13, "A desktop environment for OpenComputers.", C.muted)
    center(16, "Computer: " .. config.computerName, C.text); center(18, "User: " .. currentUser.displayName, C.text)
    center(H - 3, "Press any key to return", C.accent); waitForKey()
end

local function launchApp(id)
    if id == "settings" then settingsApp()
    elseif id == "about" then aboutApp()
    else local app = findApp(id); if app and app.run then app.run() end end
end

-- ------------------------- Start menu --------------------
local function startMenu()
    local items = {{name="Files",id="files"},{name="Notes",id="notes"},{name="Terminal",id="terminal"},{name="Settings",id="settings"},{name="About Meadows",id="about"},{name="Restart",id="restart"},{name="Shut down",id="shutdown"}}
    local selection = 1
    local menuWidth = math.min(34, W - 8)
    local menuX = math.floor((W - menuWidth) / 2)
    local menuY = math.max(1, H - 17)
    while true do
        clear(getWallpaper()); center(3, "MEADOWS", C.accent); center(5, "FOREST EDITION", C.muted)
        rect(menuX, menuY, menuWidth, math.min(15, H - menuY), C.panel); rect(menuX, menuY, menuWidth, 1, C.titlebar)
        put(menuX + 2, menuY, "START", C.white)
        for i = 1, #items do local y = menuY + 2 + i - 1; if y < H - 3 then if i == selection then rect(menuX + 1, y, menuWidth - 2, 1, C.selected) end; put(menuX + 3, y, items[i].name, C.text) end end
        put(menuX + 2, H - 4, currentUser.displayName, C.accent)
        put(menuX + 2, H - 2, "Meadows OS " .. VERSION, C.muted)
        local signal, address, first, second, third = computer.pullSignal()
        if signal == "key_down" then
            local char, code = first, second
            if code == 1 then return
            elseif code == 200 then selection = math.max(1, selection - 1)
            elseif code == 208 then selection = math.min(#items, selection + 1)
            elseif code == 28 then
                local id = items[selection].id
                if id == "restart" then computer.shutdown(true); return
                elseif id == "shutdown" then computer.shutdown(); return
                else launchApp(id); return end
            end
        elseif signal == "touch" then
            -- Touch event fields are address, x, y, button, player.
            local tx, ty = tonumber(first), tonumber(second)
            if tx and ty and ty >= menuY + 2 and ty <= menuY + 8 then
                local index = ty - menuY - 1
                if items[index] then
                    local id = items[index].id
                    if id == "restart" then computer.shutdown(true)
                    elseif id == "shutdown" then computer.shutdown()
                    else launchApp(id) end
                    return
                end
            end
            return
        end
    end
end

-- ------------------------- Desktop and taskbar ------------
local desktopIcons = {
    {id="files",name="Files",x=4,y=5},
    {id="notes",name="Notes",x=16,y=5},
    {id="terminal",name="Terminal",x=4,y=12},
    {id="settings",name="Settings",x=16,y=12},
    {id="about",name="About",x=4,y=19}
}
local selectedDesktopIcon = nil
local lastIconTap, lastIconIndex = 0, nil

local function drawDesktopIcon(icon, selected)
    local bg = selected and C.selected or C.panel2
    rect(icon.x, icon.y, 7, 3, bg)
    rect(icon.x + 2, icon.y + 1, 3, 1, selected and C.accent or C.accentDark)
    put(icon.x + 3, icon.y + 1, icon.id:sub(1, 1):upper(), C.white)
    local label = icon.name
    if selected then rect(icon.x - 1, icon.y + 3, #label + 2, 1, C.selected) end
    put(icon.x, icon.y + 3, label, C.text)
end

local function taskbarLayout()
    local items = {{id="start",label="M"},{id="files",label="F"},{id="notes",label="N"},{id="terminal",label="T"},{id="settings",label="S"}}
    local spacing = 7
    local total = #items * spacing - 1
    return items, {startX = math.max(2, math.floor((W - total) / 2)), spacing = spacing, y = H - 2}
end

local function drawTaskbar()
    local items, layout = taskbarLayout()
    rect(1, H - 2, W, 2, C.panel)
    for i = 1, #items do
        local x = layout.startX + (i - 1) * layout.spacing
        rect(x, H - 2, 5, 2, C.panel2)
        put(x + 2, H - 2, items[i].label, C.accent)
    end
    local clock = tostring(math.floor(computer.uptime())) .. "s"
    put(W - #clock - 2, H - 2, clock, C.muted)
    return items, layout
end

local function drawDesktop()
    clear(getWallpaper())
    put(4, 2, "MEADOWS", C.accent); put(4, 3, "FOREST EDITION", C.white)
    for i = 1, #desktopIcons do drawDesktopIcon(desktopIcons[i], selectedDesktopIcon == i) end
    put(4, H - 4, "Welcome, " .. currentUser.displayName, C.white)
    drawTaskbar()
end

local function desktop()
    while true do
        drawDesktop()
        -- OpenComputers key_down: signal,address,char,code,player.
        -- OpenComputers touch:    signal,address,x,y,button,player.
        local signal, address, first, second, third = computer.pullSignal()
        if signal == "key_down" then
            local char, code = first, second
            if code == 1 then startMenu()
            elseif char == 102 or char == 70 then launchApp("files")
            elseif char == 110 or char == 78 then launchApp("notes")
            elseif char == 116 or char == 84 then launchApp("terminal")
            elseif char == 115 or char == 83 then launchApp("settings")
            elseif char == 97 or char == 65 then launchApp("about") end
        elseif signal == "touch" then
            local x, y = tonumber(first), tonumber(second)
            if x and y then
                if y >= H - 2 then
                    local items, layout = taskbarLayout()
                    for i = 1, #items do
                        local bx = layout.startX + (i - 1) * layout.spacing
                        if x >= bx and x <= bx + 4 then
                            if items[i].id == "start" then startMenu() else launchApp(items[i].id) end
                            break
                        end
                    end
                else
                    for i = 1, #desktopIcons do
                        local icon = desktopIcons[i]
                        if x >= icon.x - 1 and x <= icon.x + 7 and y >= icon.y and y <= icon.y + 4 then
                            local now = computer.uptime()
                            if selectedDesktopIcon == i and lastIconIndex == i and now - lastIconTap <= 0.8 then
                                launchApp(icon.id)
                                selectedDesktopIcon, lastIconIndex = nil, nil
                            else
                                selectedDesktopIcon = i
                                lastIconIndex, lastIconTap = i, now
                            end
                            break
                        end
                    end
                end
            end
        end
    end
end

-- ------------------------- Final startup -----------------
clear(getWallpaper())
center(H - 2, "Loading Meadows desktop...", C.accent)
computer.pullSignal(0.4)
desktop()
