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
mainFrame.BackgroundColor3 = Color3.fromRGB(7, 10, 13)
mainFrame.BorderSizePixel = 1
mainFrame.BorderColor3 = Color3.fromRGB(24, 36, 44)
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
mainFrame.Active = true
mainFrame.Draggable = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = mainFrame

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 48)
titleBar.BackgroundColor3 = Color3.fromRGB(10, 15, 19)
titleBar.BorderSizePixel = 0
titleBar.Parent = mainFrame

local headerDivider = Instance.new("Frame")
headerDivider.Size = UDim2.new(1, -28, 0, 1)
headerDivider.Position = UDim2.new(0, 14, 1, -1)
headerDivider.BackgroundColor3 = Color3.fromRGB(22, 33, 40)
headerDivider.BorderSizePixel = 0
headerDivider.Parent = titleBar

local titleText = Instance.new("TextLabel")
titleText.Size = UDim2.new(0.6, 0, 1, 0)
titleText.Position = UDim2.new(0, 14, 0, 0)
titleText.BackgroundTransparency = 1
titleText.Text = "NYRA  /  CONTROL"
titleText.TextColor3 = Color3.fromRGB(232, 241, 244)
titleText.TextSize = 16
titleText.Font = Enum.Font.GothamSemibold
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.TextYAlignment = Enum.TextYAlignment.Center
titleText.Parent = titleBar

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(0.4, 0, 1, 0)
subtitle.Position = UDim2.new(0.34, 0, 0, 0)
subtitle.BackgroundTransparency = 1
subtitle.Text = "CONTROL DASHBOARD"
subtitle.TextColor3 = Color3.fromRGB(101, 116, 125)
subtitle.TextSize = 10
subtitle.Font = Enum.Font.Code
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.TextYAlignment = Enum.TextYAlignment.Center
subtitle.Parent = titleBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 32, 0, 32)
minimizeBtn.Position = UDim2.new(1, -72, 0, 13)
minimizeBtn.BackgroundColor3 = Color3.fromRGB(23, 26, 30)
minimizeBtn.Text = "─"
minimizeBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
minimizeBtn.TextSize = 20
minimizeBtn.Font = Enum.Font.Code
minimizeBtn.BorderSizePixel = 0
minimizeBtn.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 32, 0, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 13)
closeBtn.BackgroundColor3 = Color3.fromRGB(23, 26, 30)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(0, 217, 196)
closeBtn.TextSize = 16
closeBtn.Font = Enum.Font.Code
closeBtn.BorderSizePixel = 0
closeBtn.Parent = titleBar

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(0, 180, 1, -48)
tabBar.Position = UDim2.new(0, 0, 0, 48)
tabBar.BackgroundColor3 = Color3.fromRGB(8, 12, 16)
tabBar.BorderSizePixel = 1
tabBar.BorderColor3 = Color3.fromRGB(24, 36, 44)
tabBar.Parent = mainFrame

local tabs = {"Farms", "Cash Transfer", "Config", "Settings"}

local sidebarBrand = Instance.new("TextLabel")
sidebarBrand.Size = UDim2.new(1, -20, 0, 48)
sidebarBrand.Position = UDim2.new(0, 10, 0, 10)
sidebarBrand.BackgroundTransparency = 1
sidebarBrand.Text = "N  /  NYRA\nCONTROL SYSTEM"
sidebarBrand.TextColor3 = Color3.fromRGB(232, 241, 244)
sidebarBrand.TextSize = 12
sidebarBrand.Font = Enum.Font.GothamSemibold
sidebarBrand.TextXAlignment = Enum.TextXAlignment.Left
sidebarBrand.TextYAlignment = Enum.TextYAlignment.Center
sidebarBrand.Parent = tabBar

local sidebarAccent = Instance.new("Frame")
sidebarAccent.Size = UDim2.new(0, 3, 0, 30)
sidebarAccent.Position = UDim2.new(0, 0, 0, 25)
sidebarAccent.BackgroundColor3 = Color3.fromRGB(0, 217, 196)
sidebarAccent.BorderSizePixel = 0
sidebarAccent.Parent = tabBar
local tabButtons = {}

for i, name in ipairs(tabs) do
    local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -20, 0, 34)
    btn.Position = UDim2.new(0, 10, 0, 78 + (i-1) * 38)
    btn.BackgroundColor3 = i == 1 and Color3.fromRGB(13, 37, 43) or Color3.fromRGB(8, 12, 16)
    btn.Text = (i == 1 and "▌  " or "   ") .. name
    btn.TextColor3 = i == 1 and Color3.fromRGB(232, 241, 244) or Color3.fromRGB(101, 116, 125)
    btn.TextSize = 11
        btn.Font = Enum.Font.GothamMedium
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.BorderSizePixel = 0
    btn.Parent = tabBar
    local tabCorner = Instance.new("UICorner")
    tabCorner.CornerRadius = UDim.new(0, 7)
    tabCorner.Parent = btn
    tabButtons[name] = btn
end

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -192, 1, -60)
contentFrame.Position = UDim2.new(0, 192, 0, 54)
contentFrame.BackgroundColor3 = Color3.fromRGB(10, 15, 19)
contentFrame.BorderSizePixel = 0
contentFrame.Parent = mainFrame

local ambient = Instance.new("Frame")
ambient.Size = UDim2.new(0, 240, 0, 240)
ambient.Position = UDim2.new(1, -250, 0, 54)
ambient.BackgroundColor3 = Color3.fromRGB(7, 26, 36)
ambient.BackgroundTransparency = 0.88
ambient.BorderSizePixel = 0
ambient.Parent = contentFrame

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -24)
scroll.Position = UDim2.new(0, 12, 0, 12)
scroll.BackgroundColor3 = Color3.fromRGB(10, 15, 19)
scroll.BackgroundTransparency = 0.12
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.ScrollBarImageColor3 = Color3.fromRGB(38, 52, 59)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = contentFrame

local contentList = Instance.new("UIListLayout")
contentList.Parent = scroll
contentList.SortOrder = Enum.SortOrder.LayoutOrder
contentList.Padding = UDim.new(0, 8)

local function createToggle(parent, name, stateRef, key, callback, order)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, 40)
        frame.BackgroundColor3 = Color3.fromRGB(13, 19, 24)
    frame.BorderSizePixel = 1
    frame.BorderColor3 = Color3.fromRGB(24, 36, 44)
    frame.LayoutOrder = order or 1
    frame.Parent = parent
    local corner2 = Instance.new("UICorner")
    corner2.CornerRadius = UDim.new(0, 9)
    corner2.Parent = frame
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.58, 0, 1, 0)
    label.Position = UDim2.new(0, 11, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = name
    label.TextColor3 = Color3.fromRGB(242, 243, 245)
        label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Parent = frame
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 34, 0, 18)
    btn.Position = UDim2.new(0.78, 0, 0.5, -9)
        btn.BackgroundColor3 = stateRef[key] and Color3.fromRGB(8, 124, 120) or Color3.fromRGB(32, 42, 48)
    btn.Text = stateRef[key] and "ON" or "OFF"
    btn.TextColor3 = Color3.fromRGB(223, 255, 250)
    btn.TextSize = 10
    btn.Font = Enum.Font.Code
    btn.BorderSizePixel = 0
    btn.Parent = frame
        local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 12)
    btnCorner.Parent = btn
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = stateRef[key] and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = stateRef[key] and Color3.fromRGB(223, 255, 250) or Color3.fromRGB(102, 115, 122)
    knob.BorderSizePixel = 0
    knob.Parent = btn
    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(0, 16, 0, 16)
    status.Position = UDim2.new(0.92, 0, 0.5, -8)
    status.BackgroundTransparency = 1
    status.Text = "●"
    status.TextColor3 = stateRef[key] and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(82, 97, 104)
    status.TextSize = 16
    status.Font = Enum.Font.SourceSans
    status.Parent = frame
    btn.MouseButton1Click:Connect(function()
        stateRef[key] = not stateRef[key]
        local val = stateRef[key]
                btn.Text = val and "ON" or "OFF"
        btn.BackgroundColor3 = val and Color3.fromRGB(8, 124, 120) or Color3.fromRGB(32, 42, 48)
        btn.TextColor3 = Color3.fromRGB(223, 255, 250)
        knob.Position = val and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        knob.BackgroundColor3 = val and Color3.fromRGB(223, 255, 250) or Color3.fromRGB(102, 115, 122)
        status.TextColor3 = val and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(82, 97, 104)
        if callback then callback(val) end
    end)
    return frame
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
    local order = 1
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 28)
    header.BackgroundTransparency = 1
    header.Text = "═ FARMS (Cap: " .. TP_CAP .. " TPs) ═"
    header.TextColor3 = Color3.fromRGB(232, 241, 244)
    header.TextSize = 12
    header.Font = Enum.Font.Code
    header.LayoutOrder = 0
    header.Parent = scroll
    createToggle(scroll, "⚡ SUPER FARM (Reg → Cash → Dump)", state.farms, "SuperFarm", function(val)
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
    end, order)
    order = order + 1
    local farmHeader = Instance.new("TextLabel")
    farmHeader.Size = UDim2.new(1, 0, 0, 24)
    farmHeader.BackgroundTransparency = 1
    farmHeader.Text = "─ INDIVIDUAL FARMS ─"
    farmHeader.TextColor3 = Color3.fromRGB(150, 150, 170)
    farmHeader.TextSize = 11
    farmHeader.Font = Enum.Font.Code
    farmHeader.LayoutOrder = order
    farmHeader.Parent = scroll
    order = order + 1
    local farmNames = {"Dumpster Farm", "Floor Cash", "Register Farm"}
    local farmKeys = {"Dumpster", "Cash", "Register"}
    for i, name in ipairs(farmNames) do
        local key = farmKeys[i]
        createToggle(scroll, name, state.farms, key, function(val)
            if val then
                for _, k in ipairs({"Dumpster", "Cash", "Register", "SuperFarm"}) do
                    if k ~= key then state.farms[k] = false end
                end
                state.farms[key] = true
                selectedFarmKey = key
                resetTeleportSystem()
                startFarmModule(key)
            else
                for k, _ in pairs(farmThreads) do farmThreads[k] = nil end
                if selectedFarmKey == key then selectedFarmKey = nil end
                teleportToIdleForce()
            end
        end, order)
        order = order + 1
    end
    local counterFrame = Instance.new("Frame")
    counterFrame.Size = UDim2.new(1, -4, 0, 28)
    counterFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    counterFrame.BorderSizePixel = 0
    counterFrame.LayoutOrder = order
    counterFrame.Parent = scroll
    local counterCorner = Instance.new("UICorner")
    counterCorner.CornerRadius = UDim.new(0, 4)
    counterCorner.Parent = counterFrame
    local counterLabel = Instance.new("TextLabel")
    counterLabel.Size = UDim2.new(1, 0, 1, 0)
    counterLabel.BackgroundTransparency = 1
    counterLabel.Text = "🔹 TPs: 0 / " .. TP_CAP
    counterLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
    counterLabel.TextSize = 12
    counterLabel.Font = Enum.Font.Code
    counterLabel.TextXAlignment = Enum.TextXAlignment.Center
    counterLabel.Parent = counterFrame
    task.spawn(function()
        while state.running do
            local used = teleportSystem.usedTeleports
            local current = selectedFarmKey or "None"
            counterLabel.Text = "🔹 TPs: " .. used .. " / " .. TP_CAP .. " (" .. current .. ")"
            counterLabel.TextColor3 = used >= TP_CAP and Color3.fromRGB(216, 180, 90) or Color3.fromRGB(0, 217, 196)
            task.wait(0.3)
        end
    end)
    order = order + 1
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(0.4, 0, 0, 30)
    resetBtn.Position = UDim2.new(0.3, 0, 0, 0)
    resetBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    resetBtn.Text = "⟳ RESET"
    resetBtn.TextColor3 = Color3.fromRGB(216, 180, 90)
    resetBtn.TextSize = 10
    resetBtn.Font = Enum.Font.Code
    resetBtn.BorderSizePixel = 0
    resetBtn.LayoutOrder = order
    resetBtn.Parent = scroll
    local resetCorner = Instance.new("UICorner")
    resetCorner.CornerRadius = UDim.new(0, 4)
    resetCorner.Parent = resetBtn
    resetBtn.MouseButton1Click:Connect(function()
        task.spawn(function() forceResetCharacter() end)
    end)
    scroll.CanvasSize = UDim2.new(0, 0, 0, order * 36 + 60)
end



-- ═══════════════════════════════
-- CASH TRANSFER TAB
-- ═══════════════════════════════
local cashTransferUI = {}

local function buildCashTransferTab()
    clearContent()
    local order = 1

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 28)
    header.BackgroundTransparency = 1
    header.Text = "═ CASH TRANSFER ═"
    header.TextColor3 = Color3.fromRGB(232, 241, 244)
    header.TextSize = 12
    header.Font = Enum.Font.Code
    header.LayoutOrder = 0
    header.Parent = scroll

    -- Warning banner
    local warnFrame = Instance.new("Frame")
    warnFrame.Size = UDim2.new(1, -4, 0, 46)
    warnFrame.BackgroundColor3 = Color3.fromRGB(39, 39, 24)
    warnFrame.BorderSizePixel = 0
    warnFrame.LayoutOrder = order
    warnFrame.Parent = scroll
    local warnCorner = Instance.new("UICorner")
    warnCorner.CornerRadius = UDim.new(0, 4)
    warnCorner.Parent = warnFrame
    local warnLabel = Instance.new("TextLabel")
    warnLabel.Size = UDim2.new(1, -10, 1, 0)
    warnLabel.Position = UDim2.new(0, 8, 0, 0)
    warnLabel.BackgroundTransparency = 1
    warnLabel.Text = "⚠ This will reset your character, TP to the target,\nspam DropCash until your cash < 5000, then return to idle."
    warnLabel.TextColor3 = Color3.fromRGB(216, 180, 90)
    warnLabel.TextSize = 10
    warnLabel.Font = Enum.Font.Code
    warnLabel.TextXAlignment = Enum.TextXAlignment.Left
    warnLabel.TextYAlignment = Enum.TextYAlignment.Center
    warnLabel.Parent = warnFrame
    order = order + 1

    -- Player search input
    local searchFrame = Instance.new("Frame")
    searchFrame.Size = UDim2.new(1, -4, 0, 34)
    searchFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    searchFrame.BorderSizePixel = 0
    searchFrame.LayoutOrder = order
    searchFrame.Parent = scroll
    local searchCorner = Instance.new("UICorner")
    searchCorner.CornerRadius = UDim.new(0, 4)
    searchCorner.Parent = searchFrame

    local searchLabel = Instance.new("TextLabel")
    searchLabel.Size = UDim2.new(0.2, 0, 1, 0)
    searchLabel.Position = UDim2.new(0, 8, 0, 0)
    searchLabel.BackgroundTransparency = 1
    searchLabel.Text = "Player:"
    searchLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
    searchLabel.TextSize = 11
    searchLabel.Font = Enum.Font.Code
    searchLabel.TextXAlignment = Enum.TextXAlignment.Left
    searchLabel.TextYAlignment = Enum.TextYAlignment.Center
    searchLabel.Parent = searchFrame

    local searchInput = Instance.new("TextBox")
    searchInput.Size = UDim2.new(0.55, 0, 0.7, 0)
    searchInput.Position = UDim2.new(0.22, 0, 0.15, 0)
    searchInput.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    searchInput.Text = state.cashTransfer.selectedName or ""
    searchInput.PlaceholderText = "Enter player name..."
    searchInput.TextColor3 = Color3.fromRGB(200, 200, 200)
    searchInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    searchInput.TextSize = 11
    searchInput.Font = Enum.Font.Code
    searchInput.BorderSizePixel = 0
        searchInput.ClearTextOnFocus = false
    searchInput.Parent = searchFrame
    local searchInputCorner = Instance.new("UICorner")
    searchInputCorner.CornerRadius = UDim.new(0, 4)
    searchInputCorner.Parent = searchInput

    local searchBtn = Instance.new("TextButton")
    searchBtn.Size = UDim2.new(0.18, 0, 0.7, 0)
    searchBtn.Position = UDim2.new(0.8, 0, 0.15, 0)
    searchBtn.BackgroundColor3 = Color3.fromRGB(30, 50, 70)
        searchBtn.Text = "FIND"
    searchBtn.TextColor3 = Color3.fromRGB(100, 200, 255)
    searchBtn.TextSize = 10
        searchBtn.Font = Enum.Font.Code
    searchBtn.BorderSizePixel = 0
    searchBtn.Parent = searchFrame
    local searchBtnCorner = Instance.new("UICorner")
    searchBtnCorner.CornerRadius = UDim.new(0, 4)
    searchBtnCorner.Parent = searchBtn
    order = order + 1

    -- Found player display
    local foundDisplay = Instance.new("TextLabel")
    foundDisplay.Size = UDim2.new(1, 0, 0, 20)
    foundDisplay.BackgroundTransparency = 1
    foundDisplay.Text = state.cashTransfer.selectedName ~= "" and ("✅ Selected: " .. state.cashTransfer.selectedName) or "Selected: None"
    foundDisplay.TextColor3 = state.cashTransfer.selectedName ~= "" and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(155, 145, 150)
    foundDisplay.TextSize = 11
    foundDisplay.Font = Enum.Font.Code
    foundDisplay.TextXAlignment = Enum.TextXAlignment.Left
    foundDisplay.LayoutOrder = order
    foundDisplay.Parent = scroll
    cashTransferUI.foundDisplay = foundDisplay
    order = order + 1

    -- Auto-search when typing
    searchInput:GetPropertyChangedSignal("Text"):Connect(function()
        local query = searchInput.Text
        if #query >= 2 then
            local matched = findPlayerByName(query)
            if matched then
                state.cashTransfer.selectedName = matched.Name
                foundDisplay.Text = "✅ Auto-matched: " .. matched.Name
                foundDisplay.TextColor3 = Color3.fromRGB(0, 217, 196)
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
            foundDisplay.TextColor3 = Color3.fromRGB(0, 217, 196)
        else
            foundDisplay.Text = "❌ Player not found: " .. query
            foundDisplay.TextColor3 = Color3.fromRGB(0, 217, 196)
        end
    end)

    -- Player list header
    local listHeader = Instance.new("TextLabel")
    listHeader.Size = UDim2.new(1, 0, 0, 22)
    listHeader.BackgroundTransparency = 1
    listHeader.Text = "─ PLAYERS IN SERVER ─"
    listHeader.TextColor3 = Color3.fromRGB(150, 150, 170)
    listHeader.TextSize = 11
    listHeader.Font = Enum.Font.Code
    listHeader.LayoutOrder = order
    listHeader.Parent = scroll
    order = order + 1

    -- Player list container
    local listContainer = Instance.new("Frame")
    listContainer.Size = UDim2.new(1, -4, 0, 0)
    listContainer.BackgroundTransparency = 1
    listContainer.BorderSizePixel = 0
    listContainer.LayoutOrder = order
    listContainer.Parent = scroll

    local listLayout = Instance.new("UIListLayout")
    listLayout.Parent = listContainer
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 2)

    local function refreshPlayerList()
        for _, child in ipairs(listContainer:GetChildren()) do
            if child ~= listLayout then child:Destroy() end
        end
        local players = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then table.insert(players, player) end
        end
        table.sort(players, function(a,b) return a.Name < b.Name end)
        for idx, player in ipairs(players) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -4, 0, 26)
            btn.BackgroundColor3 = Color3.fromRGB(17, 20, 24)
            btn.Text = player.Name
            btn.TextColor3 = Color3.fromRGB(200, 200, 210)
            btn.TextSize = 10
            btn.Font = Enum.Font.Code
            btn.BorderSizePixel = 0
            btn.LayoutOrder = idx
            btn.Parent = listContainer
            local btnCorner = Instance.new("UICorner")
            btnCorner.CornerRadius = UDim.new(0, 12)
            btnCorner.Parent = btn
            local hasChar = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local statusDot = Instance.new("TextLabel")
            statusDot.Size = UDim2.new(0.1, 0, 1, 0)
            statusDot.Position = UDim2.new(0.9, 0, 0, 0)
            statusDot.BackgroundTransparency = 1
            statusDot.Text = hasChar and "🟢" or "🔴"
            statusDot.TextSize = 12
            statusDot.Font = Enum.Font.SourceSans
            statusDot.Parent = btn
            btn.MouseButton1Click:Connect(function()
                state.cashTransfer.selectedName = player.Name
                searchInput.Text = player.Name
                foundDisplay.Text = "✅ Selected: " .. player.Name
                foundDisplay.TextColor3 = Color3.fromRGB(0, 217, 196)
            end)
        end
        listContainer.Size = UDim2.new(1, -4, 0, math.max(1, #players) * 28)
    end

    refreshPlayerList()
    task.spawn(function()
        while state.running do
            task.wait(5)
            if state.currentTab == "Cash Transfer" then refreshPlayerList() end
        end
    end)

    order = order + 1

    -- Execute button
    local execBtn = Instance.new("TextButton")
    execBtn.Size = UDim2.new(1, -4, 0, 40)
    execBtn.BackgroundColor3 = Color3.fromRGB(8, 124, 120)
    execBtn.Text = "💸 EXECUTE CASH TRANSFER"
    execBtn.TextColor3 = Color3.fromRGB(239, 255, 252)
    execBtn.TextSize = 12
    execBtn.Font = Enum.Font.Code
    execBtn.BorderSizePixel = 0
    execBtn.LayoutOrder = order
    execBtn.Parent = scroll
    local execCorner = Instance.new("UICorner")
    execCorner.CornerRadius = UDim.new(0, 4)
    execCorner.Parent = execBtn
    cashTransferUI.execBtn = execBtn

    execBtn.MouseButton1Click:Connect(function()
        if state.cashTransfer.running then
            state.cashTransfer.running = false
            execBtn.Text = "💸 EXECUTE CASH TRANSFER"
            execBtn.BackgroundColor3 = Color3.fromRGB(8, 124, 120)
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
            foundDisplay.TextColor3 = Color3.fromRGB(0, 217, 196)
            return
        end
        execBtn.Text = "⏹ STOP TRANSFER"
        execBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
        task.spawn(function()
            cashTransferLoop(targetPlayer)
            execBtn.Text = "💸 EXECUTE CASH TRANSFER"
            execBtn.BackgroundColor3 = Color3.fromRGB(8, 124, 120)
        end)
    end)

    order = order + 1

    -- Info
    local info = Instance.new("TextLabel")
    info.Size = UDim2.new(1, -8, 0, 80)
    info.BackgroundTransparency = 1
    info.Text = "How it works:\n1. Resets your character\n2. TP's to the selected player\n3. Fires DropCash(5000) repeatedly\n4. Stops when your cash < 5000\n5. Returns to idle coords\n\nDropCash event: " .. (DROP_CASH_EVENT and "✅ Found" or "❌ Not found")
    info.TextColor3 = Color3.fromRGB(150, 150, 170)
    info.TextSize = 10
    info.Font = Enum.Font.Code
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.LayoutOrder = order
    info.Parent = scroll
    order = order + 1

    scroll.CanvasSize = UDim2.new(0, 0, 0, order * 36 + 150)
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
    header.TextColor3 = Color3.fromRGB(0, 217, 196)
    header.TextSize = 12
    header.Font = Enum.Font.Code
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
    statusLabel.Font = Enum.Font.Code
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = statusFrame
    local threatLabel = Instance.new("TextLabel")
    threatLabel.Size = UDim2.new(1, 0, 0.5, 0)
    threatLabel.Position = UDim2.new(0, 8, 0.5, -2)
    threatLabel.BackgroundTransparency = 1
    threatLabel.Text = "Threat: None detected"
    threatLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
    threatLabel.TextSize = 11
    threatLabel.Font = Enum.Font.Code
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
    refreshBtn.Font = Enum.Font.Code
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
        bannerLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
        bannerLabel.TextSize = 12
        bannerLabel.Font = Enum.Font.Code
        bannerLabel.TextXAlignment = Enum.TextXAlignment.Center
        bannerLabel.TextYAlignment = Enum.TextYAlignment.Center
        bannerLabel.Parent = banner
        order = order + 1
    end
    local watchHeader = Instance.new("TextLabel")
    watchHeader.Size = UDim2.new(1, 0, 0, 22)
    watchHeader.BackgroundTransparency = 1
    watchHeader.Text = "─ WATCHLIST (" .. #WATCHLIST .. ") ─"
    watchHeader.TextColor3 = Color3.fromRGB(0, 217, 196)
    watchHeader.TextSize = 11
    watchHeader.Font = Enum.Font.Code
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
        accent.BackgroundColor3 = inServer and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(180, 60, 60)
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
        nameLabel.TextColor3 = inServer and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(230, 200, 200)
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.Code
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row
        local idLabel = Instance.new("TextLabel")
        idLabel.Size = UDim2.new(0.6, 0, 0, 14)
        idLabel.Position = UDim2.new(0, 12, 0, 22)
        idLabel.BackgroundTransparency = 1
        idLabel.Text = "ID: " .. userId
        idLabel.TextColor3 = Color3.fromRGB(150, 130, 130)
        idLabel.TextSize = 10
        idLabel.Font = Enum.Font.Code
        idLabel.TextXAlignment = Enum.TextXAlignment.Left
        idLabel.Parent = row
        local statusLabel2 = Instance.new("TextLabel")
        statusLabel2.Size = UDim2.new(0.35, 0, 1, 0)
        statusLabel2.Position = UDim2.new(0.65, 0, 0, 0)
        statusLabel2.BackgroundTransparency = 1
        statusLabel2.Text = inServer and "⚠ IN SERVER" or "Not here"
        statusLabel2.TextColor3 = inServer and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(120, 120, 140)
        statusLabel2.TextSize = 11
        statusLabel2.Font = Enum.Font.Code
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
    listHeader.Font = Enum.Font.Code
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
        if tracked.sameServer then dot.TextColor3 = Color3.fromRGB(0, 217, 196)
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
        nameLabel.TextColor3 = tracked.sameServer and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(220, 220, 230)
        nameLabel.TextSize = 12
        nameLabel.Font = Enum.Font.Code
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = row
        local roleLabel = Instance.new("TextLabel")
        roleLabel.Size = UDim2.new(0.45, 0, 0, 14)
        roleLabel.Position = UDim2.new(0, 26, 0, 22)
        roleLabel.BackgroundTransparency = 1
        roleLabel.Text = admin.role
        roleLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
        roleLabel.TextSize = 10
        roleLabel.Font = Enum.Font.Code
        roleLabel.TextXAlignment = Enum.TextXAlignment.Left
        roleLabel.Parent = row
        local statusText = "Offline"
        local statusColor = Color3.fromRGB(120, 120, 130)
        if tracked.sameServer then statusText = "⚠ IN YOUR SERVER"; statusColor = Color3.fromRGB(0, 217, 196)
        elseif tracked.isInGame then statusText = "In game"; statusColor = Color3.fromRGB(255, 200, 100)
        elseif tracked.isOnline then statusText = "Online"; statusColor = Color3.fromRGB(100, 255, 100) end
        local statusLabel2 = Instance.new("TextLabel")
        statusLabel2.Size = UDim2.new(0.45, 0, 0, 14)
        statusLabel2.Position = UDim2.new(0.5, 0, 0, 2)
        statusLabel2.BackgroundTransparency = 1
        statusLabel2.Text = statusText
        statusLabel2.TextColor3 = statusColor
        statusLabel2.TextSize = 11
        statusLabel2.Font = Enum.Font.Code
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
        gameLabel.Font = Enum.Font.Code
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
        emptyLabel.Font = Enum.Font.Code
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
    local order = 1

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 28)
    header.BackgroundTransparency = 1
    header.Text = "═ CONFIG ═"
    header.TextColor3 = Color3.fromRGB(232, 241, 244)
    header.TextSize = 12
    header.Font = Enum.Font.Code
    header.LayoutOrder = 0
    header.Parent = scroll

    if not hasFileAPI then
        local warnLabel = Instance.new("TextLabel")
        warnLabel.Size = UDim2.new(1, -4, 0, 50)
        warnLabel.BackgroundColor3 = Color3.fromRGB(13, 19, 24)
        warnLabel.BorderSizePixel = 0
        warnLabel.Text = "⚠ File API not available.\nConfigs cannot be saved."
        warnLabel.TextColor3 = Color3.fromRGB(255, 150, 150)
        warnLabel.TextSize = 11
        warnLabel.Font = Enum.Font.Code
        warnLabel.LayoutOrder = order
        warnLabel.Parent = scroll
        order = order + 1
    end

    local saveFrame = Instance.new("Frame")
    saveFrame.Size = UDim2.new(1, -4, 0, 34)
    saveFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    saveFrame.BorderSizePixel = 0
    saveFrame.LayoutOrder = order
    saveFrame.Parent = scroll
    local saveCorner = Instance.new("UICorner")
    saveCorner.CornerRadius = UDim.new(0, 4)
    saveCorner.Parent = saveFrame

    local saveInput = Instance.new("TextBox")
    saveInput.Size = UDim2.new(0.65, 0, 0.7, 0)
    saveInput.Position = UDim2.new(0.02, 0, 0.15, 0)
    saveInput.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    saveInput.Text = state.loadedConfigName or ""
    saveInput.PlaceholderText = "Config name..."
    saveInput.TextColor3 = Color3.fromRGB(200, 200, 200)
    saveInput.PlaceholderColor3 = Color3.fromRGB(100, 100, 120)
    saveInput.TextSize = 11
    saveInput.Font = Enum.Font.Code
    saveInput.BorderSizePixel = 0
    saveInput.ClearTextOnFocus = false
    saveInput.Parent = saveFrame
    local saveInputCorner = Instance.new("UICorner")
    saveInputCorner.CornerRadius = UDim.new(0, 4)
    saveInputCorner.Parent = saveInput

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0.29, 0, 0.7, 0)
    saveBtn.Position = UDim2.new(0.69, 0, 0.15, 0)
    saveBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
    saveBtn.Text = "SAVE"
    saveBtn.TextColor3 = Color3.fromRGB(0, 217, 196)
    saveBtn.TextSize = 11
    saveBtn.Font = Enum.Font.Code
    saveBtn.BorderSizePixel = 0
    saveBtn.Parent = saveFrame
    local saveCorner2 = Instance.new("UICorner")
    saveCorner2.CornerRadius = UDim.new(0, 4)
    saveCorner2.Parent = saveBtn

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 20)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = ""
    statusLabel.TextColor3 = Color3.fromRGB(210, 145, 150)
    statusLabel.TextSize = 10
    statusLabel.Font = Enum.Font.Code
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.LayoutOrder = order + 1
    statusLabel.Parent = scroll
    order = order + 2

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
            statusLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
            task.wait(2)
            if state.currentTab == "Config" then buildConfigTab() end
        end
    end)

    local autoHeader = Instance.new("TextLabel")
    autoHeader.Size = UDim2.new(1, 0, 0, 22)
    autoHeader.BackgroundTransparency = 1
    autoHeader.Text = "─ AUTO-LOAD ON SERVER HOP ─"
    autoHeader.TextColor3 = Color3.fromRGB(150, 150, 170)
    autoHeader.TextSize = 11
    autoHeader.Font = Enum.Font.Code
    autoHeader.LayoutOrder = order
    autoHeader.Parent = scroll
    order = order + 1

    local autoFrame = Instance.new("Frame")
    autoFrame.Size = UDim2.new(1, -4, 0, 66)
    autoFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    autoFrame.BorderSizePixel = 0
    autoFrame.LayoutOrder = order
    autoFrame.Parent = scroll
    local autoCorner = Instance.new("UICorner")
    autoCorner.CornerRadius = UDim.new(0, 4)
    autoCorner.Parent = autoFrame

    local autoLabel = Instance.new("TextLabel")
    autoLabel.Size = UDim2.new(1, 0, 0, 20)
    autoLabel.Position = UDim2.new(0, 10, 0, 2)
    autoLabel.BackgroundTransparency = 1
    autoLabel.Text = "Load on hop: " .. (getAutoLoadConfig() or "None")
    autoLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    autoLabel.TextSize = 11
    autoLabel.Font = Enum.Font.Code
    autoLabel.TextXAlignment = Enum.TextXAlignment.Left
    autoLabel.Parent = autoFrame

    local btnHolder = Instance.new("Frame")
    btnHolder.Size = UDim2.new(1, -20, 0, 38)
    btnHolder.Position = UDim2.new(0, 10, 0, 24)
    btnHolder.BackgroundTransparency = 1
    btnHolder.Parent = autoFrame
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
        noCfg.Font = Enum.Font.Code
        noCfg.Parent = btnHolder
    else
        for idx, cfgName in ipairs(configs) do
            if idx > 4 then break end
            local isActive = (getAutoLoadConfig() == cfgName)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, 70, 1, 0)
            b.BackgroundColor3 = isActive and Color3.fromRGB(30, 80, 50) or Color3.fromRGB(30, 30, 45)
            b.Text = cfgName:sub(1, 8)
            b.TextColor3 = isActive and Color3.fromRGB(0, 217, 196) or Color3.fromRGB(180, 175, 180)
            b.TextSize = 10
            b.Font = Enum.Font.Code
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
        noneBtn.Font = Enum.Font.Code
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
    order = order + 1

    createToggle(scroll, "Auto Re-Execute on Hop", state, "autoReExecute", function(val) state.autoReExecute = val end, order)
    order = order + 1

    local listHeader = Instance.new("TextLabel")
    listHeader.Size = UDim2.new(1, 0, 0, 22)
    listHeader.BackgroundTransparency = 1
    listHeader.Text = "─ SAVED CONFIGS (" .. #configs .. ") ─"
    listHeader.TextColor3 = Color3.fromRGB(150, 150, 170)
    listHeader.TextSize = 11
    listHeader.Font = Enum.Font.Code
    listHeader.LayoutOrder = order
    listHeader.Parent = scroll
    order = order + 1

    if #configs == 0 then
        local emptyLabel = Instance.new("TextLabel")
        emptyLabel.Size = UDim2.new(1, -4, 0, 40)
        emptyLabel.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
        emptyLabel.BorderSizePixel = 0
        emptyLabel.Text = "No configs saved yet."
        emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
        emptyLabel.TextSize = 11
        emptyLabel.Font = Enum.Font.Code
        emptyLabel.LayoutOrder = order
        emptyLabel.Parent = scroll
        order = order + 1
    end

    for _, name in ipairs(configs) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -4, 0, 34)
        row.BackgroundColor3 = Color3.fromRGB(17, 20, 24)
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.Parent = scroll
        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 4)
        rowCorner.Parent = row
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
        nameLabel.Position = UDim2.new(0, 10, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = name
        nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.Code
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextYAlignment = Enum.TextYAlignment.Center
        nameLabel.Parent = row
        local loadBtn = Instance.new("TextButton")
        loadBtn.Size = UDim2.new(0.15, 0, 0.7, 0)
        loadBtn.Position = UDim2.new(0.58, 0, 0.15, 0)
        loadBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 40)
        loadBtn.Text = "LOAD"
        loadBtn.TextColor3 = Color3.fromRGB(0, 217, 196)
        loadBtn.TextSize = 10
        loadBtn.Font = Enum.Font.Code
        loadBtn.BorderSizePixel = 0
        loadBtn.Parent = row
        local loadCorner = Instance.new("UICorner")
        loadCorner.CornerRadius = UDim.new(0, 4)
        loadCorner.Parent = loadBtn
        local overwriteBtn = Instance.new("TextButton")
        overwriteBtn.Size = UDim2.new(0.15, 0, 0.7, 0)
        overwriteBtn.Position = UDim2.new(0.75, 0, 0.15, 0)
        overwriteBtn.BackgroundColor3 = Color3.fromRGB(60, 50, 30)
        overwriteBtn.Text = "SAVE"
        overwriteBtn.TextColor3 = Color3.fromRGB(255, 200, 100)
        overwriteBtn.TextSize = 10
        overwriteBtn.Font = Enum.Font.Code
        overwriteBtn.BorderSizePixel = 0
        overwriteBtn.Parent = row
        local overwriteCorner = Instance.new("UICorner")
        overwriteCorner.CornerRadius = UDim.new(0, 4)
        overwriteCorner.Parent = overwriteBtn
        local delBtn = Instance.new("TextButton")
        delBtn.Size = UDim2.new(0.08, 0, 0.7, 0)
        delBtn.Position = UDim2.new(0.91, 0, 0.15, 0)
        delBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
        delBtn.Text = "✕"
        delBtn.TextColor3 = Color3.fromRGB(0, 217, 196)
        delBtn.TextSize = 10
        delBtn.Font = Enum.Font.Code
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
                statusLabel.TextColor3 = Color3.fromRGB(0, 217, 196)
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

        order = order + 1
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, order * 36 + 120)
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
    header.Font = Enum.Font.Code
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
    infoLabel.Font = Enum.Font.Code
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
        btn.BackgroundColor3 = isActive and Color3.fromRGB(13, 37, 43) or Color3.fromRGB(8, 12, 16)
        btn.TextColor3 = isActive and Color3.fromRGB(232, 241, 244) or Color3.fromRGB(101, 116, 125)
        btn.Text = (isActive and "▌  " or "   ") .. tabName
    end
    if name == "Farms" then buildFarmsTab()
    
    elseif name == "Cash Transfer" then buildCashTransferTab()
    elseif name == "Config" then buildConfigTab()
    elseif name == "Settings" then buildSettingsTab()
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
