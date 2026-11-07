
-- =========================================================
-- CHANGE 5.1
-- MEADOWS OS 1.2
-- FOREST EDITION
-- PART 1 OF 4
-- Hardware, boot splash and persistent storage
-- =========================================================

local gpuAddress = component.list("gpu")()
local screenAddress = component.list("screen")()

if not gpuAddress or not screenAddress then
    error("Meadows: GPU or screen not found.")
end

local gpu = component.proxy(gpuAddress)
local computer = computer

local bound, bindError = pcall(gpu.bind, screenAddress)
if not bound then
    error("Meadows: Could not bind screen: " .. tostring(bindError))
end

local W, H = gpu.getResolution()

if W < 40 or H < 16 then
    error("Meadows: Screen must be at least 40x16.")
end

pcall(gpu.setDepth, 8)

local VERSION = "1.2"
local OS_NAME = "Meadows"
local MAX_WINDOWS = 2

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
    border = 0x365643
}

local DATA_DIR = "/.meadows"
local CONFIG_FILE = DATA_DIR .. "/system.cfg"
local ACCOUNTS_FILE = DATA_DIR .. "/accounts.db"
local NOTES_FILE = DATA_DIR .. "/notes.txt"
local STORAGE_ID_FILE = DATA_DIR .. "/storage.id"

-- ---------------------------------------------------------
-- Graphics helpers
-- ---------------------------------------------------------

local function rect(x, y, w, h, color)
    x = math.floor(x)
    y = math.floor(y)
    w = math.floor(w)
    h = math.floor(h)

    if x < 1 then
        w = w - (1 - x)
        x = 1
    end

    if y < 1 then
        h = h - (1 - y)
        y = 1
    end

    if x + w - 1 > W then
        w = W - x + 1
    end

    if y + h - 1 > H then
        h = H - y + 1
    end

    if w <= 0 or h <= 0 then return end

    gpu.setBackground(color)
    gpu.fill(x, y, w, h, " ")
end

local function put(x, y, value, color)
    value = tostring(value or "")
    x = math.floor(x)
    y = math.floor(y)

    if y < 1 or y > H or x > W then return end

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
    value = tostring(value or "")
    put(math.floor((W - #value) / 2) + 1, y, value, color)
end

local function clear(color)
    rect(1, 1, W, H, color or C.background)
end

local function waitForKey()
    while true do
        local signal = computer.pullSignal()
        if signal == "key_down" then
            return
        end
    end
end

-- ---------------------------------------------------------
-- Meadows boot splash
-- ---------------------------------------------------------

local function bootSplash()
    local frames = {"|", "/", "-", "\\"}

    for frame = 1, 24 do
        gpu.setForeground(C.white)
        gpu.setBackground(C.background)
        clear(C.background)

        local logoX = math.floor(W / 2) - 4
        local logoY = math.floor(H / 2) - 4

        rect(logoX, logoY, 3, 2, C.accentDark)
        rect(logoX + 4, logoY, 3, 2, C.accentDark)
        rect(logoX, logoY + 3, 3, 2, C.accent)
        rect(logoX + 4, logoY + 3, 3, 2, C.accent)

        center(logoY + 6, "MEADOWS", C.white)
        center(logoY + 8, "FOREST EDITION", C.accent)

        local spinner = frames[(frame - 1) % #frames + 1]
        center(H - 3, "Starting Meadows EFI " .. spinner, C.muted)
        center(H - 1, "VERSION " .. VERSION, C.muted)

        computer.pullSignal(0.12)
    end
end

bootSplash()

-- ---------------------------------------------------------
-- Filesystem helpers
-- ---------------------------------------------------------

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

        if not readOK or not data or #data == 0 then
            break
        end

        chunks[#chunks + 1] = data
    end

    pcall(fs.close, handle)
    return table.concat(chunks)
end

local function fsWrite(fs, path, data)
    data = tostring(data or "")

    local ok, handle = pcall(fs.open, path, "w")
    if not ok or not handle then
        return false, "Could not open file for writing."
    end

    local writeOK, result = pcall(fs.write, handle, data)
    local closeOK = pcall(fs.close, handle)

    if not writeOK or result == false or not closeOK then
        return false, "Could not write file."
    end

    local check = fsRead(fs, path)

    if check ~= data then
        return false, "Storage verification failed."
    end

    return true
end

-- ---------------------------------------------------------
-- Discover writable filesystems
-- ---------------------------------------------------------

local drives = {}

for address in component.list("filesystem") do
    local proxyOK, fs = pcall(component.proxy, address)

    if proxyOK and fs then
        local readOnly = true

        if fs.isReadOnly then
            local ok, value = pcall(fs.isReadOnly)
            if ok then readOnly = value == true end
        end

        local total = 0
        local used = 0
        local label = "Unnamed"

        if fs.spaceTotal then
            local ok, value = pcall(fs.spaceTotal)
            if ok then total = tonumber(value) or 0 end
        end

        if fs.spaceUsed then
            local ok, value = pcall(fs.spaceUsed)
            if ok then used = tonumber(value) or 0 end
        end

        if fs.getLabel then
            local ok, value = pcall(fs.getLabel)
            if ok and value and value ~= "" then
                label = tostring(value)
            end
        end

        if not readOnly then
            drives[#drives + 1] = {
                address = address,
                fs = fs,
                label = label,
                total = total,
                used = used,
                readOnly = false
            }
        end
    end
end

if #drives == 0 then
    error("Meadows: No writable filesystem found.")
end

-- ---------------------------------------------------------
-- Drive selection
-- ---------------------------------------------------------

local function chooseStorage()
    local choice = 1

    while true do
        clear()

        center(2, "MEADOWS INSTALLATION", C.accent)
        center(4, "Choose where Meadows will store its data.", C.white)

        for i = 1, #drives do
            local disk = drives[i]
            local y = 7 + (i - 1) * 2

            if y < H - 4 then
                if i == choice then
                    rect(3, y, W - 6, 1, C.accentDark)
                end

                local free = math.max(0, disk.total - disk.used)
                local capacity = disk.total > 0
                    and (math.floor(free / 1024) .. " KB free")
                    or "Capacity unknown"

                put(4, y,
                    tostring(i) .. ". " .. disk.label ..
                    " | " .. capacity,
                    C.white)
            end
        end

        center(H - 2, "UP/DOWN: Select     ENTER: Confirm", C.accent)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 200 then
                choice = math.max(1, choice - 1)

            elseif code == 208 then
                choice = math.min(#drives, choice + 1)

            elseif code == 28 or char == 13 then
                return drives[choice]
            end
        end
    end
end

-- Prefer a drive with an existing Meadows installation.
local selectedDisk = nil

for i = 1, #drives do
    if fsExists(drives[i].fs, DATA_DIR) and
        fsExists(drives[i].fs, STORAGE_ID_FILE) then

        local saved = fsRead(drives[i].fs, STORAGE_ID_FILE)

        if saved and saved:gsub("%s+", "") == drives[i].address then
            selectedDisk = drives[i]
            break
        end
    end
end

if not selectedDisk then
    selectedDisk = chooseStorage()
end

if not selectedDisk then
    error("Meadows: No installation drive selected.")
end

local filesystem = selectedDisk.fs
local STORAGE_ADDRESS = selectedDisk.address

-- ---------------------------------------------------------
-- Set drive label
-- ---------------------------------------------------------

if filesystem.setLabel then
    local ok, result = pcall(filesystem.setLabel, "Meadows")

    if not ok or result == false then
        -- Some filesystems do not support changing labels.
        -- Installation can still continue.
    end
end

-- ---------------------------------------------------------
-- Initialize Meadows storage
-- ---------------------------------------------------------

if not fsExists(filesystem, DATA_DIR) then
    local ok, result = pcall(filesystem.makeDirectory, DATA_DIR)

    if not ok or result == false or
        not fsExists(filesystem, DATA_DIR) then
        error("Meadows: Could not create system directory.")
    end
end

local testOK = fsWrite(
    filesystem,
    DATA_DIR .. "/storage-test.tmp",
    "MEADOWS STORAGE TEST"
)

if not testOK then
    error("Meadows: Storage write test failed.")
end

pcall(filesystem.remove, DATA_DIR .. "/storage-test.tmp")

local identityOK = fsWrite(
    filesystem,
    STORAGE_ID_FILE,
    STORAGE_ADDRESS
)

if not identityOK then
    error("Meadows: Could not save drive identity.")
end

local function readFile(path)
    return fsRead(filesystem, path)
end

local function writeFile(path, data)
    return fsWrite(filesystem, path, data)
end
-- ---------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------

local config = {
    computerName = "Meadows-PC",
    wallpaper = 1,
    username = "",
    displayName = "",
    setupComplete = false,
    version = VERSION
}

local function cleanValue(value)
    value = tostring(value or "")
    value = value:gsub("[\r\n]", "")
    value = value:gsub("|", "")
    value = value:gsub("=", "")
    return value
end

local function saveConfig()
    local data = {
        "computerName=" .. cleanValue(config.computerName),
        "wallpaper=" .. cleanValue(config.wallpaper),
        "username=" .. cleanValue(config.username),
        "displayName=" .. cleanValue(config.displayName),
        "setupComplete=" .. tostring(config.setupComplete),
        "version=" .. cleanValue(config.version)
    }

    return writeFile(CONFIG_FILE, table.concat(data, "\n"))
end

local function loadConfig()
    local data = readFile(CONFIG_FILE)
    if not data then return end

    for line in data:gmatch("[^\r\n]+") do
        local key, value = line:match("^([^=]+)=(.*)$")

        if key and value then
            if key == "computerName" then
                config.computerName = value

            elseif key == "wallpaper" then
                config.wallpaper = tonumber(value) or 1

            elseif key == "username" then
                config.username = value

            elseif key == "displayName" then
                config.displayName = value

            elseif key == "setupComplete" then
                config.setupComplete = value == "true"

            elseif key == "version" then
                config.version = value
            end
        end
    end
end

loadConfig()

-- ---------------------------------------------------------
-- Password hashing
-- ---------------------------------------------------------

-- This is a lightweight local hash for a game OS prototype.
-- It is NOT secure cryptographic password storage.

local function hashPassword(password)
    local hash = 5381

    password = tostring(password or "")

    for i = 1, #password do
        hash = (hash * 33 + password:byte(i)) % 2147483647
    end

    return tostring(hash)
end

local function verifyPassword(password, savedHash)
    return hashPassword(password) == tostring(savedHash or "")
end

-- ---------------------------------------------------------
-- Account database
-- ---------------------------------------------------------

local accounts = {}

local function saveAccounts()
    local lines = {}

    for i = 1, #accounts do
        local account = accounts[i]

        local username = cleanValue(account.username)
        local displayName = cleanValue(account.displayName)
        local passwordHash = cleanValue(account.passwordHash)

        lines[#lines + 1] = table.concat({
            username,
            displayName,
            passwordHash
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
            line:match("^([^|]+)|([^|]*)|([^|]+)$")

        if username and passwordHash then
            accounts[#accounts + 1] = {
                username = username,
                displayName = displayName,
                passwordHash = passwordHash
            }
        end
    end
end

loadAccounts()

local function findAccount(username)
    username = tostring(username or ""):lower()

    for i = 1, #accounts do
        if accounts[i].username:lower() == username then
            return accounts[i], i
        end
    end

    return nil
end

local function validUsername(username)
    if #username < 3 or #username > 16 then
        return false
    end

    return username:match("^[a-zA-Z0-9_]+$") ~= nil
end

local function createAccount(username, displayName, password)
    username = tostring(username or ""):lower()
    displayName = tostring(displayName or "")
    password = tostring(password or "")

    if not validUsername(username) then
        return false, "Username must be 3-16 letters, numbers or underscores."
    end

    if findAccount(username) then
        return false, "That username already exists."
    end

    if #displayName < 1 or #displayName > 24 then
        return false, "Display name must be 1-24 characters."
    end

    if #password < 1 then
        return false, "Password cannot be empty."
    end

    accounts[#accounts + 1] = {
        username = username,
        displayName = cleanValue(displayName),
        passwordHash = hashPassword(password)
    }

    local success, reason = saveAccounts()

    if not success then
        accounts[#accounts] = nil
        return false, reason or "Could not save account."
    end

    return true
end

-- ---------------------------------------------------------
-- Input dialog
-- ---------------------------------------------------------

local function inputDialog(title, prompt, secret)
    local value = ""
    local cursor = 1

    while true do
        clear(C.background)

        rect(3, 3, W - 6, H - 6, C.panel)
        rect(3, 3, W - 6, 1, C.titlebar)

        put(5, 3, title, C.white)
        put(5, 6, prompt, C.muted)

        rect(5, 8, W - 10, 3, C.background)

        local shown = secret and string.rep("*", #value) or value

        put(6, 9, shown, C.white)
        put(6 + #shown, 9, "_", C.accent)

        center(H - 5, "ENTER: Confirm", C.accent)
        center(H - 3, "ESC: Cancel", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 or char == 27 then
                return nil

            elseif code == 28 or char == 13 then
                return value

            elseif code == 14 then
                if #value > 0 then
                    value = value:sub(1, -2)
                end

            elseif char and char >= 32 and char <= 126 then
                if #value < 48 then
                    value = value .. string.char(char)
                end
            end
        end
    end
end

-- ---------------------------------------------------------
-- Message dialog
-- ---------------------------------------------------------

local function messageDialog(title, message)
    clear(C.background)

    rect(3, 4, W - 6, H - 8, C.panel)
    rect(3, 4, W - 6, 1, C.titlebar)

    put(5, 4, title, C.white)

    local lineY = 7

    for line in tostring(message):gmatch("[^\n]+") do
        put(5, lineY, line, C.text)
        lineY = lineY + 1

        if lineY >= H - 5 then
            break
        end
    end

    center(H - 3, "Press any key to continue", C.accent)

    waitForKey()
end

-- ---------------------------------------------------------
-- Terms and conditions
-- ---------------------------------------------------------

local function termsScreen()
    local accepted = false
    local selection = 1

    while true do
        clear(C.background)

        rect(3, 2, W - 6, H - 4, C.panel)
        rect(3, 2, W - 6, 1, C.titlebar)

        put(5, 2, "MEADOWS TERMS AND CONDITIONS", C.white)

        put(5, 5, "Welcome to Meadows OS.", C.accent)

        put(5, 7, "Please read this playful system agreement:", C.text)

        put(5, 10, "1. You agree to use Meadows responsibly.", C.text)
        put(5, 12, "2. Your files and accounts are stored locally.", C.text)
        put(5, 14, "3. You have to become a slave to Izanox.", C.accent)

        put(5, 17, "This is a joke, not a real obligation.", C.muted)

        if selection == 1 then
            rect(5, H - 5, 15, 1, C.accentDark)
        else
            rect(24, H - 5, 15, 1, C.accentDark)
        end

        put(6, H - 5, "Accept", C.white)
        put(25, H - 5, "Decline", C.white)

        center(H - 2, "LEFT/RIGHT: Select     ENTER: Confirm", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 203 then
                selection = 1
            elseif code == 205 then
                selection = 2
            elseif code == 28 or char == 13 then
                if selection == 1 then
                    accepted = true
                    break
                else
                    accepted = false
                    break
                end
            end
        end
    end

    return accepted
end

-- ---------------------------------------------------------
-- First-time setup
-- ---------------------------------------------------------

local function setupWizard()
    if not termsScreen() then
        messageDialog(
            "Setup cancelled",
            "You declined the Meadows terms.\nSetup cannot continue."
        )

        computer.shutdown()
        return false
    end

    local computerName = inputDialog(
        "Computer name",
        "Choose a name for this computer:"
    )

    if not computerName then
        return false
    end

    if #computerName < 1 then
        computerName = "Meadows-PC"
    end

    local displayName = inputDialog(
        "Create account",
        "Enter your display name:"
    )

    if not displayName then
        return false
    end

    local username = inputDialog(
        "Create username",
        "Use 3-16 letters, numbers or underscores:"
    )

    if not username then
        return false
    end

    local password = inputDialog(
        "Create password",
        "Enter your account password:",
        true
    )

    if not password then
        return false
    end

    local confirmation = inputDialog(
        "Confirm password",
        "Enter your password again:",
        true
    )

    if not confirmation then
        return false
    end

    if password ~= confirmation then
        messageDialog("Password mismatch", "The passwords do not match.")
        return false
    end

    config.computerName = cleanValue(computerName)
    config.username = username:lower()
    config.displayName = cleanValue(displayName)

    local success, reason = createAccount(
        username,
        displayName,
        password
    )

    if not success then
        messageDialog("Account error", reason)
        return false
    end

    config.setupComplete = true

    local saved, saveError = saveConfig()

    if not saved then
        messageDialog(
            "Configuration error",
            tostring(saveError or "Could not save configuration.")
        )
        return false
    end

    messageDialog(
        "Setup complete",
        "Welcome to Meadows OS, " .. displayName .. "!\n\nYour account has been saved."
    )

    return true
end

-- ---------------------------------------------------------
-- Login screen
-- ---------------------------------------------------------

local function loginScreen()
    while true do
        clear(C.background)

        center(3, "MEADOWS OS", C.accent)
        center(5, config.computerName, C.muted)

        if #accounts == 0 then
            center(9, "No accounts were found.", C.text)
            center(11, "Restart setup to create an account.", C.muted)
            waitForKey()
            return nil
        end

        local selected = 1

        while true do
            clear(C.background)

            center(3, "WELCOME BACK", C.accent)
            center(5, "Select your account", C.white)

            for i = 1, #accounts do
                local account = accounts[i]
                local y = 8 + (i - 1) * 2

                if y < H - 4 then
                    if i == selected then
                        rect(4, y, W - 8, 1, C.accentDark)
                    end

                    put(
                        6,
                        y,
                        tostring(i) .. ". " ..
                        account.displayName ..
                        " (" .. account.username .. ")",
                        C.white
                    )
                end
            end

            center(H - 2, "UP/DOWN: Select     ENTER: Login", C.muted)

            local signal, address, char, code = computer.pullSignal()

            if signal == "key_down" then
                if code == 200 then
                    selected = math.max(1, selected - 1)

                elseif code == 208 then
                    selected = math.min(#accounts, selected + 1)

                elseif code == 28 or char == 13 then
                    local account = accounts[selected]

                    local password = inputDialog(
                        "Password",
                        "Enter password for " .. account.displayName .. ":",
                        true
                    )

                    if password then
                        if verifyPassword(password, account.passwordHash) then
                            return account
                        else
                            messageDialog(
                                "Login failed",
                                "Incorrect password. Please try again."
                            )
                        end
                    end

                    break

                elseif code == 1 then
                    break
                end
            end
        end
    end
end

-- ---------------------------------------------------------
-- Start setup or login
-- ---------------------------------------------------------

if not config.setupComplete or #accounts == 0 then
    local success = setupWizard()

    if not success then
        error("Meadows: Setup did not complete.")
    end

    loadAccounts()
end

local currentUser = loginScreen()

if not currentUser then
    error("Meadows: Login failed.")
end

config.username = currentUser.username
config.displayName = currentUser.displayName

saveConfig()
-- ---------------------------------------------------------
-- Keyboard helpers
-- ---------------------------------------------------------

local function pullKey()
    while true do
        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            return char, code
        end
    end
end

local function waitForKeyOrTouch()
    while true do
        local signal = computer.pullSignal()

        if signal == "key_down" or signal == "touch" then
            return signal
        end
    end
end

local function confirmDialog(title, message)
    local selection = 1

    while true do
        clear(C.background)

        rect(4, 5, W - 8, H - 10, C.panel)
        rect(4, 5, W - 8, 1, C.titlebar)

        put(6, 5, title, C.white)
        put(6, 8, message, C.text)

        if selection == 1 then
            rect(6, H - 5, 12, 1, C.accentDark)
        else
            rect(22, H - 5, 12, 1, C.accentDark)
        end

        put(7, H - 5, "Yes", C.white)
        put(23, H - 5, "No", C.white)

        center(H - 2, "LEFT/RIGHT: Select     ENTER: Confirm", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 203 then
                selection = 1
            elseif code == 205 then
                selection = 2
            elseif code == 28 or char == 13 then
                return selection == 1
            elseif code == 1 then
                return false
            end
        end
    end
end

-- ---------------------------------------------------------
-- Path utilities
-- ---------------------------------------------------------

local function normalizePath(path)
    path = tostring(path or "/")
    path = path:gsub("\\", "/")

    local segments = {}

    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #segments > 0 then
                segments[#segments] = nil
            end
        elseif part ~= "." and part ~= "" then
            segments[#segments + 1] = part
        end
    end

    if #segments == 0 then
        return "/"
    end

    return "/" .. table.concat(segments, "/")
end

local function joinPath(parent, child)
    parent = normalizePath(parent)
    child = tostring(child or "")

    if child:find("/", 1, true) or child:find("\\", 1, true) then
        return nil
    end

    if child == "" or child == "." or child == ".." then
        return nil
    end

    if parent == "/" then
        return normalizePath("/" .. child)
    end

    return normalizePath(parent .. "/" .. child)
end

local function isProtectedPath(path)
    path = normalizePath(path)

    return path == DATA_DIR or
        path:sub(1, #DATA_DIR + 1) == DATA_DIR .. "/"
end

local function safePath(path)
    path = normalizePath(path)

    if isProtectedPath(path) then
        return nil
    end

    return path
end

local function parentPath(path)
    path = normalizePath(path)

    if path == "/" then
        return "/"
    end

    local parent = path:match("^(.*)/[^/]+$")
    if not parent or parent == "" then
        return "/"
    end

    return parent
end

local function baseName(path)
    path = normalizePath(path)

    if path == "/" then
        return "/"
    end

    return path:match("([^/]+)$") or path
end

local function pathExists(path)
    return fsExists(filesystem, normalizePath(path))
end

local function isDirectory(path)
    local ok, result = pcall(filesystem.isDirectory, normalizePath(path))
    return ok and result == true
end

local function listDirectory(path)
    local result = {}

    local ok, iterator = pcall(filesystem.list, normalizePath(path))

    if not ok or not iterator then
        return result
    end

    while true do
        local success, item = pcall(iterator)

        if not success or not item then
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

        local da = pa and isDirectory(pa) or false
        local db = pb and isDirectory(pb) or false

        if da ~= db then
            return da
        end

        return a:lower() < b:lower()
    end)

    return result
end

-- ---------------------------------------------------------
-- File and folder creation
-- ---------------------------------------------------------

local function createFolder(path)
    path = safePath(path)

    if not path then
        return false, "Protected system location."
    end

    if pathExists(path) then
        return false, "This item already exists."
    end

    local ok, result = pcall(filesystem.makeDirectory, path)

    if not ok or result == false or not pathExists(path) then
        return false, "Could not create folder."
    end

    return true
end

local function createFile(path, content)
    path = safePath(path)

    if not path then
        return false, "Protected system location."
    end

    if pathExists(path) then
        return false, "This item already exists."
    end

    local success, reason = fsWrite(filesystem, path, content or "")

    if not success then
        return false, reason
    end

    return true
end

-- ---------------------------------------------------------
-- Recursive deletion
-- ---------------------------------------------------------

local function deletePath(path)
    path = safePath(path)

    if not path or path == "/" then
        return false, "Cannot delete this location."
    end

    if not pathExists(path) then
        return false, "Item does not exist."
    end

    if isDirectory(path) then
        local entries = listDirectory(path)

        for i = 1, #entries do
            local child = joinPath(path, entries[i])

            if child then
                local success, reason = deletePath(child)

                if not success then
                    return false, reason
                end
            end
        end
    end

    local ok, result = pcall(filesystem.remove, path)

    if not ok or result == false or pathExists(path) then
        return false, "Could not delete item."
    end

    return true
end

-- ---------------------------------------------------------
-- Rename
-- ---------------------------------------------------------

local function renamePath(oldPath, newName)
    oldPath = safePath(oldPath)

    if not oldPath then
        return false, "Protected system location."
    end

    newName = tostring(newName or "")

    if newName == "" or newName == "." or newName == ".." or
        newName:find("/", 1, true) or
        newName:find("\\", 1, true) then
        return false, "Invalid new name."
    end

    local destination = joinPath(parentPath(oldPath), newName)

    if not destination then
        return false, "Invalid destination."
    end

    if pathExists(destination) then
        return false, "An item with that name already exists."
    end

    local ok, result = pcall(filesystem.rename, oldPath, destination)

    if not ok or result == false or not pathExists(destination) then
        return false, "Rename failed."
    end

    return true
end

-- ---------------------------------------------------------
-- Binary-safe file copy
-- ---------------------------------------------------------

local function copyFile(source, destination)
    source = safePath(source)
    destination = safePath(destination)

    if not source or not destination then
        return false, "Protected system location."
    end

    if not pathExists(source) or isDirectory(source) then
        return false, "Source is not a regular file."
    end

    if pathExists(destination) then
        return false, "Destination already exists."
    end

    local sourceHandle
    local destinationHandle

    local ok, reason = pcall(function()
        sourceHandle = assert(filesystem.open(source, "r"))
        destinationHandle = assert(filesystem.open(destination, "w"))

        while true do
            local chunk = filesystem.read(sourceHandle, 4096)

            if not chunk or #chunk == 0 then
                break
            end

            local written = filesystem.write(destinationHandle, chunk)

            if written == false then
                error("Write failed.")
            end
        end
    end)

    if sourceHandle then
        pcall(filesystem.close, sourceHandle)
    end

    if destinationHandle then
        pcall(filesystem.close, destinationHandle)
    end

    if not ok then
        pcall(filesystem.remove, destination)
        return false, tostring(reason)
    end

    return true
end

-- ---------------------------------------------------------
-- Recursive copy
-- ---------------------------------------------------------

local function copyPath(source, destination)
    source = safePath(source)
    destination = safePath(destination)

    if not source or not destination then
        return false, "Protected system location."
    end

    if not pathExists(source) then
        return false, "Source does not exist."
    end

    if pathExists(destination) then
        return false, "Destination already exists."
    end

    if isDirectory(source) then
        if destination:sub(1, #source + 1) == source .. "/" then
            return false, "Cannot copy a folder into itself."
        end

        local ok, result = pcall(filesystem.makeDirectory, destination)

        if not ok or result == false then
            return false, "Could not create destination folder."
        end

        local entries = listDirectory(source)

        for i = 1, #entries do
            local childSource = joinPath(source, entries[i])
            local childDestination = joinPath(destination, entries[i])

            if childSource and childDestination then
                local success, reason =
                    copyPath(childSource, childDestination)

                if not success then
                    return false, reason
                end
            end
        end

        return true
    end

    return copyFile(source, destination)
end

-- ---------------------------------------------------------
-- Clipboard
-- ---------------------------------------------------------

local clipboard = nil
local clipboardMode = nil

local function pasteClipboard(currentDirectory)
    if not clipboard then
        return false, "Clipboard is empty."
    end

    local destination = joinPath(
        currentDirectory,
        baseName(clipboard)
    )

    if not destination then
        return false, "Invalid destination."
    end

    if pathExists(destination) then
        return false, "An item with that name already exists."
    end

    local success, reason = copyPath(clipboard, destination)

    if not success then
        return false, reason
    end

    if clipboardMode == "cut" then
        local removed, removeReason = deletePath(clipboard)

        if not removed then
            return false, "Copied, but original could not be removed: " ..
                tostring(removeReason)
        end
    end

    clipboard = nil
    clipboardMode = nil

    return true
end

-- ---------------------------------------------------------
-- Simple text editor
-- ---------------------------------------------------------

local function textEditor(path, initialText)
    local content = tostring(initialText or "")
    local lines = {}

    local function rebuildLines()
        lines = {}

        for line in (content .. "\n"):gmatch("(.-)\n") do
            lines[#lines + 1] = line
        end

        if #lines == 0 then
            lines[1] = ""
        end
    end

    rebuildLines()

    local cursorLine = #lines
    local cursorColumn = #(lines[cursorLine] or "")

    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "NOTEPAD - " .. baseName(path), C.white)

        local maxLines = H - 9
        local firstLine = math.max(
            1,
            cursorLine - maxLines + 1
        )

        for i = firstLine, math.min(#lines, firstLine + maxLines - 1) do
            put(4, 4 + i - firstLine, lines[i], C.text)
        end

        local cursorY = 4 + cursorLine - firstLine
        local cursorX = 4 + cursorColumn

        put(cursorX, cursorY, "_", C.accent)

        center(H - 3, "CTRL+S: Save     ESC: Exit", C.accent)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                local answer = confirmDialog(
                    "Close editor",
                    "Save before closing?"
                )

                if answer then
                    local success, reason = writeFile(
                        path,
                        table.concat(lines, "\n")
                    )

                    if not success then
                        messageDialog("Save failed", tostring(reason))
                    end
                end

                return

            elseif code == 31 and
                (char == 115 or char == 83) then

                local success, reason = writeFile(
                    path,
                    table.concat(lines, "\n")
                )

                if success then
                    messageDialog("Saved", "Your changes were saved.")
                else
                    messageDialog("Save failed", tostring(reason))
                end

            elseif code == 14 then
                if cursorColumn > 0 then
                    local line = lines[cursorLine]

                    lines[cursorLine] =
                        line:sub(1, cursorColumn) ..
                        line:sub(cursorColumn + 2)

                    cursorColumn = cursorColumn - 1

                elseif cursorLine > 1 then
                    local previous = lines[cursorLine - 1]
                    local current = lines[cursorLine]

                    cursorColumn = #previous
                    lines[cursorLine - 1] = previous .. current

                    table.remove(lines, cursorLine)
                    cursorLine = cursorLine - 1
                end

            elseif code == 28 then
                local line = lines[cursorLine]

                local left = line:sub(1, cursorColumn)
                local right = line:sub(cursorColumn + 1)

                lines[cursorLine] = left
                table.insert(lines, cursorLine + 1, right)

                cursorLine = cursorLine + 1
                cursorColumn = 0

            elseif code == 203 then
                cursorColumn = math.max(0, cursorColumn - 1)

            elseif code == 205 then
                cursorColumn = math.min(
                    #lines[cursorLine],
                    cursorColumn + 1
                )

            elseif code == 200 then
                cursorLine = math.max(1, cursorLine - 1)
                cursorColumn = math.min(
                    cursorColumn,
                    #lines[cursorLine]
                )

            elseif code == 208 then
                cursorLine = math.min(#lines, cursorLine + 1)
                cursorColumn = math.min(
                    cursorColumn,
                    #lines[cursorLine]
                )

            elseif char and char >= 32 and char <= 126 then
                local line = lines[cursorLine]

                lines[cursorLine] =
                    line:sub(1, cursorColumn) ..
                    string.char(char) ..
                    line:sub(cursorColumn + 1)

                cursorColumn = cursorColumn + 1
            end
        end
    end
end

-- ---------------------------------------------------------
-- File Explorer
-- ---------------------------------------------------------

local function filesApp()
    local currentDirectory = "/"
    local selectedIndex = 1
    local scroll = 0

    while true do
        local entries = listDirectory(currentDirectory)

        local rows = {}

        if currentDirectory ~= "/" then
            rows[#rows + 1] = {
                name = "..",
                path = parentPath(currentDirectory),
                directory = true,
                parent = true
            }
        end

        for i = 1, #entries do
            local path = joinPath(currentDirectory, entries[i])

            rows[#rows + 1] = {
                name = entries[i],
                path = path,
                directory = path and isDirectory(path) or false,
                parent = false
            }
        end

        if selectedIndex > #rows then
            selectedIndex = math.max(1, #rows)
        end

        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "FILES", C.white)
        put(4, 4, "Location: " .. currentDirectory, C.accent)

        put(4, 6, "Name", C.muted)
        put(W - 17, 6, "Type", C.muted)

        local visible = H - 13

        if selectedIndex > scroll + visible then
            scroll = selectedIndex - visible
        elseif selectedIndex <= scroll then
            scroll = selectedIndex - 1
        end

        for i = 1, visible do
            local index = i + scroll
            local item = rows[index]

            if item then
                local y = 7 + i

                if index == selectedIndex then
                    rect(3, y, W - 6, 1, C.accentDark)
                end

                local icon = item.directory and "[DIR] " or "[FILE] "

                put(4, y, icon .. item.name, C.text)

                put(
                    W - 17,
                    y,
                    item.directory and "Folder" or "File",
                    C.muted
                )
            end
        end

        center(H - 5, "ENTER: Open     ESC: Desktop", C.accent)
        center(H - 3, "N: New folder   F: New file   R: Rename", C.muted)
        center(H - 2, "C: Copy   X: Cut   V: Paste   D: Delete", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                return

            elseif code == 200 then
                selectedIndex = math.max(1, selectedIndex - 1)

            elseif code == 208 then
                selectedIndex = math.min(
                    math.max(1, #rows),
                    selectedIndex + 1
                )

            elseif code == 28 then
                local item = rows[selectedIndex]

                if item then
                    if item.directory then
                        currentDirectory = item.path
                        selectedIndex = 1
                        scroll = 0
                    else
                        local content = readFile(item.path)

                        if content then
                            textEditor(item.path, content)
                        else
                            messageDialog(
                                "Open failed",
                                "Could not read this file."
                            )
                        end
                    end
                end

            elseif char == 110 or char == 78 then
                local name = inputDialog(
                    "New folder",
                    "Enter folder name:"
                )

                if name then
                    local destination = joinPath(currentDirectory, name)

                    if destination then
                        local success, reason = createFolder(destination)

                        if not success then
                            messageDialog("Folder error", tostring(reason))
                        end
                    end
                end

            elseif char == 102 or char == 70 then
                local name = inputDialog(
                    "New file",
                    "Enter file name:"
                )

                if name then
                    local destination = joinPath(currentDirectory, name)

                    if destination then
                        local success, reason = createFile(destination, "")

                        if not success then
                            messageDialog("File error", tostring(reason))
                        end
                    end
                end

            elseif char == 114 or char == 82 then
                local item = rows[selectedIndex]

                if item and not item.parent then
                    local name = inputDialog(
                        "Rename",
                        "Enter the new name:"
                    )

                    if name then
                        local success, reason = renamePath(
                            item.path,
                            name
                        )

                        if not success then
                            messageDialog("Rename error", tostring(reason))
                        end
                    end
                end

            elseif char == 99 or char == 67 then
                local item = rows[selectedIndex]

                if item and not item.parent then
                    clipboard = item.path
                    clipboardMode = "copy"
                end

            elseif char == 120 or char == 88 then
                local item = rows[selectedIndex]

                if item and not item.parent then
                    clipboard = item.path
                    clipboardMode = "cut"
                end

            elseif char == 118 or char == 86 then
                local success, reason = pasteClipboard(currentDirectory)

                if not success then
                    messageDialog("Paste failed", tostring(reason))
                end

            elseif char == 100 or char == 68 then
                local item = rows[selectedIndex]

                if item and not item.parent then
                    if confirmDialog(
                        "Delete item",
                        "Delete " .. item.name .. "?"
                    ) then
                        local success, reason = deletePath(item.path)

                        if not success then
                            messageDialog("Delete failed", tostring(reason))
                        end

                        selectedIndex = 1
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------
-- Notes application
-- ---------------------------------------------------------

local function notesApp()
    local content = readFile(NOTES_FILE) or ""

    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "MEADOWS NOTES", C.white)

        put(4, 5, "Your notes are stored on the Meadows drive.", C.muted)

        local line = 7

        for textLine in (content .. "\n"):gmatch("(.-)\n") do
            if line >= H - 6 then break end

            put(4, line, textLine, C.text)
            line = line + 1
        end

        center(H - 5, "A: Add note     C: Clear notes", C.accent)
        center(H - 3, "ESC: Return to desktop", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                return

            elseif char == 97 or char == 65 then
                local note = inputDialog(
                    "Add note",
                    "Write your note:"
                )

                if note and note ~= "" then
                    if content ~= "" then
                        content = content .. "\n"
                    end

                    content = content .. note

                    local success, reason = writeFile(
                        NOTES_FILE,
                        content
                    )

                    if not success then
                        messageDialog("Notes error", tostring(reason))
                    end
                end

            elseif char == 99 or char == 67 then
                if confirmDialog(
                    "Clear notes",
                    "Delete all saved notes?"
                ) then
                    content = ""

                    local success, reason = writeFile(
                        NOTES_FILE,
                        content
                    )

                    if not success then
                        messageDialog("Notes error", tostring(reason))
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------
-- Terminal
-- ---------------------------------------------------------

local function terminalApp()
    local currentDirectory = "/"
    local history = {}
    local running = true

    local function terminalPrint(message, color)
        history[#history + 1] = {
            text = tostring(message),
            color = color or C.text
        }

        while #history > H - 9 do
            table.remove(history, 1)
        end
    end

    local function executeCommand(command)
        local args = {}

        for word in command:gmatch("%S+") do
            args[#args + 1] = word
        end

        local cmd = args[1]

        if not cmd then return end

        if cmd == "help" then
            terminalPrint("Available commands:")
            terminalPrint("help - Show commands")
            terminalPrint("clear - Clear terminal")
            terminalPrint("pwd - Current directory")
            terminalPrint("ls - List files")
            terminalPrint("cd PATH - Change directory")
            terminalPrint("mkdir NAME - Create folder")
            terminalPrint("touch NAME - Create file")
            terminalPrint("cat NAME - Read text file")
            terminalPrint("rm NAME - Delete item")
            terminalPrint("rename OLD NEW - Rename item")
            terminalPrint("whoami - Current account")
            terminalPrint("about - OS information")
            terminalPrint("reboot - Restart computer")
            terminalPrint("shutdown - Shut down computer")

        elseif cmd == "clear" then
            history = {}

        elseif cmd == "pwd" then
            terminalPrint(currentDirectory)

        elseif cmd == "ls" then
            local entries = listDirectory(currentDirectory)

            if #entries == 0 then
                terminalPrint("(empty)")
            else
                for i = 1, #entries do
                    local path = joinPath(currentDirectory, entries[i])
                    local suffix = path and isDirectory(path) and "/" or ""

                    terminalPrint(entries[i] .. suffix)
                end
            end

        elseif cmd == "cd" then
            local target = args[2] or "/"

            local destination

            if target:sub(1, 1) == "/" then
                destination = normalizePath(target)
            else
                destination = normalizePath(currentDirectory .. "/" .. target)
            end

            if pathExists(destination) and isDirectory(destination) then
                currentDirectory = destination
            else
                terminalPrint("Directory not found.", C.close)
            end

        elseif cmd == "mkdir" then
            if not args[2] then
                terminalPrint("Usage: mkdir NAME", C.close)
            else
                local destination = joinPath(currentDirectory, args[2])

                local success, reason = destination and
                    createFolder(destination)

                if success then
                    terminalPrint("Folder created.", C.accent)
                else
                    terminalPrint(reason or "Invalid folder name.", C.close)
                end
            end

        elseif cmd == "touch" then
            if not args[2] then
                terminalPrint("Usage: touch NAME", C.close)
            else
                local destination = joinPath(currentDirectory, args[2])

                local success, reason = destination and
                    createFile(destination, "")

                if success then
                    terminalPrint("File created.", C.accent)
                else
                    terminalPrint(reason or "Invalid file name.", C.close)
                end
            end

        elseif cmd == "cat" then
            if not args[2] then
                terminalPrint("Usage: cat NAME", C.close)
            else
                local destination = joinPath(currentDirectory, args[2])

                if destination and pathExists(destination) and
                    not isDirectory(destination) then

                    terminalPrint(readFile(destination) or "")
                else
                    terminalPrint("File not found.", C.close)
                end
            end

        elseif cmd == "rm" then
            if not args[2] then
                terminalPrint("Usage: rm NAME", C.close)
            else
                local destination = joinPath(currentDirectory, args[2])

                if destination then
                    local success, reason = deletePath(destination)

                    if success then
                        terminalPrint("Deleted.", C.accent)
                    else
                        terminalPrint(reason, C.close)
                    end
                end
            end

        elseif cmd == "rename" then
            if not args[2] or not args[3] then
                terminalPrint("Usage: rename OLD NEW", C.close)
            else
                local destination = joinPath(currentDirectory, args[2])

                local success, reason = destination and
                    renamePath(destination, args[3])

                if success then
                    terminalPrint("Renamed.", C.accent)
                else
                    terminalPrint(reason or "Rename failed.", C.close)
                end
            end

        elseif cmd == "whoami" then
            terminalPrint(currentUser.username)

        elseif cmd == "about" then
            terminalPrint("Meadows OS " .. VERSION)
            terminalPrint("Forest Edition")
            terminalPrint("Computer: " .. config.computerName)
            terminalPrint("User: " .. currentUser.displayName)

        elseif cmd == "reboot" then
            computer.shutdown(true)

        elseif cmd == "shutdown" then
            computer.shutdown()

        else
            terminalPrint("Unknown command: " .. cmd, C.close)
            terminalPrint("Type help for commands.")
        end
    end

    while running do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "MEADOWS TERMINAL", C.white)

        for i = 1, #history do
            local y = 4 + i

            if y < H - 4 then
                put(4, y, history[i].text, history[i].color)
            end
        end

        put(4, H - 4, currentDirectory .. " >", C.accent)

        local command = inputDialog(
            "Terminal command",
            "Enter a command:"
        )

        if command == nil then
            running = false
        elseif command ~= "" then
            executeCommand(command)
        end
    end
end

-- =========================================================
-- MEADOWS OS 1.2
-- PART 4 OF 4
-- DESKTOP, TASKBAR, START MENU AND SYSTEM
-- =========================================================

-- ---------------------------------------------------------
-- Wallpaper presets
-- ---------------------------------------------------------

local wallpapers = {
    0x102019,
    0x101B30,
    0x241B30,
    0x202020,
    0x0B2528
}

local wallpaperNames = {
    "Forest",
    "Midnight",
    "Purple",
    "Dark",
    "Ocean"
}

local function getWallpaper()
    local index = tonumber(config.wallpaper) or 1
    return wallpapers[index] or wallpapers[1]
end

-- ---------------------------------------------------------
-- Desktop application registry
-- ---------------------------------------------------------

local apps = {
    {
        id = "files",
        name = "Files",
        icon = "[F]",
        run = filesApp
    },
    {
        id = "notes",
        name = "Notes",
        icon = "[N]",
        run = notesApp
    },
    {
        id = "terminal",
        name = "Terminal",
        icon = "[T]",
        run = terminalApp
    },
    {
        id = "settings",
        name = "Settings",
        icon = "[S]"
    },
    {
        id = "about",
        name = "About",
        icon = "[?]"
    }
}

local function findApp(id)
    for i = 1, #apps do
        if apps[i].id == id then
            return apps[i]
        end
    end

    return nil
end

-- ---------------------------------------------------------
-- Application launcher
-- ---------------------------------------------------------

local function launchApp(id)
    local app = findApp(id)

    if not app then
        return
    end

    if app.run then
        app.run()
    elseif id == "settings" then
        -- Settings is defined below.
    elseif id == "about" then
        -- About is defined below.
    end
end

-- ---------------------------------------------------------
-- Settings application
-- ---------------------------------------------------------

local function settingsApp()
    local selection = 1

    local options = {
        "Computer name",
        "Change password",
        "Wallpaper",
        "Storage information",
        "System information",
        "Return to desktop"
    }

    while true do
        clear(C.background)

        rect(2, 2, W - 4, H - 4, C.panel)
        rect(2, 2, W - 4, 1, C.titlebar)

        put(4, 2, "MEADOWS SETTINGS", C.white)

        put(4, 4, "Personalize and manage your system.", C.muted)

        for i = 1, #options do
            local y = 7 + (i - 1) * 2

            if i == selection then
                rect(3, y, W - 6, 1, C.accentDark)
            end

            put(5, y, options[i], C.text)
        end

        center(H - 2, "UP/DOWN: Select     ENTER: Open     ESC: Back", C.muted)

        local signal, address, char, code = computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                return

            elseif code == 200 then
                selection = math.max(1, selection - 1)

            elseif code == 208 then
                selection = math.min(#options, selection + 1)

            elseif code == 28 then
                if selection == 1 then
                    local name = inputDialog(
                        "Computer name",
                        "Enter your new computer name:"
                    )

                    if name and name ~= "" then
                        config.computerName = cleanValue(name)
                        saveConfig()

                        messageDialog(
                            "Settings saved",
                            "Computer name updated."
                        )
                    end

                elseif selection == 2 then
                    local oldPassword = inputDialog(
                        "Current password",
                        "Enter your current password:",
                        true
                    )

                    if oldPassword then
                        if verifyPassword(
                            oldPassword,
                            currentUser.passwordHash
                        ) then
                            local newPassword = inputDialog(
                                "New password",
                                "Enter your new password:",
                                true
                            )

                            if newPassword and newPassword ~= "" then
                                local confirmPassword = inputDialog(
                                    "Confirm password",
                                    "Enter your new password again:",
                                    true
                                )

                                if confirmPassword == newPassword then
                                    currentUser.passwordHash =
                                        hashPassword(newPassword)

                                    local success, reason = saveAccounts()

                                    if success then
                                        messageDialog(
                                            "Password changed",
                                            "Your password has been updated."
                                        )
                                    else
                                        messageDialog(
                                            "Save failed",
                                            tostring(reason)
                                        )
                                    end
                                else
                                    messageDialog(
                                        "Password mismatch",
                                        "The new passwords do not match."
                                    )
                                end
                            end
                        else
                            messageDialog(
                                "Incorrect password",
                                "Your current password was incorrect."
                            )
                        end
                    end

                elseif selection == 3 then
                    local wallpaperSelection =
                        tonumber(config.wallpaper) or 1

                    while true do
                        clear(C.background)

                        center(3, "CHOOSE WALLPAPER", C.accent)

                        for i = 1, #wallpaperNames do
                            local y = 7 + (i - 1) * 2

                            if i == wallpaperSelection then
                                rect(5, y, W - 10, 1, C.accentDark)
                            end

                            put(7, y, wallpaperNames[i], C.white)
                        end

                        center(H - 2, "UP/DOWN: Select     ENTER: Apply     ESC: Back", C.muted)

                        local s, a, ch, co = computer.pullSignal()

                        if s == "key_down" then
                            if co == 1 then
                                break

                            elseif co == 200 then
                                wallpaperSelection = math.max(
                                    1,
                                    wallpaperSelection - 1
                                )

                            elseif co == 208 then
                                wallpaperSelection = math.min(
                                    #wallpaperNames,
                                    wallpaperSelection + 1
                                )

                            elseif co == 28 then
                                config.wallpaper = wallpaperSelection
                                saveConfig()

                                messageDialog(
                                    "Wallpaper updated",
                                    "Your desktop wallpaper has been changed."
                                )

                                break
                            end
                        end
                    end

                elseif selection == 4 then
                    local free = math.max(
                        0,
                        selectedDisk.total - selectedDisk.used
                    )

                    messageDialog(
                        "Storage information",
                        "Drive: " .. selectedDisk.label ..
                        "\nAddress: " .. STORAGE_ADDRESS ..
                        "\nTotal: " .. math.floor(selectedDisk.total / 1024) .. " KB" ..
                        "\nUsed: " .. math.floor(selectedDisk.used / 1024) .. " KB" ..
                        "\nFree: " .. math.floor(free / 1024) .. " KB"
                    )

                elseif selection == 5 then
                    messageDialog(
                        "System information",
                        "Operating system: Meadows OS" ..
                        "\nVersion: " .. VERSION ..
                        "\nEdition: Forest Edition" ..
                        "\nComputer: " .. config.computerName ..
                        "\nUser: " .. currentUser.username ..
                        "\nMaximum windows setting: " .. MAX_WINDOWS
                    )

                elseif selection == 6 then
                    return
                end
            end
        end
    end
end

-- ---------------------------------------------------------
-- About application
-- ---------------------------------------------------------

local function aboutApp()
    clear(C.background)

    rect(3, 3, W - 6, H - 6, C.panel)
    rect(3, 3, W - 6, 1, C.titlebar)

    center(6, "MEADOWS OS", C.accent)
    center(8, "FOREST EDITION", C.white)

    center(11, "Version " .. VERSION, C.text)
    center(13, "A desktop operating system for OpenComputers.", C.muted)

    center(16, "Computer: " .. config.computerName, C.text)
    center(18, "User: " .. currentUser.displayName, C.text)

    center(H - 3, "Press any key to return", C.accent)

    waitForKey()
end

-- ---------------------------------------------------------
-- Update application launcher
-- ---------------------------------------------------------

local function launchApp(id)
    if id == "settings" then
        settingsApp()

    elseif id == "about" then
        aboutApp()

    else
        local app = findApp(id)

        if app and app.run then
            app.run()
        end
    end
end

-- ---------------------------------------------------------
-- Start menu
-- ---------------------------------------------------------

local function startMenu()
    local selection = 1

    local menuItems = {
        {name = "Files", id = "files"},
        {name = "Notes", id = "notes"},
        {name = "Terminal", id = "terminal"},
        {name = "Settings", id = "settings"},
        {name = "About Meadows", id = "about"},
        {name = "Restart", id = "restart"},
        {name = "Shut down", id = "shutdown"}
    }

    while true do
        clear(getWallpaper())

        -- Background desktop.
        center(3, "MEADOWS", C.accent)
        center(5, "FOREST EDITION", C.muted)

        local menuWidth = math.min(34, W - 8)
        local menuX = math.floor((W - menuWidth) / 2)
        local menuY = math.max(2, H - 17)

        rect(menuX, menuY, menuWidth, 15, C.panel)
        rect(menuX, menuY, menuWidth, 1, C.titlebar)

        put(menuX + 2, menuY, "START", C.white)

        for i = 1, #menuItems do
            local y = menuY + 2 + (i - 1) * 1

            if i == selection then
                rect(menuX + 1, y, menuWidth - 2, 1, C.accentDark)
            end

            put(menuX + 3, y, menuItems[i].name, C.text)
        end

        put(menuX + 2, menuY + 11, currentUser.displayName, C.accent)
        put(menuX + 2, menuY + 13, "Meadows OS " .. VERSION, C.muted)

        local signal, address, char, code, x, y, button =
            computer.pullSignal()

        if signal == "key_down" then
            if code == 1 then
                return

            elseif code == 200 then
                selection = math.max(1, selection - 1)

            elseif code == 208 then
                selection = math.min(#menuItems, selection + 1)

            elseif code == 28 then
                local id = menuItems[selection].id

                if id == "restart" then
                    computer.shutdown(true)
                    return

                elseif id == "shutdown" then
                    computer.shutdown()
                    return
                else
                    launchApp(id)
                    return
                end
            end

        elseif signal == "touch" then
            if y >= menuY + 2 and y <= menuY + 8 then
                local index = y - menuY - 1

                if index >= 1 and index <= #menuItems then
                    local id = menuItems[index].id

                    if id == "restart" then
                        computer.shutdown(true)
                        return

                    elseif id == "shutdown" then
                        computer.shutdown()
                        return
                    else
                        launchApp(id)
                        return
                    end
                end
            end

            return
        end
    end
end

-- ---------------------------------------------------------
-- Desktop rendering
-- ---------------------------------------------------------

local desktopIcons = {
    {id = "files", name = "Files", x = 4, y = 4},
    {id = "notes", name = "Notes", x = 16, y = 4},
    {id = "terminal", name = "Terminal", x = 4, y = 10},
    {id = "settings", name = "Settings", x = 16, y = 10},
    {id = "about", name = "About", x = 4, y = 16}
}

local function drawDesktopIcon(icon, selected)
    local background = selected and C.accentDark or C.panel2

    rect(icon.x, icon.y, 7, 3, background)

    rect(
        icon.x + 2,
        icon.y + 1,
        3,
        1,
        selected and C.accent or C.accentDark
    )

    put(icon.x + 1, icon.y + 1,
        icon.id:sub(1, 1):upper(), C.white)

    if selected then
        rect(icon.x - 1, icon.y + 3, #icon.name + 2, 1, C.accentDark)
    end

    put(icon.x, icon.y + 3, icon.name, C.text)
end

local function taskbarLayout()
    local count = 4
    local spacing = 8
    local startX = math.floor((W - (count * spacing - 1)) / 2)

    return {
        startX = startX,
        spacing = spacing,
        count = count,
        y = H - 2
    }
end

local function drawTaskbar()
    local layout = taskbarLayout()

    rect(1, H - 2, W, 2, C.panel)

    local items = {
        {id = "start", label = "M"},
        {id = "files", label = "F"},
        {id = "notes", label = "N"},
        {id = "terminal", label = "T"}
    }

    for i = 1, #items do
        local x = layout.startX + (i - 1) * layout.spacing

        rect(x, H - 2, 5, 2, C.panel2)
        put(x + 2, H - 2, items[i].label, C.accent)
    end

    local clock = tostring(math.floor(computer.uptime())) .. "s"
    put(W - #clock - 2, H - 2, clock, C.muted)

    return items, layout
end

local selectedDesktopIcon = nil
local function drawDesktop()
    clear(getWallpaper())

    -- Decorative desktop heading.
    put(4, 2, "MEADOWS", C.accent)
    put(4, 3, "FOREST EDITION", C.white)

    for i = 1, #desktopIcons do
        drawDesktopIcon(
            desktopIcons[i],
            selectedDesktopIcon == i
        )
    end

    put(4, H - 4, "Welcome, " .. currentUser.displayName, C.white)

    drawTaskbar()
end

-- ---------------------------------------------------------
-- Desktop event loop
-- ---------------------------------------------------------

local function desktop()
    while true do
        drawDesktop()

        local signal, address, char, code, x, y, button =
            computer.pullSignal()

        if signal == "key_down" then
            -- ESC opens Start menu.
            if code == 1 then
                startMenu()

            -- Keyboard shortcuts.
            elseif char == 102 or char == 70 then
                launchApp("files")

            elseif char == 110 or char == 78 then
                launchApp("notes")

            elseif char == 116 or char == 84 then
                launchApp("terminal")

            elseif char == 115 or char == 83 then
                launchApp("settings")

            elseif char == 97 or char == 65 then
                launchApp("about")
            end

        elseif signal == "touch" then
            -- Ensure touch coordinates are numbers.
            x = tonumber(x) or 0
            y = tonumber(y) or 0

            local taskItems, layout = drawTaskbar()

            -- Ensure taskbar layout values are numbers.
            local startX = tonumber(layout.startX) or 1
            local spacing = tonumber(layout.spacing) or 8

            -- Taskbar buttons.
            if y >= (tonumber(H) or 16) - 2 then
                for i = 1, #taskItems do
                    local buttonX = startX + (i - 1) * spacing

                    if x >= buttonX and x <= buttonX + 4 then
                        local id = taskItems[i].id

                        if id == "start" then
                            startMenu()
                        else
                            launchApp(id)
                        end

                        break
                    end
                end
            end

            else
                -- Desktop icons.
                for i = 1, #desktopIcons do
                    local icon = desktopIcons[i]

                    if x >= icon.x - 1 and
                        x <= icon.x + 7 and
                        y >= icon.y and
                        y <= icon.y + 4 then

                        selectedDesktopIcon = i
                        drawDesktop()
                        launchApp(icon.id)
                        break
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------
-- Final startup
-- ---------------------------------------------------------

clear(C.background)

gpu.setBackground(C.background)
gpu.setForeground(C.accent)

center(H - 2, "Loading Meadows desktop...", C.accent)

computer.pullSignal(0.5)

clear(getWallpaper())
desktop()
