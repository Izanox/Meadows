-- CHANGE 1.5
--[[
    MEADOWS OS 0.3
    FOREST EDITION
    Native OpenComputers BIOS Kernel
]]

-- ==========================================
-- 1. HARDWARE
-- ==========================================

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
if not fsAddress then
    error("Meadows: No filesystem found")
end

local filesystem = component.proxy(fsAddress)

-- ==========================================
-- 2. SYSTEM CONFIGURATION
-- ==========================================

local OS_NAME = "Meadows"
local VERSION = "0.3"
local DATA_DIR = "/.meadows"
local CONFIG_FILE = DATA_DIR .. "/system.cfg"
local ACCOUNTS_FILE = DATA_DIR .. "/accounts.db"
local NOTES_FILE = DATA_DIR .. "/notes.txt"

local C = {
    background = 0x101A18,
    desktop = 0x14231F,
    panel = 0x1D302A,
    window = 0x243B33,
    titlebar = 0x315344,
    accent = 0x79C99E,
    text = 0xE5F1E9,
    muted = 0x91AA9B,
    close = 0xD96C6C,
    white = 0xFFFFFF
}

gpu.setDepth(8)
gpu.setBackground(C.background)
gpu.setForeground(C.text)
gpu.fill(1, 1, W, H, " ")

-- ==========================================
-- 3. GRAPHICS
-- ==========================================

local function rect(x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    gpu.setBackground(color)
    gpu.fill(x, y, w, h, " ")
end

local function put(x, y, value, color)
    value = tostring(value)

    if y < 1 or y > H or x > W or x + #value - 1 < 1 then
        return
    end

    if x < 1 then
        value = value:sub(2 - x)
        x = 1
    end

    if x + #value - 1 > W then
        value = value:sub(1, W - x + 1)
    end

    if #value == 0 then return end

    gpu.setForeground(color or C.text)
    gpu.set(x, y, value)
end

local function center(y, value, color)
    value = tostring(value)
    put(math.floor((W - #value) / 2) + 1, y, value, color)
end

local function clear()
    rect(1, 1, W, H, C.background)
end

local function line(y)
    rect(2, y, W - 2, 1, C.titlebar)
end

-- ==========================================
-- 4. FILE STORAGE
-- ==========================================

local function readFile(path)
    local ok, handle = pcall(filesystem.open, path, "r")

    if not ok or not handle then
        return nil
    end

    local result = ""

    while true do
        local success, data = pcall(filesystem.read, handle, 4096)

        if not success or not data or #data == 0 then
            break
        end

        result = result .. data
    end

    pcall(filesystem.close, handle)
    return result
end

local function writeFile(path, data)
    local ok, handle = pcall(filesystem.open, path, "w")

    if not ok or not handle then
        return false
    end

    local success, result = pcall(filesystem.write, handle, data)
    pcall(filesystem.close, handle)

    return success and result ~= false
end

local function initializeStorage()
    local ok, exists = pcall(filesystem.exists, DATA_DIR)

    if not ok or not exists then
        local success = pcall(filesystem.makeDirectory, DATA_DIR)

        if not success then
            error("Meadows: Cannot create system directory")
        end
    end
end

initializeStorage()

-- ==========================================
-- 5. SYSTEM CONFIGURATION DATABASE
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
    local data =
        "setupComplete=" .. tostring(config.setupComplete) .. "\n" ..
        "computerName=" .. config.computerName .. "\n" ..
        "theme=" .. config.theme .. "\n"

    if not writeFile(CONFIG_FILE, data) then
        return false
    end

    return true
end

loadConfig()

-- ==========================================
-- 6. USER ACCOUNT DATABASE
-- ==========================================

local accounts = {}

local function cleanField(value)
    value = tostring(value or "")
    value = value:gsub("[|\r\n]", "")
    return value
end

-- Simple prototype hash, NOT cryptographically secure.
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

        output = output ..
            a.username .. "|" ..
            a.display .. "|" ..
            a.salt .. "|" ..
            a.hash .. "\n"
    end

    return writeFile(ACCOUNTS_FILE, output)
end

local function loadAccounts()
    accounts = {}

    local data = readFile(ACCOUNTS_FILE)
    if not data then return end

    for line in data:gmatch("[^\r\n]+") do
        local username, display, salt, hash =
            line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")

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
    username = username:lower()

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

    local account = {
        username = username,
        display = display,
        salt = salt,
        hash = hashPassword(password, salt)
    }

    accounts[#accounts + 1] = account

    if not saveAccounts() then
        accounts[#accounts] = nil
        return false, "Could not save account database."
    end

    return true
end

local function verifyPassword(account, password)
    if not account then return false end

    return hashPassword(password, account.salt) == account.hash
end

-- ==========================================
-- 7. KEYBOARD INPUT
-- ==========================================

local function inputLine(prompt, secret)
    local value = ""
    local row = math.min(H - 3, 12)

    while true do
        clear()

        center(3, OS_NAME, C.accent)
        center(5, prompt, C.text)

        line(7)

        put(3, row, "> ", C.accent)

        local shown = secret and string.rep("*", #value) or value
        put(5, row, shown, C.white)

        center(H - 2, "ENTER: Confirm   ESC: Cancel", C.muted)

        local signal, address, char, code =
            computer.pullSignal()

        if signal == "key_down" then
            if char == 13 or code == 28 then
                return value

            elseif char == 8 or code == 14 then
                value = value:sub(1, -2)

            elseif char == 27 or code == 1 then
                return nil

            elseif char and char >= 32 and char <= 126 then
                if #value < 30 then
                    value = value .. string.char(char)
                end
            end
        end
    end
end

local function messageScreen(title, message)
    clear()

    center(4, OS_NAME, C.accent)
    center(7, title, C.white)
    center(9, message, C.muted)
    center(H - 2, "Press any key to continue", C.accent)

    while true do
        local signal = computer.pullSignal()

        if signal == "key_down" then
            return
        end
    end
end

-- ==========================================
-- 8. FIRST-TIME SETUP
-- ==========================================

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

    -- Computer name
    local pcName = inputLine("Choose a computer name", false)

    if not pcName then
        pcName = "MEADOWS-PC"
    end

    pcName = cleanField(pcName):gsub("[^%w_%-]", "")

    if #pcName < 2 then
        pcName = "MEADOWS-PC"
    end

    -- Administrator username
    local username = inputLine("Create administrator username", false)

    if not username or #username < 3 then
        username = "admin"
    end

    username = cleanField(username)

    if username:find("[^%w_]") then
        username = "admin"
    end

    if findAccount(username) then
        username = "admin"
    end

    -- Display name
    local display = inputLine("Enter your display name", false)

    if not display or display == "" then
        display = username
    end

    display = cleanField(display)

    -- Password
    local password

    while true do
        password = inputLine("Create a password (minimum 4 characters)", true)

        if not password or #password < 4 then
            messageScreen("Password required", "Please create a password with at least 4 characters.")
        else
            local confirm = inputLine("Confirm your password", true)

            if confirm == password then
                break
            end

            messageScreen("Passwords do not match", "Please try again.")
        end
    end

    -- Terms and conditions
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
        if not accepted then
            accepted = inputLine("Type ACCEPT to continue", false)
        else
            messageScreen("Terms not accepted", "You must type ACCEPT to continue.")
            accepted = inputLine("Type ACCEPT to continue", false)
        end
    end

    -- Save administrator account
    local ok, reason = createAccount(username, display, password)

    if not ok then
        error("Meadows setup: " .. tostring(reason))
    end

    config.computerName = pcName
    config.setupComplete = true

    if not saveConfig() then
        error("Meadows: Could not save system configuration")
    end

    messageScreen("Setup complete", "Your Meadows computer is ready.")
end

if not config.setupComplete or #accounts == 0 then
    setupWizard()
end

-- ==========================================
-- 9. LOGIN MANAGER
-- ==========================================

local currentUser = nil

local function loginScreen()
    while true do
        clear()

        center(3, OS_NAME, C.accent)
        center(5, config.computerName, C.muted)
        center(8, "SELECT YOUR ACCOUNT", C.white)

        for i = 1, #accounts do
            put(5, 10 + i, tostring(i) .. ". " ..
                accounts[i].display .. " (" ..
                accounts[i].username .. ")")
        end

        center(H - 2, "Enter account number or ESC to power off", C.muted)

        local choice = inputLine("Account number", false)

        if not choice then
            computer.shutdown()
            return
        end

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

-- ==========================================
-- 10. DESKTOP STATE
-- ==========================================

local windows = {}
local nextID = 0
local selected = nil
local menuOpen = false
local running = true

-- ==========================================
-- 11. WINDOW MANAGER
-- ==========================================

local function newWindow(title, width, height, content)
    width = math.min(width, W - 2)
    height = math.min(height, H - 3)

    nextID = nextID + 1

    local win = {
        id = nextID,
        title = title,
        x = math.floor((W - width) / 2),
        y = math.floor((H - height - 1) / 2) + 1,
        w = width,
        h = height,
        content = content,
        minimized = false
    }

    win.x = math.max(1, math.min(win.x, W - width + 1))
    win.y = math.max(2, math.min(win.y, H - height))

    windows[#windows + 1] = win
    selected = win.id
end

local function getWindow(id)
    for i = 1, #windows do
        if windows[i].id == id then
            return windows[i], i
        end
    end
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

    windows[#windows + 1] = win
    selected = win.id
end

local function getSelectedWindow()
    return getWindow(selected)
end

-- ==========================================
-- 12. USER MANAGEMENT
-- ==========================================

local function addUser()
    local username = inputLine("New username", false)

    if not username or username == "" then return end

    local display = inputLine("New display name", false)

    if not display or display == "" then
        display = username
    end

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

    if ok then
        messageScreen("Account created", "The new account was saved.")
    else
        messageScreen("Could not create account", tostring(reason))
    end
end

local function changeComputerName()
    local name = inputLine("New computer name", false)

    if not name or name == "" then return end

    name = cleanField(name):gsub("[^%w_%-]", "")

    if #name < 2 then
        messageScreen("Invalid name", "Please choose a longer name.")
        return
    end

    config.computerName = name

    if saveConfig() then
        messageScreen("Settings saved", "Computer name updated.")
    else
        messageScreen("Save failed", "Could not save settings.")
    end
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

    currentUser.salt = tostring(math.floor(computer.uptime() * 1000)) ..
        tostring(#accounts + 10)

    currentUser.hash = hashPassword(newPassword, currentUser.salt)

    if saveAccounts() then
        messageScreen("Password changed", "Your new password has been saved.")
    else
        messageScreen("Save failed", "Could not save the password.")
    end
end

-- ==========================================
-- 13. APPLICATIONS
-- ==========================================

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

        put(win.x + 2, win.y + 5, "Total RAM: " ..
            math.floor(computer.totalMemory() / 1024) .. " KB")

        put(win.x + 2, win.y + 6, "Free RAM: " ..
            math.floor(computer.freeMemory() / 1024) .. " KB")

        put(win.x + 2, win.y + 7, "Uptime: " ..
            math.floor(computer.uptime()) .. " seconds")

        put(win.x + 2, win.y + 8, "Resolution: " .. W .. "x" .. H)
        put(win.x + 2, win.y + 10, "Filesystem: " .. fsAddress:sub(1, 8), C.muted)
    end)
end

local function openFiles()
    newWindow("Meadows Files", 46, 16, function(win)
        put(win.x + 2, win.y + 3, "FILE SYSTEM  /", C.accent)

        local ok, files = pcall(function()
            return filesystem.list("/")
        end)

        if not ok or not files then
            put(win.x + 2, win.y + 5, "Unable to read filesystem.", C.close)
            return
        end

        local y = win.y + 5
        local count = 0

        if type(files) == "function" then
            while true do
                local success, name = pcall(files)

                if not success or not name then break end
                if y >= win.y + win.h - 1 then break end

                put(win.x + 2, y, tostring(name))
                y = y + 1
                count = count + 1
            end

        elseif type(files) == "table" then
            for _, name in pairs(files) do
                if y >= win.y + win.h - 1 then break end

                put(win.x + 2, y, tostring(name))
                y = y + 1
                count = count + 1
            end
        end

        if count == 0 then
            put(win.x + 2, y, "Directory is empty.", C.muted)
        end
    end)
end

local function openNotes()
    local notes = readFile(NOTES_FILE) or ""

    newWindow("Meadows Notes", 46, 15, function(win)
        put(win.x + 2, win.y + 3, "PERSONAL NOTES", C.accent)

        if notes == "" then
            put(win.x + 2, win.y + 5, "No notes saved.", C.muted)
        else
            local row = win.y + 5

            for textLine in notes:gmatch("[^\r\n]+") do
                if row >= win.y + win.h - 2 then break end

                put(win.x + 2, row, textLine)
                row = row + 1
            end
        end

        put(win.x + 2, win.y + win.h - 2, "Press E to edit notes.", C.accent)
    end)
end

local function editNotes()
    local notes = inputLine("Enter your new note", false)

    if notes == nil then return end

    if writeFile(NOTES_FILE, notes .. "\n") then
        messageScreen("Notes saved", "Your note was saved successfully.")
    else
        messageScreen("Save failed", "Could not save your notes.")
    end
end

local function openTerminal()
    newWindow("Meadows Terminal", 46, 15, function(win)
        put(win.x + 2, win.y + 3, "MEADOWS SHELL", C.accent)
        put(win.x + 2, win.y + 5, "Welcome, " .. currentUser.username)
        put(win.x + 2, win.y + 7, "Available commands:", C.muted)
        put(win.x + 2, win.y + 8, "help")
        put(win.x + 2, win.y + 9, "about")
        put(win.x + 2, win.y + 10, "monitor")
        put(win.x + 2, win.y + 11, "logout")
        put(win.x + 2, win.y + 13, "Interactive shell is in development.", C.muted)
    end)
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

-- ==========================================
-- 14. APPLICATION REGISTRY
-- ==========================================

local apps = {
    {name = "Files", action = openFiles},
    {name = "Terminal", action = openTerminal},
    {name = "Notes", action = openNotes},
    {name = "Monitor", action = openMonitor},
    {name = "Settings", action = openSettings},
    {name = "About", action = openAbout}
}

-- ==========================================
-- 15. SHUTDOWN AND LOGOUT
-- ==========================================

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

    currentUser = nil

    loginScreen()

    if currentUser then
        openAbout()
    end
end

-- ==========================================
-- 16. WINDOW RENDERING
-- ==========================================

local function drawWindow(win)
    if win.minimized then return end

    rect(win.x, win.y, win.w, win.h, C.window)

    rect(
        win.x,
        win.y,
        win.w,
        2,
        win.id == selected and C.titlebar or C.panel
    )

    put(win.x + 2, win.y, win.title, C.white)
    put(win.x + win.w - 3, win.y, "x", C.close)

    if win.content then
        win.content(win)
    end
end

-- ==========================================
-- 17. DESKTOP DRAWING
-- ==========================================

local function draw()
    clear()

    -- Wallpaper
    rect(1, 1, W, H - 1, C.desktop)

    -- Top header
    rect(1, 1, W, 1, C.panel)

    put(3, 1, "MEADOWS", C.accent)
    put(W - 8, 1, "v" .. VERSION, C.muted)

    -- Desktop applications
    local y = 4

    for i = 1, #apps do
        if y < H - 1 then
            put(3, y, "[]", C.accent)
            put(7, y, apps[i].name, C.text)
        end

        y = y + 3
    end

    -- Windows
    for i = 1, #windows do
        drawWindow(windows[i])
    end

    -- Start menu
    if menuOpen then
        local menuY = math.max(2, H - 15)

        rect(2, menuY, 25, 13, C.panel)

        put(4, menuY + 1, "MEADOWS MENU", C.accent)
        line(menuY + 2)

        for i = 1, #apps do
            put(4, menuY + i + 2,
                tostring(i) .. ". " .. apps[i].name)
        end

        put(4, menuY + 10, "L. Logout", C.accent)
        put(4, menuY + 11, "Q. Shutdown", C.close)
    end

    -- Taskbar
    rect(1, H, W, 1, C.panel)

    put(2, H, "M", C.accent)
    put(5, H, config.computerName, C.text)

    -- Clock
    local uptime = math.floor(computer.uptime())

    local clock =
        tostring(math.floor(uptime / 60)) ..
        "m " ..
        tostring(uptime % 60) ..
        "s"

    put(W - #clock - 1, H, clock, C.accent)
end

-- ==========================================
-- 18. TOUCH HANDLING
-- ==========================================

local function handleTouch(x, y)
    -- Start menu
    if menuOpen then
        local menuY = math.max(2, H - 15)

        if y >= menuY + 3 and y <= menuY + 2 + #apps then
            local index = y - menuY - 2

            if apps[index] then
                apps[index].action()
            end

        elseif y == menuY + 10 then
            logout()
        elseif y == menuY + 11 then
            shutdown()
        end

        menuOpen = false
        return
    end

    -- Start button
    if y == H and x <= 3 then
        menuOpen = true
        return
    end

    -- Desktop shortcuts
    local iconY = 4

    for i = 1, #apps do
        if iconY < H - 1 and
            x >= 3 and x <= 20 and y == iconY then

            apps[i].action()
            return
        end

        iconY = iconY + 3
    end

    -- Windows
    for i = #windows, 1, -1 do
        local win = windows[i]

        if not win.minimized and
            x >= win.x and x <= win.x + win.w - 1 and
            y >= win.y and y < win.y + win.h then

            bringToFront(i)

            -- Close button
            if y == win.y and x >= win.x + win.w - 4 then
                closeWindow(win.id)
            end

            return
        end
    end
end

-- ==========================================
-- 19. KEYBOARD HANDLING
-- ==========================================

local function handleKey(char, code)
    -- Start menu shortcuts
    if menuOpen then
        if char == 113 or char == 81 then
            shutdown()
            return

        elseif char == 108 or char == 76 then
            logout()
            return

        elseif char >= 49 and char <= 57 then
            local index = char - 48

            if apps[index] then
                apps[index].action()
            end

            menuOpen = false
            return
        end
    end

    -- M: Open/close start menu
    if char == 109 or char == 77 then
        menuOpen = not menuOpen
        return
    end

    -- Escape: Close menu
    if code == 1 or char == 27 then
        menuOpen = false
        return
    end

    -- Selected application shortcuts
    local win = getSelectedWindow()

    if win then
        if win.title == "Meadows Settings" then
            if char == 97 or char == 65 then
                addUser()

            elseif char == 99 or char == 67 then
                changeComputerName()

            elseif char == 112 or char == 80 then
                changePassword()
            end

        elseif win.title == "Meadows Notes" then
            if char == 101 or char == 69 then
                editNotes()
            end
        end
    end

    -- Ctrl+Q: Shutdown
    if char == 17 then
        shutdown()
    end
end

-- ==========================================
-- 20. STARTUP
-- ==========================================

clear()

center(math.floor(H / 2) - 2, "MEADOWS", C.accent)
center(math.floor(H / 2), "Starting desktop environment...", C.muted)

computer.pullSignal(0.5)

openAbout()

draw()

-- ==========================================
-- 21. MAIN EVENT LOOP
-- ==========================================

while running do
    local signal, address, p1, p2, p3 =
        computer.pullSignal(0.2)

    if signal == "touch" then
        handleTouch(p1, p2)

    elseif signal == "key_down" then
        handleKey(p1, p2)

    elseif signal == "interrupted" then
        -- Ignore interrupt
    end

    if running then
        draw()
    end
end
