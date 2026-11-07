
-- ==========================================
-- CHANGE 4.5
-- MEADOWS OS 1.1
-- WINDOWS 11 + FOREST EDITION
-- Native OpenComputers BIOS Kernel
-- ==========================================

-- ==========================================
-- 1. HARDWARE AND BOOT SPLASH
-- ==========================================

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()

if not gpuAddress or not screenAddress then
    error("Meadows: GPU or screen missing")
end

local gpu = component.proxy(gpuAddress)
local computer = computer
gpu.bind(screenAddress)

local W, H = gpu.getResolution()

if W < 40 or H < 16 then
    error("Meadows: Minimum resolution is 40x16")
end

gpu.setDepth(8)

local DATA_DIR = "/.meadows"
local CONFIG_FILE = DATA_DIR .. "/system.cfg"
local ACCOUNTS_FILE = DATA_DIR .. "/accounts.db"
local NOTES_FILE = DATA_DIR .. "/notes.txt"
local STORAGE_ID_FILE = DATA_DIR .. "/storage.id"

local bootAddress = nil

if computer.getBootAddress then
    local ok, address = pcall(computer.getBootAddress)
    if ok then bootAddress = address end
end

local C = {
    background = 0x0B1511,
    desktop = 0x102019,
    panel = 0x172820,
    panel2 = 0x20382B,
    window = 0x192B22,
    titlebar = 0x294B38,
    accent = 0x72D69A,
    accentDark = 0x285C3D,
    text = 0xE8F5EC,
    muted = 0x9BB5A3,
    close = 0xE36F70,
    white = 0xFFFFFF,
    border = 0x365643,
    shadow = 0x080E0B
}

-- ==========================================
-- 2. WINDOWS-INSPIRED BOOT ANIMATION
-- ==========================================

local function bootSplash()
    local frames = {"|", "/", "-", "\\"}

    for frame = 1, 20 do
        gpu.setBackground(C.background)
        gpu.setForeground(C.text)
        gpu.fill(1, 1, W, H, " ")

        local logoX = math.floor(W / 2) - 4
        local logoY = math.floor(H / 2) - 5

        -- Meadows four-part logo
        gpu.setBackground(C.accentDark)
        gpu.fill(logoX, logoY, 3, 2, " ")
        gpu.fill(logoX + 4, logoY, 3, 2, " ")

        gpu.setBackground(C.accent)
        gpu.fill(logoX, logoY + 3, 3, 2, " ")
        gpu.fill(logoX + 4, logoY + 3, 3, 2, " ")

        gpu.setBackground(C.background)
        gpu.setForeground(C.white)

        local name = "MEADOWS"
        gpu.set(math.floor((W - #name) / 2) + 1,
            logoY + 6, name)

        gpu.setForeground(C.muted)
        local edition = "FOREST EDITION"
        gpu.set(math.floor((W - #edition) / 2) + 1,
            logoY + 8, edition)

        gpu.setForeground(C.accent)
        local loading = "Starting Meadows " ..
            frames[(frame - 1) % #frames + 1]

        gpu.set(math.floor((W - #loading) / 2) + 1,
            H - 3, loading)

        gpu.setForeground(C.muted)
        gpu.set(math.floor((W - 13) / 2) + 1,
            H - 1, "VERSION 1.1")

        computer.pullSignal(0.1)
    end
end

bootSplash()

-- ==========================================
-- 3. FILESYSTEM DISCOVERY
-- ==========================================

local function fsExists(fs, path)
    local ok, result = pcall(fs.exists, path)
    return ok and result == true
end

local function fsRead(fs, path)
    local ok, handle = pcall(fs.open, path, "r")
    if not ok or not handle then return nil end

    local result = ""

    while true do
        local readOK, data = pcall(fs.read, handle, 4096)

        if not readOK or not data or #data == 0 then
            break
        end

        result = result .. data
    end

    pcall(fs.close, handle)
    return result
end

local function fsWrite(fs, path, data)
    local ok, handle = pcall(fs.open, path, "w")
    if not ok or not handle then return false end

    local writeOK, result = pcall(fs.write, handle, data)
    pcall(fs.close, handle)

    if not writeOK or result == false then
        return false
    end

    return fsRead(fs, path) == data
end

local filesystems = {}

for address in component.list("filesystem") do
    -- Never use the filesystem we booted from as permanent storage.
    if address ~= bootAddress then
        local ok, fs = pcall(component.proxy, address)

        if ok and fs then
            local readOnly = true

            if fs.isReadOnly then
                local roOK, value = pcall(fs.isReadOnly)
                if roOK then readOnly = value end
            end

            local total = 0
            local used = 0
            local label = "Unnamed drive"

            if fs.spaceTotal then
                local good, value = pcall(fs.spaceTotal)
                if good then total = tonumber(value) or 0 end
            end

            if fs.spaceUsed then
                local good, value = pcall(fs.spaceUsed)
                if good then used = tonumber(value) or 0 end
            end

            if fs.getLabel then
                local good, value = pcall(fs.getLabel)
                if good and value and value ~= "" then
                    label = tostring(value)
                end
            end

            filesystems[#filesystems + 1] = {
                address = address,
                fs = fs,
                label = label,
                readOnly = readOnly,
                total = total,
                used = used
            }
        end
    end
end

if #filesystems == 0 then
    error("Meadows: No storage drives found. Install a hard drive.")
end

-- ==========================================
-- 4. DRIVE SELECTION SCREEN
-- ==========================================

local function chooseStorage()
    local choice = 1
    local scroll = 0

    while true do
        gpu.setBackground(C.background)
        gpu.setForeground(C.text)
        gpu.fill(1, 1, W, H, " ")

        gpu.setForeground(C.accent)
        local title = "WELCOME TO MEADOWS SETUP"
        gpu.set(math.floor((W - #title) / 2) + 1, 2, title)

        gpu.setForeground(C.white)
        local subtitle = "Choose your Meadows installation drive"
        gpu.set(math.floor((W - #subtitle) / 2) + 1, 4, subtitle)

        gpu.setForeground(C.muted)
        gpu.set(3, 6, "Select a writable hard drive:")

        local visible = math.max(1, H - 10)

        if choice <= scroll then
            scroll = choice - 1
        elseif choice > scroll + visible then
            scroll = choice - visible
        end

        for row = 1, visible do
            local index = scroll + row
            local disk = filesystems[index]

            if not disk then break end

            local y = 7 + row
            local free = math.max(0, disk.total - disk.used)

            if index == choice then
                gpu.setBackground(C.accentDark)
            else
                gpu.setBackground(C.panel)
            end

            gpu.fill(3, y, W - 6, 1, " ")

            gpu.setForeground(disk.readOnly and C.muted or C.white)

            local capacity

            if disk.total > 0 then
                capacity = tostring(math.floor(free / 1024)) ..
                    " KB free / " ..
                    tostring(math.floor(disk.total / 1024)) .. " KB"
            else
                capacity = "Capacity unknown"
            end

            local state = disk.readOnly and "READ ONLY" or "AVAILABLE"

            local entry = tostring(index) .. ". " ..
                disk.label .. " | " .. capacity .. " | " .. state

            gpu.set(4, y, entry:sub(1, W - 8))
        end

        gpu.setBackground(C.background)
        gpu.setForeground(C.accent)
        gpu.set(3, H - 3, "UP/DOWN: Select    ENTER: Confirm")

        gpu.setForeground(C.muted)
        gpu.set(3, H - 1, "Your accounts, settings and notes will be saved here.")

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 200 then
                choice = math.max(1, choice - 1)

            elseif code == 208 then
                choice = math.min(#filesystems, choice + 1)

            elseif char and char >= 49 and char <= 57 then
                local number = char - 48
                if filesystems[number] then
                    choice = number
                end

            elseif code == 28 or char == 13 then
                local disk = filesystems[choice]

                if disk and not disk.readOnly then
                    return disk
                end
            end
        end
    end
end

-- ==========================================
-- 5. RESTORE PREVIOUSLY SELECTED DRIVE
-- ==========================================

local selectedDisk = nil

for _, disk in ipairs(filesystems) do
    if not disk.readOnly and fsExists(disk.fs, STORAGE_ID_FILE) then
        local savedAddress = fsRead(disk.fs, STORAGE_ID_FILE)

        if savedAddress then
            savedAddress = savedAddress:gsub("%s+", "")

            if savedAddress == disk.address then
                selectedDisk = disk
                break
            end
        end
    end
end

-- If no saved drive exists, ask the user.
if not selectedDisk then
    selectedDisk = chooseStorage()
end

if not selectedDisk or selectedDisk.readOnly then
    error("Meadows: Selected drive is unavailable or read-only.")
end

local fsAddress = selectedDisk.address
local filesystem = selectedDisk.fs
local STORAGE_ADDRESS = fsAddress

-- ==========================================
-- 6. INITIALIZE PERSISTENT STORAGE
-- ==========================================

local existsOK, directoryExists = pcall(filesystem.exists, DATA_DIR)

if not existsOK then
    error("Meadows: Cannot inspect selected drive.")
end

if not directoryExists then
    local makeOK = pcall(filesystem.makeDirectory, DATA_DIR)

    if not makeOK or not fsExists(filesystem, DATA_DIR) then
        error("Meadows: Cannot create system directory on selected drive.")
    end
end

-- Test actual writing before saving user data.
local testPath = DATA_DIR .. "/storage-test.tmp"

if not fsWrite(filesystem, testPath, "MEADOWS STORAGE TEST") then
    error("Meadows: Selected drive failed its write test.")
end

pcall(filesystem.remove, testPath)

-- Save the selected drive's identity.
if not fsWrite(filesystem, STORAGE_ID_FILE, fsAddress) then
    error("Meadows: Could not save storage identity.")
end

-- ==========================================
-- 7. CONFIGURATION AND GRAPHICS
-- ==========================================

local OS_NAME = "Meadows"
local VERSION = "1.1"
local MAX_WINDOWS = 2

gpu.setDepth(8)
gpu.setBackground(C.background)
gpu.setForeground(C.text)
gpu.fill(1, 1, W, H, " ")

local function rect(x, y, w, h, color)
    x, y, w, h = math.floor(x), math.floor(y),
        math.floor(w), math.floor(h)

    if x < 1 then w, x = w - (1 - x), 1 end
    if y < 1 then h, y = h - (1 - y), 1 end
    if x + w - 1 > W then w = W - x + 1 end
    if y + h - 1 > H then h = H - y + 1 end

    if w <= 0 or h <= 0 then return end

    gpu.setBackground(color)
    gpu.fill(x, y, w, h, " ")
end

local function put(x, y, value, color)
    value = tostring(value or "")

    if y < 1 or y > H or x > W or x + #value - 1 < 1 then
        return
    end

    if x < 1 then
        value, x = value:sub(2 - x), 1
    end

    if x + #value - 1 > W then
        value = value:sub(1, W - x + 1)
    end

    if #value == 0 then return end

    gpu.setForeground(color or C.text)
    gpu.set(x, y, value)
end

local function center(y, value, color)
    value = tostring(value or "")
    put(math.floor((W - #value) / 2) + 1, y, value, color)
end

local function clear()
    rect(1, 1, W, H, C.background)
end

local function line(y)
    rect(2, y, W - 2, 1, C.titlebar)
end

-- ==========================================
-- 8. FILE STORAGE
-- ==========================================

local function readFile(path)
    return fsRead(filesystem, path)
end

local function writeFile(path, data)
    return fsWrite(filesystem, path, tostring(data or ""))
end

local function initializeStorage()
    if not fsExists(filesystem, DATA_DIR) then
        local ok = pcall(filesystem.makeDirectory, DATA_DIR)

        if not ok or not fsExists(filesystem, DATA_DIR) then
            error("Meadows: Storage initialization failed.")
        end
    end
end

initializeStorage()

-- ==========================================
-- 9. CONFIGURATION DATABASE
-- ==========================================

local config = {
    setupComplete = false,
    computerName = "MEADOWS-PC",
    theme = "forest"
}

local function loadConfig()
    local data = readFile(CONFIG_FILE)
    if not data then return end

    for key, value in data:gmatch("([%w_]+)=([^\r\n]*)") do
        if key == "setupComplete" then
            config.setupComplete = value == "true"
        elseif key == "computerName" then
            config.computerName = value
        elseif key == "theme" then
            config.theme = value
        end
    end
end

local function saveConfig()
    return writeFile(CONFIG_FILE,
        "setupComplete=" .. tostring(config.setupComplete) .. "\n" ..
        "computerName=" .. config.computerName .. "\n" ..
        "theme=" .. config.theme .. "\n")
end

loadConfig()

-- ==========================================
-- 10. ACCOUNT DATABASE
-- ==========================================

local accounts = {}

local function cleanField(value)
    return tostring(value or ""):gsub("[|\r\n]", "")
end

-- Prototype hash only; not cryptographically secure.
local function hashPassword(password, salt)
    local hash = 5381
    local input = salt .. password

    for i = 1, #input do
        hash = (hash * 33 + input:byte(i)) % 2147483647
    end

    return tostring(math.floor(hash))
end

local function saveAccounts()
    local output = ""

    for i = 1, #accounts do
        local a = accounts[i]

        output = output .. a.username .. "|" ..
            a.display .. "|" .. a.salt .. "|" ..
            a.hash .. "\n"
    end

    return writeFile(ACCOUNTS_FILE, output)
end

local function loadAccounts()
    accounts = {}

    local data = readFile(ACCOUNTS_FILE)
    if not data then return end

    for entry in data:gmatch("[^\r\n]+") do
        local username, display, salt, hash =
            entry:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")

        if username and display and salt and hash then
            accounts[#accounts + 1] = {
                username = username,
                display = display,
                salt = salt,
                hash = hash
            }
        end
    end
end

loadAccounts()

local function findAccount(username)
    username = tostring(username or ""):lower()

    for i = 1, #accounts do
        if accounts[i].username:lower() == username then
            return accounts[i]
        end
    end

    return nil
end

local function createAccount(username, display, password)
    username = cleanField(username)
    display = cleanField(display)
    password = tostring(password or "")

    if #username < 3 or #password < 4 then
        return false, "Username or password too short."
    end

    if username:find("[^%w_]") then
        return false, "Use only letters, numbers and underscores."
    end

    if findAccount(username) then
        return false, "That username already exists."
    end

    local salt = tostring(math.floor(computer.uptime() * 1000)) ..
        tostring(#accounts + 1)

    accounts[#accounts + 1] = {
        username = username,
        display = display,
        salt = salt,
        hash = hashPassword(password, salt)
    }

    if not saveAccounts() then
        accounts[#accounts] = nil
        return false, "Could not save account database."
    end

    return true
end

local function verifyPassword(account, password)
    if not account then return false end

    return hashPassword(
        tostring(password or ""), account.salt
    ) == account.hash
end

-- ==========================================
-- 11. INPUT AND MESSAGE DIALOGS
-- ==========================================

local function inputDialog(prompt, secret, multiline)
    local value = ""

    local panelW = math.min(W - 4, 50)
    local panelH = multiline and math.min(H - 4, 12) or 8

    local panelX = math.floor((W - panelW) / 2)
    local panelY = math.floor((H - panelH) / 2)

    local function drawDialog()
        rect(panelX, panelY, panelW, panelH, C.panel)
        rect(panelX, panelY, panelW, 2, C.titlebar)
        rect(panelX, panelY, panelW, 1, C.accentDark)

        put(panelX + 2, panelY, "MEADOWS", C.accent)
        put(panelX + panelW - 4, panelY, "X", C.close)
        put(panelX + 2, panelY + 3, prompt, C.text)

        rect(panelX + 2, panelY + 4,
            panelW - 4, multiline and 4 or 1, C.panel2)

        if multiline then
            local lines = {}

            for textLine in (value .. "\n"):gmatch("(.-)\n") do
                lines[#lines + 1] = textLine
            end

            local first = math.max(1, #lines - 3)

            for i = first, #lines do
                put(panelX + 3, panelY + 4 + i - first,
                    lines[i], C.white)
            end
        else
            local shown = secret and
                string.rep("*", #value) or value

            put(panelX + 3, panelY + 4, shown .. "_", C.white)
        end

        put(panelX + 2, panelY + panelH - 1,
            multiline and "CTRL+S: Save   ESC: Cancel" or
            "ENTER: Confirm   ESC: Cancel", C.muted)
    end

    while true do
        drawDialog()

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 or char == 27 then
                return nil

            elseif multiline and char == 19 then
                return value

            elseif char == 13 or code == 28 then
                if multiline then
                    value = value .. "\n"
                else
                    return value
                end

            elseif char == 8 or code == 14 then
                value = value:sub(1, -2)

            elseif char and char >= 32 and char <= 126 then
                if #value < (multiline and 1000 or 100) then
                    value = value .. string.char(char)
                end
            end
        end
    end
end

local function inputLine(prompt, secret)
    return inputDialog(prompt, secret, false)
end

local function inputMultiline(prompt)
    return inputDialog(prompt, false, true)
end

local function messageScreen(title, message)
    local panelW = math.min(W - 4, 50)
    local panelH = 7

    local panelX = math.floor((W - panelW) / 2)
    local panelY = math.floor((H - panelH) / 2)

    rect(panelX, panelY, panelW, panelH, C.panel)
    rect(panelX, panelY, panelW, 2, C.titlebar)

    put(panelX + 2, panelY, title, C.accent)
    put(panelX + 2, panelY + 3, message, C.text)
    put(panelX + 2, panelY + 5,
        "Press any key to continue", C.muted)

    while true do
        local signal = computer.pullSignal()
        if signal == "key_down" then break end
    end
end

-- ==========================================
-- 12. FIRST-TIME SETUP WIZARD
-- ==========================================

local function setupWizard()
    clear()

    center(3, OS_NAME .. " 1.1", C.accent)
    center(5, "FIRST-TIME SETUP", C.white)
    center(8, "Welcome to your new Meadows computer.", C.text)
    center(10, "Your selected drive is ready.", C.muted)
    center(H - 2, "Press any key to begin", C.accent)

    while true do
        local signal = computer.pullSignal()
        if signal == "key_down" then break end
    end

    local pcName = inputLine("Choose a computer name", false) or "MEADOWS-PC"

    pcName = cleanField(pcName):gsub("[^%w_%-]", "")

    if #pcName < 2 then
        pcName = "MEADOWS-PC"
    end

    local username = inputLine("Create administrator username", false) or "admin"
    username = cleanField(username)

    if #username < 3 or username:find("[^%w_]") or findAccount(username) then
        username = "admin"

        local suffix = 1

        while findAccount(username) do
            suffix = suffix + 1
            username = "admin" .. tostring(suffix)
        end
    end

    local display = inputLine("Enter your display name", false)

    if not display or display == "" then
        display = username
    end

    display = cleanField(display)

    local password

    while true do
        password = inputLine(
            "Create a password (minimum 4 characters)", true)

        if not password or #password < 4 then
            messageScreen("Password required",
                "Please create a password with at least 4 characters.")
        else
            local confirm = inputLine("Confirm your password", true)

            if confirm == password then
                break
            end

            messageScreen("Passwords do not match",
                "Please try again.")
        end
    end

    clear()

    center(2, "MEADOWS TERMS AND CONDITIONS", C.accent)
    line(4)

    put(3, 6, "1. Meadows is an independent operating system.")
    put(3, 8, "2. You are responsible for your computer's data.")
    put(3, 10, "3. Do not modify system files without backups.")
    put(3, 12, "4. Local passwords provide prototype-level security.")
    put(3, 14, "5. Meadows is provided as-is.")

    center(H - 2, "Type ACCEPT to agree.", C.accent)

    local accepted = inputLine("Type ACCEPT to continue", false)

    while accepted ~= "ACCEPT" do
        if accepted then
            messageScreen("Terms not accepted",
                "You must type ACCEPT to continue.")
        end

        accepted = inputLine("Type ACCEPT to continue", false)
    end

    local ok, reason = createAccount(username, display, password)

    if not ok then
        error("Meadows setup: " .. tostring(reason))
    end

    config.computerName = pcName
    config.setupComplete = true

    if not saveConfig() then
        error("Meadows: Could not save system configuration.")
    end

    messageScreen("Setup complete",
        "Your Meadows computer is ready.")
end

-- Existing accounts are authoritative.
if #accounts == 0 then
    setupWizard()

elseif not config.setupComplete then
    config.setupComplete = true

    if not saveConfig() then
        error("Meadows: Could not repair system configuration.")
    end
end

-- ==========================================
-- 13. LOGIN SYSTEM
-- ==========================================

local currentUser = nil
local loginAttempts = 0

local function loginScreen()
    while not currentUser do
        clear()

        rect(1, 1, W, H, C.background)

        local logoX = math.floor(W / 2) - 3
        local logoY = 3

        rect(logoX, logoY, 2, 2, C.accentDark)
        rect(logoX + 3, logoY, 2, 2, C.accentDark)
        rect(logoX, logoY + 3, 2, 2, C.accent)
        rect(logoX + 3, logoY + 3, 2, 2, C.accent)

        center(logoY + 6, config.computerName, C.white)
        center(logoY + 8, "MEADOWS OS 1.1", C.accent)

        local username = inputLine("Username", false)

        if not username then
            username = ""
        end

        local account = findAccount(username)

        if account then
            local password = inputLine("Password", true)

            if password and verifyPassword(account, password) then
                currentUser = account
                loginAttempts = 0
            else
                loginAttempts = loginAttempts + 1
                messageScreen("Login failed", "Incorrect password.")
            end
        else
            loginAttempts = loginAttempts + 1
            messageScreen("Login failed", "Account not found.")
        end
    end
end

loginScreen()

-- ==========================================
-- 14. WINDOW MANAGER
-- ==========================================

local windows = {}
local activeWindow = nil
local nextWindowID = 1

local function windowCount()
    return #windows
end

local function findWindow(id)
    for i = 1, #windows do
        if windows[i].id == id then
            return windows[i], i
        end
    end

    return nil
end

local function closeWindow(id)
    for i = #windows, 1, -1 do
        if windows[i].id == id then
            table.remove(windows, i)

            if activeWindow == id then
                activeWindow = nil

                if #windows > 0 then
                    activeWindow = windows[#windows].id
                end
            end

            return true
        end
    end

    return false
end

local function minimizeWindow(id)
    local win = findWindow(id)

    if not win then return end

    win.minimized = true

    if activeWindow == id then
        activeWindow = nil

        for i = #windows, 1, -1 do
            if not windows[i].minimized then
                activeWindow = windows[i].id
                break
            end
        end
    end
end

local function restoreWindow(id)
    local win = findWindow(id)

    if not win then return end

    win.minimized = false
    activeWindow = id
end

local function focusWindow(id)
    local win = findWindow(id)

    if not win then return end

    win.minimized = false
    activeWindow = id

    for i = 1, #windows do
        if windows[i].id == id then
            local selected = table.remove(windows, i)
            windows[#windows + 1] = selected
            break
        end
    end
end

local function openWindow(title, app, data)
    local existing = nil

    -- Only one window per app.
    for i = 1, #windows do
        if windows[i].app == app then
            existing = windows[i]
            break
        end
    end

    if existing then
        restoreWindow(existing.id)
        focusWindow(existing.id)
        return existing
    end

    if windowCount() >= MAX_WINDOWS then
        messageScreen("Window limit",
            "Only two windows can be open at once.")
        return nil
    end

    local win = {
        id = nextWindowID,
        title = title,
        app = app,
        data = data or {},
        minimized = false,
        x = 4 + (#windows * 3),
        y = 3 + (#windows * 2),
        width = math.min(W - 8, 54),
        height = math.min(H - 8, 19)
    }

    nextWindowID = nextWindowID + 1

    windows[#windows + 1] = win
    activeWindow = win.id

    return win
end

-- ==========================================
-- 15. FILESYSTEM HELPERS
-- ==========================================

local function normalizePath(path)
    path = tostring(path or "/")

    if path == "" then
        return "/"
    end

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

local function joinPath(parent, name)
    parent = normalizePath(parent)
    name = tostring(name or ""):gsub("/", "")

    if parent == "/" then
        return "/" .. name
    end

    return parent .. "/" .. name
end

local function isProtectedPath(path)
    path = normalizePath(path)

    return path == DATA_DIR or
        path:sub(1, #DATA_DIR + 1) == DATA_DIR .. "/"
end

local function listDirectory(path)
    path = normalizePath(path)

    local ok, iterator = pcall(filesystem.list, path)

    if not ok or not iterator then
        return {}
    end

    local result = {}

    while true do
        local readOK, item = pcall(iterator)

        if not readOK or not item then
            break
        end

        item = tostring(item):gsub("/$", "")

        if item ~= "" and item ~= "." and item ~= ".." then
            result[#result + 1] = item
        end
    end

    table.sort(result, function(a, b)
        local pa = joinPath(path, a)
        local pb = joinPath(path, b)

        local da = filesystem.isDirectory(pa)
        local db = filesystem.isDirectory(pb)

        if da ~= db then
            return da
        end

        return a:lower() < b:lower()
    end)

    return result
end

local function readTextFile(path)
    path = normalizePath(path)

    if not fsExists(filesystem, path) then
        return nil
    end

    return readFile(path)
end

local function writeTextFile(path, contents)
    path = normalizePath(path)

    if isProtectedPath(path) then
        return false, "Protected system folder."
    end

    local parent = path:match("^(.*)/[^/]+$")

    if parent and parent ~= "" and not fsExists(filesystem, parent) then
        return false, "Parent folder does not exist."
    end

    if filesystem.isDirectory(path) then
        return false, "Cannot write to a folder."
    end

    if not writeFile(path, contents) then
        return false, "Could not write file."
    end

    return true
end

local function createFolder(path)
    path = normalizePath(path)

    if isProtectedPath(path) then
        return false, "Protected system folder."
    end

    if fsExists(filesystem, path) then
        return false, "That name already exists."
    end

    local parent = path:match("^(.*)/[^/]+$")

    if parent and parent ~= "" and not fsExists(filesystem, parent) then
        return false, "Parent folder does not exist."
    end

    local ok, result = pcall(filesystem.makeDirectory, path)

    if not ok or result == false or not fsExists(filesystem, path) then
        return false, "Could not create folder."
    end

    return true
end

local function deletePath(path)
    path = normalizePath(path)

    if path == "/" or isProtectedPath(path) then
        return false, "This location is protected."
    end

    if not fsExists(filesystem, path) then
        return false, "File or folder not found."
    end

    local ok, result = pcall(filesystem.remove, path)

    if not ok or result == false then
        return false, "Could not delete item."
    end

    return true
end

local function renamePath(oldPath, newPath)
    oldPath = normalizePath(oldPath)
    newPath = normalizePath(newPath)

    if oldPath == "/" or isProtectedPath(oldPath) or
        isProtectedPath(newPath) then
        return false, "This location is protected."
    end

    if not fsExists(filesystem, oldPath) then
        return false, "Original item not found."
    end

    if fsExists(filesystem, newPath) then
        return false, "Destination already exists."
    end

    local ok, result = pcall(filesystem.rename, oldPath, newPath)

    if not ok or result == false then
        return false, "Rename failed."
    end

    return true
end

-- ==========================================
-- 16. FILE COPY AND CUT
-- ==========================================

local function copyFileContents(source, destination)
    local data = readTextFile(source)

    if data == nil then
        return false, "Could not read source file."
    end

    return writeTextFile(destination, data)
end

local function copyDirectory(source, destination)
    if not fsExists(filesystem, source) then
        return false, "Source not found."
    end

    if not filesystem.isDirectory(source) then
        return copyFileContents(source, destination)
    end

    local ok, reason = createFolder(destination)

    if not ok then
        return false, reason
    end

    local children = listDirectory(source)

    for i = 1, #children do
        local name = children[i]

        local childSource = joinPath(source, name)
        local childDestination = joinPath(destination, name)

        local copied, copyError = copyDirectory(
            childSource, childDestination)

        if not copied then
            return false, copyError
        end
    end

    return true
end

local clipboard = {
    path = nil,
    mode = nil
}

local function clipboardCopy(path)
    path = normalizePath(path)

    if isProtectedPath(path) then
        return false, "Cannot copy protected system files."
    end

    if not fsExists(filesystem, path) then
        return false, "Item not found."
    end

    clipboard.path = path
    clipboard.mode = "copy"

    return true
end

local function clipboardCut(path)
    path = normalizePath(path)

    if path == "/" or isProtectedPath(path) then
        return false, "Cannot cut this item."
    end

    if not fsExists(filesystem, path) then
        return false, "Item not found."
    end

    clipboard.path = path
    clipboard.mode = "cut"

    return true
end

local function clipboardPaste(destination)
    if not clipboard.path or not clipboard.mode then
        return false, "Clipboard is empty."
    end

    destination = normalizePath(destination)

    if not filesystem.isDirectory(destination) then
        return false, "Destination is not a folder."
    end

    local name = clipboard.path:match("([^/]+)$")

    if not name then
        return false, "Invalid source."
    end

    local target = joinPath(destination, name)

    if target == clipboard.path then
        return false, "Source and destination are the same."
    end

    if fsExists(filesystem, target) then
        return false, "An item with that name already exists."
    end

    if clipboard.mode == "cut" then
        local ok, reason = renamePath(clipboard.path, target)

        if ok then
            clipboard.path = nil
            clipboard.mode = nil
        end

        return ok, reason
    end

    return copyDirectory(clipboard.path, target)
end

-- ==========================================
-- 17. FILES APP
-- ==========================================

local function filesApp()
    local currentPath = "/"
    local selectedIndex = 1
    local scroll = 0
    local contextOpen = false

    local function drawFiles()
        clear()

        put(2, 1, "MEADOWS FILES", C.accent)
        put(W - 13, 1, "[ESC] Close", C.muted)

        rect(2, 3, W - 4, 2, C.panel)
        put(4, 3, "Location: " .. currentPath, C.white)

        local entries = listDirectory(currentPath)

        local visible = H - 9

        if selectedIndex < 1 then selectedIndex = 1 end

        if selectedIndex > #entries and #entries > 0 then
            selectedIndex = #entries
        end

        if selectedIndex <= scroll then
            scroll = selectedIndex - 1
        elseif selectedIndex > scroll + visible then
            scroll = selectedIndex - visible
        end

        if currentPath ~= "/" then
            put(4, 6, "..", C.accent)
        end

        for i = 1, visible do
            local index = scroll + i
            local name = entries[index]

            if not name then break end

            local fullPath = joinPath(currentPath, name)
            local isDirectory = filesystem.isDirectory(fullPath)

            local y = 6 + i

            if index == selectedIndex then
                rect(3, y, W - 6, 1, C.accentDark)
            end

            local prefix = isDirectory and "[DIR] " or "[FILE] "
            put(4, y, prefix .. name, C.text)
        end

        rect(2, H - 2, W - 4, 1, C.panel)
        put(3, H - 2,
            "ENTER Open | N New | D Delete | R Rename | C Copy | X Cut | V Paste",
            C.muted)
    end

    local function askName(prompt)
        local name = inputLine(prompt, false)

        if not name or name == "" then
            return nil
        end

        if name:find("/") or name == "." or name == ".." then
            messageScreen("Invalid name", "Choose a valid file or folder name.")
            return nil
        end

        return name
    end

    while true do
        drawFiles()

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                return

            elseif code == 200 then
                selectedIndex = math.max(1, selectedIndex - 1)

            elseif code == 208 then
                selectedIndex = math.min(
                    #listDirectory(currentPath),
                    selectedIndex + 1)

            elseif code == 28 then
                local entries = listDirectory(currentPath)

                if currentPath ~= "/" and selectedIndex == 1 then
                    currentPath = currentPath:match("^(.*)/[^/]+$") or "/"
                    selectedIndex = 1
                    scroll = 0
                else
                    local index = selectedIndex

                    if currentPath ~= "/" then
                        index = index - 1
                    end

                    local name = entries[index]

                    if name then
                        local path = joinPath(currentPath, name)

                        if filesystem.isDirectory(path) then
                            currentPath = path
                            selectedIndex = 1
                            scroll = 0
                        else
                            local data = readTextFile(path)

                            if data then
                                local preview = data:sub(1, 1500)
                                messageScreen(name, preview)
                            end
                        end
                    end
                end

            elseif char == 110 then
                local name = askName("New folder name")

                if name then
                    local ok, reason = createFolder(
                        joinPath(currentPath, name))

                    if not ok then
                        messageScreen("Create folder", reason)
                    end
                end

            elseif char == 102 then
                local name = askName("New file name")

                if name then
                    local ok, reason = writeTextFile(
                        joinPath(currentPath, name), "")

                    if not ok then
                        messageScreen("Create file", reason)
                    end
                end

            elseif char == 100 then
                local entries = listDirectory(currentPath)
                local index = selectedIndex

                if currentPath ~= "/" then
                    index = index - 1
                end

                local name = entries[index]

                if name then
                    local answer = inputLine(
                        "Type DELETE to confirm", false)

                    if answer == "DELETE" then
                        local ok, reason = deletePath(
                            joinPath(currentPath, name))

                        if not ok then
                            messageScreen("Delete failed", reason)
                        else
                            selectedIndex = math.max(1, selectedIndex - 1)
                        end
                    end
                end

            elseif char == 114 then
                local entries = listDirectory(currentPath)
                local index = selectedIndex

                if currentPath ~= "/" then
                    index = index - 1
                end

                local name = entries[index]

                if name then
                    local newName = askName("New name")

                    if newName then
                        local ok, reason = renamePath(
                            joinPath(currentPath, name),
                            joinPath(currentPath, newName))

                        if not ok then
                            messageScreen("Rename failed", reason)
                        end
                    end
                end

            elseif char == 99 then
                local entries = listDirectory(currentPath)
                local index = selectedIndex

                if currentPath ~= "/" then
                    index = index - 1
                end

                local name = entries[index]

                if name then
                    local ok, reason = clipboardCopy(
                        joinPath(currentPath, name))

                    if not ok then
                        messageScreen("Copy failed", reason)
                    end
                end

            elseif char == 120 then
                local entries = listDirectory(currentPath)
                local index = selectedIndex

                if currentPath ~= "/" then
                    index = index - 1
                end

                local name = entries[index]

                if name then
                    local ok, reason = clipboardCut(
                        joinPath(currentPath, name))

                    if not ok then
                        messageScreen("Cut failed", reason)
                    end
                end

            elseif char == 118 then
                local ok, reason = clipboardPaste(currentPath)

                if not ok then
                    messageScreen("Paste failed", reason)
                end
            end
        end
    end
end

-- ==========================================
-- 18. NOTES APP
-- ==========================================

local function notesApp()
    local notes = readFile(NOTES_FILE) or ""
    local cursor = #notes + 1
    local scroll = 0

    local function saveNotes()
        if not writeFile(NOTES_FILE, notes) then
            messageScreen("Notes", "Could not save notes.")
            return false
        end

        return true
    end

    local function drawNotes()
        clear()

        put(2, 1, "MEADOWS NOTES", C.accent)
        put(W - 13, 1, "[ESC] Close", C.muted)

        rect(2, 3, W - 4, H - 7, C.panel)

        local lines = {}

        for textLine in (notes .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = textLine
        end

        local visible = H - 10

        if cursor > #notes then
            local cursorLine = 1

            for _ in notes:gmatch("\n") do
                cursorLine = cursorLine + 1
            end

            if cursorLine > visible then
                scroll = cursorLine - visible
            end
        end

        for i = 1, visible do
            local lineIndex = scroll + i

            if lines[lineIndex] then
                put(4, 4 + i, lines[lineIndex], C.text)
            end
        end

        rect(2, H - 3, W - 4, 1, C.titlebar)
        put(3, H - 3, "CTRL+S Save | ENTER New line | ESC Close", C.white)
    end

    while true do
        drawNotes()

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                saveNotes()
                return

            elseif char == 19 then
                saveNotes()

            elseif code == 28 then
                notes = notes .. "\n"
                cursor = #notes + 1

            elseif code == 14 then
                if #notes > 0 then
                    notes = notes:sub(1, -2)
                    cursor = #notes + 1
                end

            elseif char and char >= 32 and char <= 126 then
                if #notes < 10000 then
                    notes = notes .. string.char(char)
                    cursor = #notes + 1
                end
            end
        end
    end
end

-- ==========================================
-- 19. TERMINAL APP
-- ==========================================

local function terminalApp()
    local history = {}
    local currentPath = "/"

    local function terminalPrint(message, color)
        history[#history + 1] = {
            text = tostring(message),
            color = color or C.text
        }

        while #history > H - 7 do
            table.remove(history, 1)
        end
    end

    local function executeCommand(command)
        local args = {}

        for word in command:gmatch("%S+") do
            args[#args + 1] = word
        end

        local cmd = args[1] or ""

        if cmd == "" then
            return

        elseif cmd == "help" then
            terminalPrint("Meadows Terminal commands:", C.accent)
            terminalPrint("help, clear, ls, pwd, cd")
            terminalPrint("mkdir, touch, cat, write, rm")
            terminalPrint("whoami, hostname, storage, date")

        elseif cmd == "clear" then
            history = {}

        elseif cmd == "pwd" then
            terminalPrint(currentPath)

        elseif cmd == "whoami" then
            terminalPrint(currentUser.username, C.accent)

        elseif cmd == "hostname" then
            terminalPrint(config.computerName)

        elseif cmd == "date" then
            terminalPrint("Uptime: " .. tostring(math.floor(computer.uptime())) .. " seconds")

        elseif cmd == "storage" then
            terminalPrint("Drive: " .. STORAGE_ADDRESS)
            terminalPrint("Label: " .. selectedDisk.label)
            terminalPrint("Used: " .. tostring(selectedDisk.used))
            terminalPrint("Total: " .. tostring(selectedDisk.total))

        elseif cmd == "ls" then
            local entries = listDirectory(currentPath)

            for i = 1, #entries do
                local path = joinPath(currentPath, entries[i])
                local suffix = filesystem.isDirectory(path) and "/" or ""

                terminalPrint(entries[i] .. suffix)
            end

        elseif cmd == "cd" then
            local target = args[2] or "/"

            if target == ".." then
                currentPath = currentPath:match("^(.*)/[^/]+$") or "/"
            else
                local path

                if target:sub(1, 1) == "/" then
                    path = normalizePath(target)
                else
                    path = joinPath(currentPath, target)
                end

                if fsExists(filesystem, path) and
                    filesystem.isDirectory(path) then
                    currentPath = path
                else
                    terminalPrint("Directory not found.", C.close)
                end
            end

        elseif cmd == "mkdir" then
            local name = args[2]

            if not name then
                terminalPrint("Usage: mkdir foldername", C.muted)
            else
                local ok, reason = createFolder(
                    joinPath(currentPath, name))

                terminalPrint(ok and "Folder created." or reason,
                    ok and C.accent or C.close)
            end

        elseif cmd == "touch" then
            local name = args[2]

            if not name then
                terminalPrint("Usage: touch filename", C.muted)
            else
                local ok, reason = writeTextFile(
                    joinPath(currentPath, name), "")

                terminalPrint(ok and "File created." or reason,
                    ok and C.accent or C.close)
            end

        elseif cmd == "cat" then
            local name = args[2]

            if not name then
                terminalPrint("Usage: cat filename", C.muted)
            else
                local data = readTextFile(joinPath(currentPath, name))

                if data then
                    terminalPrint(data)
                else
                    terminalPrint("File not found.", C.close)
                end
            end

        elseif cmd == "write" then
            local name = args[2]
            local content = table.concat(args, " ", 3)

            if not name then
                terminalPrint("Usage: write filename text", C.muted)
            else
                local ok, reason = writeTextFile(
                    joinPath(currentPath, name), content)

                terminalPrint(ok and "File saved." or reason,
                    ok and C.accent or C.close)
            end

        elseif cmd == "rm" then
            local name = args[2]

            if not name then
                terminalPrint("Usage: rm filename", C.muted)
            else
                local ok, reason = deletePath(
                    joinPath(currentPath, name))

                terminalPrint(ok and "Removed." or reason,
                    ok and C.accent or C.close)
            end

        else
            terminalPrint("Unknown command: " .. cmd, C.close)
        end
    end

    while true do
        clear()

        put(2, 1, "MEADOWS TERMINAL", C.accent)
        put(W - 13, 1, "[ESC] Close", C.muted)

        rect(2, 3, W - 4, H - 6, C.panel)

        for i = 1, #history do
            put(4, 3 + i, history[i].text, history[i].color)
        end

        rect(2, H - 2, W - 4, 1, C.titlebar)
        put(3, H - 2, currentPath .. " >", C.accent)

        local command = inputLine(
            currentPath .. " >", false)

        if command == nil then
            return
        end

        executeCommand(command)
    end
end

-- ==========================================
-- 20. SETTINGS APP
-- ==========================================

local function settingsApp()
    while true do
        clear()

        center(2, "MEADOWS SETTINGS", C.accent)
        center(4, "Manage your computer", C.muted)

        put(4, 7, "1. Change computer name", C.text)
        put(4, 9, "2. Change display name", C.text)
        put(4, 11, "3. Change password", C.text)
        put(4, 13, "4. Storage information", C.text)
        put(4, 15, "5. About Meadows", C.text)

        center(H - 2, "Press 1-5 or ESC to close", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                return

            elseif char == 49 then
                local name = inputLine("New computer name", false)

                if name and name ~= "" then
                    config.computerName =
                        cleanField(name):gsub("[^%w_%-]", "")

                    if not saveConfig() then
                        messageScreen("Settings", "Could not save settings.")
                    end
                end

            elseif char == 50 then
                local display = inputLine("New display name", false)

                if display and display ~= "" then
                    currentUser.display = cleanField(display)

                    if not saveAccounts() then
                        messageScreen("Settings", "Could not save account.")
                    end
                end

            elseif char == 51 then
                local oldPassword = inputLine("Current password", true)

                if verifyPassword(currentUser, oldPassword) then
                    local newPassword = inputLine("New password", true)

                    if newPassword and #newPassword >= 4 then
                        local confirm = inputLine("Confirm new password", true)

                        if confirm == newPassword then
                            local oldHash = currentUser.hash
                            local oldSalt = currentUser.salt

                            currentUser.salt =
                                tostring(math.floor(computer.uptime() * 1000))

                            currentUser.hash =
                                hashPassword(newPassword, currentUser.salt)

                            if not saveAccounts() then
                                currentUser.hash = oldHash
                                currentUser.salt = oldSalt
                                messageScreen("Settings", "Could not save password.")
                            else
                                messageScreen("Settings", "Password changed.")
                            end
                        else
                            messageScreen("Settings", "Passwords do not match.")
                        end
                    else
                        messageScreen("Settings", "Password must be at least 4 characters.")
                    end
                else
                    messageScreen("Settings", "Current password incorrect.")
                end

            elseif char == 52 then
                messageScreen("Storage",
                    "Drive: " .. selectedDisk.label ..
                    " | Used: " .. tostring(selectedDisk.used) ..
                    " | Total: " .. tostring(selectedDisk.total))

            elseif char == 53 then
                messageScreen("About Meadows",
                    "Meadows OS 1.1 - Forest Edition")
            end
        end
    end
end

-- ==========================================
-- 21. ABOUT APP
-- ==========================================

local function aboutApp()
    clear()

    center(3, "MEADOWS OS", C.accent)
    center(5, "Version 1.1 - Forest Edition", C.white)

    center(8, "An independent OpenComputers operating system.", C.text)
    center(10, "Designed for a simple desktop experience.", C.muted)
    center(12, "Storage: " .. selectedDisk.label, C.muted)

    center(H - 2, "Press any key to close", C.accent)

    while true do
        local signal = computer.pullSignal()

        if signal == "key_down" then
            break
        end
    end
end

-- ==========================================
-- 22. APP REGISTRY
-- ==========================================

local apps = {
    {
        name = "Files",
        icon = "▣",
        description = "Browse your files",
        run = filesApp
    },
    {
        name = "Notes",
        icon = "▤",
        description = "Write your notes",
        run = notesApp
    },
    {
        name = "Terminal",
        icon = ">_",
        description = "Command terminal",
        run = terminalApp
    },
    {
        name = "Settings",
        icon = "⚙",
        description = "System settings",
        run = settingsApp
    },
    {
        name = "About",
        icon = "i",
        description = "About Meadows",
        run = aboutApp
    }
}

local function findApp(name)
    for i = 1, #apps do
        if apps[i].name:lower() == tostring(name):lower() then
            return apps[i]
        end
    end

    return nil
end

local function launchApp(name)
    local app = findApp(name)

    if not app then
        return false
    end

    -- The application runs as a foreground app.
    -- Part 3 supplies the desktop and taskbar around it.
    app.run()

    return true
end

-- ==========================================
-- CHANGE 4.4
-- PART 3 OF 3
-- DESKTOP AND MAIN EVENT LOOP
-- ==========================================

-- ==========================================
-- 23. DESKTOP STATE
-- ==========================================

local desktopSelection = 1
local desktopScroll = 0
local desktopMenuOpen = false
local desktopMenuSelection = 1
local desktopMenuItems = {
    "Files",
    "Notes",
    "Terminal",
    "Settings",
    "About",
    "Log out",
    "Restart",
    "Shutdown"
}

local running = true
local clockText = "MEADOWS"

-- ==========================================
-- 24. DESKTOP ICON LAYOUT
-- ==========================================

local function drawDesktopIcon(x, y, icon, name, selected)
    if selected then
        rect(x - 1, y - 1, 9, 5, C.accentDark)
    end

    rect(x + 1, y, 5, 3, C.panel2)
    put(x + 3, y + 1, icon, C.accent)

    local label = tostring(name)
    if #label > 9 then
        label = label:sub(1, 8) .. "."
    end

    put(x - 1, y + 4, label, C.white)
end

local function desktopColumns()
    return math.max(1, math.floor((W - 4) / 12))
end

local function drawDesktopIcons()
    local columns = desktopColumns()
    local startY = 3
    local rowGap = 7

    for i = 1, #apps do
        local index = i - desktopScroll

        if index > 0 then
            local col = (index - 1) % columns
            local row = math.floor((index - 1) / columns)

            local x = 3 + col * 12
            local y = startY + row * rowGap

            if y < H - 6 then
                drawDesktopIcon(
                    x,
                    y,
                    apps[i].icon,
                    apps[i].name,
                    desktopSelection == i
                )
            end
        end
    end
end

-- ==========================================
-- 25. TASKBAR
-- ==========================================

local function drawTaskbar()
    local taskbarY = H - 3

    rect(1, taskbarY, W, 3, C.panel)

    -- Top border
    rect(1, taskbarY, W, 1, C.border)

    local items = {
        {name = "Start", icon = "M"},
        {name = "Files", icon = "F"},
        {name = "Notes", icon = "N"},
        {name = "Terminal", icon = ">_"},
        {name = "Settings", icon = "S"}
    }

    local totalWidth = 0

    for i = 1, #items do
        totalWidth = totalWidth + #items[i].icon + 4
    end

    local startX = math.floor((W - totalWidth) / 2) + 1

    for i = 1, #items do
        local item = items[i]
        local itemWidth = #item.icon + 4

        rect(startX, taskbarY + 1, itemWidth, 2, C.panel2)
        put(startX + 2, taskbarY + 1, item.icon, C.accent)

        startX = startX + itemWidth + 1
    end

    -- Clock / status on right
    put(W - 13, taskbarY + 1, "MEADOWS", C.accent)
    put(W - 13, taskbarY + 2, "v1.1", C.muted)
end

-- ==========================================
-- 26. START MENU
-- ==========================================

local function drawStartMenu()
    local menuW = math.min(34, W - 4)
    local menuH = math.min(15, H - 5)

    local x = math.floor((W - menuW) / 2)
    local y = H - menuH - 3

    rect(x, y, menuW, menuH, C.panel)
    rect(x, y, menuW, 2, C.titlebar)

    put(x + 2, y, "MEADOWS START", C.accent)
    put(x + 2, y + 3, "Welcome, " .. currentUser.display, C.white)

    local visible = menuH - 6

    for i = 1, #desktopMenuItems do
        local row = y + 5 + i

        if row >= y + menuH - 1 then
            break
        end

        if desktopMenuSelection == i then
            rect(x + 1, row, menuW - 2, 1, C.accentDark)
        end

        put(x + 3, row, desktopMenuItems[i], C.text)
    end
end

-- ==========================================
-- 27. DESKTOP DRAWING
-- ==========================================

local function drawDesktop()
    rect(1, 1, W, H, C.desktop)

    -- Subtle forest-style background
    for y = 1, H - 4 do
        if y % 4 == 0 then
            rect(1, y, W, 1, C.background)
        end
    end

    put(3, 1, "MEADOWS", C.accent)
    put(12, 1, config.computerName, C.muted)

    drawDesktopIcons()
    drawTaskbar()

    if desktopMenuOpen then
        drawStartMenu()
    end
end

-- ==========================================
-- 28. DESKTOP APP LAUNCHER
-- ==========================================

local function runDesktopApp(index)
    local app = apps[index]

    if not app then
        return
    end

    clear()

    local ok, err = pcall(app.run)

    if not ok then
        messageScreen(
            "Application error",
            tostring(err):sub(1, 100)
        )
    end
end

-- ==========================================
-- 29. START MENU ACTIONS
-- ==========================================

local function handleStartMenu()
    local selected = desktopMenuItems[desktopMenuSelection]

    if selected == "Log out" then
        currentUser = nil
        desktopMenuOpen = false
        loginScreen()

    elseif selected == "Restart" then
        computer.shutdown(true)

    elseif selected == "Shutdown" then
        computer.shutdown(false)

    else
        desktopMenuOpen = false

        if selected == "Files" then
            runDesktopApp(1)
        elseif selected == "Notes" then
            runDesktopApp(2)
        elseif selected == "Terminal" then
            runDesktopApp(3)
        elseif selected == "Settings" then
            runDesktopApp(4)
        elseif selected == "About" then
            runDesktopApp(5)
        end
    end
end

-- ==========================================
-- 30. TASKBAR ACTIONS
-- ==========================================

local function handleTaskbarClick(x)
    local items = {
        "Start",
        "Files",
        "Notes",
        "Terminal",
        "Settings"
    }

    local totalWidth = 0

    for i = 1, #items do
        totalWidth = totalWidth + #items[i] + 4
    end

    local startX = math.floor((W - totalWidth) / 2) + 1

    for i = 1, #items do
        local itemWidth = #items[i] + 4

        if x >= startX and x <= startX + itemWidth then
            if items[i] == "Start" then
                desktopMenuOpen = not desktopMenuOpen
                return
            end

            desktopMenuOpen = false

            if items[i] == "Files" then
                runDesktopApp(1)
            elseif items[i] == "Notes" then
                runDesktopApp(2)
            elseif items[i] == "Terminal" then
                runDesktopApp(3)
            elseif items[i] == "Settings" then
                runDesktopApp(4)
            end

            return
        end

        startX = startX + itemWidth + 1
    end
end

-- ==========================================
-- 31. DESKTOP KEYBOARD CONTROLS
-- ==========================================

local function handleDesktopKey(char, code)
    if desktopMenuOpen then
        if code == 1 then
            desktopMenuOpen = false

        elseif code == 200 then
            desktopMenuSelection =
                math.max(1, desktopMenuSelection - 1)

        elseif code == 208 then
            desktopMenuSelection =
                math.min(#desktopMenuItems, desktopMenuSelection + 1)

        elseif code == 28 then
            handleStartMenu()
        end

        return
    end

    if code == 200 then
        desktopSelection =
            math.max(1, desktopSelection - 1)

    elseif code == 208 then
        desktopSelection =
            math.min(#apps, desktopSelection + 1)

    elseif code == 203 then
        desktopSelection =
            math.max(1, desktopSelection - 1)

    elseif code == 205 then
        desktopSelection =
            math.min(#apps, desktopSelection + 1)

    elseif code == 28 then
        runDesktopApp(desktopSelection)

    elseif char == 27 then
        desktopMenuOpen = true
        desktopMenuSelection = 1

    elseif char == 49 then
        runDesktopApp(1)

    elseif char == 50 then
        runDesktopApp(2)

    elseif char == 51 then
        runDesktopApp(3)

    elseif char == 52 then
        runDesktopApp(4)

    elseif char == 53 then
        runDesktopApp(5)
    end
end

-- ==========================================
-- 32. MOUSE SUPPORT
-- ==========================================

local function handleMouse(x, y, button)
    if y >= H - 3 then
        handleTaskbarClick(x)
        return
    end

    if desktopMenuOpen then
        local menuW = math.min(34, W - 4)
        local menuH = math.min(15, H - 5)

        local menuX = math.floor((W - menuW) / 2)
        local menuY = H - menuH - 3

        if x >= menuX and x <= menuX + menuW and
            y >= menuY + 6 and y < menuY + menuH - 1 then

            desktopMenuSelection = y - menuY - 5
            handleStartMenu()
        else
            desktopMenuOpen = false
        end

        return
    end

    if y < 3 or y >= H - 6 then
        return
    end

    local columns = desktopColumns()
    local row = math.floor((y - 3) / 7)
    local col = math.floor((x - 3) / 12)

    local index = row * columns + col + 1 + desktopScroll

    if index >= 1 and index <= #apps then
        desktopSelection = index

        if button == 0 then
            runDesktopApp(index)
        end
    end
end

-- ==========================================
-- 33. SYSTEM STATUS
-- ==========================================

local function drawSystemStatus()
    local freeMemory = 0

    if computer.freeMemory then
        local ok, result = pcall(computer.freeMemory)

        if ok then
            freeMemory = tonumber(result) or 0
        end
    end

    put(2, H - 4,
        "User: " .. currentUser.username ..
        " | Free RAM: " .. tostring(math.floor(freeMemory / 1024)) .. " KB",
        C.muted)
end

-- ==========================================
-- 34. MAIN DESKTOP LOOP
-- ==========================================

local function desktopLoop()
    while running do
        drawDesktop()
        drawSystemStatus()

        local signal, address, x, y, button = computer.pullSignal(0.1)

        if signal == "key_down" then
            handleDesktopKey(x, y)

        elseif signal == "touch" then
            handleMouse(x, y, button)

        elseif signal == "interrupted" then
            -- Ignore Ctrl+C so the desktop does not terminate.
        end
    end
end

-- ==========================================
-- 35. START MEADOWS
-- ==========================================

local function startMeadows()
    while true do
        if not currentUser then
            loginScreen()
        end

        desktopLoop()

        if not running then
            break
        end
    end
end

local success, errorMessage = pcall(startMeadows)

if not success then
    gpu.setBackground(C.background)
    gpu.setForeground(C.close)
    gpu.fill(1, 1, W, H, " ")

    center(math.floor(H / 2) - 2, "MEADOWS SYSTEM ERROR", C.close)
    center(math.floor(H / 2), tostring(errorMessage):sub(1, W - 4), C.text)
    center(math.floor(H / 2) + 2, "Restart the computer to try again.", C.muted)

    computer.pullSignal()
end

-- ==========================================
-- END OF MEADOWS OS 1.1
-- ==========================================
