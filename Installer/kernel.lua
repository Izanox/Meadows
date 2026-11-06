-- ==========================================
-- CHANGE 2.0
-- MEADOWS OS 0.5
-- FOREST EDITION
-- Native OpenComputers BIOS Kernel
-- ==========================================

-- 1. HARDWARE
local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()
if not gpuAddress or not screenAddress then
    error("Meadows: GPU or screen missing")
end

local gpu = component.proxy(gpuAddress)
gpu.bind(screenAddress)
local W, H = gpu.getResolution()
if W < 40 or H < 16 then
    error("Meadows: Minimum resolution is 40x16")
end

local computer = computer
local fsAddress = component.list("filesystem")()
if not fsAddress then error("Meadows: No filesystem found") end
local filesystem = component.proxy(fsAddress)

-- 2. CONFIGURATION
local OS_NAME = "Meadows"
local VERSION = "0.5"
local DATA_DIR = "/.meadows"
local CONFIG_FILE = DATA_DIR .. "/system.cfg"
local ACCOUNTS_FILE = DATA_DIR .. "/accounts.db"
local NOTES_FILE = DATA_DIR .. "/notes.txt"

local C = {
    background = 0x0B1511, desktop = 0x102019,
    panel = 0x172820, panel2 = 0x20382B,
    window = 0x192B22, titlebar = 0x294B38,
    accent = 0x72D69A, accentDark = 0x285C3D,
    text = 0xE8F5EC, muted = 0x9BB5A3,
    close = 0xE36F70, white = 0xFFFFFF,
    border = 0x365643, shadow = 0x080E0B
}

gpu.setDepth(8)
gpu.setBackground(C.background)
gpu.setForeground(C.text)
gpu.fill(1, 1, W, H, " ")

-- 3. GRAPHICS
local function rect(x, y, w, h, color)
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
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
    if y < 1 or y > H or x > W or x + #value - 1 < 1 then return end
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

local function clear()
    rect(1, 1, W, H, C.background)
end

local function line(y)
    rect(2, y, W - 2, 1, C.titlebar)
end

-- 4. FILE STORAGE
local function readFile(path)
    local ok, handle = pcall(filesystem.open, path, "r")
    if not ok or not handle then return nil end
    local result = ""
    while true do
        local success, data = pcall(filesystem.read, handle, 4096)
        if not success or not data or #data == 0 then break end
        result = result .. data
    end
    pcall(filesystem.close, handle)
    return result
end

local function writeFile(path, data)
    local ok, handle = pcall(filesystem.open, path, "w")
    if not ok or not handle then return false end
    local success, result = pcall(filesystem.write, handle, data)
    pcall(filesystem.close, handle)
    return success and result ~= false
end

local function initializeStorage()
    local ok, exists = pcall(filesystem.exists, DATA_DIR)
    if not ok then error("Meadows: Cannot check system directory") end
    if not exists then
        pcall(filesystem.makeDirectory, DATA_DIR)
        local checkOK, created = pcall(filesystem.exists, DATA_DIR)
        if not checkOK or not created then error("Meadows: Cannot create system directory") end
    end
end
initializeStorage()

-- 5. CONFIGURATION DATABASE
local config = { setupComplete = false, computerName = "MEADOWS-PC", theme = "forest" }

local function loadConfig()
    local data = readFile(CONFIG_FILE)
    if not data then return end
    for key, value in data:gmatch("([%w_]+)=([^\r\n]*)") do
        if key == "setupComplete" then config.setupComplete = value == "true"
        elseif key == "computerName" then config.computerName = value
        elseif key == "theme" then config.theme = value end
    end
end

local function saveConfig()
    return writeFile(CONFIG_FILE,
        "setupComplete=" .. tostring(config.setupComplete) .. "\n" ..
        "computerName=" .. config.computerName .. "\n" ..
        "theme=" .. config.theme .. "\n")
end
loadConfig()

-- 6. ACCOUNT DATABASE
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
        output = output .. a.username .. "|" .. a.display .. "|" ..
            a.salt .. "|" .. a.hash .. "\n"
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
                username = username, display = display, salt = salt, hash = hash
            }
        end
    end
end
loadAccounts()

local function findAccount(username)
    username = tostring(username or ""):lower()
    for i = 1, #accounts do
        if accounts[i].username:lower() == username then return accounts[i] end
    end
    return nil
end

local function createAccount(username, display, password)
    username, display = cleanField(username), cleanField(display)
    password = tostring(password or "")
    if #username < 3 or #password < 4 then return false, "Username or password too short." end
    if username:find("[^%w_]") then return false, "Use only letters, numbers and underscores." end
    if findAccount(username) then return false, "That username already exists." end

    local salt = tostring(math.floor(computer.uptime() * 1000)) .. tostring(#accounts + 1)
    accounts[#accounts + 1] = {
        username = username, display = display,
        salt = salt, hash = hashPassword(password, salt)
    }
    if not saveAccounts() then
        accounts[#accounts] = nil
        return false, "Could not save account database."
    end
    return true
end

local function verifyPassword(account, password)
    if not account then return false end
    return hashPassword(tostring(password or ""), account.salt) == account.hash
end

-- 7. INPUT AND MESSAGE DIALOGS
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
        rect(panelX + 2, panelY + 4, panelW - 4, multiline and 4 or 1, C.panel2)

        if multiline then
            local lines = {}
            for textLine in (value .. "\n"):gmatch("(.-)\n") do
                lines[#lines + 1] = textLine
            end
            local first = math.max(1, #lines - 3)
            for i = first, #lines do
                put(panelX + 3, panelY + 4 + i - first, lines[i], C.white)
            end
        else
            local shown = secret and string.rep("*", #value) or value
            put(panelX + 3, panelY + 4, shown .. "_", C.white)
        end

        put(panelX + 2, panelY + panelH - 1,
            multiline and "CTRL+S: Save   ESC: Cancel" or "ENTER: Confirm   ESC: Cancel",
            C.muted)
    end

    while true do
        drawDialog()
        local signal, address, char, code = computer.pullSignal()
        if signal == "key_down" then
            if code == 1 or char == 27 then return nil
            elseif multiline and char == 19 then return value
            elseif char == 13 or code == 28 then
                if multiline then value = value .. "\n" else return value end
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
    put(panelX + 2, panelY + 5, "Press any key to continue", C.muted)
    while true do
        local signal = computer.pullSignal()
        if signal == "key_down" then break end
    end
end

-- 8. SETUP WIZARD
local function setupWizard()
    clear()
    center(3, OS_NAME, C.accent)
    center(5, "FIRST-TIME SETUP", C.white)
    center(8, "Welcome to your new Meadows computer.", C.text)
    center(10, "Let's configure your system.", C.muted)
    center(H - 2, "Press any key to begin", C.accent)
    while true do
        local signal = computer.pullSignal()
        if signal == "key_down" then break end
    end

    local pcName = inputLine("Choose a computer name", false) or "MEADOWS-PC"
    pcName = cleanField(pcName):gsub("[^%w_%-]", "")
    if #pcName < 2 then pcName = "MEADOWS-PC" end

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
    if not display or display == "" then display = username end
    display = cleanField(display)

    local password
    while true do
        password = inputLine("Create a password (minimum 4 characters)", true)
        if not password or #password < 4 then
            messageScreen("Password required", "Please create a password with at least 4 characters.")
        else
            local confirm = inputLine("Confirm your password", true)
            if confirm == password then break end
            messageScreen("Passwords do not match", "Please try again.")
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
        if accepted then messageScreen("Terms not accepted", "You must type ACCEPT to continue.") end
        accepted = inputLine("Type ACCEPT to continue", false)
    end

    local ok, reason = createAccount(username, display, password)
    if not ok then error("Meadows setup: " .. tostring(reason)) end
    config.computerName = pcName
    config.setupComplete = true
    if not saveConfig() then error("Meadows: Could not save system configuration") end
    messageScreen("Setup complete", "Your Meadows computer is ready.")
end

if not config.setupComplete or #accounts == 0 then setupWizard() end

-- 9. LOGIN
local currentUser = nil

local function loginScreen()
    while true do
        clear()
        center(3, OS_NAME, C.accent)
        center(5, config.computerName, C.muted)
        center(8, "SELECT YOUR ACCOUNT", C.white)

        for i = 1, #accounts do
            put(5, 10 + i, tostring(i) .. ". " .. accounts[i].display ..
                " (" .. accounts[i].username .. ")")
        end

        center(H - 2, "Enter account number or ESC to power off", C.muted)
        local choice = inputLine("Account number", false)
        if not choice then computer.shutdown() return end

        local index = tonumber(choice)
        if index and accounts[index] then
            local account = accounts[index]
            local password = inputLine("Password for " .. account.display, true)
            if password and verifyPassword(account, password) then
                currentUser = account
                return
            end
            messageScreen("Login failed", "Incorrect password.")
        else
            messageScreen("Account not found", "Choose a valid account number.")
        end
    end
end
loginScreen()

-- 10. WINDOW MANAGER
local windows = {}
local nextID = 0
local selected = nil
local menuOpen = false
local running = true
local dragState = nil

local function getWindow(id)
    for i = 1, #windows do
        if windows[i].id == id then return windows[i], i end
    end
end

local function getSelectedWindow()
    return getWindow(selected)
end

local function closeWindow(id)
    local _, index = getWindow(id)
    if index then
        table.remove(windows, index)
        selected = windows[#windows] and windows[#windows].id or nil
    end
end

local function bringToFront(index)
    local win = table.remove(windows, index)
    if not win then return end
    windows[#windows + 1] = win
    selected = win.id
end

local function newWindow(title, width, height, content)
    for i = 1, #windows do
        if windows[i].title == title then
            windows[i].minimized = false
            windows[i].content = content
            bringToFront(i)
            return
        end
    end

    if #windows >= 2 then
        table.remove(windows, 1)
    end

    width = math.min(width, W - 4)
    height = math.min(height, H - 5)
    nextID = nextID + 1

    local win = {
        id = nextID, title = title,
        x = math.floor((W - width) / 2),
        y = math.max(2, math.floor((H - height - 2) / 2)),
        w = width, h = height, content = content,
        minimized = false, maximized = false
    }
    windows[#windows + 1] = win
    selected = win.id
end

local function maximizeWindow(win)
    if not win.maximized then
        win.oldX, win.oldY, win.oldW, win.oldH = win.x, win.y, win.w, win.h
        win.x, win.y, win.w, win.h = 2, 2, W - 3, H - 5
        win.maximized = true
    else
        win.x, win.y, win.w, win.h = win.oldX, win.oldY, win.oldW, win.oldH
        win.maximized = false
    end
end

-- 11. USER MANAGEMENT
local function addUser()
    local username = inputLine("New username", false)
    if not username or username == "" then return end
    local display = inputLine("New display name", false)
    if not display or display == "" then display = username end
    local password = inputLine("New password (minimum 4 characters)", true)
    if not password or #password < 4 then
        messageScreen("Invalid password", "Password must contain at least 4 characters.")
        return
    end
    local confirm = inputLine("Confirm new password", true)
    if confirm ~= password then
        messageScreen("Password mismatch", "The passwords did not match.")
        return
    end
    local ok, reason = createAccount(username, display, password)
    if ok then messageScreen("Account created", "The new account was saved.")
    else messageScreen("Could not create account", tostring(reason)) end
end

local function changeComputerName()
    local name = inputLine("New computer name", false)
    if not name or name == "" then return end
    name = cleanField(name):gsub("[^%w_%-]", "")
    if #name < 2 then
        messageScreen("Invalid name", "Please choose a longer name.")
        return
    end
    local old = config.computerName
    config.computerName = name
    if saveConfig() then messageScreen("Settings saved", "Computer name updated.")
    else config.computerName = old messageScreen("Save failed", "Could not save settings.") end
end

local function changePassword()
    local oldPassword = inputLine("Current password", true)
    if not verifyPassword(currentUser, oldPassword or "") then
        messageScreen("Password incorrect", "Your current password was not accepted.")
        return
    end
    local newPassword = inputLine("New password", true)
    if not newPassword or #newPassword < 4 then
        messageScreen("Invalid password", "Password must have at least 4 characters.")
        return
    end
    local confirm = inputLine("Confirm new password", true)
    if confirm ~= newPassword then
        messageScreen("Password mismatch", "The passwords did not match.")
        return
    end

    local oldSalt, oldHash = currentUser.salt, currentUser.hash
    currentUser.salt = tostring(math.floor(computer.uptime() * 1000)) .. tostring(#accounts + 10)
    currentUser.hash = hashPassword(newPassword, currentUser.salt)
    if saveAccounts() then
        messageScreen("Password changed", "Your new password has been saved.")
    else
        currentUser.salt, currentUser.hash = oldSalt, oldHash
        messageScreen("Save failed", "Could not save the password.")
    end
end

-- 12. APPLICATIONS
local function openAbout()
    newWindow("About Meadows", 42, 13, function(win)
        put(win.x + 2, win.y + 3, "MEADOWS OPERATING SYSTEM", C.accent)
        put(win.x + 2, win.y + 5, "Version: " .. VERSION)
        put(win.x + 2, win.y + 6, "Edition: Forest")
        put(win.x + 2, win.y + 7, "Computer: " .. config.computerName)
        put(win.x + 2, win.y + 8, "User: " .. currentUser.username)
        put(win.x + 2, win.y + 10, "Platform: OpenComputers BIOS", C.muted)
    end)
end

local function openMonitor()
    newWindow("System Monitor", 42, 14, function(win)
        put(win.x + 2, win.y + 3, "SYSTEM INFORMATION", C.accent)
        put(win.x + 2, win.y + 5, "Total RAM: " .. math.floor(computer.totalMemory() / 1024) .. " KB")
        put(win.x + 2, win.y + 6, "Free RAM: " .. math.floor(computer.freeMemory() / 1024) .. " KB")
        put(win.x + 2, win.y + 7, "Uptime: " .. math.floor(computer.uptime()) .. " seconds")
        put(win.x + 2, win.y + 8, "Resolution: " .. W .. "x" .. H)
        put(win.x + 2, win.y + 10, "Filesystem: " .. fsAddress:sub(1, 8), C.muted)
    end)
end

-- 13. FILE MANAGER
local fileState = { path = "/", entries = {}, scroll = 0, selected = 1 }

local function refreshFiles()
    fileState.entries = {}
    local ok, iterator = pcall(filesystem.list, fileState.path)
    if not ok or not iterator then return false end

    if type(iterator) == "function" then
        while true do
            local success, name = pcall(iterator)
            if not success or not name then break end
            fileState.entries[#fileState.entries + 1] = tostring(name)
        end
    elseif type(iterator) == "table" then
        for _, name in pairs(iterator) do
            fileState.entries[#fileState.entries + 1] = tostring(name)
        end
    end

    table.sort(fileState.entries)
    fileState.scroll = 0
    if fileState.selected > #fileState.entries then fileState.selected = #fileState.entries end
    if fileState.selected < 1 then fileState.selected = 1 end
    return true
end

local function joinPath(base, name)
    if base == "/" then return "/" .. name:gsub("^/+", "") end
    return base:gsub("/+$", "") .. "/" .. name:gsub("^/+", "")
end

local function selectedFile()
    return fileState.entries[fileState.selected]
end

local function openFiles()
    fileState.path = "/"
    fileState.selected = 1
    refreshFiles()

    newWindow("Files", 48, 17, function(win)
        put(win.x + 2, win.y + 2, "PATH: " .. fileState.path, C.accent)
        put(win.x + 2, win.y + 4, "NAME", C.muted)
        put(win.x + win.w - 12, win.y + 4, "TYPE", C.muted)
        rect(win.x + 1, win.y + 5, win.w - 2, 1, C.border)

        local visible = math.max(1, win.h - 8)
        for row = 1, visible do
            local index = fileState.scroll + row
            local name = fileState.entries[index]
            if not name then break end
            local y = win.y + 5 + row
            if index == fileState.selected then rect(win.x + 1, y, win.w - 2, 1, C.accentDark) end
            local folder = name:sub(-1) == "/"
            put(win.x + 2, y, folder and "[+] " or "[ ]", C.accent)
            put(win.x + 7, y, name, C.text)
            put(win.x + win.w - 12, y, folder and "Folder" or "File", C.muted)
        end

        put(win.x + 2, win.y + win.h - 2, "ENTER Open  BACKSPACE Back  N New folder", C.accent)
        put(win.x + 2, win.y + win.h - 1, tostring(#fileState.entries) .. " items", C.muted)
    end)
end

local function openSelectedFile()
    local name = selectedFile()
    if not name then return end
    local path = joinPath(fileState.path, name)
    if name:sub(-1) == "/" then
        fileState.path = path
        fileState.selected = 1
        refreshFiles()
    else
        local data = readFile(path)
        if data == nil then
            messageScreen("Cannot open file", "This file could not be read as text.")
            return
        end
        newWindow("File: " .. name, 48, 15, function(win)
            put(win.x + 2, win.y + 2, path, C.accent)
            local lines, row = 0, win.y + 4
            for textLine in (data .. "\n"):gmatch("(.-)\n") do
                if row >= win.y + win.h - 2 then break end
                put(win.x + 2, row, textLine)
                row, lines = row + 1, lines + 1
            end
            put(win.x + 2, win.y + win.h - 1, "Text preview", C.muted)
        end)
    end
end

local function createFolder()
    local name = inputLine("New folder name", false)
    if not name or name == "" then return end
    name = name:gsub("[/\\]", "")
    if name == "" then return end
    local path = joinPath(fileState.path, name)
    local ok, result = pcall(filesystem.makeDirectory, path)
    if not ok or result == false then messageScreen("Folder failed", "Could not create the folder.") end
    refreshFiles()
end

local function renameSelected()
    local oldName = selectedFile()
    if not oldName then return end
    local newName = inputLine("New name", false)
    if not newName or newName == "" then return end
    newName = newName:gsub("[/\\]", "")
    local oldPath = joinPath(fileState.path, oldName)
    local newPath = joinPath(fileState.path, newName)
    local ok, result = pcall(filesystem.rename, oldPath, newPath)
    if not ok or result == false then messageScreen("Rename failed", "Could not rename this item.") end
    refreshFiles()
end

local function deleteSelected()
    local name = selectedFile()
    if not name then return end
    local confirm = inputLine("Type DELETE to remove " .. name, false)
    if confirm ~= "DELETE" then return end
    local path = joinPath(fileState.path, name)
    local ok, result = pcall(filesystem.remove, path)
    if not ok or result == false then messageScreen("Delete failed", "Could not remove this item.") end
    refreshFiles()
end

-- 14. NOTES
local function openNotes()
    newWindow("Meadows Notes", 46, 15, function(win)
        put(win.x + 2, win.y + 3, "PERSONAL NOTES", C.accent)
        local notes = readFile(NOTES_FILE) or ""
        if notes == "" then
            put(win.x + 2, win.y + 5, "No notes saved yet.", C.muted)
        else
            local row = win.y + 5
            for textLine in notes:gmatch("[^\r\n]+") do
                if row >= win.y + win.h - 2 then break end
                put(win.x + 2, row, textLine)
                row = row + 1
            end
        end
        put(win.x + 2, win.y + win.h - 2, "E - Add note", C.accent)
    end)
end

local function editNotes()
    local newNote = inputMultiline("Write note (CTRL+S to save)")
    if not newNote or newNote == "" then return end
    local oldNotes = readFile(NOTES_FILE) or ""
    if oldNotes ~= "" then oldNotes = oldNotes .. "\n" end
    if not writeFile(NOTES_FILE, oldNotes .. newNote) then
        messageScreen("Save failed", "Could not save your note.")
    end
end

-- 15. TERMINAL AND SETTINGS
local function openTerminal()
    newWindow("Meadows Terminal", 46, 15, function(win)
        put(win.x + 2, win.y + 3, "MEADOWS SHELL", C.accent)
        put(win.x + 2, win.y + 5, "T - Type a command", C.text)
        put(win.x + 2, win.y + 7, "Commands: help, about, monitor, files, notes, clear", C.muted)
        put(win.x + 2, win.y + 10, "Interactive shell prototype", C.accent)
    end)
end

local function runTerminalCommand()
    local command = inputLine("Meadows command", false)
    if not command then return end
    command = command:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if command == "help" then
        messageScreen("Terminal help", "about, monitor, files, notes, clear, logout, shutdown")
    elseif command == "about" then openAbout()
    elseif command == "monitor" then openMonitor()
    elseif command == "files" then openFiles()
    elseif command == "notes" then openNotes()
    elseif command == "clear" then
        local win = getSelectedWindow()
        if win and win.title == "Meadows Terminal" then win.content = function(w) put(w.x + 2, w.y + 3, "Terminal cleared.", C.muted) end end
    elseif command == "logout" then logout()
    elseif command == "shutdown" then shutdown()
    else messageScreen("Unknown command", "Type help to see available commands.") end
end

local function openSettings()
    newWindow("Meadows Settings", 46, 16, function(win)
        put(win.x + 2, win.y + 3, "SYSTEM SETTINGS", C.accent)
        put(win.x + 2, win.y + 5, "Computer: " .. config.computerName)
        put(win.x + 2, win.y + 6, "Signed in: " .. currentUser.display)
        put(win.x + 2, win.y + 8, "A - Add a user")
        put(win.x + 2, win.y + 9, "C - Change computer name")
        put(win.x + 2, win.y + 10, "P - Change your password")
        put(win.x + 2, win.y + 13, "Press a key to perform an action.", C.muted)
    end)
end

-- 16. APP REGISTRY
local apps = {
    {name = "Files", symbol = "F", action = openFiles},
    {name = "Terminal", symbol = ">", action = openTerminal},
    {name = "Notes", symbol = "N", action = openNotes},
    {name = "Monitor", symbol = "M", action = openMonitor},
    {name = "Settings", symbol = "S", action = openSettings},
    {name = "About", symbol = "i", action = openAbout}
}

-- 17. POWER AND LOGOUT
local function shutdown()
    running = false
    clear()
    center(math.floor(H / 2), "MEADOWS IS SHUTTING DOWN", C.accent)
    computer.shutdown()
end

local function restart()
    running = false
    clear()
    center(math.floor(H / 2), "RESTARTING MEADOWS", C.accent)
    computer.shutdown(true)
end

local function logout()
    windows = {}
    selected = nil
    menuOpen = false
    dragState = nil
    currentUser = nil
    loginScreen()
    if currentUser then openAbout() end
end

-- 18. WINDOW DRAWING
local function drawWindow(win)
    if win.minimized then return end
    rect(win.x + 1, win.y + 1, win.w, win.h, C.shadow)
    rect(win.x, win.y, win.w, win.h, C.window)
    rect(win.x, win.y, win.w, 2, win.id == selected and C.titlebar or C.panel2)
    put(win.x + 2, win.y, "*", C.accent)
    put(win.x + 4, win.y, win.title, C.white)
    put(win.x + win.w - 10, win.y, "_", C.muted)
    put(win.x + win.w - 7, win.y, "+", C.accent)
    put(win.x + win.w - 3, win.y, "X", C.close)
    rect(win.x, win.y + win.h - 1, win.w, 1, C.border)
    if win.content then win.content(win) end
end

-- 19. DESKTOP
local function getIconPosition(i)
    local x = (i % 2 == 1) and 3 or 12
    local step = math.max(2, math.floor((H - 8) / 3))
    local y = 6 + math.floor((i - 1) / 2) * step
    return x, y
end

local function drawDesktop()
    clear()
    rect(1, 1, W, H, C.desktop)
    rect(1, 1, W, 1, C.panel)
    put(3, 1, "MEADOWS", C.accent)
    put(12, 1, "FOREST EDITION", C.muted)
    put(W - 8, 1, VERSION, C.muted)
    put(3, 3, "Welcome back,", C.muted)
    put(3, 4, currentUser.display, C.accent)

    for i = 1, #apps do
        local x, y = getIconPosition(i)
        rect(x, y, 5, 2, C.panel2)
        rect(x, y, 5, 1, C.border)
        put(x + 2, y, apps[i].symbol, C.accent)
    end
    put(3, H - 3, "MEADOWS OS 0.5", C.muted)
end

local function drawStartMenu()
    local menuY = H - 13
    rect(2, menuY, 27, 11, C.panel)
    rect(2, menuY, 27, 1, C.accentDark)
    put(4, menuY + 1, "MEADOWS", C.accent)
    put(19, menuY + 1, "MENU", C.muted)
    rect(3, menuY + 2, 25, 1, C.border)

    for i = 1, #apps do
        local row = menuY + 2 + i
        put(4, row, tostring(i), C.accent)
        put(7, row, apps[i].name, C.text)
    end
    rect(3, menuY + 9, 25, 1, C.border)
    put(4, menuY + 10, "L Logout", C.muted)
    put(18, menuY + 10, "Q Power", C.close)
end

local function drawTaskbar()
    rect(1, H - 1, W, 2, C.panel)
    rect(2, H - 1, 5, 2, menuOpen and C.accentDark or C.panel2)
    put(4, H, "M", C.accent)

    local x = 9
    for i = 1, #windows do
        local win = windows[i]
        local label = win.title
        if #label > 8 then label = label:sub(1, 8) end
        local buttonWidth = #label + 3
        if x + buttonWidth < W - 12 then
            rect(x, H - 1, buttonWidth, 2, win.id == selected and C.accentDark or C.panel2)
            put(x + 1, H, label, win.id == selected and C.white or C.muted)
            x = x + buttonWidth + 1
        end
    end

    local uptime = math.floor(computer.uptime())
    local clock = tostring(math.floor(uptime / 60)) .. "m " .. tostring(uptime % 60) .. "s"
    put(W - #clock - 2, H, clock, C.accent)
end

local function draw()
    drawDesktop()
    for i = 1, #windows do drawWindow(windows[i]) end
    if menuOpen then drawStartMenu() end
    drawTaskbar()
end

-- 20. TOUCH AND MOUSE
local function handleTouch(x, y)
    if menuOpen then
        local menuY = H - 13
        if x >= 2 and x <= 29 then
            if y >= menuY + 3 and y <= menuY + 2 + #apps then
                local index = y - menuY - 2
                if apps[index] then apps[index].action() end
            elseif y == menuY + 10 then
                if x >= 18 then shutdown() else logout() end
            end
        end
        menuOpen = false
        return
    end

    if y >= H - 1 then
        if x <= 7 then menuOpen = not menuOpen return end
        local position = 9
        for i = 1, #windows do
            local win = windows[i]
            local label = win.title
            if #label > 8 then label = label:sub(1, 8) end
            local width = #label + 3
            if x >= position and x < position + width then
                win.minimized = false
                local _, index = getWindow(win.id)
                if index then bringToFront(index) end
                return
            end
            position = position + width + 1
        end
        return
    end

    -- Check windows before desktop shortcuts.
    for i = #windows, 1, -1 do
        local win = windows[i]
        if not win.minimized and x >= win.x and x <= win.x + win.w - 1
            and y >= win.y and y < win.y + win.h then
            bringToFront(i)
            win = getSelectedWindow()

            if y == win.y and x >= win.x + win.w - 4 then
                closeWindow(win.id)
                return
            end

            if y == win.y and x >= win.x + win.w - 7 and x < win.x + win.w - 4 then
                maximizeWindow(win)
                return
            end

            if y == win.y and x >= win.x + win.w - 10 and x < win.x + win.w - 7 then
                win.minimized = true
                selected = nil
                return
            end

            if y == win.y or y == win.y + 1 then
                dragState = {id = win.id, offsetX = x - win.x, offsetY = y - win.y}
            end

            if win.title == "Files" and y >= win.y + 6 and y < win.y + win.h - 2 then
                local row = y - (win.y + 5)
                local index = fileState.scroll + row
                if fileState.entries[index] then fileState.selected = index end
            end
            return
        end
    end

    for i = 1, #apps do
        local iconX, iconY = getIconPosition(i)
        if x >= iconX and x <= iconX + 4 and y >= iconY and y <= iconY + 1 then
            apps[i].action()
            return
        end
    end
end

local function handleDrag(x, y)
    if not dragState then return end
    local win = getWindow(dragState.id)
    if not win or win.maximized then return end
    win.x = math.max(1, math.min(x - dragState.offsetX, W - win.w + 1))
    win.y = math.max(2, math.min(y - dragState.offsetY, H - win.h - 2))
end

-- 21. KEYBOARD
local function handleKey(char, code)
    if menuOpen then
        if char == 113 or char == 81 then shutdown() return
        elseif char == 108 or char == 76 then logout() return
        elseif char and char >= 49 and char <= 57 then
            local index = char - 48
            if apps[index] then apps[index].action() end
            menuOpen = false
            return
        end
    end

    if char == 109 or char == 77 then menuOpen = not menuOpen return end
    if code == 1 or char == 27 then menuOpen = false dragState = nil return end

    local win = getSelectedWindow()
    if win then
        if win.title == "Meadows Settings" then
            if char == 97 or char == 65 then addUser()
            elseif char == 99 or char == 67 then changeComputerName()
            elseif char == 112 or char == 80 then changePassword() end

        elseif win.title == "Meadows Notes" then
            if char == 101 or char == 69 then editNotes() end

        elseif win.title == "Meadows Terminal" then
            if char == 116 or char == 84 then runTerminalCommand() end

        elseif win.title == "Files" then
            if code == 28 or char == 13 then openSelectedFile()
            elseif code == 14 or char == 8 then
                if fileState.path ~= "/" then
                    fileState.path = fileState.path:match("^(.*)/[^/]+/?$") or "/"
                    if fileState.path == "" then fileState.path = "/" end
                    fileState.selected = 1
                    refreshFiles()
                end
            elseif char == 110 or char == 78 then createFolder()
            elseif char == 114 or char == 82 then renameSelected()
            elseif char == 100 or char == 68 then deleteSelected()
            elseif code == 200 then
                fileState.selected = math.max(1, fileState.selected - 1)
            elseif code == 208 then
                fileState.selected = math.min(#fileState.entries, fileState.selected + 1)
            end

            local visible = math.max(1, win.h - 8)
            if fileState.selected <= fileState.scroll then fileState.scroll = fileState.selected - 1 end
            if fileState.selected > fileState.scroll + visible then fileState.scroll = fileState.selected - visible end
        end
    end

    if char == 17 then shutdown() end
end

-- 22. STARTUP
clear()
center(math.floor(H / 2) - 2, "MEADOWS", C.accent)
center(math.floor(H / 2), "Preparing your forest desktop...", C.muted)
computer.pullSignal(0.5)
openAbout()
draw()

-- 23. MAIN EVENT LOOP
while running do
    local signal, address, p1, p2, p3 = computer.pullSignal(0.2)

    if signal == "touch" then
        handleTouch(p1, p2)
    elseif signal == "drag" then
        handleDrag(p1, p2)
    elseif signal == "drop" then
        dragState = nil
    elseif signal == "key_down" then
        handleKey(p1, p2)
    elseif signal == "interrupted" then
        -- Ignore interrupt.
    end

    if running then draw() end
end
