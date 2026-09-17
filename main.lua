-- NYRA UI PERFORMANCE MODE: lightweight visuals + short event-driven tweens.
local Players = game:GetService("Players")

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer

-- ═══════════════════════════════
-- CONFIG / PERSISTENCE
-- ═══════════════════════════════
local CONFIG_FOLDER = "PhotonConfigs"
local STATE_FILE = "PhotonConfigs/_state.json"
local AUTO_LOAD_FILE = "PhotonConfigs/_autoload.txt"
local SELF_PATH = "PhotonConfigs/_script.lua"

local hasFileAPI = (writefile and readfile and isfile and listfiles and makefolder and isfolder)
local hasQueue = (queue_on_teleport ~= nil) or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)

local state = {
    farms = { Dumpster = false, Cash = false, Register = false, SuperFarm = false },
    
    protection = { AntiAFK = false, AntiAdmin = true },
    cashTransfer = { selectedName = "", running = false },
    running = true, minimized = false, currentTab = "Farms",
    farmMovementMode = "TP",
    autoReExecute = true,
    loadedConfigName = nil
}


local function safeWrite(path, data)
    if not writefile then return false end
    return (pcall(function() writefile(path, data) end))
end

local function safeRead(path)
    if not readfile or not isfile then return nil end
    local ok, data = pcall(function()
        if isfile(path) then return readfile(path) end
        return nil
    end)
    if ok then return data end
    return nil
end

local function safeList(folder)
    if not listfiles then return {} end
    local ok, files = pcall(function()
        if isfolder and isfolder(folder) then return listfiles(folder) end
        return listfiles("")
    end)
    if ok and files then return files end
    return {}
end

local function safeFolder(folder)
    if not makefolder or not isfolder then return end
    pcall(function()
        if not isfolder(folder) then makefolder(folder) end
    end)
end

local function safeDelete(path)
    if not delfile then return end
    pcall(function() delfile(path) end)
end

safeFolder(CONFIG_FOLDER)

local function listConfigs()
    local configs = {}
    local seen = {}
    local searchPaths = {CONFIG_FOLDER, "", CONFIG_FOLDER .. "/"}
    for _, searchPath in ipairs(searchPaths) do
        local files = safeList(searchPath)
        for _, file in ipairs(files) do
            local cleanPath = file
            if searchPath == "" and not cleanPath:find("PhotonConfigs") then
                -- skip
            else
                local name = cleanPath:match("PhotonConfigs[/\\]([^/\\]+)%.json$")
                if not name then name = cleanPath:match("([^/\\]+)%.json$") end
                if name and name ~= "_last" and name ~= "_state" and name ~= "_script" and not seen[name] then
                    seen[name] = true
                    table.insert(configs, name)
                end
            end
        end
    end
    table.sort(configs)
    return configs
end

local function saveConfig(name)
    local data = {
        farms = state.farms,
        farmMovementMode = state.farmMovementMode,
        
        protection = state.protection,
        antiAdmin = { enabled = antiAdmin.enabled, autoLeave = antiAdmin.autoLeave },
        cashTransfer = state.cashTransfer
    }
    return safeWrite(CONFIG_FOLDER .. "/" .. name .. ".json", HttpService:JSONEncode(data))
end

local function loadConfigData(name)
    local raw = safeRead(CONFIG_FOLDER .. "/" .. name .. ".json")
    if not raw then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok then return data end
    return nil
end

local function deleteConfig(name)
    safeDelete(CONFIG_FOLDER .. "/" .. name .. ".json")
end

local function setAutoLoadConfig(name)
    if name and name ~= "" then safeWrite(AUTO_LOAD_FILE, name)
    else safeDelete(AUTO_LOAD_FILE) end
end

local function getAutoLoadConfig()
    local raw = safeRead(AUTO_LOAD_FILE)
    if raw and raw ~= "" then return raw:gsub("%s+", "") end
    return nil
end

state.loadedConfigName = getAutoLoadConfig()



-- Self source save
local SELF_SOURCE = nil
do
    pcall(function()
        local info = debug.getinfo(1, "S")
        if info and info.source then
            if info.source:sub(1,1) == "@" then SELF_SOURCE = safeRead(info.source:sub(2))
            elseif info.source:sub(1,1) == "=" then SELF_SOURCE = info.source:sub(2) end
        end
    end)
    if SELF_SOURCE and #SELF_SOURCE > 100 then safeWrite(SELF_PATH, SELF_SOURCE) end
end

local function queueReload()
    if not state.autoReExecute then return end
    local autoloadName = getAutoLoadConfig()
    if not autoloadName then return end
    local reloadCode = string.format([[
        task.wait(4)
        local ok, src = pcall(function() return readfile("PhotonConfigs/_script.lua") end)
        if ok and src and #src > 100 then
            pcall(function() loadstring(src)() end)
        end
    ]])
    local queued = false
    pcall(function() if queue_on_teleport then queue_on_teleport(reloadCode); queued = true end end)
    if not queued then pcall(function() if syn and syn.queue_on_teleport then syn.queue_on_teleport(reloadCode); queued = true end end) end
    if not queued then pcall(function() if fluxus and fluxus.queue_on_teleport then fluxus.queue_on_teleport(reloadCode); queued = true end end) end
    if queued then print("[XENON] ✅ Queued reload") end
end

-- ═══════════════════════════════
-- INTRO SKIP
-- ═══════════════════════════════
local IntroEvents = ReplicatedStorage:WaitForChild("Events")
local IntroWeaponEvent = IntroEvents:WaitForChild("WeaponEvent")

local function skipIntro()
    pcall(function() firesignal(IntroWeaponEvent.OnClientEvent, "IntroEnd") end)
    pcall(function() IntroWeaponEvent:FireServer("RequestToEndIntro") end)
end

skipIntro()
task.spawn(function()
    for i = 1, 15 do skipIntro(); task.wait(1) end
end)
localPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    skipIntro()
end)

-- ═══════════════════════════════
-- ANTI-ADMIN
-- ═══════════════════════════════
local TARGET_GROUP_ID = 17385992

local WATCHLIST = {
    [7057703919] = {username = "u_nregretful", displayName = "McChickenpls", note = "Watchlist"},
    [8949298535] = {username = "nsomniakk", displayName = "nso", note = "Watchlist"},
    [1922797141] = {username = "GamerGardenia", displayName = "Matcha", note = "Watchlist"},
    [1129299091] = {username = "emiromania3", displayName = "emiromania3", note = "Watchlist"},
    [335940915]  = {username = "TrueMystic04", displayName = "Mystic", note = "Watchlist"}
}

local antiAdmin = {
    enabled = true, checked = {}, autoLeave = true, checkInterval = 3,
    adminRanks = {"Owner","Co-Owner","Developer","Admin","Moderator","Head Admin","Senior Admin","Lead Developer","Head Developer"},
    isHandlingAdmin = false, trackedAdmins = {}, groupMembers = {},
    lastGroupFetch = 0, groupFetchCooldown = 60, sameServerAdmins = {},
    onSameServer = false, watchlistHits = {}
}

local groupMembersCache = {}

local function isWatchlisted(player)
    if WATCHLIST[player.UserId] then return true end
    local lowerName = string.lower(player.Name)
    for _, entry in pairs(WATCHLIST) do
        if string.lower(entry.username) == lowerName then return true end
    end
    return false
end

local function checkWatchlistInServer()
    local found = {}
    antiAdmin.watchlistHits = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and isWatchlisted(player) then
            table.insert(found, player.Name)
            antiAdmin.watchlistHits[player.UserId] = true
        end
    end
    return found
end

local function isPlayerInTargetGroup(player)
    if groupMembersCache[player.UserId] ~= nil then return groupMembersCache[player.UserId] end
    local rank = player:FindFirstChild("Rank") or player:FindFirstChild("rank")
    if rank and rank.Value and rank.Value > 0 then
        local rankName = player:FindFirstChild("RankName") or player:FindFirstChild("rankName")
        if rankName then
            local lowerName = string.lower(rankName.Value)
            for _, adminRank in ipairs(antiAdmin.adminRanks) do
                if lowerName:find(string.lower(adminRank)) then
                    groupMembersCache[player.UserId] = true
                    return true
                end
            end
        end
    end
    groupMembersCache[player.UserId] = false
    return false
end

local function isPlayerAdmin(player)
    if antiAdmin.checked[player.UserId] ~= nil then return antiAdmin.checked[player.UserId] end
    if not isPlayerInTargetGroup(player) then antiAdmin.checked[player.UserId] = false; return false end
    local rankName = player:FindFirstChild("RankName") or player:FindFirstChild("rankName")
    if rankName then
        local lowerName = string.lower(rankName.Value)
        for _, adminRank in ipairs(antiAdmin.adminRanks) do
            if lowerName:find(string.lower(adminRank)) then antiAdmin.checked[player.UserId] = true; return true end
        end
    end
    antiAdmin.checked[player.UserId] = false
    return false
end

local function checkForAdminsInServer()
    local found = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and isPlayerAdmin(player) then table.insert(found, player) end
    end
    return found
end

local function fetchGroupAdmins()
    local now = tick()
    if now - antiAdmin.lastGroupFetch < antiAdmin.groupFetchCooldown then return antiAdmin.groupMembers end
    antiAdmin.lastGroupFetch = now
    local admins = {}
    local cursor = ""
    for page = 1, 5 do
        local url = string.format("https://groups.roblox.com/v1/groups/%d/users?limit=100&sortOrder=Asc&cursor=%s", TARGET_GROUP_ID, cursor)
        local success, response = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
        if not success or not response or not response.data then break end
        for _, member in ipairs(response.data) do
            local roleName = member.role and member.role.name or ""
            local lowerRole = string.lower(roleName)
            for _, adminRank in ipairs(antiAdmin.adminRanks) do
                if lowerRole:find(string.lower(adminRank)) then
                    table.insert(admins, {userId = member.user.userId, username = member.user.username, displayName = member.user.displayName or member.user.username, role = roleName})
                    break
                end
            end
        end
        cursor = response.nextPageCursor
        if not cursor or cursor == "" then break end
        task.wait(0.2)
    end
    antiAdmin.groupMembers = admins
    return admins
end

local function fetchUserPresence(userId)
    local body = HttpService:JSONEncode({userIds = {userId}})
    local success, response = pcall(function()
        return HttpService:JSONDecode(HttpService:RequestAsync({
            Url = "https://presence.roblox.com/v1/presence/users",
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = body
        }).Body)
    end)
    if not success or not response or not response.userPresences then return nil end
    local p = response.userPresences[1]
    if not p then return nil end
    local presenceType = p.userPresenceType
    return {isOnline = presenceType > 0, isInGame = presenceType == 2, placeId = p.placeId, gameId = p.gameId, lastOnline = p.lastOnline, lastLocation = p.lastLocation}
end

local function fetchGameName(placeId)
    if not placeId then return nil end
    local uniUrl = string.format("https://apis.roblox.com/universes/v1/places/%d/universe", placeId)
    local success, uniRes = pcall(function() return HttpService:JSONDecode(game:HttpGet(uniUrl)) end)
    if success and uniRes and uniRes.universeId then
        local detailUrl = string.format("https://games.roblox.com/v1/games?universeIds=%d", uniRes.universeId)
        local s2, detailRes = pcall(function() return HttpService:JSONDecode(game:HttpGet(detailUrl)) end)
        if s2 and detailRes and detailRes.data and detailRes.data[1] then return detailRes.data[1].name end
    end
    return nil
end

local function updateAdminTracker()
    local admins = fetchGroupAdmins()
    for userId, entry in pairs(WATCHLIST) do
        local already = false
        for _, a in ipairs(admins) do if a.userId == userId then already = true break end end
        if not already then table.insert(admins, {userId = userId, username = entry.username, displayName = entry.displayName, role = entry.note or "Watchlist"}) end
    end
    if #admins == 0 then return end
    for _, admin in ipairs(admins) do
        local presence = fetchUserPresence(admin.userId)
        local sameServer = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == admin.userId then sameServer = true break end
        end
        local gameName = nil
        if presence and presence.placeId then
            gameName = fetchGameName(presence.placeId)
            if gameName then
                antiAdmin.trackedAdmins[admin.userId] = antiAdmin.trackedAdmins[admin.userId] or {}
                antiAdmin.trackedAdmins[admin.userId].cachedGameName = gameName
                antiAdmin.trackedAdmins[admin.userId].cachedGameId = presence.placeId
            end
        end
        local cached = antiAdmin.trackedAdmins[admin.userId]
        if not gameName and cached and cached.cachedGameId == (presence and presence.placeId) then gameName = cached.cachedGameName end
        antiAdmin.trackedAdmins[admin.userId] = {
            userId = admin.userId, username = admin.username, displayName = admin.displayName, role = admin.role,
            isOnline = presence and presence.isOnline or false,
            isInGame = presence and presence.isInGame or false,
            placeId = presence and presence.placeId, gameId = presence and presence.gameId,
            currentGameName = gameName, sameServer = sameServer,
            lastOnline = presence and presence.lastOnline, lastLocation = presence and presence.lastLocation,
            cachedGameName = gameName or (cached and cached.cachedGameName),
            cachedGameId = (presence and presence.placeId) or (cached and cached.cachedGameId),
            lastUpdate = tick()
        }
        task.wait(0.3)
    end
    antiAdmin.sameServerAdmins = {}
    for userId, data in pairs(antiAdmin.trackedAdmins) do
        if data.sameServer and data.isOnline then table.insert(antiAdmin.sameServerAdmins, data.username) end
    end
    antiAdmin.onSameServer = #antiAdmin.sameServerAdmins > 0
end

local function getWorkingServers(placeId)
    local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
    local success, response = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
    if not success or not response or not response.data then return {} end
    local servers = {}
    for _, server in ipairs(response.data) do
        if server.id and server.playing and server.maxPlayers and server.playing < server.maxPlayers and server.id ~= game.JobId then
            table.insert(servers, server.id)
        end
    end
    return servers
end

local function attemptServerHop()
    local success = pcall(function()
        local servers = getWorkingServers(game.PlaceId)
        if #servers == 0 then error("No servers available") end
        local targetServer = servers[math.random(1, #servers)]
        queueReload()
        task.wait(0.5)
        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer, localPlayer)
    end)
    return success
end

local function handleAdminDetection(reason)
    if antiAdmin.isHandlingAdmin then return end
    antiAdmin.isHandlingAdmin = true
    print("[XENON] ⚠️ ADMIN DETECTED — " .. reason)
    queueReload()
    task.wait(0.5)
    local hopSuccess = attemptServerHop()
    if hopSuccess then task.wait(8) end
    pcall(function() TeleportService:Teleport(game.PlaceId) end)
    task.wait(1)
    pcall(function() localPlayer:Kick("Anti-Admin triggered") end)
    task.wait(0.5)
    pcall(function() game:Shutdown() end)
end

local function antiAdminLoop()
    while state.running and antiAdmin.enabled do
        task.wait(antiAdmin.checkInterval)
        local watchHits = checkWatchlistInServer()
        if #watchHits > 0 and antiAdmin.autoLeave then
            handleAdminDetection("WATCHLIST: " .. table.concat(watchHits, ", "))
            break
        end
        local admins = checkForAdminsInServer()
        if #admins > 0 and antiAdmin.autoLeave then
            local names = {}
            for _, p in ipairs(admins) do table.insert(names, p.Name) end
            handleAdminDetection("in-server: " .. table.concat(names, ", "))
            break
        end
    end
end

task.spawn(antiAdminLoop)

Players.PlayerAdded:Connect(function(player)
    if not antiAdmin.enabled then return end
    task.wait(2)
    if isWatchlisted(player) and antiAdmin.autoLeave then handleAdminDetection("watchlist joined: " .. player.Name); return end
    if isPlayerAdmin(player) and antiAdmin.autoLeave then handleAdminDetection("joined: " .. player.Name) end
end)

task.spawn(function()
    task.wait(5)
    while state.running do
        if antiAdmin.enabled then pcall(updateAdminTracker) end
        task.wait(30)
    end
end)

-- ═══════════════════════════════
-- HELPERS
-- ═══════════════════════════════
local function getHRP()
    local char = localPlayer.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then return char:FindFirstChild("HumanoidRootPart") end
    return nil
end

local function getHumanoid()
    local char = localPlayer.Character
    if char then return char:FindFirstChildOfClass("Humanoid") end
    return nil
end

local BLACKLISTED_ANCESTORS = {
    "casino", "bank", "vault", "gunpowder", "gunpowder_vault",
    "safebox", "deposit", "atm", "safe", "crate", "cashregister"
}

local function isBlacklisted(part)
    local parent = part.Parent
    local depth = 0
    while parent and parent ~= Workspace and depth < 8 do
        local pname = string.lower(parent.Name)
        for _, blocked in ipairs(BLACKLISTED_ANCESTORS) do
            if pname:find(blocked) then return true end
        end
        parent = parent.Parent
        depth = depth + 1
    end
    return false
end

local function isValidFloorCash(desc)
    if not desc:IsA("BasePart") then return false end
    if desc.Transparency >= 0.5 or desc.Size.Y > 3 then return false end
    if desc.Size.Y <= 0.1 then return false end
    if isBlacklisted(desc) then return false end
    local name = string.lower(desc.Name)
    local pname = desc.Parent and string.lower(desc.Parent.Name) or ""
    local nameMatch = false
    if name == "cash" or name == "cashspawn" or name == "part" or
       pname == "cash" or pname == "cashspawn" or pname == "part" or
       name:find("cash") or name:find("money") then nameMatch = true end
    if not nameMatch then return false end
    local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt or not prompt.Enabled then return false end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {desc, localPlayer.Character}
    local result = Workspace:Raycast(desc.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, -5, 0), rayParams)
    if not result then return false end
    return true
end

-- ═══════════════════════════════
-- TP SYSTEM
-- ═══════════════════════════════
local TP_CAP = 8
local teleportSystem = {
    usedTeleports = 0, generation = 0,
    farms = { Dumpster = { memory = {} }, Cash = { memory = {} }, Register = { memory = {} }, SuperFarm = { memory = {} } }
}
local selectedFarmKey = nil
local isResetting = false

local function resetTeleportSystem()
    teleportSystem.usedTeleports = 0
    teleportSystem.generation = teleportSystem.generation + 1
    for name, farm in pairs(teleportSystem.farms) do farm.memory = {} end
end

local startFarmModule
local forceResetCharacter

local function useTeleport()
    teleportSystem.usedTeleports = teleportSystem.usedTeleports + 1
    if teleportSystem.usedTeleports >= TP_CAP and not isResetting then
        isResetting = true
        task.spawn(function() forceResetCharacter() end)
        return true
    end
    return false
end

local movementTween = nil
local movementGeneration = 0

local function chainTeleport(pos)
    local hrp = getHRP()
    if not hrp then return false end

    movementGeneration = movementGeneration + 1
    local myMovement = movementGeneration
    if movementTween then
        pcall(function() movementTween:Cancel() end)
        movementTween = nil
    end

    local target = CFrame.new(pos + Vector3.new(0, 3, 0))

    -- TP mode intentionally preserves the original farm teleport logic.
    if state.farmMovementMode ~= "Tween" then
        local hum = getHumanoid()
        if hum then hum.PlatformStand = true; hum.WalkSpeed = 0 end
        hrp.CFrame = target
        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
        task.wait(0.05)
        if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
        useTeleport()
        return true
    end

    -- Tween mode: constant 30 studs/second, independent of distance.
    local distance = (hrp.Position - target.Position).Magnitude
    if distance <= 1 then return true end

    local duration = distance / 30
    local driver = Instance.new("CFrameValue")
    driver.Value = hrp.CFrame

    local connection
    connection = driver:GetPropertyChangedSignal("Value"):Connect(function()
        if myMovement ~= movementGeneration then return end
        local currentHRP = getHRP()
        if currentHRP then
            currentHRP.CFrame = driver.Value
            currentHRP.AssemblyLinearVelocity = Vector3.new(0,0,0)
            currentHRP.AssemblyAngularVelocity = Vector3.new(0,0,0)
        end
    end)

    movementTween = TweenService:Create(driver, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {Value = target})
    movementTween:Play()
    movementTween.Completed:Wait()

    if connection then connection:Disconnect() end
    driver:Destroy()
    movementTween = nil

    local finalHRP = getHRP()
    if finalHRP and myMovement == movementGeneration then
        finalHRP.CFrame = target
        finalHRP.AssemblyLinearVelocity = Vector3.new(0,0,0)
        finalHRP.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end
    return true
end

local function firePrompt(prompt)
    if not prompt or not prompt.Enabled then return false end
    task.wait(0.04)
    if fireproximityprompt then pcall(function() fireproximityprompt(prompt) end); return true end
    if prompt and prompt.Parent then
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(0.08)
            prompt:InputHoldEnd()
        end)
        return true
    end
    return false
end

local function firePromptLong(prompt, duration)
    if not prompt or not prompt.Enabled then return false end
    task.wait(0.04)
    if fireproximityprompt then pcall(function() fireproximityprompt(prompt) end); return true end
    if prompt and prompt.Parent then
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(duration)
            prompt:InputHoldEnd()
        end)
        return true
    end
    return false
end

local IDLE_COORDINATES = Vector3.new(-1383.37, -6.14, -601.22)

local function teleportToIdleForce()
    local hrp = getHRP()
    if not hrp then return end
    local hum = getHumanoid()
    if hum then hum.PlatformStand = true; hum.WalkSpeed = 0 end
    hrp.CFrame = CFrame.new(IDLE_COORDINATES + Vector3.new(0, 3, 0))
    hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
    hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
    task.wait(0.05)
    if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
end

-- ═══════════════════════════════
-- STATE
-- ═══════════════════════════════

local farmThreads = {}
local antiAFKConnection = nil
local cashTransferThread = nil

-- ═══════════════════════════════
-- SCAN
-- ═══════════════════════════════
local function getCash()
    local hrp = getHRP()
    if not hrp then return nil, nil end
    local map = Workspace:FindFirstChild("HardTime") or Workspace
    local closest, cPrompt, cDist = nil, nil, 999999999
    local memory = teleportSystem.farms.Cash.memory
    for _, desc in ipairs(map:GetDescendants()) do
        if desc:IsA("BasePart") and not memory[desc] then
            if isValidFloorCash(desc) then
                local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
                local dist = (hrp.Position - desc.Position).Magnitude
                if dist < cDist then cDist = dist; closest = desc; cPrompt = prompt end
            end
        end
    end
    return closest, cPrompt
end

local function getRegisters()
    local hrp = getHRP()
    if not hrp then return nil, nil end
    local map = Workspace:FindFirstChild("HardTime") or Workspace
    local closest, cPrompt, cDist = nil, nil, 999999999
    local memory = teleportSystem.farms.Register.memory
    for _, desc in ipairs(map:GetDescendants()) do
        if desc:IsA("BasePart") and not memory[desc] then
            local name = string.lower(desc.Name)
            local pname = desc.Parent and string.lower(desc.Parent.Name) or ""
            if (name:find("register") or pname:find("register")) and not name:find("button") and not name:find("gui") then
                if isBlacklisted(desc) then continue end
                local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled then
                    local dist = (hrp.Position - desc.Position).Magnitude
                    if dist < cDist then cDist = dist; closest = desc; cPrompt = prompt end
                end
            end
        end
    end
    return closest, cPrompt
end

local function getDumpsters()
    local list = {}
    local map = Workspace:FindFirstChild("HardTime") or Workspace
    local memory = teleportSystem.farms.Dumpster.memory
    local hrp = getHRP()
    if not hrp then return list end
    for _, desc in ipairs(map:GetDescendants()) do
        if desc:IsA("BasePart") then
            local name = string.lower(desc.Name)
            local pname = desc.Parent and string.lower(desc.Parent.Name) or ""
            if name:find("dumpster") or pname:find("dumpster") or name:find("searchable") or name:find("prop") then
                if isBlacklisted(desc) then continue end
                local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled and not memory[desc] then
                    table.insert(list, {Part = desc, Prompt = prompt, Dist = (hrp.Position - desc.Position).Magnitude})
                end
            end
        end
    end
    table.sort(list, function(a,b) return a.Dist < b.Dist end)
    return list
end

local function findCashNear(pos, radius)
    local map = Workspace:FindFirstChild("HardTime") or Workspace
    local found = {}
    for _, desc in ipairs(map:GetDescendants()) do
        if desc:IsA("BasePart") then
            if isValidFloorCash(desc) then
                local pr = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
                if pr and pr.Enabled and not teleportSystem.farms.Register.memory[desc] then
                    local d = (pos - desc.Position).Magnitude
                    if d <= radius then table.insert(found, {Part = desc, Prompt = pr, Dist = d}) end
                end
            end
        end
    end
    table.sort(found, function(a,b) return a.Dist < b.Dist end)
    return found
end

-- ═══════════════════════════════
-- DUMPSTER SELL
-- ═══════════════════════════════
local dumpsterSelling = false
local PAWN_SHOP = Vector3.new(-1305.85, 2.39, -845.55)
local SELL_BTN = Vector2.new(559, 274)
local CLOSE_BTN = Vector2.new(946, 198)

local function dumpsterSellRoutine()
    if dumpsterSelling then return end
    if teleportSystem.usedTeleports >= TP_CAP then return end
    dumpsterSelling = true
    chainTeleport(PAWN_SHOP)
    task.wait(0.15)
    local function getItemCount()
        local backpack = localPlayer:FindFirstChild("Backpack")
        if not backpack then return 0 end
        local count = 0
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") or child:IsA("HopperBin") then count = count + 1 end
        end
        return count
    end
    local items = getItemCount()
    local attempts = 0
    while items > 0 and attempts < 20 do
        attempts = attempts + 1
        pcall(function()
            UserInputService:SetMouseLocation(SELL_BTN.X, SELL_BTN.Y)
            task.wait(0.03)
            UserInputService:MouseButton1Click(SELL_BTN)
        end)
        task.wait(0.08)
        items = getItemCount()
        if items == 0 then
            pcall(function()
                UserInputService:SetMouseLocation(CLOSE_BTN.X, CLOSE_BTN.Y)
                task.wait(0.03)
                UserInputService:MouseButton1Click(CLOSE_BTN)
            end)
            break
        end
        task.wait(0.05)
    end
    dumpsterSelling = false
end

-- ═══════════════════════════════
-- RESET
-- ═══════════════════════════════
forceResetCharacter = function()
    if not isResetting then isResetting = true end
    teleportSystem.generation = teleportSystem.generation + 1
    for key, _ in pairs(farmThreads) do farmThreads[key] = nil end
    local Event = ReplicatedStorage:FindFirstChild("Events")
    if Event then
        local reset = Event:FindFirstChild("Reset")
        if reset then pcall(function() reset:FireServer("Reset") end) end
    end
    local old = localPlayer.Character
    local t = 0
    repeat task.wait(0.1); t = t + 0.1
    until (localPlayer.Character and localPlayer.Character ~= old and localPlayer.Character:FindFirstChild("HumanoidRootPart")) or t > 8
    task.wait(0.5)
    skipIntro()
    teleportSystem.usedTeleports = 0
    for name, farm in pairs(teleportSystem.farms) do farm.memory = {} end
    if selectedFarmKey and state.farms[selectedFarmKey] then
        task.wait(0.3)
        startFarmModule(selectedFarmKey)
    else
        teleportToIdleForce()
    end
    isResetting = false
end

-- ═══════════════════════════════
-- CASH TRANSFER LOGIC
-- ═══════════════════════════════
local DROP_CASH_EVENT = nil
do
    local Events = ReplicatedStorage:FindFirstChild("Events")
    if Events then
        DROP_CASH_EVENT = Events:FindFirstChild("DropCash")
    end
end

-- Reads player's own cash value from leaderstats (fallback if not present)
local function getOwnCash()
    -- Try leaderstats first
    local stats = localPlayer:FindFirstChild("leaderstats")
    if stats then
        for _, stat in ipairs(stats:GetChildren()) do
            local n = string.lower(stat.Name)
            if n == "cash" or n == "money" or n == "$" then
                if stat:IsA("IntValue") or stat:IsA("NumberValue") then return stat.Value end
            end
        end
    end
    -- Try PlayerGui stat displays
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if pg then
        -- Search common paths
        for _, desc in ipairs(pg:GetDescendants()) do
            if desc:IsA("TextLabel") then
                local text = desc.Text or ""
                local num = tonumber((text:gsub("[^%d]", "")))
                if num and text:find("%$") and #text < 20 then
                    -- Heuristic: first $-containing label with a number
                    return num
                end
            end
        end
    end
    return nil
end

local function findPlayerByName(name)
    if not name or name == "" then return nil end
    local lowerQuery = string.lower(name)
    -- exact match first
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and string.lower(player.Name) == lowerQuery then return player end
    end
    -- display name match
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and string.lower(player.DisplayName or "") == lowerQuery then return player end
    end
    -- prefix match
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and string.lower(player.Name):sub(1, #lowerQuery) == lowerQuery then return player end
    end
    return nil
end

local function cashTransferLoop(targetPlayer)
    print("[XENON] 💸 Cash Transfer starting → " .. targetPlayer.Name)
    state.cashTransfer.running = true

    -- Reset character to ensure clean state
    print("[XENON] 🔄 Resetting character first...")
    local Event = ReplicatedStorage:FindFirstChild("Events")
    if Event then
        local reset = Event:FindFirstChild("Reset")
        if reset then pcall(function() reset:FireServer("Reset") end) end
    end

    local oldChar = localPlayer.Character
    local t = 0
    repeat task.wait(0.1); t = t + 0.1
    until (localPlayer.Character and localPlayer.Character ~= oldChar and localPlayer.Character:FindFirstChild("HumanoidRootPart")) or t > 8
    task.wait(0.7)
    skipIntro()
    task.wait(0.3)

    -- TP to target player
    local targetHRP = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not targetHRP then
        print("[XENON] ⚠️ Target has no character — aborting")
        state.cashTransfer.running = false
        teleportToIdleForce()
        return
    end

    print("[XENON] 📍 TPing to " .. targetPlayer.Name)
    local hrp = getHRP()
    if hrp then
        local hum = getHumanoid()
        if hum then hum.PlatformStand = true; hum.WalkSpeed = 0 end
        hrp.CFrame = CFrame.new(targetHRP.Position + Vector3.new(0, 3, 0))
        hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
        task.wait(0.1)
        if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
    end

    if not DROP_CASH_EVENT then
        print("[XENON] ⚠️ DropCash event not found — aborting")
        state.cashTransfer.running = false
        teleportToIdleForce()
        return
    end

    -- Spam DropCash until own cash < 5000
    local lastCash = nil
    local spamCount = 0
    local maxSpam = 500 -- safety cap
    local noValueStreak = 0

    while state.cashTransfer.running and state.running do
        -- Check cash value
        local cash = getOwnCash()
        if cash ~= nil then
            lastCash = cash
            noValueStreak = 0
            if cash < 5000 then
                print("[XENON] ✅ Cash under 5000 (" .. cash .. ") — stopping")
                break
            end
        else
            noValueStreak = noValueStreak + 1
            if noValueStreak > 60 then
                -- 30 seconds without detecting cash — bail
                print("[XENON] ⚠️ Could not read cash value — stopping after 30s")
                break
            end
        end

        if spamCount >= maxSpam then
            print("[XENON] ⚠️ Hit spam cap (" .. maxSpam .. ") — stopping")
            break
        end

        -- Fire the drop event
        pcall(function() DROP_CASH_EVENT:FireServer(5000) end)
        spamCount = spamCount + 1

        -- Re-TP in case we drift (every 20 fires)
        if spamCount % 20 == 0 then
            local freshHRP = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if freshHRP then
                local myHrp = getHRP()
                if myHrp then myHrp.CFrame = CFrame.new(freshHRP.Position + Vector3.new(0, 3, 0)) end
            end
        end

        task.wait(0.05)
    end

    print("[XENON] 💸 Cash Transfer finished. Fires: " .. spamCount .. " | Last cash: " .. tostring(lastCash))

    -- TP back to idle
    task.wait(0.5)
    teleportToIdleForce()
    print("[XENON] 📍 Returned to idle")

    state.cashTransfer.running = false
end

-- ═══════════════════════════════
-- FARM LOOPS
-- ═══════════════════════════════
local function superFarmLoop(myGen)
    while state.farms.SuperFarm and state.running do
        if myGen ~= teleportSystem.generation then return end
        if isResetting or teleportSystem.usedTeleports >= TP_CAP then task.wait(0.3) continue end
        local didSomething = false
        if not didSomething and teleportSystem.usedTeleports < TP_CAP and not isResetting then
            local reg, regPrompt = getRegisters()
            if reg and regPrompt then
                local height = reg.Size.Y or 2
                chainTeleport(reg.Position + Vector3.new(0, height + 1.5, 0))
                task.wait(0.05)
                for i = 1, 5 do firePrompt(regPrompt); task.wait(0.04) end
                firePromptLong(regPrompt, 1.2)
                teleportSystem.farms.Register.memory[reg] = true
                teleportSystem.farms.Register.memory[regPrompt] = true
                task.wait(0.4)
                local spawned = findCashNear(reg.Position, 50)
                for _, c in ipairs(spawned) do
                    if teleportSystem.usedTeleports >= TP_CAP or isResetting then break end
                    if myGen ~= teleportSystem.generation then return end
                    if not teleportSystem.farms.Register.memory[c.Part] then
                        chainTeleport(c.Part.Position + Vector3.new(0, 2, 0))
                        task.wait(0.05)
                        if c.Prompt and c.Prompt.Enabled then firePrompt(c.Prompt); task.wait(0.03); firePromptLong(c.Prompt, 0.3) end
                        teleportSystem.farms.Register.memory[c.Part] = true
                        teleportSystem.farms.Register.memory[c.Prompt] = true
                        task.wait(0.05)
                    end
                end
                didSomething = true
            end
        end
        if not didSomething and teleportSystem.usedTeleports < TP_CAP and not isResetting then
            local cash, cashPrompt = getCash()
            if cash and cashPrompt then
                chainTeleport(cash.Position + Vector3.new(0, -4, 0))
                task.wait(0.05)
                firePrompt(cashPrompt); task.wait(0.03); firePrompt(cashPrompt); task.wait(0.03); firePromptLong(cashPrompt, 0.3)
                teleportSystem.farms.Cash.memory[cash] = true
                teleportSystem.farms.Cash.memory[cashPrompt] = true
                didSomething = true
            end
        end
        if not didSomething and teleportSystem.usedTeleports < TP_CAP and not isResetting then
            local dumpsters = getDumpsters()
            if #dumpsters > 0 then
                local dump = dumpsters[1]
                chainTeleport(dump.Part.Position)
                task.wait(0.05)
                firePrompt(dump.Prompt)
                teleportSystem.farms.Dumpster.memory[dump.Part] = true
                teleportSystem.farms.Dumpster.memory[dump.Prompt] = true
                didSomething = true
                if #dumpsters <= 1 then task.wait(0.3); dumpsterSellRoutine() end
            end
        end
        if not didSomething then
            teleportToIdleForce()
            task.wait(1.5)
            for _, farm in pairs(teleportSystem.farms) do if #farm.memory > 20 then farm.memory = {} end end
        else
            task.wait(0.1)
        end
    end
end

local function dumpsterLoop(myGen)
    while state.farms.Dumpster and state.running do
        if myGen ~= teleportSystem.generation then return end
        if isResetting or teleportSystem.usedTeleports >= TP_CAP then task.wait(0.3) continue end
        local dumpsters = getDumpsters()
        if #dumpsters > 0 then
            for _, d in ipairs(dumpsters) do
                if not state.farms.Dumpster or isResetting then break end
                if teleportSystem.usedTeleports >= TP_CAP then break end
                if myGen ~= teleportSystem.generation then return end
                chainTeleport(d.Part.Position)
                task.wait(0.05)
                if d.Prompt and d.Prompt.Enabled then firePrompt(d.Prompt) end
                teleportSystem.farms.Dumpster.memory[d.Part] = true
                teleportSystem.farms.Dumpster.memory[d.Prompt] = true
                task.wait(0.05)
            end
            if state.farms.Dumpster and teleportSystem.usedTeleports < TP_CAP and not isResetting then
                dumpsterSellRoutine()
                task.wait(0.3)
            end
        else
            teleportToIdleForce()
            task.wait(2)
            if #teleportSystem.farms.Dumpster.memory > 20 then teleportSystem.farms.Dumpster.memory = {} end
        end
    end
end

local function cashLoop(myGen)
    while state.farms.Cash and state.running do
        if myGen ~= teleportSystem.generation then return end
        if isResetting or teleportSystem.usedTeleports >= TP_CAP then task.wait(0.3) continue end
        local target, prompt = getCash()
        if target and prompt then
            chainTeleport(target.Position + Vector3.new(0, -4, 0))
            task.wait(0.05)
            if prompt and prompt.Enabled then firePrompt(prompt); task.wait(0.03); firePrompt(prompt); task.wait(0.03); firePromptLong(prompt, 0.3) end
            teleportSystem.farms.Cash.memory[target] = true
            teleportSystem.farms.Cash.memory[prompt] = true
            task.wait(0.1)
        else
            teleportToIdleForce()
            task.wait(2)
            if #teleportSystem.farms.Cash.memory > 20 then teleportSystem.farms.Cash.memory = {} end
        end
    end
end

local function regLoop(myGen)
    while state.farms.Register and state.running do
        if myGen ~= teleportSystem.generation then return end
        if isResetting or teleportSystem.usedTeleports >= TP_CAP then task.wait(0.3) continue end
        local target, prompt = getRegisters()
        if target and prompt then
            local height = target.Size.Y or 2
            chainTeleport(target.Position + Vector3.new(0, height + 1.5, 0))
            task.wait(0.05)
            if prompt and prompt.Enabled then
                for i = 1, 5 do firePrompt(prompt); task.wait(0.04) end
                firePromptLong(prompt, 1.2)
            end
            teleportSystem.farms.Register.memory[target] = true
            teleportSystem.farms.Register.memory[prompt] = true
            task.wait(0.5)
            task.wait(0.1)
        else
            teleportToIdleForce()
            task.wait(2)
            if #teleportSystem.farms.Register.memory > 20 then teleportSystem.farms.Register.memory = {} end
        end
    end
end

startFarmModule = function(name)
    if not state.farms[name] then return end
    for key, _ in pairs(farmThreads) do farmThreads[key] = nil end
    task.wait(0.15)
    local myGen = teleportSystem.generation
    local funcs = {Dumpster = dumpsterLoop, Cash = cashLoop, Register = regLoop, SuperFarm = superFarmLoop}
    if funcs[name] then
        farmThreads[name] = coroutine.create(function() funcs[name](myGen) end)
        task.spawn(farmThreads[name])
    end
end





-- ═══════════════════════════════
-- APPLY CONFIG DATA
-- ═══════════════════════════════
local function applyConfigData(data)
    if not data then return end
    if data.farmMovementMode == "TP" or data.farmMovementMode == "Tween" then
        state.farmMovementMode = data.farmMovementMode
    end
    if data.farms then
        for k, v in pairs(data.farms) do state.farms[k] = v end
        local activeFarm = nil
        if state.farms.SuperFarm then activeFarm = "SuperFarm"
        elseif state.farms.Register then activeFarm = "Register"
        elseif state.farms.Cash then activeFarm = "Cash"
        elseif state.farms.Dumpster then activeFarm = "Dumpster" end
        if activeFarm then
            selectedFarmKey = activeFarm
            resetTeleportSystem()
            task.wait(0.3)
            startFarmModule(activeFarm)
        end
    end
    
    if data.protection then
        for k, v in pairs(data.protection) do state.protection[k] = v end
        antiAdmin.enabled = state.protection.AntiAdmin ~= false
        antiAdmin.autoLeave = state.protection.AntiAdmin ~= false
        if state.protection.AntiAFK then
            if antiAFKConnection then antiAFKConnection:Disconnect() end
            antiAFKConnection = localPlayer.Idled:Connect(function()
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end)
        end
    end
    if data.antiAdmin then
        antiAdmin.enabled = data.antiAdmin.enabled ~= false
        antiAdmin.autoLeave = data.antiAdmin.autoLeave ~= false
    end
end

-- ═══════════════════════════════
-- UI
-- ═══════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "XenonUI"
screenGui.Parent = CoreGui
screenGui.Enabled = true
screenGui.ResetOnSpawn = false

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 760, 0, 470)
mainFrame.Position = UDim2.new(0.5, -380, 0.5, -235)
mainFrame.BackgroundColor3 = Color3.fromRGB(8, 11, 14)
mainFrame.BorderSizePixel = 1
mainFrame.BorderColor3 = Color3.fromRGB(24, 36, 44)
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
mainFrame.Active = true
mainFrame.Draggable = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainFrame

local leftSidebar = Instance.new("Frame")
leftSidebar.Size = UDim2.new(0, 108, 1, 0)
leftSidebar.BackgroundColor3 = Color3.fromRGB(16, 20, 25)
leftSidebar.BorderSizePixel = 1
leftSidebar.BorderColor3 = Color3.fromRGB(24, 36, 44)
leftSidebar.Parent = mainFrame

local logoArea = Instance.new("Frame")
logoArea.Size = UDim2.new(1, -28, 0, 70)
logoArea.Position = UDim2.new(0, 14, 0, 14)
logoArea.BackgroundTransparency = 1
logoArea.Parent = leftSidebar

local logoText = Instance.new("TextLabel")
logoText.Size = UDim2.new(1, 0, 0, 30)
logoText.BackgroundTransparency = 1
logoText.Text = "XENON"
logoText.TextColor3 = Color3.fromRGB(232, 241, 244)
logoText.TextSize = 18
logoText.Font = Enum.Font.GothamSemibold
logoText.TextXAlignment = Enum.TextXAlignment.Left
logoText.Parent = logoArea

local logoAccent = Instance.new("Frame")
logoAccent.Size = UDim2.new(0, 4, 0, 24)
logoAccent.Position = UDim2.new(0, -6, 0, 0)
logoAccent.BackgroundColor3 = Color3.fromRGB(0, 198, 188)
logoAccent.BorderSizePixel = 0
logoAccent.Parent = logoText

local logoSub = Instance.new("TextLabel")
logoSub.Size = UDim2.new(1, 0, 0, 20)
logoSub.Position = UDim2.new(0, 0, 0, 34)
logoSub.BackgroundTransparency = 1
logoSub.Text = "compact workspace"
logoSub.TextColor3 = Color3.fromRGB(101, 116, 125)
logoSub.TextSize = 9
logoSub.Font = Enum.Font.Gotham
logoSub.TextXAlignment = Enum.TextXAlignment.Left
logoSub.Parent = logoArea

local navContainer = Instance.new("Frame")
navContainer.Size = UDim2.new(1, -16, 0, 130)
navContainer.Position = UDim2.new(0, 8, 0, 88)
navContainer.BackgroundTransparency = 1
navContainer.Parent = leftSidebar

local navList = Instance.new("UIListLayout")
navList.Parent = navContainer
navList.SortOrder = Enum.SortOrder.LayoutOrder
navList.Padding = UDim.new(0, 8)

local tabs = {"Farms"}
local tabButtons = {}

for i, name in ipairs(tabs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 50)
    btn.BackgroundTransparency = i == 1 and 0 or 1
    btn.BackgroundColor3 = i == 1 and Color3.fromRGB(37, 136, 199) or Color3.fromRGB(16, 20, 25)
    btn.Text = (i == 1 and "◈  Automation" or name)
    btn.TextColor3 = Color3.fromRGB(232, 241, 244)
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamMedium
    btn.TextXAlignment = Enum.TextXAlignment.Center
    btn.BorderSizePixel = 0
    btn.LayoutOrder = i
    btn.Parent = navContainer
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn
    if i == 1 then
        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 3, 1, 0)
        accent.BackgroundColor3 = Color3.fromRGB(0, 198, 188)
        accent.BorderSizePixel = 0
        accent.Parent = btn
    end
    tabButtons[name] = btn
end

local headerBar = Instance.new("Frame")
headerBar.Size = UDim2.new(1, -108, 0, 56)
headerBar.Position = UDim2.new(0, 108, 0, 0)
headerBar.BackgroundColor3 = Color3.fromRGB(11, 15, 19)
headerBar.BorderSizePixel = 0
headerBar.Parent = mainFrame

local headerDivider = Instance.new("Frame")
headerDivider.Size = UDim2.new(1, -28, 0, 1)
headerDivider.Position = UDim2.new(0, 14, 1, -1)
headerDivider.BackgroundColor3 = Color3.fromRGB(22, 33, 40)
headerDivider.BorderSizePixel = 0
headerDivider.Parent = headerBar

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(0.7, 0, 1, 0)
titleText.Position = UDim2.new(0, 14, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "Automation"
titleText.TextColor3 = Color3.fromRGB(232, 241, 244)
titleText.TextSize = 17
titleText.Font = Enum.Font.GothamSemibold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextYAlignment = Enum.TextYAlignment.Center
titleText.Parent = headerBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 32, 0, 32)
minimizeBtn.Position = UDim2.new(1, -72, 0, 12)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(23, 26, 30)
minimizeBtn.Text = "—"
minimizeBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
minimizeBtn.TextSize = 20
minimizeBtn.Font = Enum.Font.GothamMedium
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = headerBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 12)
closeBtn.BackgroundColor3 = Color3.fromRGB(23, 26, 30)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(0, 198, 188)
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.GothamMedium
closeBtn.BorderSizePixel = 0
closeBtn.Parent = headerBar

-- XENON identity watermark (screen-level, top-right; independent of the window)
local watermark = Instance.new("Frame")
watermark.Name = "XenonWatermark"
watermark.Size = UDim2.new(0, 292, 0, 44)
watermark.AnchorPoint = Vector2.new(1, 0)
watermark.Position = UDim2.new(1, -18, 0, 16)
watermark.BackgroundColor3 = Color3.fromRGB(8, 18, 30)
watermark.BackgroundTransparency = 0.02
watermark.BorderSizePixel = 0
watermark.ZIndex = 100
watermark.Parent = screenGui
local watermarkCorner = Instance.new("UICorner")
watermarkCorner.CornerRadius = UDim.new(0, 14)
watermarkCorner.Parent = watermark
local watermarkStroke = Instance.new("UIStroke")
watermarkStroke.Color = Color3.fromRGB(45, 191, 139)
watermarkStroke.Transparency = 0.45
watermarkStroke.Thickness = 1
watermarkStroke.Parent = watermark
local watermarkName = Instance.new("TextLabel")
watermarkName.Size = UDim2.new(0, 60, 1, 0)
watermarkName.Position = UDim2.new(0, 12, 0, 0)
watermarkName.BackgroundTransparency = 1
watermarkName.Text = "XENON"
watermarkName.TextColor3 = Color3.fromRGB(78, 190, 255)
watermarkName.TextSize = 13
watermarkName.Font = Enum.Font.GothamBold
watermarkName.TextXAlignment = Enum.TextXAlignment.Left
watermarkName.Parent = watermark
local watermarkDivider = Instance.new("Frame")
watermarkDivider.Size = UDim2.new(0, 1, 0, 20)
watermarkDivider.Position = UDim2.new(0, 72, 0.5, -10)
watermarkDivider.BackgroundColor3 = Color3.fromRGB(44, 67, 73)
watermarkDivider.BorderSizePixel = 0
watermarkDivider.Parent = watermark
local watermarkUser = Instance.new("TextLabel")
watermarkUser.Size = UDim2.new(0, 112, 1, 0)
watermarkUser.Position = UDim2.new(0, 84, 0, 0)
watermarkUser.BackgroundTransparency = 1
watermarkUser.Text = "@" .. localPlayer.Name
watermarkUser.TextColor3 = Color3.fromRGB(203, 214, 218)
watermarkUser.TextSize = 10
watermarkUser.Font = Enum.Font.GothamMedium
watermarkUser.TextXAlignment = Enum.TextXAlignment.Left
watermarkUser.TextTruncate = Enum.TextTruncate.AtEnd
watermarkUser.Parent = watermark

local watermarkRouteDivider = Instance.new("Frame")
watermarkRouteDivider.Size = UDim2.new(0, 1, 0, 20)
watermarkRouteDivider.Position = UDim2.new(0, 204, 0.5, -10)
watermarkRouteDivider.BackgroundColor3 = Color3.fromRGB(44, 67, 73)
watermarkRouteDivider.BorderSizePixel = 0
watermarkRouteDivider.Parent = watermark

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -108, 1, -56)
contentArea.Position = UDim2.new(0, 108, 0, 56)
contentArea.BackgroundTransparency = 1
contentArea.Parent = mainFrame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -28, 1, -20)
scroll.Position = UDim2.new(0, 14, 0, 10)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(38, 52, 59)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = contentArea

local contentGrid = Instance.new("UIListLayout")
contentGrid.Name = "UIListLayout"
contentGrid.Parent = scroll
contentGrid.SortOrder = Enum.SortOrder.LayoutOrder
contentGrid.Padding = UDim.new(0, 8)

local function createCard(parent, title, icon)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.BackgroundColor3 = Color3.fromRGB(14, 19, 24)
    card.BackgroundTransparency = 0.08
    card.BorderSizePixel = 0
    card.ClipsDescendants = false
    card.Parent = parent

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 12)
    cardCorner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(31, 40, 47)
    stroke.Transparency = 0.22
    stroke.Thickness = 1
    stroke.Parent = card

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, -24, 0, 38)
    header.Position = UDim2.new(0, 12, 0, 8)
    header.BackgroundTransparency = 1
    header.Parent = card

    local iconLabel = Instance.new("TextLabel")
    iconLabel.Size = UDim2.new(0, 28, 1, 0)
    iconLabel.BackgroundTransparency = 1
    iconLabel.Text = icon or "•"
    iconLabel.TextColor3 = Color3.fromRGB(76, 171, 232)
    iconLabel.TextSize = 16
    iconLabel.Font = Enum.Font.GothamSemibold
    iconLabel.TextXAlignment = Enum.TextXAlignment.Left
    iconLabel.Parent = header

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Size = UDim2.new(1, -32, 1, 0)
    titleLabel.Position = UDim2.new(0, 28, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.TextColor3 = Color3.fromRGB(232, 239, 242)
    titleLabel.TextSize = 13
    titleLabel.Font = Enum.Font.GothamSemibold
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = header

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -24, 0, 1)
    divider.Position = UDim2.new(0, 12, 0, 45)
    divider.BackgroundColor3 = Color3.fromRGB(35, 44, 51)
    divider.BackgroundTransparency = 0.25
    divider.BorderSizePixel = 0
    divider.Parent = card

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -24, 0, 0)
    content.Position = UDim2.new(0, 12, 0, 52)
    content.BackgroundTransparency = 1
    content.ClipsDescendants = false
    content.Parent = card

    local list = Instance.new("UIListLayout")
    list.Parent = content
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 4)

    return card, content
end

local function createToggle(parent, name, stateRef, key, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 44)
    frame.BackgroundTransparency = 1
    frame.ZIndex = 40
    frame.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(218, 227, 231)
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = frame

    local toggle = Instance.new("Frame")
    toggle.Size = UDim2.new(0, 40, 0, 22)
    toggle.Position = UDim2.new(1, -40, 0.5, -11)
    toggle.BackgroundColor3 = stateRef[key] and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(43, 51, 57)
    toggle.BorderSizePixel = 0
    toggle.Parent = frame

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 0)
    toggleCorner.Parent = toggle

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = stateRef[key] and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(244, 249, 250)
    knob.BorderSizePixel = 0
    knob.Parent = toggle

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = frame

    btn.MouseButton1Click:Connect(function()
        stateRef[key] = not stateRef[key]
        local val = stateRef[key]
        toggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(43, 51, 57)
        knob.Position = val and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
        if callback then callback(val) end
    end)

    return frame
end

local function createMovementDropdown(parent)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 42)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.55, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = "Movement Mode"
    label.TextColor3 = Color3.fromRGB(218, 227, 231)
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0, 156, 0, 32)
    button.Position = UDim2.new(1, -156, 0.5, -16)
    button.BackgroundColor3 = Color3.fromRGB(16, 25, 37)
    button.BorderSizePixel = 1
    button.BorderColor3 = Color3.fromRGB(37, 136, 199)
    button.TextColor3 = Color3.fromRGB(100, 200, 255)
    button.TextSize = 11
    button.Font = Enum.Font.GothamMedium
    button.Text = state.farmMovementMode .. "  ▾"
    button.AutoButtonColor = false
    button.ZIndex = 42
    button.Parent = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = button

    local menu = Instance.new("Frame")
    menu.Size = UDim2.new(0, 156, 0, 68)
    menu.Position = UDim2.new(1, -156, 1, 2)
    menu.BackgroundColor3 = Color3.fromRGB(12, 18, 24)
    menu.BorderSizePixel = 1
    menu.BorderColor3 = Color3.fromRGB(37, 136, 199)
    menu.Visible = false
    menu.ZIndex = 100
    menu.Parent = frame

    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 6)
    menuCorner.Parent = menu

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 2)
    list.Parent = menu

    local function addOption(name)
        local option = Instance.new("TextButton")
        option.Size = UDim2.new(1, 0, 0, 32)
        option.BackgroundTransparency = 1
        option.Text = name
        option.TextColor3 = Color3.fromRGB(218, 227, 231)
        option.TextSize = 11
        option.Font = Enum.Font.GothamMedium
        option.BorderSizePixel = 0
        option.ZIndex = 101
        option.Parent = menu
        option.MouseButton1Click:Connect(function()
            state.farmMovementMode = name
            button.Text = name .. "  ▾"
            menu.Visible = false
        end)
    end

    addOption("TP")
    addOption("Tween")

    button.MouseButton1Click:Connect(function()
        menu.Visible = not menu.Visible
    end)

    return frame
end

local function clearContent()
    for _, child in ipairs(scroll:GetChildren()) do
        if child ~= contentGrid then child:Destroy() end
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
end

-- ═══════════════════════════════
-- FARMS TAB
-- ═══════════════════════════════
local function buildFarmsTab()
    clearContent()
    titleText.Text = "Automation"

    local card1, content1 = createCard(scroll, "Automation", "⚡")
    createMovementDropdown(content1)
    createToggle(content1, "All Routes", state.farms, "SuperFarm", function(val)
        if val then
            for _, key in ipairs({"Dumpster", "Cash", "Register"}) do state.farms[key] = false end
            state.farms.SuperFarm = true
            selectedFarmKey = "SuperFarm"
            resetTeleportSystem()
            startFarmModule("SuperFarm")
        else
            for key, _ in pairs(farmThreads) do farmThreads[key] = nil end
            selectedFarmKey = nil
            teleportToIdleForce()
        end
    end)
    createToggle(content1, "Bin Route", state.farms, "Dumpster", function(val)
        if val then
            for _, k in ipairs({"Dumpster", "Cash", "Register", "SuperFarm"}) do
                if k ~= "Dumpster" then state.farms[k] = false end
            end
            state.farms.Dumpster = true
            selectedFarmKey = "Dumpster"
            resetTeleportSystem()
            startFarmModule("Dumpster")
        else
            for k, _ in pairs(farmThreads) do farmThreads[k] = nil end
            if selectedFarmKey == "Dumpster" then selectedFarmKey = nil end
            teleportToIdleForce()
        end
    end)
    createToggle(content1, "Cash Route", state.farms, "Cash", function(val)
        if val then
            for _, k in ipairs({"Dumpster", "Cash", "Register", "SuperFarm"}) do
                if k ~= "Cash" then state.farms[k] = false end
            end
            state.farms.Cash = true
            selectedFarmKey = "Cash"
            resetTeleportSystem()
            startFarmModule("Cash")
        else
            for k, _ in pairs(farmThreads) do farmThreads[k] = nil end
            if selectedFarmKey == "Cash" then selectedFarmKey = nil end
            teleportToIdleForce()
        end
    end)
    createToggle(content1, "Register Route", state.farms, "Register", function(val)
        if val then
            for _, k in ipairs({"Dumpster", "Cash", "Register", "SuperFarm"}) do
                if k ~= "Register" then state.farms[k] = false end
            end
            state.farms.Register = true
            selectedFarmKey = "Register"
            resetTeleportSystem()
            startFarmModule("Register")
        else
            for k, _ in pairs(farmThreads) do farmThreads[k] = nil end
            if selectedFarmKey == "Register" then selectedFarmKey = nil end
            teleportToIdleForce()
        end
    end)

    local card2, content2 = createCard(scroll, "Controls", "↻")

    local resetHint = Instance.new("TextLabel")
    resetHint.Size = UDim2.new(1, 0, 0, 28)
    resetHint.BackgroundTransparency = 1
    resetHint.Text = "Restart your character and refresh the farm route state."
    resetHint.TextColor3 = Color3.fromRGB(126, 143, 153)
    resetHint.TextSize = 10
    resetHint.Font = Enum.Font.Gotham
    resetHint.TextXAlignment = Enum.TextXAlignment.Left
    resetHint.TextYAlignment = Enum.TextYAlignment.Center
    resetHint.TextWrapped = true
    resetHint.Parent = content2

    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(1, 0, 0, 38)
    resetBtn.BackgroundColor3 = Color3.fromRGB(20, 33, 47)
    resetBtn.Text = "↻   Reset Farm State"
    resetBtn.TextColor3 = Color3.fromRGB(218, 235, 246)
    resetBtn.TextSize = 11
    resetBtn.Font = Enum.Font.GothamSemibold
    resetBtn.BorderSizePixel = 0
    resetBtn.AutoButtonColor = false
    resetBtn.Parent = content2
    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 9)
    resetCorner.Parent = resetBtn
    local resetStroke = Instance.new("UIStroke")
    resetStroke.Color = Color3.fromRGB(37, 136, 199)
    resetStroke.Transparency = 0.55
    resetStroke.Thickness = 1
    resetStroke.Parent = resetBtn
    resetBtn.MouseEnter:Connect(function()
        resetBtn.BackgroundColor3 = Color3.fromRGB(27, 49, 69)
    end)
    resetBtn.MouseLeave:Connect(function()
        resetBtn.BackgroundColor3 = Color3.fromRGB(20, 33, 47)
    end)
    resetBtn.MouseButton1Click:Connect(function()
        task.spawn(function() forceResetCharacter() end)
    end)

    -- Adjust card sizes
    card1.Size = UDim2.new(1, 0, 0, content1.UIListLayout.AbsoluteContentSize.Y + 62)
    card2.Size = UDim2.new(1, 0, 0, content2.UIListLayout.AbsoluteContentSize.Y + 62)
    scroll.CanvasSize = UDim2.new(0, 0, 0, scroll.UIListLayout.AbsoluteContentSize.Y + 24)
end



-- ═══════════════════════════════
-- CASH TRANSFER TAB
-- ═══════════════════════════════
local function buildCashTransferTab()
    clearContent()
    titleText.Text = "Cash Transfer"

    local card1, content1 = createCard(scroll, "Recipient", "•")
    local searchFrame = Instance.new("Frame")
    searchFrame.Size = UDim2.new(1, 0, 0, 32)
    searchFrame.BackgroundColor3 = Color3.fromRGB(16, 25, 37)
    searchFrame.BorderSizePixel = 1
    searchFrame.BorderColor3 = Color3.fromRGB(36, 51, 63)
    searchFrame.Parent = content1
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 6)
    searchCorner.Parent = searchFrame

    local searchInput = Instance.new("TextBox")
    searchInput.Size = UDim2.new(0.7, 0, 0.8, 0)
    searchInput.Position = UDim2.new(0, 8, 0.1, 0)
    searchInput.BackgroundTransparency = 1
    searchInput.Text = state.cashTransfer.selectedName or ""
    searchInput.PlaceholderText = "Find player..."
    searchInput.TextColor3 = Color3.fromRGB(220, 232, 236)
    searchInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    searchInput.TextSize = 12
    searchInput.Font = Enum.Font.Gotham
    searchInput.BorderSizePixel = 0
    searchInput.Parent = searchFrame

    local searchBtn = Instance.new("TextButton")
    searchBtn.Size = UDim2.new(0.25, 0, 0.8, 0)
    searchBtn.Position = UDim2.new(0.72, 0, 0.1, 0)
    searchBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 80)
    searchBtn.Text = "FIND"
    searchBtn.TextColor3 = Color3.fromRGB(100, 200, 255)
    searchBtn.TextSize = 10
    searchBtn.Font = Enum.Font.Gotham
    searchBtn.BorderSizePixel = 0
    searchBtn.Parent = searchFrame
    local searchBtnCorner = Instance.new("UICorner")
    searchBtnCorner.CornerRadius = UDim.new(0, 4)
    searchBtnCorner.Parent = searchBtn

    local foundDisplay = Instance.new("TextLabel")
    foundDisplay.Size = UDim2.new(1, 0, 0, 20)
    foundDisplay.BackgroundTransparency = 1
    foundDisplay.Text = state.cashTransfer.selectedName ~= "" and ("✅ Selected: " .. state.cashTransfer.selectedName) or "Selected: None"
    foundDisplay.TextColor3 = state.cashTransfer.selectedName ~= "" and Color3.fromRGB(0, 198, 188) or Color3.fromRGB(155, 145, 150)
    foundDisplay.TextSize = 11
    foundDisplay.Font = Enum.Font.Gotham
    foundDisplay.TextXAlignment = Enum.TextXAlignment.Left
    foundDisplay.Parent = content1

    searchInput:GetPropertyChangedSignal("Text"):Connect(function()
        local query = searchInput.Text
        if #query >= 2 then
            local matched = findPlayerByName(query)
            if matched then
                state.cashTransfer.selectedName = matched.Name
                foundDisplay.Text = "✅ Auto-matched: " .. matched.Name
                foundDisplay.TextColor3 = Color3.fromRGB(0, 198, 188)
            end
        end
    end)

    searchBtn.MouseButton1Click:Connect(function()
        local query = searchInput.Text
        if query == "" then
            foundDisplay.Text = "⚠ Enter a name"
            foundDisplay.TextColor3 = Color3.fromRGB(255, 150, 100)
            return
        end
        local matched = findPlayerByName(query)
        if matched then
            state.cashTransfer.selectedName = matched.Name
            foundDisplay.Text = "✅ Selected: " .. matched.Name
            foundDisplay.TextColor3 = Color3.fromRGB(0, 198, 188)
        else
            foundDisplay.Text = "❌ Player not found: " .. query
            foundDisplay.TextColor3 = Color3.fromRGB(0, 198, 188)
        end
    end)

    local card2, content2 = createCard(scroll, "Players in session", "•")
    local listContainer = Instance.new("Frame")
    listContainer.Size = UDim2.new(1, 0, 0, 4)
    listContainer.BackgroundTransparency = 1
    listContainer.ClipsDescendants = false
    listContainer.Parent = content2

    local listLayout = Instance.new("UIListLayout")
    listLayout.Parent = listContainer
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 4)

    local function refreshPlayerList()
        for _, child in ipairs(listContainer:GetChildren()) do
            if child ~= listLayout then child:Destroy() end
        end
        local players = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then table.insert(players, player) end
        end
        table.sort(players, function(a,b) return a.Name < b.Name end)
        for _, player in ipairs(players) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 0, 28)
            btn.BackgroundColor3 = Color3.fromRGB(17, 20, 24)
            btn.Text = player.Name
            btn.TextColor3 = Color3.fromRGB(200, 200, 210)
            btn.TextSize = 11
            btn.Font = Enum.Font.Gotham
            btn.BorderSizePixel = 0
            btn.Parent = listContainer
            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 6)
            btnCorner.Parent = btn
            local hasChar = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local statusDot = Instance.new("TextLabel")
            statusDot.Size = UDim2.new(0, 12, 1, 0)
            statusDot.Position = UDim2.new(1, -16, 0, 0)
            statusDot.BackgroundTransparency = 1
            statusDot.Text = hasChar and "🟢" or "🔴"
            statusDot.TextSize = 12
            statusDot.Font = Enum.Font.SourceSans
            statusDot.Parent = btn
            btn.MouseButton1Click:Connect(function()
                state.cashTransfer.selectedName = player.Name
                searchInput.Text = player.Name
                foundDisplay.Text = "Selected: " .. player.Name
                foundDisplay.TextColor3 = Color3.fromRGB(0, 198, 188)
            end)
        end

        -- Keep the list/card geometry synchronized with the actual number of players.
        -- This prevents rows from visually extending into the next section.
        task.defer(function()
            local listHeight = math.max(4, listLayout.AbsoluteContentSize.Y)
            listContainer.Size = UDim2.new(1, 0, 0, listHeight)
            card2.Size = UDim2.new(1, 0, 0, listHeight + 70)
            scroll.CanvasSize = UDim2.new(0, 0, 0, scroll.UIListLayout.AbsoluteContentSize.Y + 24)
        end)
    end

    refreshPlayerList()
    task.spawn(function()
        while state.running do
            task.wait(5)
            if state.currentTab == "Cash Transfer" then refreshPlayerList() end
        end
    end)

    local card3, content3 = createCard(scroll, "Transfer", "•")
    local warnLabel = Instance.new("TextLabel")
    warnLabel.Size = UDim2.new(1, 0, 0, 40)
    warnLabel.BackgroundTransparency = 1
    warnLabel.Text = "Transfer controls and session status"
    warnLabel.TextColor3 = Color3.fromRGB(216, 180, 90)
    warnLabel.TextSize = 10
    warnLabel.Font = Enum.Font.Gotham
    warnLabel.TextWrapped = true
    warnLabel.Parent = content3

    local execBtn = Instance.new("TextButton")
    execBtn.Size = UDim2.new(1, 0, 0, 36)
    execBtn.BackgroundColor3 = Color3.fromRGB(20, 107, 145)
    execBtn.Text = "Start transfer"
    execBtn.TextColor3 = Color3.fromRGB(239, 255, 252)
    execBtn.TextSize = 12
    execBtn.Font = Enum.Font.Gotham
    execBtn.BorderSizePixel = 0
    execBtn.Parent = content3
    local execCorner = Instance.new("UICorner")
    execCorner.CornerRadius = UDim.new(0, 6)
    execCorner.Parent = execBtn

    execBtn.MouseButton1Click:Connect(function()
        if state.cashTransfer.running then
            state.cashTransfer.running = false
            execBtn.Text = "Start transfer"
            execBtn.BackgroundColor3 = Color3.fromRGB(20, 107, 145)
            return
        end
        local targetName = state.cashTransfer.selectedName
        if not targetName or targetName == "" then
            foundDisplay.Text = "⚠ No player selected"
            foundDisplay.TextColor3 = Color3.fromRGB(255, 150, 100)
            return
        end
        local targetPlayer = nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name == targetName then targetPlayer = p; break end
        end
        if not targetPlayer then
            foundDisplay.Text = "❌ Player no longer in server"
            foundDisplay.TextColor3 = Color3.fromRGB(0, 198, 188)
            return
        end
        execBtn.Text = "Stop transfer"
        execBtn.BackgroundColor3 = Color3.fromRGB(45, 71, 82)
        task.spawn(function()
            cashTransferLoop(targetPlayer)
            execBtn.Text = "💸 EXECUTE CASH TRANSFER"
            execBtn.BackgroundColor3 = Color3.fromRGB(20, 107, 145)
        end)
    end)

    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, 0, 0, 60)
    info.BackgroundTransparency = 1
    info.Text = "Transfer channel: " .. (DROP_CASH_EVENT and "Available" or "Unavailable")
    info.TextColor3 = Color3.fromRGB(150, 150, 170)
    info.TextSize = 10
    info.Font = Enum.Font.Gotham
    info.Parent = content3

    -- Adjust sizes
    card1.Size = UDim2.new(1, 0, 0, 100)
    card2.Size = UDim2.new(1, 0, 0, math.max(74, listLayout.AbsoluteContentSize.Y + 70))
    card3.Size = UDim2.new(1, 0, 0, 150)
    scroll.CanvasSize = UDim2.new(0, 0, 0, scroll.UIListLayout.AbsoluteContentSize.Y + 24)
end

-- ═══════════════════════════════
-- ANTI-ADMIN TAB
-- ═══════════════════════════════
local antiAdminUI = {}

-- Admin monitoring remains active in the background; its page is intentionally hidden.
local function buildAntiAdminTab()
    clearContent()
    local order = 1
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 28)
    header.BackgroundTransparency = 1
    header.Text = "═ ANTI-ADMIN TRACKER ═"
    header.TextColor3 = Color3.fromRGB(0, 198, 188)
    header.TextSize = 12
    header.Font = Enum.Font.Gotham
    header.LayoutOrder = 0
    header.Parent = scroll
    local statusFrame = Instance.new("Frame")
    statusFrame.Size = UDim2.new(1, -4, 0, 44)
    statusFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    statusFrame.BorderSizePixel = 0
    statusFrame.LayoutOrder = order
    statusFrame.Parent = scroll
    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 4)
    statusCorner.Parent = statusFrame
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
    statusLabel.Position = UDim2.new(0, 8, 0, 4)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Status: Monitoring"
    statusLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    statusLabel.TextSize = 12
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = statusFrame
    local threatLabel = Instance.new("TextLabel")
    threatLabel.Size = UDim2.new(1, 0, 0.5, 0)
    threatLabel.Position = UDim2.new(0, 8, 0.5, -2)
    threatLabel.BackgroundTransparency = 1
    threatLabel.Text = "Threat: None detected"
    threatLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    threatLabel.TextSize = 11
    threatLabel.Font = Enum.Font.Gotham
    threatLabel.TextXAlignment = Enum.TextXAlignment.Left
    threatLabel.Parent = statusFrame
    antiAdminUI.statusLabel = statusLabel
    antiAdminUI.threatLabel = threatLabel
    order = order + 1
    createToggle(scroll, "Anti-Admin Protection", state.protection, "AntiAdmin", function(val)
        antiAdmin.enabled = val
        antiAdmin.autoLeave = val
    end, order)
    order = order + 1
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1, -4, 0, 30)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(30, 50, 70)
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Text = "⟳ REFRESH TRACKER"
    refreshBtn.TextColor3 = Color3.fromRGB(100, 200, 255)
    refreshBtn.TextSize = 11
    refreshBtn.Font = Enum.Font.Gotham
    refreshBtn.LayoutOrder = order
    refreshBtn.Parent = scroll
    local refreshCorner = Instance.new("UICorner")
    refreshCorner.CornerRadius = UDim.new(0, 4)
    refreshCorner.Parent = refreshBtn
    refreshBtn.MouseButton1Click:Connect(function()
        refreshBtn.Text = "⟳ FETCHING..."
        antiAdmin.lastGroupFetch = 0
        task.spawn(function()
            local success = pcall(updateAdminTracker)
            refreshBtn.Text = success and "⟳ REFRESH TRACKER" or "⟳ FAILED — RETRY"
            if not success then task.wait(2); refreshBtn.Text = "⟳ REFRESH TRACKER" end
            if state.currentTab == "Anti-Admin" then buildAntiAdminTab() end
        end)
    end)
    order = order + 1
    if #antiAdmin.sameServerAdmins > 0 then
        local banner = Instance.new("Frame")
        banner.Size = UDim2.new(1, -4, 0, 36)
        banner.BackgroundColor3 = Color3.fromRGB(7, 26, 36)
        banner.BorderSizePixel = 0
        banner.LayoutOrder = order
        banner.Parent = scroll
        local bannerCorner = Instance.new("UICorner")
        bannerCorner.CornerRadius = UDim.new(0, 4)
        bannerCorner.Parent = banner
        local bannerLabel = Instance.new("TextLabel")
        bannerLabel.Size = UDim2.new(1, -8, 1, 0)
        bannerLabel.Position = UDim2.new(0, 4, 0, 0)
        bannerLabel.BackgroundTransparency = 1
        bannerLabel.Text = "🚨 " .. #antiAdmin.sameServerAdmins .. " ADMIN(S) IN YOUR SERVER"
        bannerLabel.TextColor3 = Color3.fromRGB(0, 198, 188)
        bannerLabel.TextSize = 12
        bannerLabel.Font = Enum.Font.Gotham
        bannerLabel.TextXAlignment = Enum.TextXAlignment.Center
        bannerLabel.TextYAlignment = Enum.TextYAlignment.Center
        bannerLabel.Parent = banner
        order = order + 1
    end
    local watchHeader = Instance.new("TextLabel")
    watchHeader.Size = UDim2.new(1, 0, 0, 22)
    watchHeader.BackgroundTransparency = 1
    watchHeader.Text = "─ WATCHLIST (" .. #WATCHLIST .. ") ─"
    watchHeader.TextColor3 = Color3.fromRGB(0, 198, 188)
    watchHeader.TextSize = 11
    watchHeader.Font = Enum.Font.Gotham
    watchHeader.LayoutOrder = order
    watchHeader.Parent = scroll
    order = order + 1
    for userId, entry in pairs(WATCHLIST) do
        local inServer = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == userId then inServer = true break end
        end
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 40)
        row.BackgroundColor3 = inServer and Color3.fromRGB(80, 20, 20) or Color3.fromRGB(25, 20, 20)
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = scroll
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row
        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 4, 1, 0)
        accent.BackgroundColor3 = inServer and Color3.fromRGB(0, 198, 188) or Color3.fromRGB(180, 60, 60)
        accent.BorderSizePixel = 0
        accent.Parent = row
        local accentCorner = Instance.new("UICorner")
        accentCorner.CornerRadius = UDim.new(0, 4)
        accentCorner.Parent = accent
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.6, 0, 0, 20)
        nameLabel.Position = UDim2.new(0, 12, 0, 2)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = entry.username .. " (" .. entry.displayName .. ")"
        nameLabel.TextColor3 = inServer and Color3.fromRGB(0, 198, 188) or Color3.fromRGB(230, 200, 200)
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row
        local idLabel = Instance.new("TextLabel")
        idLabel.Size = UDim2.new(0.6, 0, 0, 14)
        idLabel.Position = UDim2.new(0, 12, 0, 22)
        idLabel.BackgroundTransparency = 1
        idLabel.Text = "ID: " .. userId
        idLabel.TextColor3 = Color3.fromRGB(150, 130, 130)
        idLabel.TextSize = 10
        idLabel.Font = Enum.Font.Gotham
        idLabel.TextXAlignment = Enum.TextXAlignment.Left
        idLabel.Parent = row
        local statusLabel2 = Instance.new("TextLabel")
        statusLabel2.Size = UDim2.new(0.35, 0, 1, 0)
        statusLabel2.Position = UDim2.new(0.65, 0, 0, 0)
        statusLabel2.BackgroundTransparency = 1
        statusLabel2.Text = inServer and "⚠ IN SERVER" or "Not here"
        statusLabel2.TextColor3 = inServer and Color3.fromRGB(0, 198, 188) or Color3.fromRGB(120, 120, 140)
        statusLabel2.TextSize = 11
        statusLabel2.Font = Enum.Font.Gotham
        statusLabel2.TextXAlignment = Enum.TextXAlignment.Right
        statusLabel2.TextYAlignment = Enum.TextYAlignment.Center
        statusLabel2.Parent = row
        order = order + 1
    end
    local listHeader = Instance.new("TextLabel")
    listHeader.Size = UDim2.new(1, 0, 0, 22)
    listHeader.BackgroundTransparency = 1
    listHeader.Text = "─ GROUP ADMINS (" .. #antiAdmin.groupMembers .. ") ─"
    listHeader.TextColor3 = Color3.fromRGB(150, 150, 170)
    listHeader.TextSize = 11
    listHeader.Font = Enum.Font.Gotham
    listHeader.LayoutOrder = order
    listHeader.Parent = scroll
    order = order + 1
    local sortedAdmins = {}
    for _, admin in ipairs(antiAdmin.groupMembers) do table.insert(sortedAdmins, admin) end
    table.sort(sortedAdmins, function(a, b)
        local aTrack = antiAdmin.trackedAdmins[a.userId]
        local bTrack = antiAdmin.trackedAdmins[b.userId]
        local aScore = (aTrack and aTrack.sameServer and 4) or (aTrack and aTrack.isOnline and 3) or (aTrack and aTrack.isInGame and 2) or 1
        local bScore = (bTrack and bTrack.sameServer and 4) or (bTrack and bTrack.isOnline and 3) or (bTrack and bTrack.isInGame and 2) or 1
        if aScore ~= bScore then return aScore > bScore end
        return a.username < b.username
    end)
    for _, admin in ipairs(sortedAdmins) do
        local tracked = antiAdmin.trackedAdmins[admin.userId] or {}
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 46)
        row.BackgroundColor3 = tracked.sameServer and Color3.fromRGB(60, 20, 20) or Color3.fromRGB(22, 22, 35)
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = scroll
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row
        local dot = Instance.new("TextLabel")
        dot.Size = UDim2.new(0, 20, 0, 20)
        dot.Position = UDim2.new(0, 6, 0, 4)
        dot.BackgroundTransparency = 1
        dot.Text = "●"
        if tracked.sameServer then dot.TextColor3 = Color3.fromRGB(0, 198, 188)
        elseif tracked.isInGame then dot.TextColor3 = Color3.fromRGB(255, 200, 50)
        elseif tracked.isOnline then dot.TextColor3 = Color3.fromRGB(100, 255, 100)
        else dot.TextColor3 = Color3.fromRGB(80, 80, 90) end
        dot.TextSize = 18
        dot.Font = Enum.Font.SourceSans
        dot.Parent = row
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.45, 0, 0, 20)
        nameLabel.Position = UDim2.new(0, 26, 0, 2)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = admin.username
        nameLabel.TextColor3 = tracked.sameServer and Color3.fromRGB(0, 198, 188) or Color3.fromRGB(220, 220, 230)
        nameLabel.TextSize = 12
        nameLabel.Font = Enum.Font.Gotham
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row
        local roleLabel = Instance.new("TextLabel")
        roleLabel.Size = UDim2.new(0.45, 0, 0, 14)
        roleLabel.Position = UDim2.new(0, 26, 0, 22)
        roleLabel.BackgroundTransparency = 1
        roleLabel.Text = admin.role
        roleLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
        roleLabel.TextSize = 10
        roleLabel.Font = Enum.Font.Gotham
        roleLabel.TextXAlignment = Enum.TextXAlignment.Left
        roleLabel.Parent = row
        local statusText = "Offline"
        local statusColor = Color3.fromRGB(120, 120, 130)
        if tracked.sameServer then statusText = "⚠ IN YOUR SERVER"; statusColor = Color3.fromRGB(0, 198, 188)
        elseif tracked.isInGame then statusText = "In game"; statusColor = Color3.fromRGB(255, 200, 100)
        elseif tracked.isOnline then statusText = "Online"; statusColor = Color3.fromRGB(100, 255, 100) end
        local statusLabel2 = Instance.new("TextLabel")
        statusLabel2.Size = UDim2.new(0.45, 0, 0, 14)
        statusLabel2.Position = UDim2.new(0.5, 0, 0, 2)
        statusLabel2.BackgroundTransparency = 1
        statusLabel2.Text = statusText
        statusLabel2.TextColor3 = statusColor
        statusLabel2.TextSize = 11
        statusLabel2.Font = Enum.Font.Gotham
        statusLabel2.TextXAlignment = Enum.TextXAlignment.Right
        statusLabel2.Parent = row
        local gameLabel = Instance.new("TextLabel")
        gameLabel.Size = UDim2.new(0.5, -6, 0, 20)
        gameLabel.Position = UDim2.new(0.5, 0, 0, 22)
        gameLabel.BackgroundTransparency = 1
        local gameText = "—"
        if tracked.sameServer then gameText = "This server"
        elseif tracked.currentGameName then
            gameText = tracked.currentGameName
            if #gameText > 22 then gameText = gameText:sub(1, 20) .. "..." end
        elseif tracked.isInGame then gameText = "Unknown game" end
        gameLabel.Text = gameText
        gameLabel.TextColor3 = Color3.fromRGB(170, 170, 190)
        gameLabel.TextSize = 10
        gameLabel.Font = Enum.Font.Gotham
        gameLabel.TextXAlignment = Enum.TextXAlignment.Right
        gameLabel.Parent = row
        order = order + 1
    end
    if #sortedAdmins == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, -4, 0, 60)
        emptyLabel.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
        emptyLabel.BorderSizePixel = 0
        emptyLabel.Text = "No admins cached.\nTap REFRESH to fetch."
        emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
        emptyLabel.TextSize = 11
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.LayoutOrder = order
        emptyLabel.Parent = scroll
        order = order + 1
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, order * 38 + 100)
end



-- ═══════════════════════════════
-- CONFIG TAB
-- ═══════════════════════════════
local function buildConfigTab()
    clearContent()
    titleText.Text = "Config"

    if not hasFileAPI then
        local card1, content1 = createCard(scroll, "File API Warning", "⚠️")
        local warnLabel = Instance.new("TextLabel")
        warnLabel.Size = UDim2.new(1, 0, 0, 50)
        warnLabel.BackgroundTransparency = 1
        warnLabel.Text = "File API not available.\nConfigs cannot be saved."
        warnLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
        warnLabel.TextSize = 11
        warnLabel.Font = Enum.Font.Gotham
        warnLabel.Parent = content1
        card1.Size = UDim2.new(1, 0, 0, 100)
    end

    local card2, content2 = createCard(scroll, "Save Configuration", "💾")
    local saveInput = Instance.new("TextBox")
    saveInput.Size = UDim2.new(0.7, 0, 0, 32)
    saveInput.BackgroundColor3 = Color3.fromRGB(16, 25, 37)
    saveInput.BorderSizePixel = 1
    saveInput.BorderColor3 = Color3.fromRGB(36, 51, 63)
    saveInput.Text = state.loadedConfigName or ""
    saveInput.PlaceholderText = "Config name..."
    saveInput.TextColor3 = Color3.fromRGB(220, 232, 236)
    saveInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    saveInput.TextSize = 12
    saveInput.Font = Enum.Font.Gotham
    saveInput.Parent = content2
    local saveInputCorner = Instance.new("UICorner")
    saveInputCorner.CornerRadius = UDim.new(0, 6)
    saveInputCorner.Parent = saveInput

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.25, 0, 0, 32)
    saveBtn.BackgroundColor3 = Color3.fromRGB(20, 107, 145)
    saveBtn.Text = "SAVE"
    saveBtn.TextColor3 = Color3.fromRGB(239, 255, 252)
    saveBtn.TextSize = 11
    saveBtn.Font = Enum.Font.Gotham
    saveBtn.BorderSizePixel = 0
    saveBtn.Parent = content2
    local saveBtnCorner = Instance.new("UICorner")
    saveBtnCorner.CornerRadius = UDim.new(0, 6)
    saveBtnCorner.Parent = saveBtn

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 20)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = ""
    statusLabel.TextColor3 = Color3.fromRGB(210, 145, 150)
    statusLabel.TextSize = 10
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = content2

    saveBtn.MouseButton1Click:Connect(function()
        local name = saveInput.Text
        if not name or name == "" then
            statusLabel.Text = "⚠ Enter a name first"
            statusLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
            task.wait(2)
            if state.currentTab == "Config" then buildConfigTab() end
            return
        end
        local ok = saveConfig(name)
        if ok then
            state.loadedConfigName = name
            statusLabel.Text = "✅ Saved: " .. name
            statusLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
            task.wait(1.5)
            if state.currentTab == "Config" then buildConfigTab() end
        else
            statusLabel.Text = "❌ Failed to save"
            statusLabel.TextColor3 = Color3.fromRGB(0, 198, 188)
            task.wait(2)
            if state.currentTab == "Config" then buildConfigTab() end
        end
    end)

    local card3, content3 = createCard(scroll, "Auto-Load Settings", "⟳")
    local autoLabel = Instance.new("TextLabel")
    autoLabel.Size = UDim2.new(1, 0, 0, 20)
    autoLabel.BackgroundTransparency = 1
    autoLabel.Text = "Load on hop: " .. (getAutoLoadConfig() or "None")
    autoLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    autoLabel.TextSize = 12
    autoLabel.Font = Enum.Font.Gotham
    autoLabel.Parent = content3

    local btnHolder = Instance.new("Frame")
    btnHolder.Size = UDim2.new(1, 0, 0, 38)
    btnHolder.BackgroundTransparency = 1
    btnHolder.Parent = content3
    local btnList = Instance.new("UIListLayout")
    btnList.Parent = btnHolder
    btnList.SortOrder = Enum.SortOrder.LayoutOrder
    btnList.FillDirection = Enum.FillDirection.Horizontal
    btnList.Padding = UDim.new(0, 4)

    local configs = listConfigs()
    if #configs == 0 then
        local noCfg = Instance.new("TextLabel")
        noCfg.Size = UDim2.new(1, 0, 1, 0)
        noCfg.BackgroundTransparency = 1
        noCfg.Text = "No configs saved yet"
        noCfg.TextColor3 = Color3.fromRGB(120, 120, 140)
        noCfg.TextSize = 10
        noCfg.Font = Enum.Font.Gotham
        noCfg.Parent = btnHolder
    else
        for idx, cfgName in ipairs(configs) do
            if idx > 4 then break end
            local isActive = (getAutoLoadConfig() == cfgName)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, 70, 1, 0)
            b.BackgroundColor3 = isActive and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(30, 30, 45)
            b.Text = cfgName:sub(1, 8)
            b.TextColor3 = isActive and Color3.fromRGB(0, 198, 188) or Color3.fromRGB(180, 175, 180)
            b.TextSize = 10
            b.Font = Enum.Font.Gotham
            b.BorderSizePixel = 0
            b.Parent = btnHolder
            local bCorner = Instance.new("UICorner")
            bCorner.CornerRadius = UDim.new(0, 4)
            bCorner.Parent = b
            b.MouseButton1Click:Connect(function()
                setAutoLoadConfig(cfgName)
                state.loadedConfigName = cfgName
                statusLabel.Text = "✅ Auto-load set to: " .. cfgName
                statusLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
                task.wait(1)
                if state.currentTab == "Config" then buildConfigTab() end
            end)
        end
        local noneBtn = Instance.new("TextButton")
        noneBtn.Size = UDim2.new(0, 50, 1, 0)
        noneBtn.BackgroundColor3 = Color3.fromRGB(40, 25, 25)
        noneBtn.Text = "None"
        noneBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
        noneBtn.TextSize = 10
        noneBtn.Font = Enum.Font.Gotham
        noneBtn.BorderSizePixel = 0
        noneBtn.Parent = btnHolder
        local noneCorner = Instance.new("UICorner")
        noneCorner.CornerRadius = UDim.new(0, 4)
        noneCorner.Parent = noneBtn
        noneBtn.MouseButton1Click:Connect(function()
            setAutoLoadConfig(nil)
            state.loadedConfigName = nil
            statusLabel.Text = "Auto-load disabled"
            statusLabel.TextColor3 = Color3.fromRGB(200, 150, 150)
            task.wait(1)
            if state.currentTab == "Config" then buildConfigTab() end
        end)
    end

    createToggle(content3, "Auto Re-Execute on Hop", state, "autoReExecute", function(val) state.autoReExecute = val end)

    local card4, content4 = createCard(scroll, "Saved Configurations", "📁")
    if #configs == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, 0, 0, 40)
        emptyLabel.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
        emptyLabel.Text = "No configs saved yet."
        emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
        emptyLabel.TextSize = 11
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.Parent = content4
        local emptyCorner = Instance.new("UICorner")
        emptyCorner.CornerRadius = UDim.new(0, 6)
        emptyCorner.Parent = emptyLabel
    else
        for _, name in ipairs(configs) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 36)
            row.BackgroundColor3 = Color3.fromRGB(17, 20, 24)
            row.BorderSizePixel = 0
            row.Parent = content4
            local rowCorner = Instance.new("UICorner")
            rowCorner.CornerRadius = UDim.new(0, 6)
            rowCorner.Parent = row
            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(0.5, 0, 1, 0)
            nameLabel.Position = UDim2.new(0, 10, 0, 0)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Text = name
            nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
            nameLabel.TextSize = 12
            nameLabel.Font = Enum.Font.Gotham
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Parent = row
            local loadBtn = Instance.new("TextButton")
            loadBtn.Size = UDim2.new(0, 50, 0, 28)
            loadBtn.Position = UDim2.new(0.55, 0, 0.5, -14)
            loadBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
            loadBtn.Text = "LOAD"
            loadBtn.TextColor3 = Color3.fromRGB(0, 198, 188)
            loadBtn.TextSize = 10
            loadBtn.Font = Enum.Font.Gotham
            loadBtn.BorderSizePixel = 0
            loadBtn.Parent = row
            local loadCorner = Instance.new("UICorner")
            loadCorner.CornerRadius = UDim.new(0, 4)
            loadCorner.Parent = loadBtn
            local overwriteBtn = Instance.new("TextButton")
            overwriteBtn.Size = UDim2.new(0, 50, 0, 28)
            overwriteBtn.Position = UDim2.new(0.7, 0, 0.5, -14)
            overwriteBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 30)
            overwriteBtn.Text = "SAVE"
            overwriteBtn.TextColor3 = Color3.fromRGB(255, 200, 100)
            overwriteBtn.TextSize = 10
            overwriteBtn.Font = Enum.Font.Gotham
            overwriteBtn.BorderSizePixel = 0
            overwriteBtn.Parent = row
            local overwriteCorner = Instance.new("UICorner")
            overwriteCorner.CornerRadius = UDim.new(0, 4)
            overwriteCorner.Parent = overwriteBtn
            local delBtn = Instance.new("TextButton")
            delBtn.Size = UDim2.new(0, 35, 0, 28)
            delBtn.Position = UDim2.new(0.88, 0, 0.5, -14)
            delBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
            delBtn.Text = "✕"
            delBtn.TextColor3 = Color3.fromRGB(0, 198, 188)
            delBtn.TextSize = 10
            delBtn.Font = Enum.Font.Gotham
            delBtn.BorderSizePixel = 0
            delBtn.Parent = row
            local delCorner = Instance.new("UICorner")
            delCorner.CornerRadius = UDim.new(0, 4)
            delCorner.Parent = delBtn

            loadBtn.MouseButton1Click:Connect(function()
                local data = loadConfigData(name)
                if data then
                    state.loadedConfigName = name
                    applyConfigData(data)
                    statusLabel.Text = "✅ Loaded: " .. name
                    statusLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
                    task.wait(1.5)
                    if state.currentTab == "Config" then buildConfigTab() end
                else
                    statusLabel.Text = "❌ Failed to load"
                    statusLabel.TextColor3 = Color3.fromRGB(0, 198, 188)
                    task.wait(2)
                    if state.currentTab == "Config" then buildConfigTab() end
                end
            end)

            overwriteBtn.MouseButton1Click:Connect(function()
                local ok = saveConfig(name)
                if ok then
                    state.loadedConfigName = name
                    statusLabel.Text = "💾 Overwrote: " .. name
                    statusLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
                    task.wait(1.5)
                    if state.currentTab == "Config" then buildConfigTab() end
                end
            end)

            delBtn.MouseButton1Click:Connect(function()
                deleteConfig(name)
                if getAutoLoadConfig() == name then setAutoLoadConfig(nil) end
                statusLabel.Text = "🗑️ Deleted: " .. name
                statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
                task.wait(1)
                if state.currentTab == "Config" then buildConfigTab() end
            end)
        end
    end

    -- Adjust sizes
    card2.Size = UDim2.new(1, 0, 0, 120)
    card3.Size = UDim2.new(1, 0, 0, content3.UIListLayout.AbsoluteContentSize.Y + 60)
    card4.Size = UDim2.new(1, 0, 0, content4.UIListLayout.AbsoluteContentSize.Y + 60)
    scroll.CanvasSize = UDim2.new(0, 0, 0, scroll.UIListLayout.AbsoluteContentSize.Y + 24)
end

-- ═══════════════════════════════
-- SETTINGS TAB
-- ═══════════════════════════════
local function buildSettingsTab()
    clearContent()
    local order = 1
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 28)
    header.BackgroundTransparency = 1
    header.Text = "═ SYSTEM ═"
    header.TextColor3 = Color3.fromRGB(200, 200, 200)
    header.TextSize = 12
    header.Font = Enum.Font.Gotham
    header.LayoutOrder = 0
    header.Parent = scroll
    createToggle(scroll, "Anti-AFK", state.protection, "AntiAFK", function(val)
        if val then
            if antiAFKConnection then antiAFKConnection:Disconnect() end
            antiAFKConnection = localPlayer.Idled:Connect(function()
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end)
        else
            if antiAFKConnection then antiAFKConnection:Disconnect(); antiAFKConnection = nil end
        end
    end, order)
    order = order + 1
    local infoFrame = Instance.new("Frame")
    infoFrame.Size = UDim2.new(1, -4, 0, 60)
    infoFrame.BackgroundColor3 = Color3.fromRGB(17, 20, 24)
    infoFrame.BorderSizePixel = 0
    infoFrame.LayoutOrder = order
    infoFrame.Parent = scroll
    local infoCorner = Instance.new("UICorner")
    infoCorner.CornerRadius = UDim.new(0, 4)
    infoCorner.Parent = infoFrame
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, -10, 1, 0)
    infoLabel.Position = UDim2.new(0, 8, 0, 0)
    infoLabel.BackgroundTransparency = 1
    infoLabel.Text = "File API: " .. (hasFileAPI and "✅" or "❌")
        .. "\nqueue_on_teleport: " .. (hasQueue and "✅" or "❌")
        .. "\nDropCash event: " .. (DROP_CASH_EVENT and "✅" or "❌")
        .. "\nExecutor: Delta"
    infoLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
    infoLabel.TextSize = 11
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextYAlignment = Enum.TextYAlignment.Center
    infoLabel.Parent = infoFrame
    order = order + 1
    scroll.CanvasSize = UDim2.new(0, 0, 0, order * 36 + 80)
end

local function switchTab(name)
    state.currentTab = name
    for tabName, btn in pairs(tabButtons) do
        local isActive = tabName == name
        btn.BackgroundColor3 = isActive and Color3.fromRGB(37, 136, 199) or Color3.fromRGB(16, 20, 25)
        btn.TextColor3 = isActive and Color3.fromRGB(232, 241, 244) or Color3.fromRGB(101, 116, 125)
        btn.Text = (tabName == "Farms" and "◈  Automation" or tabName)
    end
    if name == "Farms" then
        buildFarmsTab()
    elseif name == "Anti-Admin" then
        buildAntiAdminTab()
    end
end

for name, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function() switchTab(name) end)
end

-- Minimize
local miniCircle = Instance.new("Frame")
miniCircle.Size = UDim2.new(0, 0, 0, 0)
miniCircle.Position = UDim2.new(0, 12, 0, 12)
miniCircle.BackgroundColor3 = Color3.fromRGB(7, 26, 36)
miniCircle.BorderSizePixel = 1
miniCircle.BorderColor3 = Color3.fromRGB(0, 198, 188)
miniCircle.Parent = screenGui
miniCircle.Visible = false
miniCircle.Active = true
local circleCorner = Instance.new("UICorner")
circleCorner.CornerRadius = UDim.new(1, 0)
circleCorner.Parent = miniCircle
local circleText = Instance.new("TextLabel")
circleText.Size = UDim2.new(1, 0, 1, 0)
circleText.BackgroundTransparency = 1
circleText.Text = "N"
circleText.TextColor3 = Color3.fromRGB(95, 255, 240)
circleText.TextSize = 20
circleText.Font = Enum.Font.Gotham
circleText.TextScaled = true
circleText.Parent = miniCircle
local miniClick = Instance.new("TextButton")
miniClick.Size = UDim2.new(1, 0, 1, 0)
miniClick.BackgroundTransparency = 1
miniClick.Text = ""
miniClick.Parent = miniCircle

minimizeBtn.MouseButton1Click:Connect(function()
    if state.minimized then return end
    state.minimized = true
    local shrink = TweenService:Create(mainFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Size = UDim2.new(0, 0, 0, 0),
        Position = UDim2.new(0, 12, 0, 12)
    })
    shrink:Play()
    shrink.Completed:Wait()
    mainFrame.Visible = false
    miniCircle.Visible = true
    miniCircle.Size = UDim2.new(0, 0, 0, 0)
    local expand = TweenService:Create(miniCircle, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(0, 48, 0, 48)})
    expand:Play()
end)

miniClick.MouseButton1Click:Connect(function()
    if not state.minimized then return end
    state.minimized = false
    local shrink = TweenService:Create(miniCircle, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrink:Play()
    shrink.Completed:Wait()
    miniCircle.Visible = false
    mainFrame.Visible = true
    mainFrame.Size = UDim2.new(0, 0, 0, 0)
    mainFrame.Position = UDim2.new(0, 12, 0, 12)
    local expand = TweenService:Create(mainFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 760, 0, 470),
        Position = UDim2.new(0.5, -380, 0.5, -235)
    })
    expand:Play()
end)

closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
    state.running = false
end)


localPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F5 then
        state.running = false
        state.cashTransfer.running = false
        for key in pairs(state.farms) do state.farms[key] = false end
        for key, _ in pairs(farmThreads) do farmThreads[key] = nil end
        teleportSystem.generation = teleportSystem.generation + 1
        teleportSystem.usedTeleports = 0
        if antiAFKConnection then antiAFKConnection:Disconnect(); antiAFKConnection = nil end
    end
end)

switchTab("Farms")

-- Startup
task.spawn(function()
    local char = localPlayer.Character
    while not char or not char:FindFirstChild("HumanoidRootPart") do
        task.wait(0.5)
        char = localPlayer.Character
    end
    skipIntro()
    task.wait(0.5)
    local Event = ReplicatedStorage:FindFirstChild("Events")
    if Event then
        local reset = Event:FindFirstChild("Reset")
        if reset then pcall(function() reset:FireServer("Reset") end) end
    end
    local oldChar = localPlayer.Character
    local t = 0
    repeat task.wait(0.1); t = t + 0.1
    until (localPlayer.Character and localPlayer.Character ~= oldChar and localPlayer.Character:FindFirstChild("HumanoidRootPart")) or t > 8
    task.wait(0.5)
    skipIntro()
    task.wait(0.3)
    teleportToIdleForce()

    task.wait(1)
    local autoName = getAutoLoadConfig()
    if autoName and state.autoReExecute then
        local data = loadConfigData(autoName)
        if data then
            applyConfigData(data)
            state.loadedConfigName = autoName
            if state.currentTab == "Farms" then buildFarmsTab() end
        end
    end
end)

print("Made by the OneAndOnlyXen.")
