-- Change 1.2
--[[
    MEADOWS OS
    Version: 0.2
    Independent OpenComputers Desktop Environment
]]

-- ==========================================
-- HARDWARE INITIALIZATION
-- ==========================================

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()

if not gpuAddress or not screenAddress then
    error("Meadows: GPU or screen missing")
end

local gpu = component.proxy(gpuAddress)
gpu.bind(screenAddress)

local W, H = gpu.getResolution()

if W < 30 or H < 12 then
    error("Meadows: Screen resolution too small")
end

local fsAddress = component.list("filesystem")()
local filesystem = fsAddress and component.proxy(fsAddress) or nil

local VERSION = "0.2"
local OS_NAME = "Meadows"

-- ==========================================
-- COLORS
-- ==========================================

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
-- GRAPHICS FUNCTIONS
-- ==========================================

local function rect(x, y, w, h, color, char)
    if w <= 0 or h <= 0 then return end

    gpu.setBackground(color)
    gpu.fill(x, y, w, h, char or " ")
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

-- ==========================================
-- BOOT SCREEN
-- ==========================================

clear()

center(math.floor(H / 2) - 2, OS_NAME, C.accent)
center(math.floor(H / 2), "A different kind of desktop.", C.muted)
center(math.floor(H / 2) + 3, "Starting system...", C.text)

for i = 1, 20 do
    local width = math.min(20, W - 4)
    local x = math.floor((W - width) / 2) + 1
    local filled = math.floor(width * i / 20)
    local barY = math.min(H - 1, math.floor(H / 2) + 5)

    rect(x, barY, width, 1, C.panel)
    rect(x, barY, filled, 1, C.accent)

    computer.pullSignal(0.035)
end

-- ==========================================
-- DESKTOP STATE
-- ==========================================

local windows = {}
local nextID = 0
local selected = nil
local menuOpen = false
local running = true

-- ==========================================
-- WINDOW MANAGER
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

-- ==========================================
-- APPLICATIONS
-- ==========================================

local function openAbout()
    newWindow("About Meadows", 38, 11, function(win)
        put(win.x + 2, win.y + 3, "MEADOWS OPERATING SYSTEM", C.accent)
        put(win.x + 2, win.y + 5, "Version: " .. VERSION)
        put(win.x + 2, win.y + 6, "Platform: OpenComputers")

        put(win.x + 2, win.y + 7, "Memory: " ..
            math.floor(computer.totalMemory() / 1024) .. " KB")

        put(win.x + 2, win.y + 9, "Made for a different desktop.", C.muted)
    end)
end

local function openMonitor()
    newWindow("System Monitor", 38, 12, function(win)
        put(win.x + 2, win.y + 3, "SYSTEM INFORMATION", C.accent)

        put(win.x + 2, win.y + 5, "Memory: " ..
            math.floor(computer.freeMemory() / 1024) .. " KB free")

        put(win.x + 2, win.y + 6, "Uptime: " ..
            math.floor(computer.uptime()) .. " seconds")

        put(win.x + 2, win.y + 7, "Screen: " .. W .. " x " .. H)
        put(win.x + 2, win.y + 9, "Meadows " .. VERSION, C.muted)
    end)
end

local function openNotes()
    local notes = ""

    newWindow("Meadows Notes", 42, 13, function(win)
        put(win.x + 2, win.y + 3, "NOTES", C.accent)

        put(win.x + 2, win.y + 5,
            notes == "" and "No notes yet." or notes)

        put(win.x + 2, win.y + 8, "Note editing coming soon.", C.muted)
    end)
end

local function openTerminal()
    newWindow("Meadows Terminal", 46, 13, function(win)
        put(win.x + 2, win.y + 3, "MEADOWS SHELL", C.accent)
        put(win.x + 2, win.y + 5, "Available demo commands:", C.muted)
        put(win.x + 2, win.y + 6, "about")
        put(win.x + 2, win.y + 7, "monitor")
        put(win.x + 2, win.y + 8, "clear")
        put(win.x + 2, win.y + 10, "Interactive shell coming soon.")
    end)
end


local function openFiles()
    newWindow("Meadows Files", 46, 15, function(win)
        put(win.x + 2, win.y + 3, "FILE SYSTEM  /", C.accent)

        if not filesystem then
            put(win.x + 2, win.y + 5,
                "No filesystem component found.", C.close)
            return
        end

        local ok, files = pcall(function()
            return filesystem.list("/")
        end)

        if not ok then
            put(win.x + 2, win.y + 5,
                "Unable to read filesystem.", C.close)
            return
        end

        if type(files) ~= "function" then
            put(win.x + 2, win.y + 5,
                "Invalid directory listing.", C.close)
            return
        end

        local y = win.y + 5
        local count = 0

        while true do
            local success, name = pcall(files)

            if not success or not name then
                break
            end

            if y >= win.y + win.h - 1 then
                break
            end

            put(win.x + 2, y, name)
            y = y + 1
            count = count + 1
        end

        if count == 0 then
            put(win.x + 2, y, "Directory is empty.", C.muted)
        end
    end)
end


-- ==========================================
-- APPLICATION LIST
-- ==========================================

local apps = {
    {name = "Files", action = openFiles},
    {name = "Terminal", action = openTerminal},
    {name = "Notes", action = openNotes},
    {name = "Monitor", action = openMonitor},
    {name = "About", action = openAbout}
}

-- ==========================================
-- WINDOW DRAWING
-- ==========================================

local function drawWindow(win)
    if win.minimized then return end

    rect(win.x, win.y, win.w, win.h, C.window)
    rect(win.x, win.y, win.w, 2, C.titlebar)

    put(win.x + 2, win.y, win.title, C.white)
    put(win.x + win.w - 3, win.y, "x", C.close)

    if win.content then
        win.content(win)
    end
end

-- ==========================================
-- SHUTDOWN
-- ==========================================

local function shutdown()
    running = false

    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, W, H, " ")

    computer.shutdown()
end

-- ==========================================
-- DESKTOP DRAWING
-- ==========================================

local function draw()
    clear()

    -- Desktop background
    rect(1, 1, W, H - 1, C.desktop)

    -- Header
    rect(1, 1, W, 1, C.panel)
    put(3, 1, OS_NAME:upper(), C.accent)
    put(W - 8, 1, "v" .. VERSION, C.muted)

    -- Desktop icons
    local y = 4

    for i = 1, #apps do
        if y < H - 1 then
            put(3, y, "[]", C.accent)
            put(7, y, apps[i].name, C.text)
        end

        y = y + 3
    end

    -- Windows (last window is drawn on top)
    for i = 1, #windows do
        drawWindow(windows[i])
    end

    -- Start menu
    if menuOpen then
        local menuY = math.max(2, H - 13)

        rect(2, menuY, 23, 11, C.panel)
        put(4, menuY + 1, "MEADOWS MENU", C.accent)

        for i = 1, #apps do
            put(4, menuY + i + 2, i .. ". " .. apps[i].name)
        end

        put(4, menuY + 9, "Q. Shutdown", C.close)
    end

    -- Taskbar
    rect(1, H, W, 1, C.panel)

    put(2, H, "M", C.accent)
    put(5, H, "Meadows Desktop", C.text)

    -- Uptime clock
    local uptime = math.floor(computer.uptime())
    local clock = tostring(math.floor(uptime / 60)) ..
        "m " .. tostring(uptime % 60) .. "s"

    put(W - #clock - 1, H, clock, C.accent)
end

-- ==========================================
-- TOUCH EVENTS
-- ==========================================

local function handleTouch(x, y)
    -- Start menu
    if menuOpen then
        local menuY = math.max(2, H - 13)

        if y >= menuY + 3 and y <= menuY + 7 then
            local index = y - menuY - 2

            if apps[index] then
                apps[index].action()
            end

        elseif y == menuY + 9 then
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

    -- Desktop icons
    local iconY = 4

    for i = 1, #apps do
        if iconY < H - 1 and
            x >= 3 and x <= 18 and y == iconY then

            apps[i].action()
            return
        end

        iconY = iconY + 3
    end

    -- Window interactions
    for i = #windows, 1, -1 do
        local win = windows[i]

        if not win.minimized and
            x >= win.x and x <= win.x + win.w - 1 and
            y >= win.y and y < win.y + win.h then

            -- Bring selected window to front
            bringToFront(i)

            -- Close button
            if y == win.y and
                x >= win.x + win.w - 4 then

                closeWindow(win.id)
            end

            return
        end
    end
end

-- ==========================================
-- KEYBOARD EVENTS
-- ==========================================

local function handleKey(char, code)
    -- Q: Shutdown from start menu
    if menuOpen and (char == 113 or char == 81) then
        shutdown()
        return
    end

    -- M: Toggle start menu
    if char == 109 or char == 77 then
        menuOpen = not menuOpen
        return
    end

    -- Escape: Close start menu
    if code == 1 then
        menuOpen = false
    end
end

-- ==========================================
-- STARTUP
-- ==========================================

openAbout()
draw()

while running do
    local signal, address, p1, p2, p3 =
        computer.pullSignal(0.2)

    if signal == "touch" then
        -- OpenComputers touch:
        -- address, x, y, button, player
        handleTouch(p1, p2)

    elseif signal == "key_down" then
        -- OpenComputers key_down:
        -- address, character, keyCode, player
        handleKey(p1, p2)

    elseif signal == "interrupted" then
        -- Ignore interruption
    end

    if running then
        draw()
    end
end
