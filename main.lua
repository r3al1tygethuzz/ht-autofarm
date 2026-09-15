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
    if queued then print("[PHOTON] ✅ Queued reload") end
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
    print("[PHOTON] ⚠️ ADMIN DETECTED — " .. reason)
    queueReload()
    task.wait(0.5)
    local hopSuccess = attemptServerHop()
    if hopSuccess then task.wait(5) end
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

local function chainTeleport(pos)
    local hrp = getHRP()
    if not hrp then return false end
    local hum = getHumanoid()
    if hum then hum.PlatformStand = true; hum.WalkSpeed = 0 end
    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
    hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
    task.wait(0.05)
    if hum then hum.PlatformStand = false; hum.WalkSpeed = 16 end
    useTeleport()
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
local state = {
    farms = { Dumpster = false, Cash = false, Register = false, SuperFarm = false },
    
    protection = { AntiAFK = false, AntiAdmin = true },
    cashTransfer = { selectedName = "", running = false },
    running = true, minimized = false, currentTab = "Farms",
    autoReExecute = true,
    loadedConfigName = getAutoLoadConfig()
}

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
    print("[PHOTON] 💸 Cash Transfer starting → " .. targetPlayer.Name)
    state.cashTransfer.running = true

    -- Reset character to ensure clean state
    print("[PHOTON] 🔄 Resetting character first...")
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
        print("[PHOTON] ⚠️ Target has no character — aborting")
        state.cashTransfer.running = false
        teleportToIdleForce()
        return
    end

    print("[PHOTON] 📍 TPing to " .. targetPlayer.Name)
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
        print("[PHOTON] ⚠️ DropCash event not found — aborting")
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
                print("[PHOTON] ✅ Cash under 5000 (" .. cash .. ") — stopping")
                break
            end
        else
            noValueStreak = noValueStreak + 1
            if noValueStreak > 60 then
                -- 30 seconds without detecting cash — bail
                print("[PHOTON] ⚠️ Could not read cash value — stopping after 30s")
                break
            end
        end

        if spamCount >= maxSpam then
            print("[PHOTON] ⚠️ Hit spam cap (" .. maxSpam .. ") — stopping")
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

    print("[PHOTON] 💸 Cash Transfer finished. Fires: " .. spamCount .. " | Last cash: " .. tostring(lastCash))

    -- TP back to idle
    task.wait(0.5)
    teleportToIdleForce()
    print("[PHOTON] 📍 Returned to idle")

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
screenGui.Name = "NyraUI"
screenGui.Parent = CoreGui
screenGui.Enabled = true
screenGui.ResetOnSpawn = false

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 780, 0, 500)
mainFrame.Position = UDim2.new(0.5, -390, 0.5, -250)
mainFrame.BackgroundColor3 = Color3.fromRGB(8, 11, 14)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
mainFrame.Active = true
mainFrame.Draggable = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 9)
corner.Parent = mainFrame

local bgGradient = Instance.new("UIGradient")
bgGradient.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 11, 14)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 26, 36))
}
bgGradient.Parent = mainFrame

local leftSidebar = Instance.new("Frame")
leftSidebar.Size = UDim2.new(0, 120, 1, 0)
leftSidebar.BackgroundColor3 = Color3.fromRGB(16, 20, 25)
leftSidebar.BorderSizePixel = 0
leftSidebar.Parent = mainFrame

local logoArea = Instance.new("Frame")
logoArea.Size = UDim2.new(1, -16, 0, 60)
logoArea.Position = UDim2.new(0, 8, 0, 12)
logoArea.BackgroundTransparency = 1
logoArea.Parent = leftSidebar

local logoText = Instance.new("TextLabel")
logoText.Size = UDim2.new(1, 0, 1, 0)
logoText.BackgroundTransparency = 1
logoText.Text = "NYRA"
logoText.TextColor3 = Color3.fromRGB(234, 247, 245)
logoText.TextSize = 18
logoText.Font = Enum.Font.GothamSemibold
logoText.TextXAlignment = Enum.TextXAlignment.Center
logoText.Parent = logoArea

local navContainer = Instance.new("Frame")
navContainer.Size = UDim2.new(1, -16, 0, 300)
navContainer.Position = UDim2.new(0, 8, 0, 80)
navContainer.BackgroundTransparency = 1
navContainer.Parent = leftSidebar

local navList = Instance.new("UIListLayout")
navList.Parent = navContainer
navList.SortOrder = Enum.SortOrder.LayoutOrder
navList.Padding = UDim.new(0, 6)

local tabs = {"Farms", "Cash Transfer", "Anti-Admin"}
local tabButtons = {}

for i, name in ipairs(tabs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 50)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.BorderSizePixel = 0
    btn.LayoutOrder = i
    btn.Parent = navContainer
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn
    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 22, 0, 22)
    icon.Position = UDim2.new(0, 10, 0, 5)
    icon.BackgroundTransparency = 1
    icon.Text = (name == "Farms" and "⚡") or (name == "Cash Transfer" and "💸") or "🛡️"
    icon.TextSize = 20
    icon.Font = Enum.Font.SourceSans
    icon.Parent = btn
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -32, 0, 18)
    label.Position = UDim2.new(0, 10, 0, 27)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = btn
    btn.Icon = icon
    btn.Label = label
    if i == 1 then
        btn.BackgroundTransparency = 0
        btn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
        icon.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        local glow = Instance.new("UIGradient")
        glow.Color = ColorSequence.new(Color3.fromRGB(58, 159, 232), Color3.fromRGB(0, 217, 196))
        glow.Parent = btn
    else
        icon.TextColor3 = Color3.fromRGB(155, 167, 173)
        label.TextColor3 = Color3.fromRGB(120, 133, 140)
    end
    tabButtons[name] = btn
end

local headerBar = Instance.new("Frame")
headerBar.Size = UDim2.new(1, -120, 0, 50)
headerBar.Position = UDim2.new(0, 120, 0, 0)
headerBar.BackgroundColor3 = Color3.fromRGB(11, 15, 19)
headerBar.BorderSizePixel = 0
headerBar.Parent = mainFrame

local headerDivider = Instance.new("Frame")
headerDivider.Size = UDim2.new(1, -20, 0, 1)
headerDivider.Position = UDim2.new(0, 10, 1, -1)
headerDivider.BackgroundColor3 = Color3.fromRGB(37, 46, 53)
headerDivider.BorderSizePixel = 0
headerDivider.Parent = headerBar

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(0.7, 0, 1, 0)
titleText.Position = UDim2.new(0, 12, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "Farms"
titleText.TextColor3 = Color3.fromRGB(241, 245, 246)
titleText.TextSize = 20
titleText.Font = Enum.Font.GothamSemibold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextYAlignment = Enum.TextYAlignment.Center
titleText.Parent = headerBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 30, 0, 30)
minimizeBtn.Position = UDim2.new(1, -70, 0, 10)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 41)
minimizeBtn.Text = "─"
minimizeBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
minimizeBtn.TextSize = 16
minimizeBtn.Font = Enum.Font.Gotham
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = headerBar
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = minimizeBtn

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -35, 0, 10)
closeBtn.BackgroundColor3 = Color3.fromRGB(35, 38, 41)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(0, 217, 196)
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.Gotham
closeBtn.BorderSizePixel = 0
closeBtn.Parent = headerBar
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

local contentArea = Instance.new("Frame")
contentArea.Size = UDim2.new(1, -120, 1, -50)
contentArea.Position = UDim2.new(0, 120, 0, 50)
contentArea.BackgroundTransparency = 1
contentArea.Parent = mainFrame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -12)
scroll.Position = UDim2.new(0, 10, 0, 6)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(48, 52, 59)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = contentArea

local contentList = Instance.new("UIListLayout")
contentList.Parent = scroll
contentList.SortOrder = Enum.SortOrder.LayoutOrder
contentList.Padding = UDim.new(0, 0)

local function createRow(parent, label, rightElement)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local labelText = Instance.new("TextLabel")
    labelText.Size = UDim2.new(0.5, 0, 1, 0)
    labelText.BackgroundTransparency = 1
    labelText.Text = label
    labelText.TextColor3 = Color3.fromRGB(241, 245, 246)
    labelText.TextSize = 13
    labelText.Font = Enum.Font.GothamMedium
    labelText.TextXAlignment = Enum.TextXAlignment.Left
    labelText.Parent = row

    if rightElement then
        rightElement.Size = UDim2.new(0, 0, 1, 0)
        rightElement.Position = UDim2.new(1, -rightElement.Size.X.Offset, 0, 0)
        rightElement.Parent = row
    end

    return row
end

local function createDivider(parent)
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, 0, 0, 1)
    div.BackgroundColor3 = Color3.fromRGB(37, 46, 53)
    div.BorderSizePixel = 0
    div.Parent = parent
    return div
end

local function createToggle(parent, label, stateRef, key, callback)
    local row = createRow(parent, label)

    local toggle = Instance.new("Frame")
    toggle.Size = UDim2.new(0, 38, 0, 20)
    toggle.Position = UDim2.new(1, -38, 0.5, -10)
    toggle.BackgroundColor3 = stateRef[key] and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
    toggle.BorderSizePixel = 0
    toggle.Parent = row
    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(0, 10)
    toggleCorner.Parent = toggle

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = stateRef[key] and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = toggle
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = row
    btn.MouseButton1Click:Connect(function()
        stateRef[key] = not stateRef[key]
        local val = stateRef[key]
        toggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
        knob.Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        if callback then callback(val) end
    end)
    return row
end

local function clearContent()
    for _, child in ipairs(scroll:GetChildren()) do
        if child ~= contentList then child:Destroy() end
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
end

-- ═══════════════════════════════
-- FARMS TAB
-- ═══════════════════════════════
local function buildFarmsTab()
    clearContent()
    titleText.Text = "Farms"

    local superFarmRow = createRow(scroll, "Super Farm")
    local superFarmToggle = Instance.new("Frame")
    superFarmToggle.Size = UDim2.new(0, 38, 0, 20)
    superFarmToggle.Position = UDim2.new(1, -38, 0.5, -10)
    superFarmToggle.BackgroundColor3 = state.farms.SuperFarm and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
    superFarmToggle.BorderSizePixel = 0
    superFarmToggle.Parent = superFarmRow
    local superFarmCorner = Instance.new("UICorner")
    superFarmCorner.CornerRadius = UDim.new(0, 10)
    superFarmCorner.Parent = superFarmToggle
    local superFarmKnob = Instance.new("Frame")
    superFarmKnob.Size = UDim2.new(0, 16, 0, 16)
    superFarmKnob.Position = state.farms.SuperFarm and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    superFarmKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    superFarmKnob.BorderSizePixel = 0
    superFarmKnob.Parent = superFarmToggle
    local superFarmKnobCorner = Instance.new("UICorner")
    superFarmKnobCorner.CornerRadius = UDim.new(1, 0)
    superFarmKnobCorner.Parent = superFarmKnob
    local superFarmBtn = Instance.new("TextButton")
    superFarmBtn.Size = UDim2.new(1, 0, 1, 0)
    superFarmBtn.BackgroundTransparency = 1
    superFarmBtn.Text = ""
    superFarmBtn.Parent = superFarmRow
    superFarmBtn.MouseButton1Click:Connect(function()
        local val = not state.farms.SuperFarm
        state.farms.SuperFarm = val
        superFarmToggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
        superFarmKnob.Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
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
    createDivider(scroll)

    local dumpsterRow = createRow(scroll, "Dumpster Farm")
    local dumpsterToggle = Instance.new("Frame")
    dumpsterToggle.Size = UDim2.new(0, 38, 0, 20)
    dumpsterToggle.Position = UDim2.new(1, -38, 0.5, -10)
    dumpsterToggle.BackgroundColor3 = state.farms.Dumpster and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
    dumpsterToggle.BorderSizePixel = 0
    dumpsterToggle.Parent = dumpsterRow
    local dumpsterCorner = Instance.new("UICorner")
    dumpsterCorner.CornerRadius = UDim.new(0, 10)
    dumpsterCorner.Parent = dumpsterToggle
    local dumpsterKnob = Instance.new("Frame")
    dumpsterKnob.Size = UDim2.new(0, 16, 0, 16)
    dumpsterKnob.Position = state.farms.Dumpster and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    dumpsterKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dumpsterKnob.BorderSizePixel = 0
    dumpsterKnob.Parent = dumpsterToggle
    local dumpsterKnobCorner = Instance.new("UICorner")
    dumpsterKnobCorner.CornerRadius = UDim.new(1, 0)
    dumpsterKnobCorner.Parent = dumpsterKnob
    local dumpsterBtn = Instance.new("TextButton")
    dumpsterBtn.Size = UDim2.new(1, 0, 1, 0)
    dumpsterBtn.BackgroundTransparency = 1
    dumpsterBtn.Text = ""
    dumpsterBtn.Parent = dumpsterRow
    dumpsterBtn.MouseButton1Click:Connect(function()
        local val = not state.farms.Dumpster
        state.farms.Dumpster = val
        dumpsterToggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
        dumpsterKnob.Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
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
    createDivider(scroll)

    local cashRow = createRow(scroll, "Floor Cash")
    local cashToggle = Instance.new("Frame")
    cashToggle.Size = UDim2.new(0, 38, 0, 20)
    cashToggle.Position = UDim2.new(1, -38, 0.5, -10)
    cashToggle.BackgroundColor3 = state.farms.Cash and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
    cashToggle.BorderSizePixel = 0
    cashToggle.Parent = cashRow
    local cashCorner = Instance.new("UICorner")
    cashCorner.CornerRadius = UDim.new(0, 10)
    cashCorner.Parent = cashToggle
    local cashKnob = Instance.new("Frame")
    cashKnob.Size = UDim2.new(0, 16, 0, 16)
    cashKnob.Position = state.farms.Cash and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    cashKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    cashKnob.BorderSizePixel = 0
    cashKnob.Parent = cashToggle
    local cashKnobCorner = Instance.new("UICorner")
    cashKnobCorner.CornerRadius = UDim.new(1, 0)
    cashKnobCorner.Parent = cashKnob
    local cashBtn = Instance.new("TextButton")
    cashBtn.Size = UDim2.new(1, 0, 1, 0)
    cashBtn.BackgroundTransparency = 1
    cashBtn.Text = ""
    cashBtn.Parent = cashRow
    cashBtn.MouseButton1Click:Connect(function()
        local val = not state.farms.Cash
        state.farms.Cash = val
        cashToggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
        cashKnob.Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
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
    createDivider(scroll)

    local registerRow = createRow(scroll, "Register Farm")
    local registerToggle = Instance.new("Frame")
    registerToggle.Size = UDim2.new(0, 38, 0, 20)
    registerToggle.Position = UDim2.new(1, -38, 0.5, -10)
    registerToggle.BackgroundColor3 = state.farms.Register and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
    registerToggle.BorderSizePixel = 0
    registerToggle.Parent = registerRow
    local registerCorner = Instance.new("UICorner")
    registerCorner.CornerRadius = UDim.new(0, 10)
    registerCorner.Parent = registerToggle
    local registerKnob = Instance.new("Frame")
    registerKnob.Size = UDim2.new(0, 16, 0, 16)
    registerKnob.Position = state.farms.Register and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    registerKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    registerKnob.BorderSizePixel = 0
    registerKnob.Parent = registerToggle
    local registerKnobCorner = Instance.new("UICorner")
    registerKnobCorner.CornerRadius = UDim.new(1, 0)
    registerKnobCorner.Parent = registerKnob
    local registerBtn = Instance.new("TextButton")
    registerBtn.Size = UDim2.new(1, 0, 1, 0)
    registerBtn.BackgroundTransparency = 1
    registerBtn.Text = ""
    registerBtn.Parent = registerRow
    registerBtn.MouseButton1Click:Connect(function()
        local val = not state.farms.Register
        state.farms.Register = val
        registerToggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
        registerKnob.Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
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
    createDivider(scroll)

    local statusRow = createRow(scroll, "Status")
    local counterLabel = Instance.new("TextLabel")
    counterLabel.Size = UDim2.new(0, 120, 0, 24)
    counterLabel.Position = UDim2.new(1, -120, 0.5, -12)
    counterLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    counterLabel.Text = "0 / " .. TP_CAP
    counterLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
    counterLabel.TextSize = 12
    counterLabel.Font = Enum.Font.Gotham
    counterLabel.TextXAlignment = Enum.TextXAlignment.Center
    counterLabel.Parent = statusRow
    local counterCorner = Instance.new("UICorner")
    counterCorner.CornerRadius = UDim.new(0, 6)
    counterCorner.Parent = counterLabel
    createDivider(scroll)

    local resetRow = createRow(scroll, "Actions")
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0, 80, 0, 28)
    resetBtn.Position = UDim2.new(1, -80, 0.5, -14)
    resetBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
    resetBtn.Text = "Reset"
    resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetBtn.TextSize = 12
    resetBtn.Font = Enum.Font.GothamMedium
    resetBtn.BorderSizePixel = 0
    resetBtn.Parent = resetRow
    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 6)
    resetCorner.Parent = resetBtn
    resetBtn.MouseButton1Click:Connect(function()
        task.spawn(function() forceResetCharacter() end)
    end)

    -- Update status
    local updateStatus = function()
        local used = teleportSystem.usedTeleports
        local current = selectedFarmKey or "None"
        counterLabel.Text = used .. " / " .. TP_CAP
        counterLabel.TextColor3 = used >= TP_CAP and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(0, 217, 196)
    end
    updateStatus()
    local statusUpdater = task.spawn(function()
        while state.running and state.currentTab == "Farms" do
            updateStatus()
            task.wait(0.5)
        end
    end)
    -- Store for cleanup
    if not scroll:FindFirstChild("StatusUpdater") then
        local conn = Instance.new("ObjectValue")
        conn.Name = "StatusUpdater"
        conn.Value = statusUpdater
        conn.Parent = scroll
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

-- ═══════════════════════════════
-- CASH TRANSFER TAB
-- ═══════════════════════════════
local function buildCashTransferTab()
    clearContent()
    titleText.Text = "Cash Transfer"

    local searchRow = createRow(scroll, "Target player")
    local searchInput = Instance.new("TextBox")
    searchInput.Size = UDim2.new(0, 320, 0, 32)
    searchInput.Position = UDim2.new(1, -320, 0.5, -16)
    searchInput.BackgroundColor3 = Color3.fromRGB(41, 47, 53)
    searchInput.Text = state.cashTransfer.selectedName or ""
    searchInput.PlaceholderText = "Enter player name..."
    searchInput.TextColor3 = Color3.fromRGB(229, 235, 237)
    searchInput.PlaceholderColor3 = Color3.fromRGB(160, 171, 179)
    searchInput.TextSize = 12
    searchInput.Font = Enum.Font.Gotham
    searchInput.BorderSizePixel = 0
    searchInput.Parent = searchRow
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 8)
    searchCorner.Parent = searchInput
    createDivider(scroll)

    local findRow = createRow(scroll, "Find player")
    local findBtn = Instance.new("TextButton")
    findBtn.Size = UDim2.new(0, 100, 0, 32)
    findBtn.Position = UDim2.new(1, -100, 0.5, -16)
    findBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
    findBtn.Text = "Find"
    findBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
    findBtn.TextSize = 12
    findBtn.Font = Enum.Font.GothamMedium
    findBtn.BorderSizePixel = 0
    findBtn.Parent = findRow
    local findCorner = Instance.new("UICorner")
    findCorner.CornerRadius = UDim.new(0, 8)
    findCorner.Parent = findBtn
    createDivider(scroll)

    local selectedRow = createRow(scroll, "Selected")
    local selectedLabel = Instance.new("TextLabel")
    selectedLabel.Size = UDim2.new(0, 320, 0, 24)
    selectedLabel.Position = UDim2.new(1, -320, 0.5, -12)
    selectedLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    selectedLabel.Text = state.cashTransfer.selectedName ~= "" and state.cashTransfer.selectedName or "None"
    selectedLabel.TextColor3 = state.cashTransfer.selectedName ~= "" and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(129, 133, 137)
    selectedLabel.TextSize = 12
    selectedLabel.Font = Enum.Font.Gotham
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Center
    selectedLabel.Parent = selectedRow
    local selectedCorner = Instance.new("UICorner")
    selectedCorner.CornerRadius = UDim.new(0, 6)
    selectedCorner.Parent = selectedLabel
    createDivider(scroll)

    local playersHeader = Instance.new("TextLabel")
    playersHeader.Size = UDim2.new(1, 0, 0, 28)
    playersHeader.BackgroundTransparency = 1
    playersHeader.Text = "Players in server"
    playersHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    playersHeader.TextSize = 14
    playersHeader.Font = Enum.Font.GothamSemibold
    playersHeader.Parent = scroll
    createDivider(scroll)

    local function refreshPlayerList()
        -- Clear existing player rows
        for _, child in ipairs(scroll:GetChildren()) do
            if child.Name == "PlayerRow" then child:Destroy() end
        end
        local players = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then table.insert(players, player) end
        end
        table.sort(players, function(a,b) return a.Name < b.Name end)
        for _, player in ipairs(players) do
            local playerRow = createRow(scroll, player.Name)
            playerRow.Name = "PlayerRow"
            local selectBtn = Instance.new("TextButton")
            selectBtn.Size = UDim2.new(0, 80, 0, 28)
            selectBtn.Position = UDim2.new(1, -80, 0.5, -14)
            selectBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
            selectBtn.Text = "Select"
            selectBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
            selectBtn.TextSize = 12
            selectBtn.Font = Enum.Font.GothamMedium
            selectBtn.BorderSizePixel = 0
            selectBtn.Parent = playerRow
            local selectCorner = Instance.new("UICorner")
            selectCorner.CornerRadius = UDim.new(0, 6)
            selectCorner.Parent = selectBtn
            selectBtn.MouseButton1Click:Connect(function()
                state.cashTransfer.selectedName = player.Name
                searchInput.Text = player.Name
                selectedLabel.Text = player.Name
                selectedLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
            end)
            createDivider(scroll)
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
    end

    refreshPlayerList()

    local execRow = createRow(scroll, "Execute transfer")
    local execBtn = Instance.new("TextButton")
    execBtn.Size = UDim2.new(0, 120, 0, 32)
    execBtn.Position = UDim2.new(1, -120, 0.5, -16)
    execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
    execBtn.Text = "Execute"
    execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    execBtn.TextSize = 12
    execBtn.Font = Enum.Font.GothamMedium
    execBtn.BorderSizePixel = 0
    execBtn.Parent = execRow
    local execCorner = Instance.new("UICorner")
    execCorner.CornerRadius = UDim.new(0, 8)
    execCorner.Parent = execBtn
    execBtn.MouseButton1Click:Connect(function()
        if state.cashTransfer.running then
            state.cashTransfer.running = false
            execBtn.Text = "Execute"
            execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
            return
        end
        local targetName = state.cashTransfer.selectedName
        if not targetName or targetName == "" then
            selectedLabel.Text = "No player selected"
            selectedLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
            return
        end
        local targetPlayer = nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name == targetName then targetPlayer = p; break end
        end
        if not targetPlayer then
            selectedLabel.Text = "Player no longer in server"
            selectedLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
            return
        end
        execBtn.Text = "Stop"
        execBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
        task.spawn(function()
            cashTransferLoop(targetPlayer)
            execBtn.Text = "Execute"
            execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
        end)
    end)
    createDivider(scroll)

    local infoRow = createRow(scroll, "Event status")
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(0, 320, 0, 24)
    infoLabel.Position = UDim2.new(1, -320, 0.5, -12)
    infoLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    infoLabel.Text = "DropCash: " .. (DROP_CASH_EVENT and "Found" or "Not found")
    infoLabel.TextColor3 = DROP_CASH_EVENT and Color3.fromRGB(100, 255, 150) or Color3.fromRGB(255, 150, 150)
    infoLabel.TextSize = 12
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextXAlignment = Enum.TextXAlignment.Center
    infoLabel.Parent = infoRow
    local infoCorner = Instance.new("UICorner")
    infoCorner.CornerRadius = UDim.new(0, 6)
    infoCorner.Parent = infoLabel
    createDivider(scroll)

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

-- ═══════════════════════════════
-- ANTI-ADMIN TAB
-- ═══════════════════════════════
local function buildAntiAdminTab()
    clearContent()
    titleText.Text = "Anti-Admin"

    createToggle(scroll, "Protection", state.protection, "AntiAdmin", function(val)
        antiAdmin.enabled = val
        antiAdmin.autoLeave = val
    end)
    createDivider(scroll)

    local refreshRow = createRow(scroll, "Tracker")
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 100, 0, 32)
    refreshBtn.Position = UDim2.new(1, -100, 0.5, -16)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
    refreshBtn.Text = "Refresh"
    refreshBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
    refreshBtn.TextSize = 12
    refreshBtn.Font = Enum.Font.GothamMedium
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Parent = refreshRow
    local refreshCorner = Instance.new("UICorner")
    refreshCorner.CornerRadius = UDim.new(0, 8)
    refreshCorner.Parent = refreshBtn
    refreshBtn.MouseButton1Click:Connect(function()
        refreshBtn.Text = "Fetching..."
        antiAdmin.lastGroupFetch = 0
        task.spawn(function()
            local success = pcall(updateAdminTracker)
            refreshBtn.Text = success and "Refresh" or "Failed"
            if not success then task.wait(2); refreshBtn.Text = "Refresh" end
            if state.currentTab == "Anti-Admin" then buildAntiAdminTab() end
        end)
    end)
    createDivider(scroll)

    if #antiAdmin.sameServerAdmins > 0 then
        local alertRow = createRow(scroll, "Alert")
        local alertLabel = Instance.new("TextLabel")
        alertLabel.Size = UDim2.new(0, 280, 0, 24)
        alertLabel.Position = UDim2.new(1, -280, 0.5, -12)
        alertLabel.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
        alertLabel.Text = #antiAdmin.sameServerAdmins .. " admin(s) in server"
        alertLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
        alertLabel.TextSize = 12
        alertLabel.Font = Enum.Font.Gotham
        alertLabel.TextXAlignment = Enum.TextXAlignment.Center
        alertLabel.Parent = alertRow
        local alertCorner = Instance.new("UICorner")
        alertCorner.CornerRadius = UDim.new(0, 6)
        alertCorner.Parent = alertLabel
        createDivider(scroll)
    end

    local watchlistHeader = Instance.new("TextLabel")
    watchlistHeader.Size = UDim2.new(1, 0, 0, 28)
    watchlistHeader.BackgroundTransparency = 1
    watchlistHeader.Text = "Watchlist (" .. #WATCHLIST .. ")"
    watchlistHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    watchlistHeader.TextSize = 14
    watchlistHeader.Font = Enum.Font.GothamSemibold
    watchlistHeader.Parent = scroll
    createDivider(scroll)

    for userId, entry in pairs(WATCHLIST) do
        local inServer = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == userId then inServer = true break end
        end
        local watchRow = createRow(scroll, entry.username)
        local statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(0, 120, 0, 24)
        statusLabel.Position = UDim2.new(1, -120, 0.5, -12)
        statusLabel.BackgroundColor3 = inServer and Color3.fromRGB(60, 30, 30) or Color3.fromRGB(36, 43, 49)
        statusLabel.Text = inServer and "In Server" or "Not Here"
        statusLabel.TextColor3 = inServer and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(129, 133, 137)
        statusLabel.TextSize = 12
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.TextXAlignment = Enum.TextXAlignment.Center
        statusLabel.Parent = watchRow
        local statusCorner = Instance.new("UICorner")
        statusCorner.CornerRadius = UDim.new(0, 6)
        statusCorner.Parent = watchRow
        createDivider(scroll)
    end

    local groupHeader = Instance.new("TextLabel")
    groupHeader.Size = UDim2.new(1, 0, 0, 28)
    groupHeader.BackgroundTransparency = 1
    groupHeader.Text = "Group Admins (" .. #antiAdmin.groupMembers .. ")"
    groupHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    groupHeader.TextSize = 14
    groupHeader.Font = Enum.Font.GothamSemibold
    groupHeader.Parent = scroll
    createDivider(scroll)

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
        local adminRow = createRow(scroll, admin.username)
        local statusText = "Offline"
        local statusColor = Color3.fromRGB(129, 133, 137)
        if tracked.sameServer then statusText = "In Server"; statusColor = Color3.fromRGB(255, 150, 150)
        elseif tracked.isInGame then statusText = "In Game"; statusColor = Color3.fromRGB(255, 200, 100)
        elseif tracked.isOnline then statusText = "Online"; statusColor = Color3.fromRGB(100, 255, 100) end
        local adminStatus = Instance.new("TextLabel")
        adminStatus.Size = UDim2.new(0, 120, 0, 24)
        adminStatus.Position = UDim2.new(1, -120, 0.5, -12)
        adminStatus.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
        adminStatus.Text = statusText
        adminStatus.TextColor3 = statusColor
        adminStatus.TextSize = 12
        adminStatus.Font = Enum.Font.Gotham
        adminStatus.TextXAlignment = Enum.TextXAlignment.Center
        adminStatus.Parent = adminRow
        local adminCorner = Instance.new("UICorner")
        adminCorner.CornerRadius = UDim.new(0, 6)
        adminStatus.Parent = adminRow
        createDivider(scroll)
    end

    if #sortedAdmins == 0 then
        local emptyRow = createRow(scroll, "No admins cached")
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(0, 320, 0, 24)
        emptyLabel.Position = UDim2.new(1, -320, 0.5, -12)
        emptyLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
        emptyLabel.Text = "Tap refresh to fetch"
        emptyLabel.TextColor3 = Color3.fromRGB(129, 133, 137)
        emptyLabel.TextSize = 12
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
        emptyLabel.Parent = emptyRow
        local emptyCorner = Instance.new("UICorner")
        emptyCorner.CornerRadius = UDim.new(0, 6)
        emptyCorner.Parent = emptyLabel
        createDivider(scroll)
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

local function switchTab(name)
    state.currentTab = name
    for tabName, btn in pairs(tabButtons) do
        local isActive = tabName == name
        btn.BackgroundTransparency = isActive and 0 or 1
        if isActive then
            btn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
            btn.Icon.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Label.TextColor3 = Color3.fromRGB(255, 255, 255)
            local glow = Instance.new("UIGradient")
            glow.Color = ColorSequence.new(Color3.fromRGB(58, 159, 232), Color3.fromRGB(0, 217, 196))
            glow.Parent = btn
        else
            btn.Icon.TextColor3 = Color3.fromRGB(155, 167, 173)
            btn.Label.TextColor3 = Color3.fromRGB(120, 133, 140)
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("UIGradient") then child:Destroy() end
            end
        end
    end
    if name == "Farms" then buildFarmsTab()
    elseif name == "Cash Transfer" then buildCashTransferTab()
    elseif name == "Anti-Admin" then buildAntiAdminTab()
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
miniCircle.BorderColor3 = Color3.fromRGB(0, 217, 196)
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
circleText.Font = Enum.Font.Code
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
    local shrink = TweenService:Create(miniCircle, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrink:Play()
    shrink.Completed:Wait()
    miniCircle.Visible = false
    mainFrame.Visible = true
    mainFrame.Size = UDim2.new(0, 0, 0, 0)
    mainFrame.Position = UDim2.new(0, 12, 0, 12)
    local expand = TweenService:Create(mainFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 780, 0, 500),
        Position = UDim2.new(0.5, -390, 0.5, -250)
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

print("Made by the OneAndOnlyXen.")erKnob
    local registerBtn = Instance.new("TextButton")
    registerBtn.Size = UDim2.new(1, 0, 1, 0)
    registerBtn.BackgroundTransparency = 1
    registerBtn.Text = ""
    registerBtn.Parent = registerRow
    registerBtn.MouseButton1Click:Connect(function()
        local val = not state.farms.Register
        state.farms.Register = val
        registerToggle.BackgroundColor3 = val and Color3.fromRGB(58, 159, 232) or Color3.fromRGB(48, 56, 64)
        registerKnob.Position = val and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
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
    createDivider(scroll)

    local statusRow = createRow(scroll, "Status")
    local counterLabel = Instance.new("TextLabel")
    counterLabel.Size = UDim2.new(0, 120, 0, 24)
    counterLabel.Position = UDim2.new(1, -120, 0.5, -12)
    counterLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    counterLabel.Text = "0 / " .. TP_CAP
    counterLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
    counterLabel.TextSize = 12
    counterLabel.Font = Enum.Font.Gotham
    counterLabel.TextXAlignment = Enum.TextXAlignment.Center
    counterLabel.Parent = statusRow
    local counterCorner = Instance.new("UICorner")
    counterCorner.CornerRadius = UDim.new(0, 6)
    counterCorner.Parent = counterLabel
    createDivider(scroll)

    local resetRow = createRow(scroll, "Actions")
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0, 80, 0, 28)
    resetBtn.Position = UDim2.new(1, -80, 0.5, -14)
    resetBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
    resetBtn.Text = "Reset"
    resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetBtn.TextSize = 12
    resetBtn.Font = Enum.Font.GothamMedium
    resetBtn.BorderSizePixel = 0
    resetBtn.Parent = resetRow
    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 6)
    resetCorner.Parent = resetBtn
    resetBtn.MouseButton1Click:Connect(function()
        task.spawn(function() forceResetCharacter() end)
    end)

    -- Update status
    local updateStatus = function()
        local used = teleportSystem.usedTeleports
        local current = selectedFarmKey or "None"
        counterLabel.Text = used .. " / " .. TP_CAP
        counterLabel.TextColor3 = used >= TP_CAP and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(0, 217, 196)
    end
    updateStatus()
    local statusUpdater = task.spawn(function()
        while state.running and state.currentTab == "Farms" do
            updateStatus()
            task.wait(0.5)
        end
    end)
    -- Store for cleanup
    if not scroll:FindFirstChild("StatusUpdater") then
        local conn = Instance.new("ObjectValue")
        conn.Name = "StatusUpdater"
        conn.Value = statusUpdater
        conn.Parent = scroll
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

    local statusRow = createRow(scroll, "Status")
    local counterLabel = Instance.new("TextLabel")
    counterLabel.Size = UDim2.new(0, 120, 0, 24)
    counterLabel.Position = UDim2.new(1, -120, 0.5, -12)
    counterLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    counterLabel.Text = "0 / " .. TP_CAP
    counterLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
    counterLabel.TextSize = 12
    counterLabel.Font = Enum.Font.Gotham
    counterLabel.TextXAlignment = Enum.TextXAlignment.Center
    counterLabel.Parent = statusRow
    local counterCorner = Instance.new("UICorner")
    counterCorner.CornerRadius = UDim.new(0, 6)
    counterCorner.Parent = counterLabel
    createDivider(scroll)

    local resetRow = createRow(scroll, "Actions")
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0, 80, 0, 28)
    resetBtn.Position = UDim2.new(1, -80, 0.5, -14)
    resetBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
    resetBtn.Text = "Reset"
    resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetBtn.TextSize = 12
    resetBtn.Font = Enum.Font.GothamMedium
    resetBtn.BorderSizePixel = 0
    resetBtn.Parent = resetRow
    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 6)
    resetCorner.Parent = resetBtn
    resetBtn.MouseButton1Click:Connect(function()
        task.spawn(function() forceResetCharacter() end)
    end)

    -- Update status
    local updateStatus = function()
        local used = teleportSystem.usedTeleports
        local current = selectedFarmKey or "None"
        counterLabel.Text = used .. " / " .. TP_CAP
        counterLabel.TextColor3 = used >= TP_CAP and Color3.fromRGB(255, 200, 100) or Color3.fromRGB(0, 217, 196)
    end
    updateStatus()
    local statusUpdater = task.spawn(function()
        while state.running and state.currentTab == "Farms" do
            updateStatus()
            task.wait(0.5)
        end
    end)
    -- Store for cleanup
    if not scroll:FindFirstChild("StatusUpdater") then
        local conn = Instance.new("ObjectValue")
        conn.Name = "StatusUpdater"
        conn.Value = statusUpdater
        conn.Parent = scroll
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end



-- ═══════════════════════════════
-- CASH TRANSFER TAB
-- ═══════════════════════════════
local function buildCashTransferTab()
    clearContent()
    titleText.Text = "Cash Transfer"

    local searchRow = createRow(scroll, "Target player")
    local searchInput = Instance.new("TextBox")
    searchInput.Size = UDim2.new(0, 320, 0, 32)
    searchInput.Position = UDim2.new(1, -320, 0.5, -16)
    searchInput.BackgroundColor3 = Color3.fromRGB(41, 47, 53)
    searchInput.Text = state.cashTransfer.selectedName or ""
    searchInput.PlaceholderText = "Enter player name..."
    searchInput.TextColor3 = Color3.fromRGB(229, 235, 237)
    searchInput.PlaceholderColor3 = Color3.fromRGB(160, 171, 179)
    searchInput.TextSize = 12
    searchInput.Font = Enum.Font.Gotham
    searchInput.BorderSizePixel = 0
    searchInput.Parent = searchRow
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 8)
    searchCorner.Parent = searchInput
    createDivider(scroll)

    local findRow = createRow(scroll, "Find player")
    local findBtn = Instance.new("TextButton")
    findBtn.Size = UDim2.new(0, 100, 0, 32)
    findBtn.Position = UDim2.new(1, -100, 0.5, -16)
    findBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
    findBtn.Text = "Find"
    findBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
    findBtn.TextSize = 12
    findBtn.Font = Enum.Font.GothamMedium
    findBtn.BorderSizePixel = 0
    findBtn.Parent = findRow
    local findCorner = Instance.new("UICorner")
    findCorner.CornerRadius = UDim.new(0, 8)
    findCorner.Parent = findBtn
    createDivider(scroll)

    local selectedRow = createRow(scroll, "Selected")
    local selectedLabel = Instance.new("TextLabel")
    selectedLabel.Size = UDim2.new(0, 320, 0, 24)
    selectedLabel.Position = UDim2.new(1, -320, 0.5, -12)
    selectedLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    selectedLabel.Text = state.cashTransfer.selectedName ~= "" and state.cashTransfer.selectedName or "None"
    selectedLabel.TextColor3 = state.cashTransfer.selectedName ~= "" and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(129, 133, 137)
    selectedLabel.TextSize = 12
    selectedLabel.Font = Enum.Font.Gotham
    selectedLabel.TextXAlignment = Enum.TextXAlignment.Center
    selectedLabel.Parent = selectedRow
    local selectedCorner = Instance.new("UICorner")
    selectedCorner.CornerRadius = UDim.new(0, 6)
    selectedCorner.Parent = selectedLabel
    createDivider(scroll)

    local playersHeader = Instance.new("TextLabel")
playersHeader.Size = UDim2.new(1, 0, 0, 28)
playersHeader.BackgroundTransparency = 1
playersHeader.Text = "Players in server"
playersHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
playersHeader.TextSize = 14
playersHeader.Font = Enum.Font.GothamSemibold
playersHeader.Parent = scroll
createDivider(scroll)

local function refreshPlayerList()
    -- Clear existing player rows
    for _, child in ipairs(scroll:GetChildren()) do
        if child.Name == "PlayerRow" then child:Destroy() end
    end
    local players = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then table.insert(players, player) end
    end
    table.sort(players, function(a,b) return a.Name < b.Name end)
    for _, player in ipairs(players) do
        local playerRow = createRow(scroll, player.Name)
        playerRow.Name = "PlayerRow"
        local selectBtn = Instance.new("TextButton")
        selectBtn.Size = UDim2.new(0, 80, 0, 28)
        selectBtn.Position = UDim2.new(1, -80, 0.5, -14)
        selectBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
        selectBtn.Text = "Select"
        selectBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
        selectBtn.TextSize = 12
        selectBtn.Font = Enum.Font.GothamMedium
        selectBtn.BorderSizePixel = 0
        selectBtn.Parent = playerRow
        local selectCorner = Instance.new("UICorner")
        selectCorner.CornerRadius = UDim.new(0, 6)
        selectCorner.Parent = selectBtn
        selectBtn.MouseButton1Click:Connect(function()
            state.cashTransfer.selectedName = player.Name
            searchInput.Text = player.Name
            selectedLabel.Text = player.Name
            selectedLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
        end)
        createDivider(scroll)
    end
    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

refreshPlayerList()

local execRow = createRow(scroll, "Execute transfer")
local execBtn = Instance.new("TextButton")
execBtn.Size = UDim2.new(0, 120, 0, 32)
execBtn.Position = UDim2.new(1, -120, 0.5, -16)
execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
execBtn.Text = "Execute"
execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
execBtn.TextSize = 12
execBtn.Font = Enum.Font.GothamMedium
execBtn.BorderSizePixel = 0
execBtn.Parent = execRow
local execCorner = Instance.new("UICorner")
execCorner.CornerRadius = UDim.new(0, 8)
execCorner.Parent = execBtn
execBtn.MouseButton1Click:Connect(function()
    if state.cashTransfer.running then
        state.cashTransfer.running = false
        execBtn.Text = "Execute"
        execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
        return
    end
    local targetName = state.cashTransfer.selectedName
    if not targetName or targetName == "" then
        selectedLabel.Text = "No player selected"
        selectedLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
        return
    end
    local targetPlayer = nil
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Name == targetName then targetPlayer = p; break end
    end
    if not targetPlayer then
        selectedLabel.Text = "Player no longer in server"
        selectedLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
        return
    end
    execBtn.Text = "Stop"
    execBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
    task.spawn(function()
        cashTransferLoop(targetPlayer)
        execBtn.Text = "Execute"
        execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
    end)
end)
createDivider(scroll)

local infoRow = createRow(scroll, "Event status")
local infoLabel = Instance.new("TextLabel")
infoLabel.Size = UDim2.new(0, 320, 0, 24)
infoLabel.Position = UDim2.new(1, -320, 0.5, -12)
infoLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
infoLabel.Text = "DropCash: " .. (DROP_CASH_EVENT and "Found" or "Not found")
infoLabel.TextColor3 = DROP_CASH_EVENT and Color3.fromRGB(100, 255, 150) or Color3.fromRGB(255, 150, 150)
infoLabel.TextSize = 12
infoLabel.Font = Enum.Font.Gotham
infoLabel.TextXAlignment = Enum.TextXAlignment.Center
infoLabel.Parent = infoRow
local infoCorner = Instance.new("UICorner")
infoCorner.CornerRadius = UDim.new(0, 6)
infoCorner.Parent = infoLabel
createDivider(scroll)

scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

-- ═══════════════════════════════
-- ANTI-ADMIN TAB
-- ═══════════════════════════════
local function buildAntiAdminTab()
    clearContent()
    titleText.Text = "Anti-Admin"

    createToggle(scroll, "Protection", state.protection, "AntiAdmin", function(val)
        antiAdmin.enabled = val
        antiAdmin.autoLeave = val
    end)
    createDivider(scroll)

    local refreshRow = createRow(scroll, "Tracker")
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 100, 0, 32)
    refreshBtn.Position = UDim2.new(1, -100, 0.5, -16)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
    refreshBtn.Text = "Refresh"
    refreshBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
    refreshBtn.TextSize = 12
    refreshBtn.Font = Enum.Font.GothamMedium
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Parent = refreshRow
    local refreshCorner = Instance.new("UICorner")
    refreshCorner.CornerRadius = UDim.new(0, 8)
    refreshCorner.Parent = refreshBtn
    refreshBtn.MouseButton1Click:Connect(function()
        refreshBtn.Text = "Fetching..."
        antiAdmin.lastGroupFetch = 0
        task.spawn(function()
            local success = pcall(updateAdminTracker)
            refreshBtn.Text = success and "Refresh" or "Failed"
            if not success then task.wait(2); refreshBtn.Text = "Refresh" end
            if state.currentTab == "Anti-Admin" then buildAntiAdminTab() end
        end)
    end)
    createDivider(scroll)

    if #antiAdmin.sameServerAdmins > 0 then
        local alertRow = createRow(scroll, "Alert")
        local alertLabel = Instance.new("TextLabel")
        alertLabel.Size = UDim2.new(0, 280, 0, 24)
        alertLabel.Position = UDim2.new(1, -280, 0.5, -12)
        alertLabel.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
        alertLabel.Text = #antiAdmin.sameServerAdmins .. " admin(s) in server"
        alertLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
        alertLabel.TextSize = 12
        alertLabel.Font = Enum.Font.Gotham
        alertLabel.TextXAlignment = Enum.TextXAlignment.Center
        alertLabel.Parent = alertRow
        local alertCorner = Instance.new("UICorner")
        alertCorner.CornerRadius = UDim.new(0, 6)
        alertCorner.Parent = alertLabel
        createDivider(scroll)
    end

    local watchlistHeader = Instance.new("TextLabel")
    watchlistHeader.Size = UDim2.new(1, 0, 0, 28)
    watchlistHeader.BackgroundTransparency = 1
    watchlistHeader.Text = "Watchlist (" .. #WATCHLIST .. ")"
    watchlistHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    watchlistHeader.TextSize = 14
    watchlistHeader.Font = Enum.Font.GothamSemibold
    watchlistHeader.Parent = scroll
    createDivider(scroll)

    for userId, entry in pairs(WATCHLIST) do
        local inServer = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == userId then inServer = true break end
        end
        local watchRow = createRow(scroll, entry.username)
        local statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(0, 120, 0, 24)
        statusLabel.Position = UDim2.new(1, -120, 0.5, -12)
        statusLabel.BackgroundColor3 = inServer and Color3.fromRGB(60, 30, 30) or Color3.fromRGB(36, 43, 49)
        statusLabel.Text = inServer and "In Server" or "Not Here"
        statusLabel.TextColor3 = inServer and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(129, 133, 137)
        statusLabel.TextSize = 12
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.TextXAlignment = Enum.TextXAlignment.Center
        statusLabel.Parent = watchRow
        local statusCorner = Instance.new("UICorner")
        statusCorner.CornerRadius = UDim.new(0, 6)
        statusCorner.Parent = watchRow
        createDivider(scroll)
    end

    local groupHeader = Instance.new("TextLabel")
    groupHeader.Size = UDim2.new(1, 0, 0, 28)
    groupHeader.BackgroundTransparency = 1
    groupHeader.Text = "Group Admins (" .. #antiAdmin.groupMembers .. ")"
    groupHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    groupHeader.TextSize = 14
    groupHeader.Font = Enum.Font.GothamSemibold
    groupHeader.Parent = scroll
    createDivider(scroll)

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
        local adminRow = createRow(scroll, admin.username)
        local statusText = "Offline"
        local statusColor = Color3.fromRGB(129, 133, 137)
        if tracked.sameServer then statusText = "In Server"; statusColor = Color3.fromRGB(255, 150, 150)
        elseif tracked.isInGame then statusText = "In Game"; statusColor = Color3.fromRGB(255, 200, 100)
        elseif tracked.isOnline then statusText = "Online"; statusColor = Color3.fromRGB(100, 255, 100) end
        local adminStatus = Instance.new("TextLabel")
        adminStatus.Size = UDim2.new(0, 120, 0, 24)
        adminStatus.Position = UDim2.new(1, -120, 0.5, -12)
        adminStatus.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
        adminStatus.Text = statusText
        adminStatus.TextColor3 = statusColor
        adminStatus.TextSize = 12
        adminStatus.Font = Enum.Font.Gotham
        adminStatus.TextXAlignment = Enum.TextXAlignment.Center
        adminStatus.Parent = adminRow
        local adminCorner = Instance.new("UICorner")
        adminCorner.CornerRadius = UDim.new(0, 6)
        adminStatus.Parent = adminRow
        createDivider(scroll)
    end

    if #sortedAdmins == 0 then
        local emptyRow = createRow(scroll, "No admins cached")
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(0, 320, 0, 24)
        emptyLabel.Position = UDim2.new(1, -320, 0.5, -12)
        emptyLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
        emptyLabel.Text = "Tap refresh to fetch"
        emptyLabel.TextColor3 = Color3.fromRGB(129, 133, 137)
        emptyLabel.TextSize = 12
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
        emptyLabel.Parent = emptyRow
        local emptyCorner = Instance.new("UICorner")
        emptyCorner.CornerRadius = UDim.new(0, 6)
        emptyCorner.Parent = emptyLabel
        createDivider(scroll)
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

local function switchTab(name)
    state.currentTab = name
    for tabName, btn in pairs(tabButtons) do
        local isActive = tabName == name
        btn.BackgroundTransparency = isActive and 0 or 1
        if isActive then
            btn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
            btn.Icon.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Label.TextColor3 = Color3.fromRGB(255, 255, 255)
            local glow = Instance.new("UIGradient")
            glow.Color = ColorSequence.new(Color3.fromRGB(58, 159, 232), Color3.fromRGB(0, 217, 196))
            glow.Parent = btn
        else
            btn.Icon.TextColor3 = Color3.fromRGB(155, 167, 173)
            btn.Label.TextColor3 = Color3.fromRGB(120, 133, 140)
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("UIGradient") then child:Destroy() end
            end
        end
    end
    if name == "Farms" then buildFarmsTab()
    elseif name == "Cash Transfer" then buildCashTransferTab()
    elseif name == "Anti-Admin" then buildAntiAdminTab()
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
miniCircle.BorderColor3 = Color3.fromRGB(0, 217, 196)
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
circleText.Font = Enum.Font.Code
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
    local shrink = TweenService:Create(miniCircle, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrink:Play()
    shrink.Completed:Wait()
    miniCircle.Visible = false
    mainFrame.Visible = true
    mainFrame.Size = UDim2.new(0, 0, 0, 0)
    mainFrame.Position = UDim2.new(0, 12, 0, 12)
    local expand = TweenService:Create(mainFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 780, 0, 500),
        Position = UDim2.new(0.5, -390, 0.5, -250)
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

print("Made by the OneAndOnlyXen.")dTransparency = 1
    playersHeader.Text = "Players in server"
    playersHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    playersHeader.TextSize = 14
    playersHeader.Font = Enum.Font.GothamSemibold
    playersHeader.Parent = scroll
    createDivider(scroll)

    local function refreshPlayerList()
        -- Clear existing player rows
        for _, child in ipairs(scroll:GetChildren()) do
            if child.Name == "PlayerRow" then child:Destroy() end
        end
        local players = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then table.insert(players, player) end
        end
        table.sort(players, function(a,b) return a.Name < b.Name end)
        for _, player in ipairs(players) do
            local playerRow = createRow(scroll, player.Name)
            playerRow.Name = "PlayerRow"
            local selectBtn = Instance.new("TextButton")
            selectBtn.Size = UDim2.new(0, 80, 0, 28)
            selectBtn.Position = UDim2.new(1, -80, 0.5, -14)
            selectBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
            selectBtn.Text = "Select"
            selectBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
            selectBtn.TextSize = 12
            selectBtn.Font = Enum.Font.GothamMedium
            selectBtn.BorderSizePixel = 0
            selectBtn.Parent = playerRow
            local selectCorner = Instance.new("UICorner")
            selectCorner.CornerRadius = UDim.new(0, 6)
            selectCorner.Parent = selectBtn
            selectBtn.MouseButton1Click:Connect(function()
                state.cashTransfer.selectedName = player.Name
                searchInput.Text = player.Name
                selectedLabel.Text = player.Name
                selectedLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
            end)
            createDivider(scroll)
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
    end

    refreshPlayerList()

    local execRow = createRow(scroll, "Execute transfer")
    local execBtn = Instance.new("TextButton")
    execBtn.Size = UDim2.new(0, 120, 0, 32)
    execBtn.Position = UDim2.new(1, -120, 0.5, -16)
    execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
    execBtn.Text = "Execute"
    execBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    execBtn.TextSize = 12
    execBtn.Font = Enum.Font.GothamMedium
    execBtn.BorderSizePixel = 0
    execBtn.Parent = execRow
    local execCorner = Instance.new("UICorner")
    execCorner.CornerRadius = UDim.new(0, 8)
    execCorner.Parent = execBtn
    execBtn.MouseButton1Click:Connect(function()
        if state.cashTransfer.running then
            state.cashTransfer.running = false
            execBtn.Text = "Execute"
            execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
            return
        end
        local targetName = state.cashTransfer.selectedName
        if not targetName or targetName == "" then
            selectedLabel.Text = "No player selected"
            selectedLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
            return
        end
        local targetPlayer = nil
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name == targetName then targetPlayer = p; break end
        end
        if not targetPlayer then
            selectedLabel.Text = "Player no longer in server"
            selectedLabel.TextColor3 = Color3.fromRGB(255, 150, 100)
            return
        end
        execBtn.Text = "Stop"
        execBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
        task.spawn(function()
            cashTransferLoop(targetPlayer)
            execBtn.Text = "Execute"
            execBtn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
        end)
    end)
    createDivider(scroll)

    local infoRow = createRow(scroll, "Event status")
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(0, 320, 0, 24)
    infoLabel.Position = UDim2.new(1, -320, 0.5, -12)
    infoLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
    infoLabel.Text = "DropCash: " .. (DROP_CASH_EVENT and "Found" or "Not found")
    infoLabel.TextColor3 = DROP_CASH_EVENT and Color3.fromRGB(100, 255, 150) or Color3.fromRGB(255, 150, 150)
    infoLabel.TextSize = 12
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextXAlignment = Enum.TextXAlignment.Center
    infoLabel.Parent = infoRow
    local infoCorner = Instance.new("UICorner")
    infoCorner.CornerRadius = UDim.new(0, 6)
    infoCorner.Parent = infoLabel
    createDivider(scroll)

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

-- ═══════════════════════════════
-- ANTI-ADMIN TAB
-- ═══════════════════════════════
local function buildAntiAdminTab()
    clearContent()
    titleText.Text = "Anti-Admin"

    createToggle(scroll, "Protection", state.protection, "AntiAdmin", function(val)
        antiAdmin.enabled = val
        antiAdmin.autoLeave = val
    end)
    createDivider(scroll)

    local refreshRow = createRow(scroll, "Tracker")
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0, 100, 0, 32)
    refreshBtn.Position = UDim2.new(1, -100, 0.5, -16)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 64)
    refreshBtn.Text = "Refresh"
    refreshBtn.TextColor3 = Color3.fromRGB(229, 235, 237)
    refreshBtn.TextSize = 12
    refreshBtn.Font = Enum.Font.GothamMedium
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Parent = refreshRow
    local refreshCorner = Instance.new("UICorner")
    refreshCorner.CornerRadius = UDim.new(0, 8)
    refreshCorner.Parent = refreshBtn
    refreshBtn.MouseButton1Click:Connect(function()
        refreshBtn.Text = "Fetching..."
        antiAdmin.lastGroupFetch = 0
        task.spawn(function()
            local success = pcall(updateAdminTracker)
            refreshBtn.Text = success and "Refresh" or "Failed"
            if not success then task.wait(2); refreshBtn.Text = "Refresh" end
            if state.currentTab == "Anti-Admin" then buildAntiAdminTab() end
        end)
    end)
    createDivider(scroll)

    if #antiAdmin.sameServerAdmins > 0 then
        local alertRow = createRow(scroll, "Alert")
        local alertLabel = Instance.new("TextLabel")
        alertLabel.Size = UDim2.new(0, 280, 0, 24)
        alertLabel.Position = UDim2.new(1, -280, 0.5, -12)
        alertLabel.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
        alertLabel.Text = #antiAdmin.sameServerAdmins .. " admin(s) in server"
        alertLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
        alertLabel.TextSize = 12
        alertLabel.Font = Enum.Font.Gotham
        alertLabel.TextXAlignment = Enum.TextXAlignment.Center
        alertLabel.Parent = alertRow
        local alertCorner = Instance.new("UICorner")
        alertCorner.CornerRadius = UDim.new(0, 6)
        alertCorner.Parent = alertLabel
        createDivider(scroll)
    end

    local watchlistHeader = Instance.new("TextLabel")
    watchlistHeader.Size = UDim2.new(1, 0, 0, 28)
    watchlistHeader.BackgroundTransparency = 1
    watchlistHeader.Text = "Watchlist (" .. #WATCHLIST .. ")"
    watchlistHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    watchlistHeader.TextSize = 14
    watchlistHeader.Font = Enum.Font.GothamSemibold
    watchlistHeader.Parent = scroll
    createDivider(scroll)

    for userId, entry in pairs(WATCHLIST) do
        local inServer = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == userId then inServer = true break end
        end
        local watchRow = createRow(scroll, entry.username)
        local statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(0, 120, 0, 24)
        statusLabel.Position = UDim2.new(1, -120, 0.5, -12)
        statusLabel.BackgroundColor3 = inServer and Color3.fromRGB(60, 30, 30) or Color3.fromRGB(36, 43, 49)
        statusLabel.Text = inServer and "In Server" or "Not Here"
        statusLabel.TextColor3 = inServer and Color3.fromRGB(255, 150, 150) or Color3.fromRGB(129, 133, 137)
        statusLabel.TextSize = 12
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.TextXAlignment = Enum.TextXAlignment.Center
        statusLabel.Parent = watchRow
        local statusCorner = Instance.new("UICorner")
        statusCorner.CornerRadius = UDim.new(0, 6)
        statusCorner.Parent = statusLabel
        createDivider(scroll)
    end

    local groupHeader = Instance.new("TextLabel")
    groupHeader.Size = UDim2.new(1, 0, 0, 28)
    groupHeader.BackgroundTransparency = 1
    groupHeader.Text = "Group Admins (" .. #antiAdmin.groupMembers .. ")"
    groupHeader.TextColor3 = Color3.fromRGB(241, 245, 246)
    groupHeader.TextSize = 14
    groupHeader.Font = Enum.Font.GothamSemibold
    groupHeader.Parent = scroll
    createDivider(scroll)

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
        local adminRow = createRow(scroll, admin.username)
        local statusText = "Offline"
        local statusColor = Color3.fromRGB(129, 133, 137)
        if tracked.sameServer then statusText = "In Server"; statusColor = Color3.fromRGB(255, 150, 150)
        elseif tracked.isInGame then statusText = "In Game"; statusColor = Color3.fromRGB(255, 200, 100)
        elseif tracked.isOnline then statusText = "Online"; statusColor = Color3.fromRGB(100, 255, 100) end
        local adminStatus = Instance.new("TextLabel")
        adminStatus.Size = UDim2.new(0, 120, 0, 24)
        adminStatus.Position = UDim2.new(1, -120, 0.5, -12)
        adminStatus.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
        adminStatus.Text = statusText
        adminStatus.TextColor3 = statusColor
        adminStatus.TextSize = 12
        adminStatus.Font = Enum.Font.Gotham
        adminStatus.TextXAlignment = Enum.TextXAlignment.Center
        adminStatus.Parent = adminRow
        local adminCorner = Instance.new("UICorner")
        adminCorner.CornerRadius = UDim.new(0, 6)
        adminStatus.Parent = adminRow
        createDivider(scroll)
    end

    if #sortedAdmins == 0 then
        local emptyRow = createRow(scroll, "No admins cached")
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(0, 280, 0, 24)
        emptyLabel.Position = UDim2.new(1, -280, 0.5, -12)
        emptyLabel.BackgroundColor3 = Color3.fromRGB(36, 43, 49)
        emptyLabel.Text = "Tap refresh to fetch"
        emptyLabel.TextColor3 = Color3.fromRGB(129, 133, 137)
        emptyLabel.TextSize = 12
        emptyLabel.Font = Enum.Font.Gotham
        emptyLabel.TextXAlignment = Enum.TextXAlignment.Center
        emptyLabel.Parent = emptyRow
        local emptyCorner = Instance.new("UICorner")
        emptyCorner.CornerRadius = UDim.new(0, 6)
        emptyCorner.Parent = emptyLabel
        createDivider(scroll)
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, contentList.AbsoluteContentSize.Y)
end

local function switchTab(name)
    state.currentTab = name
    for tabName, btn in pairs(tabButtons) do
        local isActive = tabName == name
        btn.BackgroundTransparency = isActive and 0 or 1
        if isActive then
            btn.BackgroundColor3 = Color3.fromRGB(58, 159, 232)
            btn.Icon.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Label.TextColor3 = Color3.fromRGB(255, 255, 255)
            local glow = Instance.new("UIGradient")
            glow.Color = ColorSequence.new(Color3.fromRGB(58, 159, 232), Color3.fromRGB(0, 217, 196))
            glow.Parent = btn
        else
            btn.Icon.TextColor3 = Color3.fromRGB(155, 167, 173)
            btn.Label.TextColor3 = Color3.fromRGB(120, 133, 140)
            for _, child in ipairs(btn:GetChildren()) do
                if child:IsA("UIGradient") then child:Destroy() end
            end
        end
    end
    if name == "Farms" then buildFarmsTab()
    elseif name == "Cash Transfer" then buildCashTransferTab()
    elseif name == "Anti-Admin" then buildAntiAdminTab()
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
miniCircle.BorderColor3 = Color3.fromRGB(0, 217, 196)
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
circleText.Font = Enum.Font.Code
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
    local shrink = TweenService:Create(miniCircle, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0, 0, 0, 0)})
    shrink:Play()
    shrink.Completed:Wait()
    miniCircle.Visible = false
    mainFrame.Visible = true
    mainFrame.Size = UDim2.new(0, 0, 0, 0)
    mainFrame.Position = UDim2.new(0, 12, 0, 12)
    local expand = TweenService:Create(mainFrame, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 780, 0, 500),
        Position = UDim2.new(0.5, -390, 0.5, -250)
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
