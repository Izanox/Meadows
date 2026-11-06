
--[[
    MEADOWS OS
    Version: 0.1
    Independent OpenComputers Desktop Environment
]]

-- Native OpenComputers BIOS APIs

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()

if not gpuAddress or not screenAddress then
    error("Meadows: GPU or screen missing")
end

local gpu = component.proxy(gpuAddress)

gpu.bind(screenAddress)

local computer = computer
local W, H = gpu.getResolution()

-- ==========================================
-- CONFIGURATION
-- ==========================================

local VERSION = "0.1"
local OS_NAME = "Meadows"

local W, H = gpu.getResolution()

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
-- DRAWING FUNCTIONS
-- ==========================================

local function rect(x, y, w, h, color, char)
    gpu.setBackground(color)
    gpu.fill(x, y, w, h, char or " ")
end

local function put(x, y, value, color)
    gpu.setForeground(color or C.text)
    gpu.set(x, y, tostring(value))
end

local function center(y, value, color)
    put(math.floor((W - #value) / 2) + 1, y, value, color)
end

local function clear()
    rect(1, 1, W, H, C.background)
end

-- ==========================================
-- BOOT SCREEN
-- ==========================================

clear()

rect(1, 1, W, H, C.background)

center(math.floor(H / 2) - 2, "MEADOWS", C.accent)
center(math.floor(H / 2), "A different kind of desktop.", C.muted)
center(math.floor(H / 2) + 3, "Starting system...", C.text)

for i = 1, 20 do
    local width = math.min(20, W - 4)
    local x = math.floor((W - width) / 2) + 1
    local filled = math.floor(width * i / 20)

    rect(x, math.floor(H / 2) + 5, width, 1, C.panel, " ")
    rect(x, math.floor(H / 2) + 5, filled, 1, C.accent, " ")
    os.sleep(0.035)
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
    nextID = nextID + 1

    local win = {
        id = nextID,
        title = title,
        x = math.floor((W - width) / 2),
        y = math.floor((H - height - 2) / 2),
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
        selected = windows[#windows] and windows[#windows].id
    end
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
        put(win.x + 2, win.y + 5, notes == "" and
            "No notes yet." or notes)
        put(win.x + 2, win.y + 8, "Press N to add a note.", C.muted)
    end)
end

local function openTerminal()
    newWindow("Meadows Terminal", 46, 13, function(win)
        put(win.x + 2, win.y + 3, "MEADOWS SHELL", C.accent)
        put(win.x + 2, win.y + 5, "Available commands:", C.muted)
        put(win.x + 2, win.y + 6, "about")
        put(win.x + 2, win.y + 7, "monitor")
        put(win.x + 2, win.y + 8, "clear")
        put(win.x + 2, win.y + 10, "Terminal is currently a basic shell preview.")
    end)
end

local function openFiles()
    newWindow("Meadows Files", 46, 15, function(win)
        put(win.x + 2, win.y + 3, "FILE SYSTEM", C.accent)

        local ok, files = pcall(function()
            return require("filesystem").list("/")
        end)

        if ok then
            local y = win.y + 5
            for name in files do
                if y < win.y + win.h - 2 then
                    put(win.x + 2, y, name)
                    y = y + 1
                end
            end
        else
            put(win.x + 2, win.y + 5, "Unable to read filesystem.")
        end
    end)
end

-- ==========================================
-- DESKTOP ICONS
-- ==========================================

local apps = {
    {name = "Files", action = openFiles},
    {name = "Terminal", action = openTerminal},
    {name = "Notes", action = openNotes},
    {name = "Monitor", action = openMonitor},
    {name = "About", action = openAbout}
}

-- ==========================================
-- DRAW WINDOW
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
-- DESKTOP DRAW
-- ==========================================

local function draw()
    clear()

    -- Desktop background
    rect(1, 1, W, H - 1, C.desktop)

    -- Header
    rect(1, 1, W, 1, C.panel)
    put(3, 1, "MEADOWS", C.accent)
    put(W - 18, 1, "v" .. VERSION, C.muted)

    -- Desktop icons
    local y = 4

    for i = 1, #apps do
        put(3, y, "[]", C.accent)
        put(7, y, apps[i].name, C.text)
        y = y + 3
    end

    -- Windows
    for i = 1, #windows do
        drawWindow(windows[i])
    end

    -- Start menu
    if menuOpen then
        local menuY = math.max(2, H - 13)
        rect(2, menuY, 23, 11, C.panel)
        put(4, menuY + 1, "MEADOWS MENU", C.accent)

        for i = 1, #apps do
            put(4, menuY + i + 2, (i) .. ". " .. apps[i].name)
        end

        put(4, menuY + 9, "Q. Shutdown", C.close)
    end

    -- Bottom taskbar
    rect(1, H, W, 1, C.panel)
    put(2, H, "M", C.accent)
    put(5, H, "Meadows Desktop", C.text)

    local clock = os.date("%H:%M")
    put(W - #clock - 1, H, clock, C.accent)
end

-- ==========================================
-- EVENT HANDLING
-- ==========================================

local function shutdown()
    running = false
    computer.shutdown()
end

local function handleTouch(x, y)
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
        menuOpen = not menuOpen
        return
    end

    -- Desktop applications
    if x >= 3 and x <= 18 and y >= 4 and y <= 16 then
        local index = math.floor((y - 4) / 3) + 1

        if apps[index] and (y - 4) % 3 == 0 then
            apps[index].action()
            return
        end
    end

    -- Window interactions
    for i = #windows, 1, -1 do
        local win = windows[i]

        if not win.minimized and
            x >= win.x and x <= win.x + win.w - 1 and
            y >= win.y and y < win.y + win.h then

            selected = win.id

            if y == win.y and x >= win.x + win.w - 4 then
                closeWindow(win.id)
            end

            return
        end
    end
end

-- ==========================================
-- STARTUP
-- ==========================================

openAbout()

while running do
    draw()

    local signal, address, x, y = computer.pullSignal(0.5)

    if signal == "touch" then
        handleTouch(x, y)

    elseif signal == "key_down" then
        local char = y
        local code = x

        if code == 16 then
            shutdown()
        elseif char == 109 then
            menuOpen = not menuOpen
        end

    elseif signal == "interrupted" then
        -- Ignore accidental interrupt
    end
end
