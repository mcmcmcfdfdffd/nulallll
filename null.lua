local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local PathfindingService = game:GetService("PathfindingService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Network
local RemoteFunc = ReplicatedStorage:WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-- Папка для сохранения стратегий
local STRATEGIES_FOLDER = "TDS_Strategies"

-- Создаём папку если нет
if isfolder and not isfolder(STRATEGIES_FOLDER) then
    makefolder(STRATEGIES_FOLDER)
end

-- Модули (ленивая загрузка - загружаем только когда нужно)
local TowerReplicator, SharedGameFunctions, SharedGameConstants, Asset, InventoryStore, TowerIcons

local function loadModules()
    if TowerReplicator then return end -- уже загружено
    
    print("⏳ Загрузка модулей...")
    
    -- TowerReplicator
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Client")
            and ReplicatedStorage.Client:FindFirstChild("Modules")
            and ReplicatedStorage.Client.Modules:FindFirstChild("Replicators")
            and ReplicatedStorage.Client.Modules.Replicators:FindFirstChild("TowerReplicator")
        if mod then
            TowerReplicator = require(mod)
            print("✅ TowerReplicator")
        end
    end)
    
    -- SharedGameFunctions
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Shared")
            and ReplicatedStorage.Shared:FindFirstChild("Modules")
            and ReplicatedStorage.Shared.Modules:FindFirstChild("SharedGameFunctions")
        if mod then
            SharedGameFunctions = require(mod)
            print("✅ SharedGameFunctions")
        end
    end)
    
    -- SharedGameConstants
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Shared")
            and ReplicatedStorage.Shared:FindFirstChild("Modules")
            and ReplicatedStorage.Shared.Modules:FindFirstChild("SharedGameConstants")
        if mod then
            SharedGameConstants = require(mod)
            print("✅ SharedGameConstants")
        end
    end)
    
    -- Asset
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Shared")
            and ReplicatedStorage.Shared:FindFirstChild("Modules")
            and ReplicatedStorage.Shared.Modules:FindFirstChild("Asset")
        if mod then
            Asset = require(mod)
            print("✅ Asset")
        end
    end)
    
    -- InventoryStore - пробуем оба пути
    pcall(function()
        local interfaces = ReplicatedStorage:FindFirstChild("Client")
            and ReplicatedStorage.Client:FindFirstChild("Interfaces")
        if interfaces then
            local container = interfaces:FindFirstChild("LegacyInterface")
                or interfaces:FindFirstChild("NewInterface")
            if container then
                local stores = container:FindFirstChild("Stores")
                if stores and stores:FindFirstChild("Inventory") then
                    InventoryStore = require(stores.Inventory)
                    print("✅ InventoryStore (" .. container.Name .. ")")
                end
            end
        end
    end)
    
    -- TowerIcons
    pcall(function()
        local mod = ReplicatedStorage:FindFirstChild("Shared")
            and ReplicatedStorage.Shared:FindFirstChild("Data")
            and ReplicatedStorage.Shared.Data:FindFirstChild("Icons")
        if mod then
            TowerIcons = require(mod).Towers
            print("✅ TowerIcons")
        end
    end)
    
    print("✅ Загрузка модулей завершена!")
end

-- СРАЗУ ЗАГРУЖАЕМ МОДУЛИ (НЕ В ФОНЕ!)
task.spawn(function()
    -- Ждём пока попадём в игру, не в лобби
    while true do
        local inGame = playerGui:FindFirstChild("ReactUniversalHotbar")
        if inGame then break end
        task.wait(2)
    end
    
    task.wait(2)
    loadModules()
    if UI and UI.TowerScroll then
        createTowerButtons()
    end
end)

local DEFAULT_BOUNDARY_SIZE = 1.5
pcall(function()
    if SharedGameConstants then
        DEFAULT_BOUNDARY_SIZE = SharedGameConstants.DEFAULT_BOUNDARY_SIZE or 1.5
    end
end)

local function getTowerBoundarySize(towerName)
    local size = DEFAULT_BOUNDARY_SIZE
    pcall(function()
        if Asset then
            local towerAsset = Asset("Troops", towerName)
            if towerAsset and towerAsset.Properties and towerAsset.Properties.BoundarySize then
                size = towerAsset.Properties.BoundarySize
            end
        end
    end)
    return size
end

-- ========== ВСЕ ТИПЫ ДЕЙСТВИЙ ==========
local ActionType = {
    PLACE = "PLACE",
    UPGRADE = "UPGRADE",
    UPGRADE_TO = "UPGRADE_TO",
    UPGRADE_MAX = "UPGRADE_MAX",
    MULTI_UPGRADE = "MULTI_UPGRADE",
    SELL = "SELL",
    SELL_ALL = "SELL_ALL",
    SET_TARGET = "SET_TARGET",
    SET_TARGET_AT_WAVE = "SET_TARGET_AT_WAVE",
    ABILITY = "ABILITY",
    ABILITY_LOOP = "ABILITY_LOOP",
    SET_OPTION = "SET_OPTION",
    WAIT_WAVE = "WAIT_WAVE",
    WAIT_TIME = "WAIT_TIME",
    WAIT_CASH = "WAIT_CASH",
    VOTE_SKIP = "VOTE_SKIP",
    AUTO_CHAIN = "AUTO_CHAIN",
    AUTO_CHAIN_CARAVAN = "AUTO_CHAIN_CARAVAN",
    AUTO_DJ = "AUTO_DJ",
    AUTO_NECRO = "AUTO_NECRO",
    AUTO_MERCENARY = "AUTO_MERCENARY",
    AUTO_MILITARY = "AUTO_MILITARY",
    LOADOUT = "LOADOUT",  -- НОВОЕ
    TIME_SCALE = "TIME_SCALE",
    UNLOCK_TIMESCALE = "UNLOCK_TIMESCALE",
    SELL_AT_WAVE = "SELL_AT_WAVE",
    SELL_FARMS_AT_WAVE = "SELL_FARMS_AT_WAVE",
    AUTO_PICKUPS_MODE = "AUTO_PICKUPS_MODE",
}

-- ========== СТРАТЕГИЯ ==========
local Strategy = {
    Name = "New Strategy",
    Actions = {},
    PlacedTowers = {},
    CurrentAction = 1,
    LoopingAbilities = {},
    AutoChainRunning = false,
    ActionAutoChainCaravanRunning = false,
    ActionAutoDJRunning = false,
    ActionAutoNecroRunning = false,
    ActionAutoMercenaryRunning = false,
    ActionAutoMilitaryRunning = false,
    GlobalAutoChainRunning = false,
    GlobalAutoDJRunning = false,
    GlobalAutoSkipRunning = false,
}

local State = {
    Running = false,
    Paused = false,
    AddingPosition = false,
    SelectedTower = "Scout",
    LastLog = "",
}

local Settings = {
    ActionDelay = 0.3,
    PlaceDelay = 0.3,
    UpgradeDelay = 0.3,
    SellDelay = 0.1,
    AbilityDelay = 1,
    ShowMarkers = true,
    AutoRestart = false,
    GlobalAutoChain = false,
    GlobalAutoDJ = false,
    GlobalAutoSkip = false,
    Language = "RU",
}

local AutoPickupsMode = "Instant"

-- ========== LOCALIZATION ==========
local Texts = {
    RU = {
        title = "⚡ STRATEGY BUILDER v14.0",
        start = "▶ СТАРТ",
        pause = "⏸ ПАУЗА",
        pause_go = "▶ GO",
        stop = "⏹ СТОП",
        status_ready = "⏹ Готов",
        tower_default = "🗼 БАШНЯ: %s",
        tower_stats = "🗼 %s (R=%.1f, $%d)",
        all_actions = "➕ ВСЕ ДЕЙСТВИЯ",
        save_load = "💾 СОХРАНЕНИЕ / ЗАГРУЗКА",
        config_placeholder = "Имя конфига...",
        actions_queue = "📋 ОЧЕРЕДЬ (%d)",
        export_code = "📝 CODE",
        export_json = "📦 JSON",
        import = "📥 IMPORT",
        mode = "РЕЖИМ",
        mode_place_ok = "🏗 МОЖНО СТАВИТЬ",
        mode_place_no = "❌ НЕЛЬЗЯ",
        mode_add = "🏗 ДОБАВЛЕНИЕ",
        mode_added = "✅ #%d добавлено",
        place_active = "✅ АКТИВНО",
        global_chain_on = "🔗 AUTO CHAIN: ON",
        global_chain_off = "🔗 AUTO CHAIN: OFF",
        global_dj_on = "🎵 AUTO DJ: ON",
        global_dj_off = "🎵 AUTO DJ: OFF",
        global_skip_on = "⏭ AUTO SKIP: ON",
        global_skip_off = "⏭ AUTO SKIP: OFF",
        auto_farm_on = "🔄 AUTO FARM: ON",
        auto_farm_off = "🔄 AUTO FARM: OFF",
        auto_start_on = "▶ AUTO START: ON",
        auto_start_off = "▶ AUTO START: OFF",
        mode_btn = "🗺 %s",
        farm_status_prefix = "📍 ",
        pickups_collected = "🎁 Собрано: %d",
        autofarm_config_title = "⚙️ КОНФИГ АВТОФАРМА",
        autofarm_config_placeholder = "Имя конфига автофарма...",
        queue_on = "🔄 QUEUE: ON",
        queue_off = "🔄 QUEUE: OFF",
        delay_section = "⏱ НАСТРОЙКИ ЗАДЕРЖЕК",
        delay_action = "ДЕЙСТ.",
        delay_place = "ПОСТ.",
        delay_upgrade = "АПГР.",
        delay_sell = "ПРОД.",
        delay_ability = "СКИЛЛ",
        lang_button = "🌐 RU",
        status_running = "▶ РАБОТАЕТ",
        status_paused = "⏸ ПАУЗА",
        status_stopped = "⏹ СТОП",
        towers_label = "Башен",
        action_label = "Действие",
    },
    EN = {
        title = "⚡ STRATEGY BUILDER v14.0",
        start = "▶ START",
        pause = "⏸ PAUSE",
        pause_go = "▶ GO",
        stop = "⏹ STOP",
        status_ready = "⏹ Ready",
        tower_default = "🗼 TOWER: %s",
        tower_stats = "🗼 %s (R=%.1f, $%d)",
        all_actions = "➕ ALL ACTIONS",
        save_load = "💾 SAVE / LOAD",
        config_placeholder = "Config name...",
        actions_queue = "📋 QUEUE (%d)",
        export_code = "📝 CODE",
        export_json = "📦 JSON",
        import = "📥 IMPORT",
        mode = "MODE",
        mode_place_ok = "🏗 PLACE OK",
        mode_place_no = "❌ CAN'T PLACE",
        mode_add = "🏗 ADDING",
        mode_added = "✅ #%d added",
        place_active = "✅ ACTIVE",
        global_chain_on = "🔗 AUTO CHAIN: ON",
        global_chain_off = "🔗 AUTO CHAIN: OFF",
        global_dj_on = "🎵 AUTO DJ: ON",
        global_dj_off = "🎵 AUTO DJ: OFF",
        global_skip_on = "⏭ AUTO SKIP: ON",
        global_skip_off = "⏭ AUTO SKIP: OFF",
        auto_farm_on = "🔄 AUTO FARM: ON",
        auto_farm_off = "🔄 AUTO FARM: OFF",
        auto_start_on = "▶ AUTO START: ON",
        auto_start_off = "▶ AUTO START: OFF",
        mode_btn = "🗺 %s",
        farm_status_prefix = "📍 ",
        pickups_collected = "🎁 Collected: %d",
        autofarm_config_title = "⚙️ AUTOFARM CONFIG",
        autofarm_config_placeholder = "Autofarm config name...",
        queue_on = "🔄 QUEUE: ON",
        queue_off = "🔄 QUEUE: OFF",
        delay_section = "⏱ DELAY SETTINGS",
        delay_action = "ACTION",
        delay_place = "PLACE",
        delay_upgrade = "UPGR",
        delay_sell = "SELL",
        delay_ability = "ABIL",
        lang_button = "🌐 EN",
        status_running = "▶ RUNNING",
        status_paused = "⏸ PAUSED",
        status_stopped = "⏹ STOP",
        towers_label = "Towers",
        action_label = "Action",
    }
}

local function tr(key, ...)
    local lang = Texts[Settings.Language] or Texts.RU
    local value = lang[key] or Texts.RU[key] or key
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

-- Forward declarations for UI elements used in applyLanguage
local AutoFarmSettings
local QueueSettings
local pickupsCollected
local currentGameState

local UI = {}

local function getAutoCfg()
    local cfg = rawget(_G, "TDS_AutoFarm")
    if type(cfg) == "string" then
        cfg = { ConfigName = cfg }
        _G.TDS_AutoFarm = cfg
    end
    if type(cfg) ~= "table" then
        return nil
    end
    return cfg
end

-- ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========

-- ФИКС: Улучшенное получение денег
local function getCash()
    local cash = 0
    pcall(function()
        local text = playerGui.ReactUniversalHotbar.Frame.values.cash.amount.Text
        cash = tonumber((text:gsub("%D", ""))) or 0
    end)
    return cash
end

local function getCurrentWave()
    local wave = 0
    pcall(function()
        local display = playerGui:FindFirstChild("ReactGameTopGameDisplay")
        if display and display:FindFirstChild("Frame") then
            local frame = display.Frame
            if frame:FindFirstChild("wave") then
                local waveFrame = frame.wave
                if waveFrame:FindFirstChild("container") then
                    local container = waveFrame.container
                    if container:FindFirstChild("value") then
                        local text = container.value.Text
                        wave = tonumber(text:match("^(%d+)")) or 0
                    end
                end
            end
        end
    end)
    return wave
end

local function getUnlockedTowers()
    local unlocked = {}
    pcall(function()
        local inv = InventoryStore.state.inventory:get()
        for _, item in pairs(inv) do
            if item.type == "tower" then unlocked[item.name] = true end
        end
    end)
    return unlocked
end

local function getTowerLevel(tower)
    local level = 0
    pcall(function()
        if TowerReplicator then
            local tObj = TowerReplicator.getTowerByModel(tower)
            if tObj and tObj.Upgrade then level = tObj.Upgrade end
        end
        if level == 0 then
            local replicator = tower:FindFirstChild("TowerReplicator")
            if replicator then
                level = replicator:GetAttribute("Upgrade") or 0
            end
        end
    end)
    return level
end

local function getTowerMaxLevel(towerName)
    local maxLevel = 4  -- Fallback
    
    pcall(function()
        if Asset then
            local towerAsset = Asset("Troops", towerName)
            if towerAsset and towerAsset.Stats then
                local skinStats = towerAsset.Stats.Default
                if skinStats and skinStats.Upgrades then
                    -- Считаем сколько апгрейдов в таблице
                    maxLevel = #skinStats.Upgrades
                end
            end
        end
    end)
    
    return maxLevel
end

-- ФИКС: Улучшенное получение стоимости башни
local function getTowerPlaceCost(towerName)
    local cost = 0
    
    pcall(function()
        if Asset then
            local towerAsset = Asset("Troops", towerName)
            if towerAsset and towerAsset.Stats then
                -- Берём Default скин
                local defaultStats = towerAsset.Stats.Default
                if defaultStats and defaultStats.Defaults and defaultStats.Defaults.Price then
                    cost = defaultStats.Defaults.Price
                end
            end
        end
    end)
    
    -- Fallback если не нашли
    if cost == 0 then
        local knownCosts = {
            Scout = 150, Sniper = 350, Demoman = 400, Militant = 200,
            Paintballer = 200, Freezer = 150, ["DJ Booth"] = 1500,
            Commander = 2000, Cowboy = 1000, Farm = 500, Ranger = 400,
            Turret = 2000, Electroshocker = 1000, Pyromancer = 800,
        }
        cost = knownCosts[towerName] or 200
    end
    
    return cost
end

local function getTowerUpgradeCost(towerName, currentLevel, path)
    local cost = 0
    local nextLevel = currentLevel + 1
    
    pcall(function()
        if Asset then
            local towerAsset = Asset("Troops", towerName)
            if towerAsset and towerAsset.Stats then
                -- Берём Default скин (или Golden если есть)
                local skinStats = towerAsset.Stats.Default
                
                if skinStats and skinStats.Upgrades then
                    local upgrade = skinStats.Upgrades[nextLevel]
                    if upgrade and upgrade.Cost then
                        cost = upgrade.Cost
                    end
                end
            end
        end
    end)
    
    return cost
end

local function getTowerName(tower)
    local name = "Unknown"
    pcall(function()
        if TowerReplicator then
            local tObj = TowerReplicator.getTowerByModel(tower)
            if tObj and tObj.Name then name = tObj.Name end
        end
        if name == "Unknown" then
            local replicator = tower:FindFirstChild("TowerReplicator")
            if replicator then
                name = replicator:GetAttribute("Name") or "Unknown"
            end
        end
    end)
    return name
end

local function getPlayerTeam()
    local team = nil
    pcall(function()
        local PlayerReplicator = require(ReplicatedStorage.Client.Modules.Replicators.PlayerReplicator)
        if PlayerReplicator then
            local playerData = PlayerReplicator.GetLocalPlayerRaw()
            if playerData and playerData.Team then team = playerData.Team end
        end
    end)
    return team
end

local function checkPositionValid(towerName, position, ignorePlannedPositions)
    if not towerName or not position then return false, "Нет данных" end
    
    local isValid = true
    local reason = "OK"
    
    if SharedGameFunctions and SharedGameFunctions.CheckTowerCollisions then
        pcall(function()
            local team = getPlayerTeam()
            local result, hitData = SharedGameFunctions.CheckTowerCollisions(towerName, position, team, {})
            
            if not result then
                isValid = false
                if hitData and typeof(hitData) == "Instance" then
                    reason = "Близко к: " .. hitData.Name
                else
                    reason = "Нельзя тут"
                end
            end
        end)
    end
    
    if isValid and not ignorePlannedPositions then
        local newBoundary = getTowerBoundarySize(towerName)
        
        for _, action in ipairs(Strategy.Actions) do
            if action.type == ActionType.PLACE then
                local plannedPos = action.params.position
                local plannedBoundary = getTowerBoundarySize(action.params.towerName)
                
                local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(plannedPos.X, 0, plannedPos.Z)).Magnitude
                local minDistance = newBoundary + plannedBoundary
                
                if distance < minDistance then
                    isValid = false
                    reason = "Близко к: #" .. action.params.towerName:sub(1, 8)
                    break
                end
            end
        end
    end
    
    return isValid, reason
end

local function isTimescaleLocked()
    local locked = false
    pcall(function()
        local hotbar = playerGui:FindFirstChild("ReactUniversalHotbar")
        if not hotbar then return end
        local frame = hotbar:FindFirstChild("Frame")
        if not frame then return end
        local timescale = frame:FindFirstChild("timescale")
        if not timescale then return end
        local lock = timescale:FindFirstChild("Lock")
        if not lock then return end
        locked = lock.Visible == true
    end)
    return locked
end

local function unlockTimeScale()
    pcall(function()
        RemoteFunc:InvokeServer("TicketsManager", "UnlockTimeScale")
    end)
end

local function setGameTimescale(targetValue)
    local speedList = {0, 0.5, 1, 1.5, 2}
    local targetIdx
    for i, v in ipairs(speedList) do
        if v == targetValue then
            targetIdx = i
            break
        end
    end
    if not targetIdx then return false end

    local hotbar = playerGui:FindFirstChild("ReactUniversalHotbar")
    local frame = hotbar and hotbar:FindFirstChild("Frame")
    local timescale = frame and frame:FindFirstChild("timescale")
    local speedLabel = timescale and timescale:FindFirstChild("Speed")
    if not speedLabel or not speedLabel.Text then return false end

    local currentVal = tonumber(speedLabel.Text:match("x([%d%.]+)"))
    if not currentVal then return false end

    local currentIdx
    for i, v in ipairs(speedList) do
        if v == currentVal then
            currentIdx = i
            break
        end
    end
    if not currentIdx then return false end

    local diff = targetIdx - currentIdx
    if diff < 0 then
        diff = #speedList + diff
    end

    for _ = 1, diff do
        pcall(function()
            RemoteFunc:InvokeServer("TicketsManager", "CycleTimeScale")
        end)
        task.wait(0.5)
    end

    return true
end

-- ========== ФУНКЦИИ СОХРАНЕНИЯ/ЗАГРУЗКИ ==========

local function getStrategyFiles()
    local files = {}
    pcall(function()
        if isfolder(STRATEGIES_FOLDER) then
            local allFiles = listfiles(STRATEGIES_FOLDER)
            for _, filePath in ipairs(allFiles) do
                local fileName = filePath:match("([^/\\]+)%.json$")
                if fileName then
                    table.insert(files, fileName)
                end
            end
        end
    end)
    table.sort(files)
    return files
end

local function saveStrategy(name)
    if not name or name == "" then return false, "Пустое имя" end
    
    local data = {
        name = name,
        version = "14.0",
        actions = {}
    }
    
    for _, action in ipairs(Strategy.Actions) do
        local actionData = { type = action.type, params = {} }
        
        if action.type == ActionType.PLACE then
            actionData.params.towerName = action.params.towerName
            actionData.params.x = action.params.position.X
            actionData.params.y = action.params.position.Y
            actionData.params.z = action.params.position.Z
        elseif action.type == ActionType.LOADOUT then
            actionData.params.towers = action.params.towers
        else
            for k, v in pairs(action.params) do
                if typeof(v) == "Vector3" then
                    actionData.params[k] = {x = v.X, y = v.Y, z = v.Z}
                else
                    actionData.params[k] = v
                end
            end
        end
        
        table.insert(data.actions, actionData)
    end
    
    local json = HttpService:JSONEncode(data)
    local filePath = STRATEGIES_FOLDER .. "/" .. name .. ".json"
    
    local success, err = pcall(function()
        writefile(filePath, json)
    end)
    
    if success then
        Strategy.Name = name
        return true, "Сохранено: " .. name
    else
        return false, "Ошибка: " .. tostring(err)
    end
end

-- ФИКС: Теперь возвращает данные для обновления UI
local function loadStrategy(name)
    if not name or name == "" then return false, "Пустое имя" end
    
    local filePath = STRATEGIES_FOLDER .. "/" .. name .. ".json"
    
    if not isfile(filePath) then
        return false, "Файл не найден"
    end
    
    local success, result = pcall(function()
        local json = readfile(filePath)
        return HttpService:JSONDecode(json)
    end)
    
    if not success then
        return false, "Ошибка чтения"
    end
    
    local data = result
    if type(data) ~= "table" then
        return false, "Битый файл"
    end
    if type(data.actions) ~= "table" then
        data.actions = {}
    end
    Strategy.Name = data.name or name
    Strategy.Actions = {}
    Strategy.PlacedTowers = {}
    Strategy.CurrentAction = 1
    
    for _, actionData in ipairs(data.actions or {}) do
        if type(actionData) == "table" then
            local rawParams = type(actionData.params) == "table" and actionData.params or {}
            local params = {}
            
            for k, v in pairs(rawParams) do
                if type(v) == "table" and v.x and v.y and v.z then
                    params[k] = Vector3.new(v.x, v.y, v.z)
                else
                    params[k] = v
                end
            end
            
            if actionData.type == ActionType.PLACE then
                params.position = Vector3.new(
                    rawParams.x or 0,
                    rawParams.y or 0,
                    rawParams.z or 0
                )
            end
            
            table.insert(Strategy.Actions, {
                type = actionData.type,
                params = params,
                id = HttpService:GenerateGUID(false)
            })
        end
    end
    
    return true, "Загружено: " .. #Strategy.Actions .. " действий"
end

local function safeLoadStrategy(name)
    if type(loadStrategy) ~= "function" then
        return false, "loadStrategy missing"
    end
    local ok, success, msg = pcall(loadStrategy, name)
    if not ok then
        return false, tostring(success)
    end
    return success, msg
end

local function safeAutoLoadStrategy(name)
    local ok, success, msg = pcall(function()
        if type(safeLoadStrategy) == "function" then
            return safeLoadStrategy(name)
        elseif type(loadStrategy) == "function" then
            return loadStrategy(name)
        end
        return false, "loadStrategy missing"
    end)
    if not ok then
        return false, "AutoLoad error: " .. tostring(success)
    end
    return success, msg
end

local function deleteStrategy(name)
    if not name or name == "" then return false, "Пустое имя" end
    
    local filePath = STRATEGIES_FOLDER .. "/" .. name .. ".json"
    
    if not isfile(filePath) then
        return false, "Файл не найден"
    end
    
    local success = pcall(function()
        delfile(filePath)
    end)
    
    return success, success and "Удалено" or "Ошибка удаления"
end

-- ========== ФУНКЦИИ ДЕЙСТВИЙ ==========

local function checkRes(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end
    local success, isModel = pcall(function() return data and data:IsA("Model") end)
    if success and isModel then return true end
    if type(data) == "userdata" then return true end
    return false
end

local function doPlace(towerName, position)
    local success, result = pcall(function()
        return RemoteFunc:InvokeServer("Troops", "Plаce", {
            Position = position,
            Rotation = CFrame.new()
        }, towerName)
    end)
    return success and checkRes(result), result
end

local function doUpgrade(towerModel, path)
    path = path or 1
    local success, result = pcall(function()
        return RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {
            Troop = towerModel,
            Path = path
        })
    end)
    return success and checkRes(result)
end

local function doSell(towerModel)
    local success, result = pcall(function()
        return RemoteFunc:InvokeServer("Troops", "Sell", { Troop = towerModel })
    end)
    return success and checkRes(result)
end

local function doSetTarget(towerModel, targetType)
    local success, result = pcall(function()
        return RemoteFunc:InvokeServer("Troops", "Target", "Set", {
            Troop = towerModel,
            Target = targetType
        })
    end)
    return success and checkRes(result)
end

local function doAbility(towerModel, abilityName, data)
    local success, result = pcall(function()
        return RemoteFunc:InvokeServer("Troops", "Abilities", "Activate", {
            Troop = towerModel,
            Name = abilityName,
            Data = data or {}
        })
    end)
    return success and checkRes(result)
end

local function doSetOption(towerModel, optionName, optionValue)
    local success, result = pcall(function()
        return RemoteFunc:InvokeServer("Troops", "Option", "Set", {
            Troop = towerModel,
            Name = optionName,
            Value = optionValue
        })
    end)
    return success and checkRes(result)
end

local function doVoteSkip()
    pcall(function()
        RemoteFunc:InvokeServer("Voting", "Skip")
    end)
end

-- НОВОЕ: Loadout функция
local function doLoadout(towers)
    -- Сначала снимаем все башни
    pcall(function()
        RemoteFunc:InvokeServer("Inventory", "Unequip", "tower", "")
    end)
    task.wait(0.3)
    
    -- Надеваем новые башни
    for _, towerName in ipairs(towers) do
        if towerName and towerName ~= "" then
            pcall(function()
                RemoteFunc:InvokeServer("Inventory", "Equip", "tower", towerName)
            end)
            task.wait(0.4)
        end
    end
    
    return true
end

-- ========== ГЛОБАЛЬНЫЕ AUTO ФУНКЦИИ ==========

local function startGlobalAutoChain()
    if Strategy.GlobalAutoChainRunning then return end
    Strategy.GlobalAutoChainRunning = true
    
    task.spawn(function()
        local idx = 1
        
        while Settings.GlobalAutoChain and Strategy.GlobalAutoChainRunning do
            local commanders = {}
            local towersFolder = workspace:FindFirstChild("Towers")
            
            if towersFolder then
                for _, tower in ipairs(towersFolder:GetDescendants()) do
                    if tower:IsA("Folder") and tower.Name == "TowerReplicator"
                        and tower:GetAttribute("Name") == "Commander"
                        and tower:GetAttribute("OwnerId") == player.UserId
                        and (tower:GetAttribute("Upgrade") or 0) >= 2 then
                        table.insert(commanders, tower.Parent)
                    end
                end
            end
            
            if #commanders >= 3 then
                if idx > #commanders then idx = 1 end
                
                pcall(function()
                    RemoteFunc:InvokeServer("Troops", "Abilities", "Activate", {
                        Troop = commanders[idx],
                        Name = "Call Of Arms",
                        Data = {}
                    })
                end)
                
                idx = idx + 1
                
                local waitTime = isTimescaleLocked() and 10.5 or 5.5
                task.wait(waitTime)
            else
                task.wait(1)
            end
        end
        
        Strategy.GlobalAutoChainRunning = false
    end)
end

local function stopGlobalAutoChain()
    Strategy.GlobalAutoChainRunning = false
end

local function startGlobalAutoDJ()
    if Strategy.GlobalAutoDJRunning then return end
    Strategy.GlobalAutoDJRunning = true
    
    task.spawn(function()
        while Settings.GlobalAutoDJ and Strategy.GlobalAutoDJRunning do
            local djBooth = nil
            local towersFolder = workspace:FindFirstChild("Towers")
            
            if towersFolder then
                for _, tower in ipairs(towersFolder:GetDescendants()) do
                    if tower:IsA("Folder") and tower.Name == "TowerReplicator"
                        and tower:GetAttribute("Name") == "DJ Booth"
                        and tower:GetAttribute("OwnerId") == player.UserId
                        and (tower:GetAttribute("Upgrade") or 0) >= 3 then
                        djBooth = tower.Parent
                        break
                    end
                end
            end
            
            if djBooth then
                pcall(function()
                    RemoteFunc:InvokeServer("Troops", "Abilities", "Activate", {
                        Troop = djBooth,
                        Name = "Drop The Beat",
                        Data = {}
                    })
                end)
                
                local waitTime = isTimescaleLocked() and 28 or 14
                task.wait(waitTime)
            else
                task.wait(1)
            end
        end
        
        Strategy.GlobalAutoDJRunning = false
    end)
end

local function stopGlobalAutoDJ()
    Strategy.GlobalAutoDJRunning = false
end

-- НОВОЕ: Global Auto Skip
local function startGlobalAutoSkip()
    if Strategy.GlobalAutoSkipRunning then return end
    Strategy.GlobalAutoSkipRunning = true
    
    task.spawn(function()
        while Settings.GlobalAutoSkip and Strategy.GlobalAutoSkipRunning do
            local voteUI = playerGui:FindFirstChild("ReactOverridesVote")
            local voteBtn = voteUI and voteUI:FindFirstChild("Frame") 
                and voteUI.Frame:FindFirstChild("votes")
                and voteUI.Frame.votes:FindFirstChild("vote", true)
            
            if voteBtn and voteBtn.Position == UDim2.new(0.5, 0, 0.5, 0) then
                pcall(function()
                    RemoteFunc:InvokeServer("Voting", "Skip")
                end)
            end
            
            task.wait(1)
        end
        
        Strategy.GlobalAutoSkipRunning = false
    end)
end

local function stopGlobalAutoSkip()
    Strategy.GlobalAutoSkipRunning = false
end

-- ========== СОЗДАНИЕ ДЕЙСТВИЙ ==========

local function createAction(actionType, params)
    return {
        type = actionType,
        params = params or {},
        id = HttpService:GenerateGUID(false)
    }
end

local function addPlaceAction(towerName, x, y, z)
    table.insert(Strategy.Actions, createAction(ActionType.PLACE, {
        towerName = towerName,
        position = Vector3.new(x, y, z)
    }))
    return #Strategy.Actions
end

local function addUpgradeAction(towerIndex, path)
    table.insert(Strategy.Actions, createAction(ActionType.UPGRADE, {
        towerIndex = towerIndex,
        path = path or 1
    }))
    return #Strategy.Actions
end

local function addUpgradeToAction(towerIndex, targetLevel, path)
    table.insert(Strategy.Actions, createAction(ActionType.UPGRADE_TO, {
        towerIndex = towerIndex,
        targetLevel = targetLevel,
        path = path or 1
    }))
    return #Strategy.Actions
end

local function addUpgradeMaxAction(towerIndex, path)
    table.insert(Strategy.Actions, createAction(ActionType.UPGRADE_MAX, {
        towerIndex = towerIndex,
        path = path or 1
    }))
    return #Strategy.Actions
end

local function addMultiUpgradeAction(fromIndex, toIndex, targetLevel, towerNameFilter, path)
    table.insert(Strategy.Actions, createAction(ActionType.MULTI_UPGRADE, {
        fromIndex = fromIndex or 1,
        toIndex = toIndex or 99,
        targetLevel = targetLevel or 1,
        towerNameFilter = towerNameFilter or "",
        path = path or 1
    }))
    return #Strategy.Actions
end

local function addSellAction(towerIndex)
    table.insert(Strategy.Actions, createAction(ActionType.SELL, {
        towerIndex = towerIndex
    }))
    return #Strategy.Actions
end

local function addSellAllAction()
    table.insert(Strategy.Actions, createAction(ActionType.SELL_ALL, {}))
    return #Strategy.Actions
end

local function addSetTargetAction(towerIndex, targetType)
    table.insert(Strategy.Actions, createAction(ActionType.SET_TARGET, {
        towerIndex = towerIndex,
        targetType = targetType
    }))
    return #Strategy.Actions
end

local function addAbilityAction(towerIndex, abilityName, abilityData, loop)
    local actionType = loop and ActionType.ABILITY_LOOP or ActionType.ABILITY
    table.insert(Strategy.Actions, createAction(actionType, {
        towerIndex = towerIndex,
        abilityName = abilityName,
        data = abilityData or {},
        loop = loop or false
    }))
    return #Strategy.Actions
end

local function addSetOptionAction(towerIndex, optionName, optionValue, waveReq)
    table.insert(Strategy.Actions, createAction(ActionType.SET_OPTION, {
        towerIndex = towerIndex,
        optionName = optionName,
        optionValue = optionValue,
        waveRequirement = waveReq or 0
    }))
    return #Strategy.Actions
end

local function addWaitWaveAction(wave)
    table.insert(Strategy.Actions, createAction(ActionType.WAIT_WAVE, { wave = wave }))
    return #Strategy.Actions
end

local function addWaitTimeAction(seconds)
    table.insert(Strategy.Actions, createAction(ActionType.WAIT_TIME, { seconds = seconds }))
    return #Strategy.Actions
end

local function addWaitCashAction(amount)
    table.insert(Strategy.Actions, createAction(ActionType.WAIT_CASH, { amount = amount }))
    return #Strategy.Actions
end

local function addVoteSkipAction(startWave, endWave)
    table.insert(Strategy.Actions, createAction(ActionType.VOTE_SKIP, {
        startWave = startWave or 1,
        endWave = endWave or startWave or 1
    }))
    return #Strategy.Actions
end

local function addAutoChainAction(towerIndices)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_CHAIN, {
        towerIndices = towerIndices or {}
    }))
    return #Strategy.Actions
end

local function addAutoChainOffAction()
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_CHAIN, {
        towerIndices = {},
        enabled = false
    }))
    return #Strategy.Actions
end

local function addAutoChainCaravanAction(towerIndices)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_CHAIN_CARAVAN, {
        towerIndices = towerIndices or {}
    }))
    return #Strategy.Actions
end

local function addAutoDJAction(enabled)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_DJ, {
        enabled = enabled ~= false
    }))
    return #Strategy.Actions
end

local function addAutoNecroAction(enabled)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_NECRO, {
        enabled = enabled ~= false
    }))
    return #Strategy.Actions
end

local function addAutoMercenaryAction(distance, enabled)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_MERCENARY, {
        distance = distance or 195,
        enabled = enabled ~= false
    }))
    return #Strategy.Actions
end

local function addAutoMilitaryAction(distance, enabled)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_MILITARY, {
        distance = distance or 195,
        enabled = enabled ~= false
    }))
    return #Strategy.Actions
end

local function addTimeScaleAction(value, unlock)
    table.insert(Strategy.Actions, createAction(ActionType.TIME_SCALE, {
        value = value or 1,
        unlock = unlock or false
    }))
    return #Strategy.Actions
end

local function addUnlockTimeScaleAction()
    table.insert(Strategy.Actions, createAction(ActionType.UNLOCK_TIMESCALE, {}))
    return #Strategy.Actions
end

local function addSetTargetAtWaveAction(towerIndex, targetType, wave)
    table.insert(Strategy.Actions, createAction(ActionType.SET_TARGET_AT_WAVE, {
        towerIndex = towerIndex,
        targetType = targetType,
        wave = wave or 1
    }))
    return #Strategy.Actions
end

local function addSellAtWaveAction(towerIndex, wave)
    table.insert(Strategy.Actions, createAction(ActionType.SELL_AT_WAVE, {
        towerIndex = towerIndex,
        wave = wave or 1
    }))
    return #Strategy.Actions
end

local function addSellFarmsAtWaveAction(wave)
    table.insert(Strategy.Actions, createAction(ActionType.SELL_FARMS_AT_WAVE, {
        wave = wave or 1
    }))
    return #Strategy.Actions
end

local function addAutoPickupsModeAction(mode)
    table.insert(Strategy.Actions, createAction(ActionType.AUTO_PICKUPS_MODE, {
        mode = mode or "Instant"
    }))
    return #Strategy.Actions
end

-- НОВОЕ: Добавление Loadout действия
local function addLoadoutAction(towers)
    table.insert(Strategy.Actions, createAction(ActionType.LOADOUT, {
        towers = towers or {}
    }))
    return #Strategy.Actions
end

-- ========== ВЫПОЛНЕНИЕ ДЕЙСТВИЙ ==========

local function startActionAutoDJ()
    if Strategy.ActionAutoDJRunning then return end
    Strategy.ActionAutoDJRunning = true
    task.spawn(function()
        while Strategy.ActionAutoDJRunning and State.Running do
            local djBooth = nil
            local towersFolder = workspace:FindFirstChild("Towers")
            if towersFolder then
                for _, tower in ipairs(towersFolder:GetDescendants()) do
                    if tower:IsA("Folder") and tower.Name == "TowerReplicator"
                        and tower:GetAttribute("Name") == "DJ Booth"
                        and tower:GetAttribute("OwnerId") == player.UserId
                        and (tower:GetAttribute("Upgrade") or 0) >= 3 then
                        djBooth = tower.Parent
                        break
                    end
                end
            end

            if djBooth then
                pcall(function()
                    RemoteFunc:InvokeServer("Troops", "Abilities", "Activate", {
                        Troop = djBooth,
                        Name = "Drop The Beat",
                        Data = {}
                    })
                end)
                local waitTime = isTimescaleLocked() and 28 or 14
                task.wait(waitTime)
            else
                task.wait(1)
            end
        end
        Strategy.ActionAutoDJRunning = false
    end)
end

local function startActionAutoChainCaravan(towerIndices)
    if Strategy.ActionAutoChainCaravanRunning then return end
    Strategy.ActionAutoChainCaravanRunning = true
    task.spawn(function()
        local idx = 1
        while Strategy.ActionAutoChainCaravanRunning and State.Running do
            local towerIndex = towerIndices[idx]
            local tower = Strategy.PlacedTowers[towerIndex]
            if tower and tower.Parent then
                local level = getTowerLevel(tower)
                if level >= 2 then
                    if level >= 4 then
                        doAbility(tower, "Support Caravan", {})
                        task.wait(0.1)
                    end
                    doAbility(tower, "Call Of Arms", {})
                    State.LastLog = "🚚 Chain+Caravan → #" .. towerIndex
                else
                    State.LastLog = "⚠️ #" .. towerIndex .. " нужен Lv2+"
                end
            end
            local waitTime = isTimescaleLocked() and 10.5 or 5.5
            task.wait(waitTime)
            idx = idx + 1
            if idx > #towerIndices then idx = 1 end
        end
        Strategy.ActionAutoChainCaravanRunning = false
    end)
end

local function startActionAutoNecro()
    if Strategy.ActionAutoNecroRunning then return end
    Strategy.ActionAutoNecroRunning = true
    task.spawn(function()
        local lastActivation = {}
        while Strategy.ActionAutoNecroRunning and State.Running do
            local towersFolder = workspace:FindFirstChild("Towers")
            if towersFolder then
                for _, rep in ipairs(towersFolder:GetDescendants()) do
                    if rep:IsA("Folder") and rep.Name == "TowerReplicator"
                        and rep:GetAttribute("Name") == "Necromancer"
                        and rep:GetAttribute("OwnerId") == player.UserId then
                        local necro = rep.Parent
                        local up = rep:GetAttribute("Upgrade") or 0
                        local graveStore = rep:FindFirstChild("GraveStone")
                        local maxGraves = rep:GetAttribute("Max_Graves")
                        if graveStore then
                            local gMax = graveStore:GetAttribute("Max_Graves")
                            if type(gMax) == "number" and gMax > 0 then
                                maxGraves = gMax
                            end
                        end
                        if not maxGraves or maxGraves < 2 then
                            if up >= 4 then
                                maxGraves = 9
                            elseif up >= 2 then
                                maxGraves = 6
                            else
                                maxGraves = 3
                            end
                        end

                        local graveCount = 0
                        if graveStore then
                            for k, v in pairs(graveStore:GetAttributes()) do
                                if type(k) == "string" and #k > 20 then
                                    local isDestroy = false
                                    if type(v) == "table" then
                                        for _, elem in pairs(v) do
                                            if tostring(elem) == "Destroy" then
                                                isDestroy = true
                                                break
                                            end
                                        end
                                    elseif tostring(v):find("Destroy") then
                                        isDestroy = true
                                    end
                                    if isDestroy then
                                        graveStore:SetAttribute(k, nil)
                                    else
                                        graveCount = graveCount + 1
                                    end
                                end
                            end
                        end

                        local debounce = rep:GetAttribute("AbilityDebounce") or 5
                        local now = os.clock()
                        local last = lastActivation[necro] or 0

                        if graveCount >= maxGraves and (now - last) >= debounce then
                            local ok = doAbility(necro, "Raise The Dead", {})
                            if ok then
                                lastActivation[necro] = now
                                task.wait(0.5)
                            end
                        end
                    end
                end
            end
            task.wait(0.5)
        end
        Strategy.ActionAutoNecroRunning = false
    end)
end

local function startActionAutoMercenary(distance)
    if Strategy.ActionAutoMercenaryRunning then return end
    Strategy.ActionAutoMercenaryRunning = true
    task.spawn(function()
        while Strategy.ActionAutoMercenaryRunning and State.Running do
            local towersFolder = workspace:FindFirstChild("Towers")
            if towersFolder then
                for _, rep in ipairs(towersFolder:GetDescendants()) do
                    if rep:IsA("Folder") and rep.Name == "TowerReplicator"
                        and rep:GetAttribute("Name") == "Mercenary Base"
                        and rep:GetAttribute("OwnerId") == player.UserId
                        and (rep:GetAttribute("Upgrade") or 0) >= 5 then
                        pcall(function()
                            RemoteFunc:InvokeServer("Troops", "Abilities", "Activate", {
                                Troop = rep.Parent,
                                Name = "Air-Drop",
                                Data = {
                                    pathName = 1,
                                    directionCFrame = CFrame.new(),
                                    dist = distance or 195
                                }
                            })
                        end)
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.5)
        end
        Strategy.ActionAutoMercenaryRunning = false
    end)
end

local function startActionAutoMilitary(distance)
    if Strategy.ActionAutoMilitaryRunning then return end
    Strategy.ActionAutoMilitaryRunning = true
    task.spawn(function()
        while Strategy.ActionAutoMilitaryRunning and State.Running do
            local towersFolder = workspace:FindFirstChild("Towers")
            if towersFolder then
                for _, rep in ipairs(towersFolder:GetDescendants()) do
                    if rep:IsA("Folder") and rep.Name == "TowerReplicator"
                        and rep:GetAttribute("Name") == "Military Base"
                        and rep:GetAttribute("OwnerId") == player.UserId
                        and (rep:GetAttribute("Upgrade") or 0) >= 4 then
                        pcall(function()
                            RemoteFunc:InvokeServer("Troops", "Abilities", "Activate", {
                                Troop = rep.Parent,
                                Name = "Airstrike",
                                Data = {
                                    pathName = 1,
                                    pointToEnd = CFrame.new(),
                                    dist = distance or 195
                                }
                            })
                        end)
                        task.wait(0.5)
                    end
                end
            end
            task.wait(0.5)
        end
        Strategy.ActionAutoMilitaryRunning = false
    end)
end

local function executeAction(action)
    if action.type == ActionType.PLACE then
        local p = action.params
        local cost = getTowerPlaceCost(p.towerName)
        
        while State.Running and not State.Paused do
            local cash = getCash()
            if cash >= cost then break end
            State.LastLog = string.format("💰 Жду $%d на %s (есть $%d)", cost, p.towerName, cash)
            task.wait(Settings.PlaceDelay)
        end
        
        if not State.Running then return false end
        
        State.LastLog = "🏗 Ставлю " .. p.towerName .. "..."
        
        while State.Running and not State.Paused do
            local success, result = doPlace(p.towerName, p.position)
            if success then
                task.wait(Settings.PlaceDelay)
                local towerIndex = #Strategy.PlacedTowers + 1
                
                for _, tower in pairs(workspace.Towers:GetChildren()) do
                    local owner = tower:FindFirstChild("Owner")
                    if owner and owner.Value == player.UserId then
                        local pos = tower:GetPivot().Position
                        if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(p.position.X, 0, p.position.Z)).Magnitude < 3 then
                            if not table.find(Strategy.PlacedTowers, tower) then
                                Strategy.PlacedTowers[towerIndex] = tower
                                break
                            end
                        end
                    end
                end
                
                State.LastLog = "✅ Поставил #" .. towerIndex .. " " .. p.towerName
                return true
            end
            task.wait(Settings.PlaceDelay)
        end
        
    elseif action.type == ActionType.UPGRADE then
        local p = action.params
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if not tower or not tower.Parent then
            State.LastLog = "⚠ Башня #" .. p.towerIndex .. " не найдена"
            return true
        end
        
        local towerName = getTowerName(tower)
        local currentLevel = getTowerLevel(tower)
        local cost = getTowerUpgradeCost(towerName, currentLevel, p.path)
        
        while State.Running and not State.Paused do
            local cash = getCash()
            if cash >= cost or cost == 0 then break end
            State.LastLog = string.format("💰 Жду $%d на UPG #%d (есть $%d)", cost, p.towerIndex, cash)
            task.wait(Settings.UpgradeDelay)
        end
        
        if not State.Running then return false end
        
        State.LastLog = "⬆️ Качаю #" .. p.towerIndex .. " (path " .. p.path .. ")"
        
        while State.Running and not State.Paused do
            if doUpgrade(tower, p.path) then
                State.LastLog = "✅ Прокачал #" .. p.towerIndex
                return true
            end
            task.wait(Settings.UpgradeDelay)
        end
        
    elseif action.type == ActionType.UPGRADE_TO then
        local p = action.params
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if not tower or not tower.Parent then
            State.LastLog = "⚠ Башня #" .. p.towerIndex .. " не найдена"
            return true
        end
        
        local towerName = getTowerName(tower)
        
        while State.Running and not State.Paused do
            local currentLevel = getTowerLevel(tower)
            if currentLevel >= p.targetLevel then
                State.LastLog = "✅ #" .. p.towerIndex .. " достиг Lv" .. p.targetLevel
                return true
            end
            
            local cost = getTowerUpgradeCost(towerName, currentLevel, p.path)
            local cash = getCash()
            
            if cash >= cost and cost > 0 then
                State.LastLog = string.format("⬆️ #%d: Lv%d→%d", p.towerIndex, currentLevel, p.targetLevel)
                doUpgrade(tower, p.path)
            else
                State.LastLog = string.format("💰 Жду $%d (Lv%d→%d)", cost, currentLevel, currentLevel + 1)
            end
            
            task.wait(Settings.UpgradeDelay)
        end
        
        elseif action.type == ActionType.UPGRADE_MAX then
    local p = action.params
    local tower = Strategy.PlacedTowers[p.towerIndex]
    if not tower or not tower.Parent then
        State.LastLog = "⚠ Башня #" .. p.towerIndex .. " не найдена"
        return true
    end
    
    local towerName = getTowerName(tower)
    local maxLevel = getTowerMaxLevel(towerName)
    
    while State.Running and not State.Paused do
        local currentLevel = getTowerLevel(tower)
        
        -- Проверяем макс уровень ПЕРВЫМ ДЕЛОМ
        if currentLevel >= maxLevel then
            State.LastLog = "✅ #" .. p.towerIndex .. " MAX Lv" .. currentLevel .. "/" .. maxLevel
            return true
        end
        
        local cost = getTowerUpgradeCost(towerName, currentLevel, p.path)
        
        -- Если cost = 0 или nil - апгрейдов больше нет
        if not cost or cost <= 0 then
            State.LastLog = "✅ #" .. p.towerIndex .. " MAX Lv" .. currentLevel
            return true
        end
        
        local cash = getCash()
        
        if cash >= cost then
            State.LastLog = string.format("⬆️ MAX #%d: Lv%d→%d", p.towerIndex, currentLevel, maxLevel)
            if doUpgrade(tower, p.path) then
                task.wait(Settings.UpgradeDelay)  -- Даём время на апгрейд
            end
        else
            State.LastLog = string.format("💰 Жду $%d (Lv%d/%d)", cost, currentLevel, maxLevel)
        end
        
        task.wait(Settings.UpgradeDelay)
    end
        
    elseif action.type == ActionType.MULTI_UPGRADE then
        local p = action.params
        local fromIdx = p.fromIndex or 1
        local toIdx = math.min(p.toIndex or 99, #Strategy.PlacedTowers)
        local targetLv = p.targetLevel or 1
        local filterName = p.towerNameFilter or ""
        local path = p.path or 1
        
        State.LastLog = string.format("🔄 MULTI UPG #%d-#%d → Lv%d", fromIdx, toIdx, targetLv)
        
        local allDone = false
        while State.Running and not State.Paused and not allDone do
            allDone = true
            
            for idx = fromIdx, toIdx do
                if not State.Running or State.Paused then break end
                
                local tower = Strategy.PlacedTowers[idx]
                if tower and tower.Parent then
                    local towerName = getTowerName(tower)
                    
                    local matchesFilter = (filterName == "") or (towerName == filterName)
                    
                    if matchesFilter then
                        local currentLevel = getTowerLevel(tower)
                        
                        if currentLevel < targetLv then
                            allDone = false
                            local cost = getTowerUpgradeCost(towerName, currentLevel, path)
                            local cash = getCash()
                            
                            if cash >= cost and cost > 0 then
                                State.LastLog = string.format("🔄 #%d %s: Lv%d→%d", idx, towerName:sub(1,8), currentLevel, targetLv)
                                doUpgrade(tower, path)
                                task.wait(Settings.UpgradeDelay)
                            end
                        end
                    end
                end
            end
            
            if not allDone then
                task.wait(Settings.UpgradeDelay)
            end
        end
        
        State.LastLog = string.format("✅ MULTI UPG #%d-#%d → Lv%d готово", fromIdx, toIdx, targetLv)
        return true
        
    elseif action.type == ActionType.SELL then
        local p = action.params
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "💰 Продаю #" .. p.towerIndex
            doSell(tower)
            Strategy.PlacedTowers[p.towerIndex] = nil
        end
        return true

    elseif action.type == ActionType.SELL_AT_WAVE then
        local p = action.params
        while State.Running and not State.Paused do
            if getCurrentWave() >= (p.wave or 1) then break end
            State.LastLog = "🌊 Жду волну " .. (p.wave or 1) .. " для продажи"
            task.wait(0.5)
        end
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "💰 Продаю #" .. p.towerIndex
            doSell(tower)
            Strategy.PlacedTowers[p.towerIndex] = nil
        end
        return true
        
    elseif action.type == ActionType.SELL_ALL then
        State.LastLog = "💰 Продаю все башни..."
        for idx, tower in pairs(Strategy.PlacedTowers) do
            if tower and tower.Parent then
                doSell(tower)
                task.wait(Settings.SellDelay)
            end
        end
        Strategy.PlacedTowers = {}
        State.LastLog = "✅ Все башни проданы"
        return true

    elseif action.type == ActionType.SELL_FARMS_AT_WAVE then
        local p = action.params
        while State.Running and not State.Paused do
            if getCurrentWave() >= (p.wave or 1) then break end
            State.LastLog = "🌊 Жду волну " .. (p.wave or 1) .. " для продажи ферм"
            task.wait(0.5)
        end
        local towersFolder = workspace:FindFirstChild("Towers")
        if towersFolder then
            for _, rep in ipairs(towersFolder:GetDescendants()) do
                if rep:IsA("Folder") and rep.Name == "TowerReplicator"
                    and rep:GetAttribute("Name") == "Farm"
                    and rep:GetAttribute("OwnerId") == player.UserId then
                    doSell(rep.Parent)
                    task.wait(Settings.SellDelay)
                end
            end
        end
        State.LastLog = "✅ Фермы проданы"
        return true
        
    elseif action.type == ActionType.SET_TARGET then
        local p = action.params
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "🎯 Target #" .. p.towerIndex .. " → " .. p.targetType
            doSetTarget(tower, p.targetType)
        end
        return true

    elseif action.type == ActionType.SET_TARGET_AT_WAVE then
        local p = action.params
        while State.Running and not State.Paused do
            if getCurrentWave() >= (p.wave or 1) then break end
            State.LastLog = "🌊 Жду волну " .. (p.wave or 1) .. " для таргета"
            task.wait(0.5)
        end
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "🎯 Target #" .. p.towerIndex .. " → " .. p.targetType
            doSetTarget(tower, p.targetType)
        end
        return true
        
    elseif action.type == ActionType.ABILITY then
        local p = action.params
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "⚡ Ability #" .. p.towerIndex .. " → " .. p.abilityName
            
            local data = p.data or {}
            if data.towerToClone and type(data.towerToClone) == "number" then
                data.towerToClone = Strategy.PlacedTowers[data.towerToClone]
            end
            if data.towerTarget and type(data.towerTarget) == "number" then
                data.towerTarget = Strategy.PlacedTowers[data.towerTarget]
            end
            if data.towerPosition and type(data.towerPosition) == "table" and #data.towerPosition > 0 then
                data.towerPosition = data.towerPosition[math.random(#data.towerPosition)]
            end
            
            doAbility(tower, p.abilityName, data)
        end
        return true
        
    elseif action.type == ActionType.ABILITY_LOOP then
        local p = action.params
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "🔄 Loop Ability #" .. p.towerIndex .. " → " .. p.abilityName
            
            local loopId = p.towerIndex .. "_" .. p.abilityName
            Strategy.LoopingAbilities[loopId] = true
            
            task.spawn(function()
                while Strategy.LoopingAbilities[loopId] and State.Running do
                    if tower and tower.Parent then
                        local data = p.data or {}
                        if data.towerToClone and type(data.towerToClone) == "number" then
                            data.towerToClone = Strategy.PlacedTowers[data.towerToClone]
                        end
                        if data.towerPosition and type(data.towerPosition) == "table" and #data.towerPosition > 0 then
                            data.towerPosition = data.towerPosition[math.random(#data.towerPosition)]
                        end
                        
                        doAbility(tower, p.abilityName, data)
                    end
                    task.wait(Settings.AbilityDelay)
                end
            end)
        end
        return true
        
    elseif action.type == ActionType.SET_OPTION then
        local p = action.params
        
        if p.waveRequirement and p.waveRequirement > 0 then
            while State.Running and not State.Paused do
                if getCurrentWave() >= p.waveRequirement then break end
                State.LastLog = "🌊 Жду волну " .. p.waveRequirement .. " для опции"
                task.wait(0.5)
            end
        end
        
        local tower = Strategy.PlacedTowers[p.towerIndex]
        if tower and tower.Parent then
            State.LastLog = "⚙️ Option #" .. p.towerIndex .. ": " .. p.optionName .. " = " .. tostring(p.optionValue)
            doSetOption(tower, p.optionName, p.optionValue)
        end
        return true
        
    elseif action.type == ActionType.WAIT_WAVE then
        local p = action.params
        while State.Running and not State.Paused do
            local wave = getCurrentWave()
            if wave >= p.wave then
                State.LastLog = "✅ Волна " .. p.wave
                return true
            end
            State.LastLog = "🌊 Жду волну " .. p.wave .. " (сейчас " .. wave .. ")"
            task.wait(0.5)
        end
        
    elseif action.type == ActionType.WAIT_TIME then
        local p = action.params
        local startTime = tick()
        while State.Running and not State.Paused do
            local elapsed = tick() - startTime
            if elapsed >= p.seconds then
                return true
            end
            State.LastLog = string.format("⏱ %.1f/%d сек", elapsed, p.seconds)
            task.wait(0.1)
        end
        
    elseif action.type == ActionType.WAIT_CASH then
        local p = action.params
        while State.Running and not State.Paused do
            local cash = getCash()
            if cash >= p.amount then
                State.LastLog = "✅ Накопил $" .. p.amount
                return true
            end
            State.LastLog = string.format("💰 Коплю $%d (есть $%d)", p.amount, cash)
            task.wait(0.3)
        end

    elseif action.type == ActionType.TIME_SCALE then
        local p = action.params
        if p.unlock and isTimescaleLocked() then
            unlockTimeScale()
            task.wait(0.5)
        end
        local ok = setGameTimescale(p.value or 1)
        State.LastLog = ok and ("⏩ Speed x" .. tostring(p.value or 1)) or "⚠️ TimeScale не удалось"
        return true

    elseif action.type == ActionType.UNLOCK_TIMESCALE then
        unlockTimeScale()
        State.LastLog = "🔓 TimeScale unlocked"
        return true

    elseif action.type == ActionType.AUTO_PICKUPS_MODE then
        local p = action.params
        AutoPickupsMode = (p.mode == "Pathfinding") and "Pathfinding" or "Instant"
        State.LastLog = "🎁 Pickups: " .. AutoPickupsMode
        return true
        
    elseif action.type == ActionType.VOTE_SKIP then
        local p = action.params
        for wave = p.startWave, p.endWave do
            while State.Running and not State.Paused do
                if getCurrentWave() < wave then
                    task.wait(0.5)
                else
                    local voteUI = playerGui:FindFirstChild("ReactOverridesVote")
                    local voteBtn = voteUI and voteUI:FindFirstChild("Frame") 
                        and voteUI.Frame:FindFirstChild("votes")
                        and voteUI.Frame.votes:FindFirstChild("vote", true)
                    
                    if voteBtn and voteBtn.Position == UDim2.new(0.5, 0, 0.5, 0) then
                        doVoteSkip()
                        State.LastLog = "⏭ Скип волны " .. wave
                        break
                    end
                    
                    if getCurrentWave() > wave then break end
                    task.wait(0.5)
                end
            end
        end
        return true
        
    elseif action.type == ActionType.AUTO_CHAIN then
        local p = action.params
        if p.enabled == false then
            Strategy.AutoChainRunning = false
            State.LastLog = "🔗 Chain OFF"
            return true
        end

        local indices = p.towerIndices or {}
        if #indices < 3 then 
            State.LastLog = "⚠️ Chain нужно 3+ башни!"
            return true 
        end
        
        State.LastLog = "🔗 AutoChain запущен"
        Strategy.AutoChainRunning = true
        
        task.spawn(function()
            local idx = 1
            while Strategy.AutoChainRunning and State.Running do
                local towerIndex = indices[idx]
                local tower = Strategy.PlacedTowers[towerIndex]
                
                if tower and tower.Parent then
                    local level = getTowerLevel(tower)
                    if level >= 2 then
                        doAbility(tower, "Call Of Arms", {})
                        State.LastLog = "🔗 Chain → #" .. towerIndex
                    else
                        State.LastLog = "⚠️ #" .. towerIndex .. " нужен Lv2+"
                    end
                end
                
                local waitTime = isTimescaleLocked() and 10.5 or 5.5
                task.wait(waitTime)
                
                idx = idx + 1
                if idx > #indices then idx = 1 end
            end
        end)
        
        return true

    elseif action.type == ActionType.AUTO_CHAIN_CARAVAN then
        local p = action.params
        if #p.towerIndices < 3 then
            State.LastLog = "⚠️ Chain нужно 3+ башни!"
            return true
        end
        State.LastLog = "🚚 Chain+Caravan запущен"
        startActionAutoChainCaravan(p.towerIndices)
        return true

    elseif action.type == ActionType.AUTO_DJ then
        local p = action.params
        if p.enabled == false then
            Strategy.ActionAutoDJRunning = false
            State.LastLog = "🎵 Auto DJ выключен"
        else
            State.LastLog = "🎵 Auto DJ включен"
            startActionAutoDJ()
        end
        return true

    elseif action.type == ActionType.AUTO_NECRO then
        local p = action.params
        if p.enabled == false then
            Strategy.ActionAutoNecroRunning = false
            State.LastLog = "💀 Auto Necro выключен"
        else
            State.LastLog = "💀 Auto Necro включен"
            startActionAutoNecro()
        end
        return true

    elseif action.type == ActionType.AUTO_MERCENARY then
        local p = action.params
        if p.enabled == false then
            Strategy.ActionAutoMercenaryRunning = false
            State.LastLog = "🪂 Auto Mercenary выключен"
        else
            State.LastLog = "🪂 Auto Mercenary: " .. tostring(p.distance or 195)
            startActionAutoMercenary(p.distance or 195)
        end
        return true

    elseif action.type == ActionType.AUTO_MILITARY then
        local p = action.params
        if p.enabled == false then
            Strategy.ActionAutoMilitaryRunning = false
            State.LastLog = "💥 Auto Military выключен"
        else
            State.LastLog = "💥 Auto Military: " .. tostring(p.distance or 195)
            startActionAutoMilitary(p.distance or 195)
        end
        return true
        
    -- НОВОЕ: Выполнение Loadout
    elseif action.type == ActionType.LOADOUT then
        local p = action.params
        State.LastLog = "📦 Меняю loadout: " .. table.concat(p.towers, ", ")
        doLoadout(p.towers)
        State.LastLog = "✅ Loadout изменён"
        return true
    end
    
    return false
end

local function stopAllLoops()
    for k in pairs(Strategy.LoopingAbilities) do
        Strategy.LoopingAbilities[k] = nil
    end
    Strategy.AutoChainRunning = false
    Strategy.ActionAutoChainCaravanRunning = false
    Strategy.ActionAutoDJRunning = false
    Strategy.ActionAutoNecroRunning = false
    Strategy.ActionAutoMercenaryRunning = false
    Strategy.ActionAutoMilitaryRunning = false
end

local function runStrategy()
    State.Running = true
    State.Paused = false
    Strategy.CurrentAction = 1
    Strategy.PlacedTowers = {}
    stopAllLoops()
    
    while State.Running and Strategy.CurrentAction <= #Strategy.Actions do
        if State.Paused then
            task.wait(0.1)
        else
            local action = Strategy.Actions[Strategy.CurrentAction]
            local success = executeAction(action)
            
            if success then
                Strategy.CurrentAction = Strategy.CurrentAction + 1
            end
            
            task.wait(Settings.ActionDelay)
        end
    end
    
    if Strategy.CurrentAction > #Strategy.Actions then
        State.LastLog = "🎉 Стратегия завершена!"
        if Settings.AutoRestart then
            Strategy.CurrentAction = 1
            Strategy.PlacedTowers = {}
            stopAllLoops()
            State.LastLog = "🔄 Перезапуск..."
        else
            State.Running = false
        end
    end
end

-- ========== ГЕНЕРАЦИЯ КОДА ==========

local function generateCode()
    local code = "-- Generated Strategy: " .. Strategy.Name .. "\n"
    code = code .. "-- Actions: " .. #Strategy.Actions .. "\n\n"
    
    local placeCount = 0
    
    for _, action in ipairs(Strategy.Actions) do
        local t = action.type
        local p = action.params
        
        if t == ActionType.PLACE then
            placeCount = placeCount + 1
            code = code .. string.format('TDS:Place("%s", %.2f, %.2f, %.2f) -- #%d\n',
                p.towerName, p.position.X, p.position.Y, p.position.Z, placeCount)
                
        elseif t == ActionType.UPGRADE then
            if p.path == 2 then
                code = code .. string.format('TDS:Upgrade(%d, 2)\n', p.towerIndex)
            else
                code = code .. string.format('TDS:Upgrade(%d)\n', p.towerIndex)
            end
            
        elseif t == ActionType.UPGRADE_TO then
            for _ = 1, p.targetLevel do
                if p.path == 2 then
                    code = code .. string.format('TDS:Upgrade(%d, 2)\n', p.towerIndex)
                else
                    code = code .. string.format('TDS:Upgrade(%d)\n', p.towerIndex)
                end
            end
            
        elseif t == ActionType.UPGRADE_MAX then
            code = code .. string.format('-- Upgrade #%d to MAX\nfor i = 1, 10 do TDS:Upgrade(%d%s) end\n', 
                p.towerIndex, p.towerIndex, p.path == 2 and ", 2" or "")
                
        elseif t == ActionType.MULTI_UPGRADE then
            code = code .. string.format('-- MULTI UPGRADE #%d-#%d to Lv%d%s%s\n',
                p.fromIndex, p.toIndex, p.targetLevel,
                p.towerNameFilter ~= "" and (' filter="' .. p.towerNameFilter .. '"') or "",
                p.path == 2 and " path=2" or "")
            
        elseif t == ActionType.SELL then
            code = code .. string.format('TDS:Sell(%d)\n', p.towerIndex)
            
        elseif t == ActionType.SELL_ALL then
            code = code .. 'TDS:SellAll()\n'
            
        elseif t == ActionType.SET_TARGET then
            code = code .. string.format('TDS:SetTarget(%d, "%s")\n', p.towerIndex, p.targetType)
        elseif t == ActionType.SET_TARGET_AT_WAVE then
            code = code .. string.format('TDS:SetTarget(%d, "%s", %d)\n',
                p.towerIndex, p.targetType, p.wave or 1)
            
        elseif t == ActionType.ABILITY then
            code = code .. string.format('TDS:Ability(%d, "%s")\n', p.towerIndex, p.abilityName)
            
        elseif t == ActionType.ABILITY_LOOP then
            code = code .. string.format('TDS:Ability(%d, "%s", {}, true) -- loop\n', p.towerIndex, p.abilityName)
            
        elseif t == ActionType.SET_OPTION then
            if p.waveRequirement and p.waveRequirement > 0 then
                code = code .. string.format('TDS:SetOption(%d, "%s", "%s", %d)\n', 
                    p.towerIndex, p.optionName, tostring(p.optionValue), p.waveRequirement)
            else
                code = code .. string.format('TDS:SetOption(%d, "%s", "%s")\n', 
                    p.towerIndex, p.optionName, tostring(p.optionValue))
            end
            
        elseif t == ActionType.WAIT_WAVE then
            code = code .. string.format('-- Wait for wave %d\n', p.wave)
            
        elseif t == ActionType.WAIT_TIME then
            code = code .. string.format('task.wait(%d)\n', p.seconds)
            
        elseif t == ActionType.WAIT_CASH then
            code = code .. string.format('-- Wait for $%d\n', p.amount)
            
        elseif t == ActionType.VOTE_SKIP then
            code = code .. string.format('TDS:VoteSkip(%d, %d)\n', p.startWave, p.endWave)
            
        elseif t == ActionType.AUTO_CHAIN then
            if p.enabled == false then
                code = code .. '-- Auto Chain OFF\n'
            else
                code = code .. string.format('TDS:AutoChain(%s)\n', table.concat(p.towerIndices or {}, ", "))
            end
            
        elseif t == ActionType.AUTO_CHAIN_CARAVAN then
            code = code .. string.format('-- Auto Chain + Caravan: %s\n', table.concat(p.towerIndices, ", "))
            
        elseif t == ActionType.AUTO_DJ then
            code = code .. string.format('-- Auto DJ: %s\n', p.enabled == false and "OFF" or "ON")
            
        elseif t == ActionType.AUTO_NECRO then
            code = code .. string.format('-- Auto Necro: %s\n', p.enabled == false and "OFF" or "ON")
            
        elseif t == ActionType.AUTO_MERCENARY then
            code = code .. string.format('-- Auto Mercenary: %s\n', p.enabled == false and "OFF" or ("dist=" .. tostring(p.distance or 195)))
            
        elseif t == ActionType.AUTO_MILITARY then
            code = code .. string.format('-- Auto Military: %s\n', p.enabled == false and "OFF" or ("dist=" .. tostring(p.distance or 195)))
            
        elseif t == ActionType.TIME_SCALE then
            if p.unlock then
                code = code .. 'TDS:UnlockTimeScale()\n'
            end
            code = code .. string.format('TDS:TimeScale(%s)\n', tostring(p.value or 1))
            
        elseif t == ActionType.UNLOCK_TIMESCALE then
            code = code .. 'TDS:UnlockTimeScale()\n'
            
        elseif t == ActionType.SELL_AT_WAVE then
            code = code .. string.format('TDS:Sell(%d, %d)\n', p.towerIndex, p.wave or 1)
            
        elseif t == ActionType.SELL_FARMS_AT_WAVE then
            code = code .. string.format('-- Sell Farms at wave %d\n', p.wave or 1)
            
        elseif t == ActionType.AUTO_PICKUPS_MODE then
            code = code .. string.format('-- Pickups Mode: %s\n', tostring(p.mode or "Instant"))
            
        elseif t == ActionType.LOADOUT then
            code = code .. string.format('TDS:Loadout("%s")\n', table.concat(p.towers, '", "'))
        end
    end
    
    return code
end

local function exportStrategy()
    local data = { name = Strategy.Name, actions = {} }
    
    for _, action in ipairs(Strategy.Actions) do
        local actionData = { type = action.type, params = {} }
        
        if action.type == ActionType.PLACE then
            actionData.params.towerName = action.params.towerName
            actionData.params.x = action.params.position.X
            actionData.params.y = action.params.position.Y
            actionData.params.z = action.params.position.Z
        elseif action.type == ActionType.LOADOUT then
            actionData.params.towers = action.params.towers
        else
            for k, v in pairs(action.params) do
                actionData.params[k] = v
            end
        end
        
        table.insert(data.actions, actionData)
    end
    
    return HttpService:JSONEncode(data)
end

local function importStrategy(jsonString)
    local success, data = pcall(function() return HttpService:JSONDecode(jsonString) end)
    
    if success and data then
        Strategy.Name = data.name or "Imported"
        Strategy.Actions = {}
        
        for _, actionData in ipairs(data.actions or {}) do
            local params = {}
            for k, v in pairs(actionData.params or {}) do
                params[k] = v
            end
            
            if actionData.type == ActionType.PLACE then
                params.position = Vector3.new(params.x or 0, params.y or 0, params.z or 0)
                params.x, params.y, params.z = nil, nil, nil
            end
            
            table.insert(Strategy.Actions, {
                type = actionData.type,
                params = params,
                id = HttpService:GenerateGUID(false)
            })
        end
        return true
    end
    return false
end

-- ========== UI ==========

if playerGui:FindFirstChild("StrategyBuilderUI") then
    playerGui:FindFirstChild("StrategyBuilderUI"):Destroy()
end

UI.ScreenGui = Instance.new("ScreenGui")
UI.ScreenGui.Name = "StrategyBuilderUI"
UI.ScreenGui.ResetOnSpawn = false
UI.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
UI.ScreenGui.Parent = playerGui

UI.MainFrame = Instance.new("Frame")
UI.MainFrame.Size = UDim2.new(0, 520, 0, 720)
UI.MainFrame.Position = UDim2.new(1, -530, 0.5, -360)
UI.MainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
UI.MainFrame.BorderSizePixel = 0
UI.MainFrame.Visible = false
UI.MainFrame.Parent = UI.ScreenGui

Instance.new("UICorner", UI.MainFrame).CornerRadius = UDim.new(0, 10)
UI.MainStroke = Instance.new("UIStroke", UI.MainFrame)
UI.MainStroke.Color = Color3.fromRGB(255, 130, 70)
UI.MainStroke.Thickness = 1
UI.MainStroke.Transparency = 0.15

-- UI.Header
UI.Header = Instance.new("Frame")
UI.Header.Size = UDim2.new(1, 0, 0, 38)
UI.Header.BackgroundColor3 = Color3.fromRGB(255, 110, 70)
UI.Header.BorderSizePixel = 0
UI.Header.Parent = UI.MainFrame
Instance.new("UICorner", UI.Header).CornerRadius = UDim.new(0, 10)
UI.HeaderGradient = Instance.new("UIGradient", UI.Header)
UI.HeaderGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 95, 60)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 95)),
})

UI.Title = Instance.new("TextLabel")
UI.Title.Size = UDim2.new(1, -42, 1, 0)
UI.Title.Position = UDim2.new(0, 10, 0, 0)
UI.Title.BackgroundTransparency = 1
UI.Title.Text = tr("title")
UI.Title.TextColor3 = Color3.new(1, 1, 1)
UI.Title.TextSize = 14
UI.Title.Font = Enum.Font.GothamSemibold
UI.Title.TextXAlignment = Enum.TextXAlignment.Left
UI.Title.Parent = UI.Header

UI.CloseBtn = Instance.new("TextButton")
UI.CloseBtn.Size = UDim2.new(0, 28, 0, 28)
UI.CloseBtn.Position = UDim2.new(1, -32, 0, 5)
UI.CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
UI.CloseBtn.Text = "X"
UI.CloseBtn.TextColor3 = Color3.new(1, 1, 1)
UI.CloseBtn.TextSize = 16
UI.CloseBtn.Font = Enum.Font.GothamBold
UI.CloseBtn.Parent = UI.Header
Instance.new("UICorner", UI.CloseBtn).CornerRadius = UDim.new(0, 6)

UI.LangBtn = Instance.new("TextButton")
UI.LangBtn.Size = UDim2.new(0, 48, 0, 22)
UI.LangBtn.Position = UDim2.new(1, -86, 0, 8)
UI.LangBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
UI.LangBtn.Text = tr("lang_button")
UI.LangBtn.TextColor3 = Color3.new(1, 1, 1)
UI.LangBtn.TextSize = 10
UI.LangBtn.Font = Enum.Font.GothamBold
UI.LangBtn.Parent = UI.Header
Instance.new("UICorner", UI.LangBtn).CornerRadius = UDim.new(0, 6)

-- UI.Content
UI.Content = Instance.new("ScrollingFrame")
UI.Content.Size = UDim2.new(1, -14, 1, -46)
UI.Content.Position = UDim2.new(0, 7, 0, 40)
UI.Content.BackgroundTransparency = 1
UI.Content.ScrollBarThickness = 4
UI.Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.Content.Parent = UI.MainFrame

UI.ContentLayout = Instance.new("UIListLayout", UI.Content)
UI.ContentLayout.Padding = UDim.new(0, 4)

-- ========== STATUS ==========
UI.StatusSection = Instance.new("Frame")
UI.StatusSection.Size = UDim2.new(1, 0, 0, 54)
UI.StatusSection.BackgroundColor3 = Color3.fromRGB(25, 30, 25)
UI.StatusSection.Parent = UI.Content
Instance.new("UICorner", UI.StatusSection).CornerRadius = UDim.new(0, 8)

UI.StatusLabel = Instance.new("TextLabel")
UI.StatusLabel.Size = UDim2.new(1, -10, 1, -6)
UI.StatusLabel.Position = UDim2.new(0, 5, 0, 3)
UI.StatusLabel.BackgroundTransparency = 1
UI.StatusLabel.Text = tr("status_ready")
UI.StatusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
UI.StatusLabel.TextSize = 9
UI.StatusLabel.Font = Enum.Font.Gotham
UI.StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
UI.StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
UI.StatusLabel.TextWrapped = true
UI.StatusLabel.Parent = UI.StatusSection

-- ========== CONTROLS ==========
UI.ControlSection = Instance.new("Frame")
UI.ControlSection.Size = UDim2.new(1, 0, 0, 56)
UI.ControlSection.BackgroundTransparency = 1
UI.ControlSection.Parent = UI.Content

UI.StartBtn = Instance.new("TextButton")
UI.StartBtn.Size = UDim2.new(0.32, -2, 1, 0)
UI.StartBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
UI.StartBtn.Text = tr("start")
UI.StartBtn.TextColor3 = Color3.new(1, 1, 1)
UI.StartBtn.TextSize = 11
UI.StartBtn.Font = Enum.Font.GothamBold
UI.StartBtn.Parent = UI.ControlSection
Instance.new("UICorner", UI.StartBtn).CornerRadius = UDim.new(0, 6)

UI.PauseBtn = Instance.new("TextButton")
UI.PauseBtn.Size = UDim2.new(0.32, -2, 1, 0)
UI.PauseBtn.Position = UDim2.new(0.33, 0, 0, 0)
UI.PauseBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
UI.PauseBtn.Text = tr("pause")
UI.PauseBtn.TextColor3 = Color3.new(1, 1, 1)
UI.PauseBtn.TextSize = 11
UI.PauseBtn.Font = Enum.Font.GothamBold
UI.PauseBtn.Parent = UI.ControlSection
Instance.new("UICorner", UI.PauseBtn).CornerRadius = UDim.new(0, 6)

UI.StopBtn = Instance.new("TextButton")
UI.StopBtn.Size = UDim2.new(0.32, -2, 1, 0)
UI.StopBtn.Position = UDim2.new(0.66, 0, 0, 0)
UI.StopBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
UI.StopBtn.Text = tr("stop")
UI.StopBtn.TextColor3 = Color3.new(1, 1, 1)
UI.StopBtn.TextSize = 11
UI.StopBtn.Font = Enum.Font.GothamBold
UI.StopBtn.Parent = UI.ControlSection
Instance.new("UICorner", UI.StopBtn).CornerRadius = UDim.new(0, 6)

-- ========== GLOBAL AUTO TOGGLES ==========
UI.GlobalSection = Instance.new("Frame")
UI.GlobalSection.Size = UDim2.new(1, 0, 0, 64)
UI.GlobalSection.BackgroundColor3 = Color3.fromRGB(30, 25, 35)
UI.GlobalSection.Parent = UI.Content
Instance.new("UICorner", UI.GlobalSection).CornerRadius = UDim.new(0, 8)

UI.GlobalChainBtn = Instance.new("TextButton")
UI.GlobalChainBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.GlobalChainBtn.Position = UDim2.new(0, 5, 0, 4)
UI.GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 60)
UI.GlobalChainBtn.Text = tr("global_chain_off")
UI.GlobalChainBtn.TextColor3 = Color3.new(1, 1, 1)
UI.GlobalChainBtn.TextSize = 9
UI.GlobalChainBtn.Font = Enum.Font.GothamBold
UI.GlobalChainBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.GlobalChainBtn).CornerRadius = UDim.new(0, 5)

UI.GlobalDJBtn = Instance.new("TextButton")
UI.GlobalDJBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.GlobalDJBtn.Position = UDim2.new(0.5, 0, 0, 4)
UI.GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 80)
UI.GlobalDJBtn.Text = tr("global_dj_off")
UI.GlobalDJBtn.TextColor3 = Color3.new(1, 1, 1)
UI.GlobalDJBtn.TextSize = 9
UI.GlobalDJBtn.Font = Enum.Font.GothamBold
UI.GlobalDJBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.GlobalDJBtn).CornerRadius = UDim.new(0, 5)

-- НОВОЕ: AUTO SKIP кнопка по центру снизу
UI.GlobalSkipBtn = Instance.new("TextButton")
UI.GlobalSkipBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.GlobalSkipBtn.Position = UDim2.new(0.5, 0, 0, 32)
UI.GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 60)
UI.GlobalSkipBtn.Text = tr("global_skip_off")
UI.GlobalSkipBtn.TextColor3 = Color3.new(1, 1, 1)
UI.GlobalSkipBtn.TextSize = 9
UI.GlobalSkipBtn.Font = Enum.Font.GothamBold
UI.GlobalSkipBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.GlobalSkipBtn).CornerRadius = UDim.new(0, 5)

-- ========== TOWER SELECT ==========
UI.TowerSection = Instance.new("Frame")
UI.TowerSection.Size = UDim2.new(1, 0, 0, 68)
UI.TowerSection.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
UI.TowerSection.Parent = UI.Content
Instance.new("UICorner", UI.TowerSection).CornerRadius = UDim.new(0, 8)

UI.TowerTitle = Instance.new("TextLabel")
UI.TowerTitle.Size = UDim2.new(1, -10, 0, 12)
UI.TowerTitle.Position = UDim2.new(0, 5, 0, 2)
UI.TowerTitle.BackgroundTransparency = 1
UI.TowerTitle.Text = tr("tower_default", State.SelectedTower or "Scout")
UI.TowerTitle.TextColor3 = Color3.fromRGB(255, 180, 100)
UI.TowerTitle.TextSize = 9
UI.TowerTitle.Font = Enum.Font.GothamBold
UI.TowerTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.TowerTitle.Parent = UI.TowerSection

UI.TowerScroll = Instance.new("ScrollingFrame")
UI.TowerScroll.Size = UDim2.new(1, -10, 0, 46)
UI.TowerScroll.Position = UDim2.new(0, 5, 0, 16)
UI.TowerScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
UI.TowerScroll.ScrollBarThickness = 3
UI.TowerScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
UI.TowerScroll.ScrollingDirection = Enum.ScrollingDirection.X
UI.TowerScroll.Parent = UI.TowerSection
Instance.new("UICorner", UI.TowerScroll).CornerRadius = UDim.new(0, 5)

UI.TowerLayout = Instance.new("UIListLayout", UI.TowerScroll)
UI.TowerLayout.FillDirection = Enum.FillDirection.Horizontal
UI.TowerLayout.Padding = UDim.new(0, 2)
Instance.new("UIPadding", UI.TowerScroll).PaddingLeft = UDim.new(0, 3)

-- ========== ALL ACTIONS ==========
UI.AddSection = Instance.new("Frame")
UI.AddSection.Size = UDim2.new(1, 0, 0, 280)
UI.AddSection.BackgroundColor3 = Color3.fromRGB(30, 25, 40)
UI.AddSection.Parent = UI.Content
Instance.new("UICorner", UI.AddSection).CornerRadius = UDim.new(0, 8)

UI.AddTitle = Instance.new("TextLabel")
UI.AddTitle.Size = UDim2.new(1, -10, 0, 12)
UI.AddTitle.Position = UDim2.new(0, 5, 0, 2)
UI.AddTitle.BackgroundTransparency = 1
UI.AddTitle.Text = tr("all_actions")
UI.AddTitle.TextColor3 = Color3.fromRGB(200, 150, 255)
UI.AddTitle.TextSize = 9
UI.AddTitle.Font = Enum.Font.GothamBold
UI.AddTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.AddTitle.Parent = UI.AddSection

local actionButtons = {
    -- Ряд 1
    {name = "PLACE", text = "🏗PLACE", color = Color3.fromRGB(0, 150, 80), row = 0, col = 0},
    {name = "UPGRADE", text = "⬆️UPG", color = Color3.fromRGB(80, 120, 200), row = 0, col = 1},
    {name = "UPGRADE_TO", text = "⬆️→Lv", color = Color3.fromRGB(60, 100, 180), row = 0, col = 2},
    {name = "UPGRADE_MAX", text = "⬆️MAX", color = Color3.fromRGB(40, 80, 160), row = 0, col = 3},
    {name = "UPG_PATH2", text = "⬆️P2", color = Color3.fromRGB(100, 60, 160), row = 0, col = 4},
    -- Ряд 2
    {name = "MULTI_UPG", text = "🔄MULTI", color = Color3.fromRGB(150, 100, 50), row = 1, col = 0},
    {name = "SELL", text = "💰SELL", color = Color3.fromRGB(200, 80, 80), row = 1, col = 1},
    {name = "SELL_ALL", text = "💰ALL", color = Color3.fromRGB(180, 60, 60), row = 1, col = 2},
    {name = "SET_TARGET", text = "🎯TGT", color = Color3.fromRGB(200, 150, 50), row = 1, col = 3},
    {name = "ABILITY", text = "⚡ABL", color = Color3.fromRGB(150, 100, 200), row = 1, col = 4},
    -- Ряд 3
    {name = "ABILITY_LOOP", text = "🔄LOOP", color = Color3.fromRGB(130, 80, 180), row = 2, col = 0},
    {name = "SET_OPTION", text = "⚙️OPT", color = Color3.fromRGB(100, 130, 150), row = 2, col = 1},
    {name = "WAIT_WAVE", text = "🌊WAVE", color = Color3.fromRGB(100, 150, 200), row = 2, col = 2},
    {name = "WAIT_TIME", text = "⏱TIME", color = Color3.fromRGB(150, 150, 100), row = 2, col = 3},
    {name = "WAIT_CASH", text = "💵CASH", color = Color3.fromRGB(100, 180, 100), row = 2, col = 4},
    -- Ряд 4
    {name = "VOTE_SKIP", text = "⏭SKIP", color = Color3.fromRGB(180, 120, 80), row = 3, col = 0},
    {name = "AUTO_CHAIN", text = "🔗CHAIN", color = Color3.fromRGB(200, 100, 100), row = 3, col = 1},
    {name = "LOADOUT", text = "📦LOAD", color = Color3.fromRGB(100, 150, 180), row = 3, col = 2},
    {name = "AUTO_CHAIN_OFF", text = "🔗OFF", color = Color3.fromRGB(120, 70, 70), row = 3, col = 3},
    {name = "CLEAR", text = "🗑CLEAR", color = Color3.fromRGB(100, 50, 50), row = 3, col = 4},
    -- Ряд 5
    {name = "TIME_SCALE", text = "⏩SPEED", color = Color3.fromRGB(80, 120, 140), row = 4, col = 0},
    {name = "UNLOCK_TS", text = "🔓TS", color = Color3.fromRGB(80, 110, 120), row = 4, col = 1},
    {name = "SET_TGT_W", text = "🎯@W", color = Color3.fromRGB(140, 120, 60), row = 4, col = 2},
    {name = "SELL_AT_W", text = "💰@W", color = Color3.fromRGB(160, 80, 80), row = 4, col = 3},
    {name = "SELL_FARMS", text = "🌾SELL", color = Color3.fromRGB(120, 90, 70), row = 4, col = 4},
    -- Ряд 6
    {name = "AUTO_DJ", text = "🎵DJ", color = Color3.fromRGB(120, 60, 150), row = 5, col = 0},
    {name = "CHAIN_CAR", text = "🚚CAR", color = Color3.fromRGB(150, 80, 80), row = 5, col = 1},
    {name = "AUTO_NECRO", text = "💀NEC", color = Color3.fromRGB(120, 80, 80), row = 5, col = 2},
    {name = "AUTO_MERC", text = "🪂MERC", color = Color3.fromRGB(80, 120, 100), row = 5, col = 3},
    {name = "AUTO_MIL", text = "💥MIL", color = Color3.fromRGB(120, 90, 100), row = 5, col = 4},
    -- Ряд 7
    {name = "PICKUP_MODE", text = "🎁MODE", color = Color3.fromRGB(80, 120, 120), row = 6, col = 0},
    {name = "AUTO_DJ_OFF", text = "🎵OFF", color = Color3.fromRGB(70, 50, 90), row = 6, col = 1},
    {name = "AUTO_NECRO_OFF", text = "💀OFF", color = Color3.fromRGB(80, 60, 60), row = 6, col = 2},
    {name = "AUTO_MERC_OFF", text = "🪂OFF", color = Color3.fromRGB(60, 80, 70), row = 6, col = 3},
    {name = "AUTO_MIL_OFF", text = "💥OFF", color = Color3.fromRGB(80, 70, 80), row = 6, col = 4},
}

local ActionBtns = {}
local btnWidth = 0.19
local btnHeight = 20
local startY = 16

for _, data in ipairs(actionButtons) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(btnWidth, -2, 0, btnHeight)
    btn.Position = UDim2.new(data.col * (btnWidth + 0.01), 5, 0, startY + data.row * (btnHeight + 3))
    btn.BackgroundColor3 = data.color
    btn.Text = data.text
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 8
    btn.Font = Enum.Font.GothamBold
    btn.Name = data.name
    btn.Parent = UI.AddSection
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    ActionBtns[data.name] = btn
end

-- Input Fields
local maxRow = 0
for _, data in ipairs(actionButtons) do
    if data.row > maxRow then
        maxRow = data.row
    end
end
local inputY = startY + (maxRow + 1) * (btnHeight + 3) + 4

local function createInputField(labelText, placeholder, yOffset, width, xOffset)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(width or 0.48, -3, 0, 20)
    frame.Position = UDim2.new(xOffset or 0, 5, 0, yOffset)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    frame.Parent = UI.AddSection
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 40, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = " " .. labelText
    lbl.TextColor3 = Color3.fromRGB(150, 150, 150)
    lbl.TextSize = 7
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame
    
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -42, 1, -4)
    box.Position = UDim2.new(0, 40, 0, 2)
    box.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    box.Text = ""
    box.PlaceholderText = placeholder
    box.TextColor3 = Color3.new(1, 1, 1)
    box.TextSize = 9
    box.Font = Enum.Font.Gotham
    box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    
    return box
end

UI.InputBox1 = createInputField("От#", "1", inputY, 0.19, 0)
UI.InputBox2 = createInputField("До#", "6", inputY, 0.19, 0.20)
UI.InputBox3 = createInputField("Lv", "3", inputY, 0.19, 0.40)
UI.InputBox4 = createInputField("Wave", "1", inputY, 0.19, 0.60)
UI.InputBox5 = createInputField("$", "1000", inputY, 0.19, 0.80)

UI.InputBox1.Text = "1"
UI.InputBox2.Text = "6"
UI.InputBox3.Text = "3"
UI.InputBox4.Text = "1"
UI.InputBox5.Text = "1000"

UI.InputBoxText = createInputField("Text", "Tower/Ability/Target", inputY + 22, 0.65, 0)
UI.InputBoxPath = createInputField("Path", "1", inputY + 22, 0.33, 0.66)
UI.InputBoxPath.Text = "1"

-- НОВОЕ: Поле для Loadout
UI.InputBoxLoadout = createInputField("Loadout", "Scout,Sniper,Demoman", inputY + 44, 0.98, 0)

-- ========== SAVE/LOAD SECTION ==========
UI.SaveLoadSection = Instance.new("Frame")
UI.SaveLoadSection.Size = UDim2.new(1, 0, 0, 62)
UI.SaveLoadSection.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
UI.SaveLoadSection.Parent = UI.Content
Instance.new("UICorner", UI.SaveLoadSection).CornerRadius = UDim.new(0, 8)

UI.SaveLoadTitle = Instance.new("TextLabel")
UI.SaveLoadTitle.Size = UDim2.new(1, -10, 0, 12)
UI.SaveLoadTitle.Position = UDim2.new(0, 5, 0, 2)
UI.SaveLoadTitle.BackgroundTransparency = 1
UI.SaveLoadTitle.Text = tr("save_load")
UI.SaveLoadTitle.TextColor3 = Color3.fromRGB(100, 200, 255)
UI.SaveLoadTitle.TextSize = 9
UI.SaveLoadTitle.Font = Enum.Font.GothamBold
UI.SaveLoadTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.SaveLoadTitle.Parent = UI.SaveLoadSection

UI.ConfigNameBox = Instance.new("TextBox")
UI.ConfigNameBox.Size = UDim2.new(0.55, -8, 0, 20)
UI.ConfigNameBox.Position = UDim2.new(0, 5, 0, 16)
UI.ConfigNameBox.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
UI.ConfigNameBox.Text = ""
UI.ConfigNameBox.PlaceholderText = tr("config_placeholder")
UI.ConfigNameBox.TextColor3 = Color3.new(1, 1, 1)
UI.ConfigNameBox.TextSize = 9
UI.ConfigNameBox.Font = Enum.Font.Gotham
UI.ConfigNameBox.Parent = UI.SaveLoadSection
Instance.new("UICorner", UI.ConfigNameBox).CornerRadius = UDim.new(0, 5)

UI.SaveBtn = Instance.new("TextButton")
UI.SaveBtn.Size = UDim2.new(0.22, -3, 0, 20)
UI.SaveBtn.Position = UDim2.new(0.55, 0, 0, 16)
UI.SaveBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
UI.SaveBtn.Text = "💾 SAVE"
UI.SaveBtn.TextColor3 = Color3.new(1, 1, 1)
UI.SaveBtn.TextSize = 9
UI.SaveBtn.Font = Enum.Font.GothamBold
UI.SaveBtn.Parent = UI.SaveLoadSection
Instance.new("UICorner", UI.SaveBtn).CornerRadius = UDim.new(0, 5)

UI.RefreshBtn = Instance.new("TextButton")
UI.RefreshBtn.Size = UDim2.new(0.22, -3, 0, 20)
UI.RefreshBtn.Position = UDim2.new(0.77, 0, 0, 16)
UI.RefreshBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 140)
UI.RefreshBtn.Text = "🔄"
UI.RefreshBtn.TextColor3 = Color3.new(1, 1, 1)
UI.RefreshBtn.TextSize = 11
UI.RefreshBtn.Font = Enum.Font.GothamBold
UI.RefreshBtn.Parent = UI.SaveLoadSection
Instance.new("UICorner", UI.RefreshBtn).CornerRadius = UDim.new(0, 5)

UI.ConfigScroll = Instance.new("ScrollingFrame")
UI.ConfigScroll.Size = UDim2.new(1, -10, 0, 22)
UI.ConfigScroll.Position = UDim2.new(0, 5, 0, 38)
UI.ConfigScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
UI.ConfigScroll.ScrollBarThickness = 3
UI.ConfigScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
UI.ConfigScroll.ScrollingDirection = Enum.ScrollingDirection.X
UI.ConfigScroll.Parent = UI.SaveLoadSection
Instance.new("UICorner", UI.ConfigScroll).CornerRadius = UDim.new(0, 5)

UI.ConfigLayout = Instance.new("UIListLayout", UI.ConfigScroll)
UI.ConfigLayout.FillDirection = Enum.FillDirection.Horizontal
UI.ConfigLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", UI.ConfigScroll).PaddingLeft = UDim.new(0, 3)

-- Forward declarations for UI update functions
local updateActionsDisplay
local updateMarkers
local updateConfigList

updateConfigList = function()
    for _, child in pairs(UI.ConfigScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local files = getStrategyFiles()
    
    for _, fileName in ipairs(files) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 80, 0, 20)
        btn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        btn.Text = "📁 " .. fileName:sub(1, 10)
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.TextSize = 8
        btn.Font = Enum.Font.GothamBold
        btn.Parent = UI.ConfigScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        btn.MouseButton1Click:Connect(function()
            local success, msg = safeLoadStrategy(fileName)
            State.LastLog = msg
            if success then
                UI.ConfigNameBox.Text = fileName
                -- ФИКС: Обновляем UI сразу после загрузки
                updateActionsDisplay()
                updateMarkers()
            end
        end)
        
        btn.MouseButton2Click:Connect(function()
            local success, msg = deleteStrategy(fileName)
            State.LastLog = msg
            updateConfigList()
        end)
    end
end

-- ========== ACTIONS LIST ==========
UI.ActionsSection = Instance.new("Frame")
UI.ActionsSection.Size = UDim2.new(1, 0, 0, 150)
UI.ActionsSection.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
UI.ActionsSection.Parent = UI.Content
Instance.new("UICorner", UI.ActionsSection).CornerRadius = UDim.new(0, 8)

UI.ActionsTitle = Instance.new("TextLabel")
UI.ActionsTitle.Size = UDim2.new(1, -10, 0, 12)
UI.ActionsTitle.Position = UDim2.new(0, 5, 0, 2)
UI.ActionsTitle.BackgroundTransparency = 1
UI.ActionsTitle.Text = tr("actions_queue", 0)
UI.ActionsTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
UI.ActionsTitle.TextSize = 9
UI.ActionsTitle.Font = Enum.Font.GothamBold
UI.ActionsTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.ActionsTitle.Parent = UI.ActionsSection

UI.ActionsScroll = Instance.new("ScrollingFrame")
UI.ActionsScroll.Size = UDim2.new(1, -10, 1, -20)
UI.ActionsScroll.Position = UDim2.new(0, 5, 0, 18)
UI.ActionsScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
UI.ActionsScroll.ScrollBarThickness = 3
UI.ActionsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
UI.ActionsScroll.Parent = UI.ActionsSection
Instance.new("UICorner", UI.ActionsScroll).CornerRadius = UDim.new(0, 5)

UI.ActionsListLayout = Instance.new("UIListLayout", UI.ActionsScroll)
UI.ActionsListLayout.Padding = UDim.new(0, 2)
Instance.new("UIPadding", UI.ActionsScroll).PaddingTop = UDim.new(0, 2)

-- ========== DELAY SETTINGS ==========
UI.DelaySection = Instance.new("Frame")
UI.DelaySection.Size = UDim2.new(1, 0, 0, 84)
UI.DelaySection.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
UI.DelaySection.Parent = UI.Content
Instance.new("UICorner", UI.DelaySection).CornerRadius = UDim.new(0, 8)

UI.DelayTitle = Instance.new("TextLabel")
UI.DelayTitle.Size = UDim2.new(1, -10, 0, 12)
UI.DelayTitle.Position = UDim2.new(0, 5, 0, 2)
UI.DelayTitle.BackgroundTransparency = 1
UI.DelayTitle.Text = tr("delay_section")
UI.DelayTitle.TextColor3 = Color3.fromRGB(200, 220, 255)
UI.DelayTitle.TextSize = 9
UI.DelayTitle.Font = Enum.Font.GothamBold
UI.DelayTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.DelayTitle.Parent = UI.DelaySection

local DelayLabels = {}
local DelayInputs = {}

local function createDelayField(labelKey, settingKey, xScale, yOffset, widthScale)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(widthScale, -3, 0, 20)
    frame.Position = UDim2.new(xScale, 5, 0, yOffset)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    frame.Parent = UI.DelaySection
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
    
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 50, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = tr(labelKey)
    lbl.TextColor3 = Color3.fromRGB(150, 150, 150)
    lbl.TextSize = 7
    lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame
    
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -52, 1, -4)
    box.Position = UDim2.new(0, 50, 0, 2)
    box.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    box.Text = string.format("%.2f", Settings[settingKey] or 0)
    box.TextColor3 = Color3.new(1, 1, 1)
    box.TextSize = 9
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    
    box.FocusLost:Connect(function()
        local v = tonumber((box.Text or ""):gsub(",", "."))
        if not v then v = Settings[settingKey] or 0 end
        if v < 0 then v = 0 end
        Settings[settingKey] = v
        box.Text = string.format("%.2f", Settings[settingKey])
    end)
    
    DelayLabels[settingKey] = lbl
    DelayInputs[settingKey] = box
end

createDelayField("delay_action", "ActionDelay", 0, 16, 0.48)
createDelayField("delay_place", "PlaceDelay", 0.5, 16, 0.48)
createDelayField("delay_upgrade", "UpgradeDelay", 0, 38, 0.48)
createDelayField("delay_sell", "SellDelay", 0.5, 38, 0.48)
createDelayField("delay_ability", "AbilityDelay", 0, 60, 0.98)

-- ========== EXPORT ==========
UI.ExportSection = Instance.new("Frame")
UI.ExportSection.Size = UDim2.new(1, 0, 0, 44)
UI.ExportSection.BackgroundColor3 = Color3.fromRGB(35, 30, 40)
UI.ExportSection.Parent = UI.Content
Instance.new("UICorner", UI.ExportSection).CornerRadius = UDim.new(0, 8)

UI.ExportCodeBtn = Instance.new("TextButton")
UI.ExportCodeBtn.Size = UDim2.new(0.32, -2, 0, 28)
UI.ExportCodeBtn.Position = UDim2.new(0, 5, 0, 8)
UI.ExportCodeBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 150)
UI.ExportCodeBtn.Text = tr("export_code")
UI.ExportCodeBtn.TextColor3 = Color3.new(1, 1, 1)
UI.ExportCodeBtn.TextSize = 9
UI.ExportCodeBtn.Font = Enum.Font.GothamBold
UI.ExportCodeBtn.Parent = UI.ExportSection
Instance.new("UICorner", UI.ExportCodeBtn).CornerRadius = UDim.new(0, 5)

UI.ExportJsonBtn = Instance.new("TextButton")
UI.ExportJsonBtn.Size = UDim2.new(0.32, -2, 0, 28)
UI.ExportJsonBtn.Position = UDim2.new(0.33, 0, 0, 8)
UI.ExportJsonBtn.BackgroundColor3 = Color3.fromRGB(100, 80, 150)
UI.ExportJsonBtn.Text = tr("export_json")
UI.ExportJsonBtn.TextColor3 = Color3.new(1, 1, 1)
UI.ExportJsonBtn.TextSize = 9
UI.ExportJsonBtn.Font = Enum.Font.GothamBold
UI.ExportJsonBtn.Parent = UI.ExportSection
Instance.new("UICorner", UI.ExportJsonBtn).CornerRadius = UDim.new(0, 5)

UI.ImportBtn = Instance.new("TextButton")
UI.ImportBtn.Size = UDim2.new(0.32, -2, 0, 28)
UI.ImportBtn.Position = UDim2.new(0.66, 0, 0, 8)
UI.ImportBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 80)
UI.ImportBtn.Text = tr("import")
UI.ImportBtn.TextColor3 = Color3.new(1, 1, 1)
UI.ImportBtn.TextSize = 9
UI.ImportBtn.Font = Enum.Font.GothamBold
UI.ImportBtn.Parent = UI.ExportSection
Instance.new("UICorner", UI.ImportBtn).CornerRadius = UDim.new(0, 5)

-- ========== TOGGLE ==========
UI.ToggleBtn = Instance.new("TextButton")
UI.ToggleBtn.Size = UDim2.new(0, 44, 0, 44)
UI.ToggleBtn.Position = UDim2.new(1, -52, 0.35, 0)
UI.ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 50)
UI.ToggleBtn.Text = "⚡"
UI.ToggleBtn.TextColor3 = Color3.new(1, 1, 1)
UI.ToggleBtn.TextSize = 20
UI.ToggleBtn.Font = Enum.Font.GothamBold
UI.ToggleBtn.Parent = UI.ScreenGui
Instance.new("UICorner", UI.ToggleBtn).CornerRadius = UDim.new(0, 10)

-- ========== MODE INDICATOR ==========
UI.ModeIndicator = Instance.new("Frame")
UI.ModeIndicator.Size = UDim2.new(0, 360, 0, 48)
UI.ModeIndicator.Position = UDim2.new(0.5, -180, 0, 10)
UI.ModeIndicator.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
UI.ModeIndicator.Visible = false
UI.ModeIndicator.Parent = UI.ScreenGui
Instance.new("UICorner", UI.ModeIndicator).CornerRadius = UDim.new(0, 10)

UI.ModeText = Instance.new("TextLabel")
UI.ModeText.Size = UDim2.new(1, -20, 0, 22)
UI.ModeText.Position = UDim2.new(0, 10, 0, 5)
UI.ModeText.BackgroundTransparency = 1
UI.ModeText.Text = tr("mode")
UI.ModeText.TextColor3 = Color3.new(1, 1, 1)
UI.ModeText.TextSize = 13
UI.ModeText.Font = Enum.Font.GothamBold
UI.ModeText.Parent = UI.ModeIndicator

UI.ModeSubText = Instance.new("TextLabel")
UI.ModeSubText.Size = UDim2.new(1, -20, 0, 18)
UI.ModeSubText.Position = UDim2.new(0, 10, 0, 26)
UI.ModeSubText.BackgroundTransparency = 1
UI.ModeSubText.Text = "..."
UI.ModeSubText.TextColor3 = Color3.fromRGB(200, 255, 200)
UI.ModeSubText.TextSize = 10
UI.ModeSubText.Font = Enum.Font.Gotham
UI.ModeSubText.Parent = UI.ModeIndicator

-- ========== PREVIEW ==========
UI.previewCircle = Instance.new("Part")
UI.previewCircle.Shape = Enum.PartType.Cylinder
UI.previewCircle.Anchored = true
UI.previewCircle.CanCollide = false
UI.previewCircle.CanQuery = false
UI.previewCircle.CanTouch = false
UI.previewCircle.Material = Enum.Material.Neon
UI.previewCircle.Transparency = 0.5

UI.previewOutline = Instance.new("Part")
UI.previewOutline.Shape = Enum.PartType.Cylinder
UI.previewOutline.Anchored = true
UI.previewOutline.CanCollide = false
UI.previewOutline.CanQuery = false
UI.previewOutline.CanTouch = false
UI.previewOutline.Material = Enum.Material.Neon
UI.previewOutline.Transparency = 0.3
UI.previewOutline.Color = Color3.fromRGB(255, 255, 255)

UI.previewBillboard = Instance.new("BillboardGui")
UI.previewBillboard.Size = UDim2.new(0, 150, 0, 40)
UI.previewBillboard.StudsOffset = Vector3.new(0, 2.5, 0)
UI.previewBillboard.AlwaysOnTop = true
UI.previewBillboard.Parent = UI.previewCircle

UI.previewLabel = Instance.new("TextLabel")
UI.previewLabel.Size = UDim2.new(1, 0, 1, 0)
UI.previewLabel.BackgroundTransparency = 0.2
UI.previewLabel.TextColor3 = Color3.new(1, 1, 1)
UI.previewLabel.TextSize = 10
UI.previewLabel.Font = Enum.Font.GothamBold
UI.previewLabel.TextWrapped = true
UI.previewLabel.Parent = UI.previewBillboard
Instance.new("UICorner", UI.previewLabel).CornerRadius = UDim.new(0, 5)

-- ========== MARKERS ==========
local markers = {}

local function clearMarkers()
    for _, m in pairs(markers) do if m and m.Parent then m:Destroy() end end
    markers = {}
end

updateMarkers = function()
    clearMarkers()
    if not Settings.ShowMarkers then return end
    
    local placeIndex = 0
    for _, action in ipairs(Strategy.Actions) do
        if action.type == ActionType.PLACE then
            placeIndex = placeIndex + 1
            local p = action.params
            local boundarySize = getTowerBoundarySize(p.towerName)
            local diameter = boundarySize * 2
            
            local marker = Instance.new("Part")
            marker.Shape = Enum.PartType.Cylinder
            marker.Size = Vector3.new(0.15, diameter, diameter)
            marker.CFrame = CFrame.new(p.position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
            marker.Anchored = true
            marker.CanCollide = false
            marker.CanQuery = false
            marker.CanTouch = false
            marker.Material = Enum.Material.Neon
            marker.Color = Strategy.PlacedTowers[placeIndex] and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(0, 255, 100)
            marker.Transparency = 0.5
            marker.Parent = workspace
            
            local bb = Instance.new("BillboardGui")
            bb.Size = UDim2.new(0, 80, 0, 28)
            bb.StudsOffset = Vector3.new(0, 2, 0)
            bb.AlwaysOnTop = true
            bb.Parent = marker
            
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 0.2
            lbl.BackgroundColor3 = Color3.fromRGB(0, 100, 50)
            -- ФИКС: Увеличен размер текста
            lbl.Text = "#" .. placeIndex .. " " .. (p.towerName or "?")
            lbl.TextColor3 = Color3.new(1, 1, 1)
            lbl.TextSize = 10
            lbl.Font = Enum.Font.GothamBold
            lbl.TextScaled = true
            lbl.Parent = bb
            Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 4)
            
            table.insert(markers, marker)
        end
    end
end

-- ========== UI FUNCTIONS ==========

-- ФИКС: Улучшенное описание действий (без обрезки)
local function getActionDescription(action)
    local t, p = action.type, action.params
    if t == ActionType.PLACE then 
        return "🏗 " .. (p.towerName or "?")
    elseif t == ActionType.UPGRADE then 
        return "⬆️ #" .. p.towerIndex .. (p.path == 2 and " P2" or "")
    elseif t == ActionType.UPGRADE_TO then 
        return "⬆️ #" .. p.towerIndex .. " → Lv" .. p.targetLevel
    elseif t == ActionType.UPGRADE_MAX then 
        return "⬆️ #" .. p.towerIndex .. " MAX"
    elseif t == ActionType.MULTI_UPGRADE then 
        local filter = p.towerNameFilter ~= "" and (" " .. p.towerNameFilter) or ""
        return "🔄 #" .. p.fromIndex .. "-#" .. p.toIndex .. " → Lv" .. p.targetLevel .. filter
    elseif t == ActionType.SELL then 
        return "💰 Sell #" .. p.towerIndex
    elseif t == ActionType.SELL_ALL then 
        return "💰 Sell ALL"
    elseif t == ActionType.SET_TARGET then 
        return "🎯 #" .. p.towerIndex .. " → " .. (p.targetType or "?")
    elseif t == ActionType.SET_TARGET_AT_WAVE then
        return "🎯 #" .. p.towerIndex .. " @W" .. (p.wave or 1)
    elseif t == ActionType.ABILITY then 
        return "⚡ #" .. p.towerIndex .. " " .. (p.abilityName or "?")
    elseif t == ActionType.ABILITY_LOOP then 
        return "🔄 #" .. p.towerIndex .. " Loop " .. (p.abilityName or "?")
    elseif t == ActionType.SET_OPTION then 
        return "⚙️ #" .. p.towerIndex .. " " .. (p.optionName or "?")
    elseif t == ActionType.WAIT_WAVE then 
        return "🌊 Wave " .. p.wave
    elseif t == ActionType.WAIT_TIME then 
        return "⏱ " .. p.seconds .. " sec"
    elseif t == ActionType.WAIT_CASH then 
        return "💵 $" .. p.amount
    elseif t == ActionType.VOTE_SKIP then 
        return "⏭ Skip W" .. p.startWave .. "-" .. p.endWave
    elseif t == ActionType.AUTO_CHAIN then 
        if p.enabled == false then
            return "🔗 Chain OFF"
        end
        return "🔗 Chain " .. table.concat(p.towerIndices or {}, ",")
    elseif t == ActionType.AUTO_CHAIN_CARAVAN then
        return "🚚 Chain+Caravan " .. table.concat(p.towerIndices or {}, ",")
    elseif t == ActionType.AUTO_DJ then
        return p.enabled == false and "🎵 Auto DJ OFF" or "🎵 Auto DJ ON"
    elseif t == ActionType.AUTO_NECRO then
        return p.enabled == false and "💀 Auto Necro OFF" or "💀 Auto Necro ON"
    elseif t == ActionType.AUTO_MERCENARY then
        return (p.enabled == false and "🪂 Auto Merc OFF") or ("🪂 Merc " .. tostring(p.distance or 195))
    elseif t == ActionType.AUTO_MILITARY then
        return (p.enabled == false and "💥 Auto Mil OFF") or ("💥 Mil " .. tostring(p.distance or 195))
    elseif t == ActionType.TIME_SCALE then
        return "⏩ Speed x" .. tostring(p.value or 1)
    elseif t == ActionType.UNLOCK_TIMESCALE then
        return "🔓 Unlock TimeScale"
    elseif t == ActionType.SELL_AT_WAVE then
        return "💰 #" .. p.towerIndex .. " @W" .. (p.wave or 1)
    elseif t == ActionType.SELL_FARMS_AT_WAVE then
        return "🌾 Sell Farms @W" .. (p.wave or 1)
    elseif t == ActionType.AUTO_PICKUPS_MODE then
        return "🎁 Pickups " .. tostring(p.mode or "Instant")
    elseif t == ActionType.LOADOUT then
        return "📦 " .. table.concat(p.towers or {}, ", ")
    end
    return "?"
end

updateActionsDisplay = function()
    for _, child in pairs(UI.ActionsScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    UI.ActionsTitle.Text = tr("actions_queue", #Strategy.Actions)
    
    for i, action in ipairs(Strategy.Actions) do
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -6, 0, 22)
        frame.BackgroundColor3 = i == Strategy.CurrentAction and State.Running 
            and Color3.fromRGB(50, 70, 35) or Color3.fromRGB(35, 35, 45)
        frame.Parent = UI.ActionsScroll
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
        
        local numLbl = Instance.new("TextLabel")
        numLbl.Size = UDim2.new(0, 22, 1, 0)
        numLbl.BackgroundTransparency = 1
        numLbl.Text = tostring(i)
        numLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        numLbl.TextSize = 9
        numLbl.Font = Enum.Font.GothamBold
        numLbl.Parent = frame
        
        local descLbl = Instance.new("TextLabel")
        descLbl.Size = UDim2.new(1, -80, 1, 0)
        descLbl.Position = UDim2.new(0, 22, 0, 0)
        descLbl.BackgroundTransparency = 1
        descLbl.Text = getActionDescription(action)
        descLbl.TextColor3 = Color3.new(1, 1, 1)
        descLbl.TextSize = 9
        descLbl.Font = Enum.Font.Gotham
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        -- ФИКС: Убрал TextTruncate, добавил TextScaled для длинных текстов
        descLbl.TextScaled = false
        descLbl.ClipsDescendants = true
        descLbl.Parent = frame
        
        local upBtn = Instance.new("TextButton")
        upBtn.Size = UDim2.new(0, 16, 0, 9)
        upBtn.Position = UDim2.new(1, -50, 0, 1)
        upBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 120)
        upBtn.Text = "▲"
        upBtn.TextColor3 = Color3.new(1, 1, 1)
        upBtn.TextSize = 7
        upBtn.Font = Enum.Font.GothamBold
        upBtn.Parent = frame
        Instance.new("UICorner", upBtn).CornerRadius = UDim.new(0, 2)
        
        local downBtn = Instance.new("TextButton")
        downBtn.Size = UDim2.new(0, 16, 0, 9)
        downBtn.Position = UDim2.new(1, -50, 0, 11)
        downBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 120)
        downBtn.Text = "▼"
        downBtn.TextColor3 = Color3.new(1, 1, 1)
        downBtn.TextSize = 7
        downBtn.Font = Enum.Font.GothamBold
        downBtn.Parent = frame
        Instance.new("UICorner", downBtn).CornerRadius = UDim.new(0, 2)
        
        local delBtn = Instance.new("TextButton")
        delBtn.Size = UDim2.new(0, 20, 0, 18)
        delBtn.Position = UDim2.new(1, -26, 0, 2)
        delBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
        delBtn.Text = "✕"
        delBtn.TextColor3 = Color3.new(1, 1, 1)
        delBtn.TextSize = 9
        delBtn.Font = Enum.Font.GothamBold
        delBtn.Parent = frame
        Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 3)
        
        upBtn.MouseButton1Click:Connect(function()
            if i > 1 then
                Strategy.Actions[i], Strategy.Actions[i-1] = Strategy.Actions[i-1], Strategy.Actions[i]
                updateActionsDisplay()
                updateMarkers()
            end
        end)
        
        downBtn.MouseButton1Click:Connect(function()
            if i < #Strategy.Actions then
                Strategy.Actions[i], Strategy.Actions[i+1] = Strategy.Actions[i+1], Strategy.Actions[i]
                updateActionsDisplay()
                updateMarkers()
            end
        end)
        
        delBtn.MouseButton1Click:Connect(function()
            table.remove(Strategy.Actions, i)
            updateActionsDisplay()
            updateMarkers()
        end)
    end
end

local function updateStatus()
    local cash = getCash()
    local wave = getCurrentWave()
    local placed = 0
    for _, t in pairs(Strategy.PlacedTowers) do if t then placed = placed + 1 end end
    
    local status = State.Running and (State.Paused and tr("status_paused") or tr("status_running")) or tr("status_stopped")
    local chainStatus = Settings.GlobalAutoChain and "🔗" or ""
    local djStatus = Settings.GlobalAutoDJ and "🎵" or ""
    local skipStatus = Settings.GlobalAutoSkip and "⏭" or ""  -- НОВОЕ
    
    UI.StatusLabel.Text = string.format(
        "%s %s%s%s | 💰$%d | 🌊Wave %d | 🗼%s: %d\n%s: %d/%d | %s",
        status, chainStatus, djStatus, skipStatus, cash, wave, tr("towers_label"), placed,
        tr("action_label"), Strategy.CurrentAction, #Strategy.Actions,
        State.LastLog
    )
    
    UI.StatusSection.BackgroundColor3 = State.Running 
        and (State.Paused and Color3.fromRGB(40, 40, 25) or Color3.fromRGB(20, 45, 20))
        or Color3.fromRGB(25, 30, 25)
end

local function applyLanguage()
    if UI.Title then UI.Title.Text = tr("title") end
    if UI.StartBtn then UI.StartBtn.Text = tr("start") end
    if UI.PauseBtn then UI.PauseBtn.Text = State.Paused and tr("pause_go") or tr("pause") end
    if UI.StopBtn then UI.StopBtn.Text = tr("stop") end
    if UI.TowerTitle then UI.TowerTitle.Text = tr("tower_default", State.SelectedTower or "Scout") end
    if UI.AddTitle then UI.AddTitle.Text = tr("all_actions") end
    if UI.SaveLoadTitle then UI.SaveLoadTitle.Text = tr("save_load") end
    if UI.ConfigNameBox then UI.ConfigNameBox.PlaceholderText = tr("config_placeholder") end
    if UI.ActionsTitle then UI.ActionsTitle.Text = tr("actions_queue", #Strategy.Actions) end
    if UI.ExportCodeBtn then UI.ExportCodeBtn.Text = tr("export_code") end
    if UI.ExportJsonBtn then UI.ExportJsonBtn.Text = tr("export_json") end
    if UI.ImportBtn then UI.ImportBtn.Text = tr("import") end
    if UI.DelayTitle then UI.DelayTitle.Text = tr("delay_section") end
    if DelayLabels then
        if DelayLabels.ActionDelay then DelayLabels.ActionDelay.Text = tr("delay_action") end
        if DelayLabels.PlaceDelay then DelayLabels.PlaceDelay.Text = tr("delay_place") end
        if DelayLabels.UpgradeDelay then DelayLabels.UpgradeDelay.Text = tr("delay_upgrade") end
        if DelayLabels.SellDelay then DelayLabels.SellDelay.Text = tr("delay_sell") end
        if DelayLabels.AbilityDelay then DelayLabels.AbilityDelay.Text = tr("delay_ability") end
    end
    if ActionBtns and ActionBtns.PLACE then
        ActionBtns.PLACE.Text = State.AddingPosition and tr("place_active") or "🏗PLACE"
    end
    if UI.GlobalChainBtn then
        UI.GlobalChainBtn.Text = Settings.GlobalAutoChain and tr("global_chain_on") or tr("global_chain_off")
    end
    if UI.GlobalDJBtn then
        UI.GlobalDJBtn.Text = Settings.GlobalAutoDJ and tr("global_dj_on") or tr("global_dj_off")
    end
    if UI.GlobalSkipBtn then
        UI.GlobalSkipBtn.Text = Settings.GlobalAutoSkip and tr("global_skip_on") or tr("global_skip_off")
    end
    if UI.AutoFarmBtn and AutoFarmSettings then
        UI.AutoFarmBtn.Text = AutoFarmSettings.Enabled and tr("auto_farm_on") or tr("auto_farm_off")
    end
    if UI.AutoStartBtn and AutoFarmSettings then
        UI.AutoStartBtn.Text = AutoFarmSettings.AutoStart and tr("auto_start_on") or tr("auto_start_off")
    end
    if UI.ModeBtn and AutoFarmSettings then
        UI.ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty or "?")
    end
    if UI.FarmStatusLabel and currentGameState then
        UI.FarmStatusLabel.Text = tr("farm_status_prefix") .. currentGameState
    end
    if UI.PickupsStatusLabel and pickupsCollected then
        UI.PickupsStatusLabel.Text = tr("pickups_collected", pickupsCollected)
    end
    if UI.AutoFarmConfigTitle then UI.AutoFarmConfigTitle.Text = tr("autofarm_config_title") end
    if UI.AutoFarmConfigNameBox then UI.AutoFarmConfigNameBox.PlaceholderText = tr("autofarm_config_placeholder") end
    if UI.QueueToggleBtn and QueueSettings then
        UI.QueueToggleBtn.Text = QueueSettings.Enabled and tr("queue_on") or tr("queue_off")
    end
    if UI.LangBtn then UI.LangBtn.Text = tr("lang_button") end
    if UI.ModeIndicator and not State.AddingPosition then
        UI.ModeText.Text = tr("mode")
        UI.ModeSubText.Text = "..."
    end
end

applyLanguage()

local function createTowerButtons()
    if not UI.TowerScroll then return end
    
    for _, child in pairs(UI.TowerScroll:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
    end
    
    -- НЕ вызываем loadModules тут! Просто берём что есть
    local unlocked = getUnlockedTowers()
    
    local count = 0
    for _ in pairs(unlocked) do count = count + 1 end
    
    if count == 0 then
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -10, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = "⏳ Башни загружаются..."
        lbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        lbl.TextSize = 10
        lbl.Font = Enum.Font.GothamBold
        lbl.Parent = UI.TowerScroll
        return
    end
    
    local sorted = {}
    for name in pairs(unlocked) do table.insert(sorted, name) end
    table.sort(sorted)
    
    for _, towerName in ipairs(sorted) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 42, 0, 42)
        btn.BackgroundColor3 = State.SelectedTower == towerName 
            and Color3.fromRGB(0, 130, 65) or Color3.fromRGB(40, 40, 55)
        btn.Text = ""
        btn.Parent = UI.TowerScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        
        local icon = Instance.new("ImageLabel")
        icon.Size = UDim2.new(0, 24, 0, 24)
        icon.Position = UDim2.new(0.5, -12, 0, 2)
        icon.BackgroundTransparency = 1
        icon.Parent = btn
        
        pcall(function()
            if TowerIcons and TowerIcons[towerName] then
                icon.Image = TowerIcons[towerName].Default or ""
            end
        end)
        
        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1, -2, 0, 12)
        name.Position = UDim2.new(0, 1, 1, -13)
        name.BackgroundTransparency = 1
        name.Text = towerName
        name.TextColor3 = Color3.new(1, 1, 1)
        name.TextSize = 7
        name.TextScaled = true
        name.Font = Enum.Font.GothamBold
        name.Parent = btn
        
        btn.MouseButton1Click:Connect(function()
            State.SelectedTower = towerName
            local bSize = getTowerBoundarySize(towerName)
            local cost = getTowerPlaceCost(towerName)
            UI.TowerTitle.Text = tr("tower_stats", towerName, bSize, cost)
            createTowerButtons()
        end)
    end
end

-- ========== PREVIEW MODE ==========

local previewConnection

local function updateAddPreview()
    if not State.AddingPosition then 
        UI.previewCircle.Parent = nil
        UI.previewOutline.Parent = nil
        return 
    end
    
    local mouse = player:GetMouse()
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {
        workspace:FindFirstChild("Towers"),
        workspace:FindFirstChild("NPCs"),
        workspace:FindFirstChild("ClientUnits"),
        workspace:FindFirstChild("Paths"),
        workspace.CurrentCamera,
        player.Character,
        UI.previewCircle,
        UI.previewOutline
    }
    for _, m in pairs(markers) do
        table.insert(rayParams.FilterDescendantsInstances, m)
    end
    
    local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 1000, rayParams)
    
    if ray then
        local pos = ray.Position
        local boundarySize = getTowerBoundarySize(State.SelectedTower)
        local diameter = boundarySize * 2
        
        UI.previewCircle.Size = Vector3.new(0.1, diameter, diameter)
        UI.previewCircle.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
        UI.previewCircle.Parent = workspace
        
        UI.previewOutline.Size = Vector3.new(0.05, diameter + 0.15, diameter + 0.15)
        UI.previewOutline.CFrame = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
        UI.previewOutline.Parent = workspace
        
        local isValid, reason = checkPositionValid(State.SelectedTower, pos, false)
        local cost = getTowerPlaceCost(State.SelectedTower)
        
        if isValid then
            UI.previewCircle.Color = Color3.fromRGB(0, 255, 100)
            UI.previewLabel.BackgroundColor3 = Color3.fromRGB(0, 120, 50)
            UI.previewLabel.Text = string.format("✓ %s $%d", State.SelectedTower, cost)
            UI.ModeIndicator.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
            UI.ModeText.Text = tr("mode_place_ok")
            UI.ModeSubText.Text = State.SelectedTower .. " | $" .. cost
        else
            UI.previewCircle.Color = Color3.fromRGB(255, 60, 60)
            UI.previewLabel.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
            UI.previewLabel.Text = "✕ " .. reason
            UI.ModeIndicator.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            UI.ModeText.Text = tr("mode_place_no")
            UI.ModeSubText.Text = reason
        end
    else
        UI.previewCircle.Parent = nil
        UI.previewOutline.Parent = nil
    end
end

local function startAddPositionMode()
    State.AddingPosition = true
    UI.ModeIndicator.Visible = true
    ActionBtns.PLACE.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
    ActionBtns.PLACE.Text = tr("place_active")
    previewConnection = RunService.RenderStepped:Connect(updateAddPreview)
end

local function stopAddPositionMode()
    State.AddingPosition = false
    UI.ModeIndicator.Visible = false
    UI.previewCircle.Parent = nil
    UI.previewOutline.Parent = nil
    ActionBtns.PLACE.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
    ActionBtns.PLACE.Text = "🏗PLACE"
    if previewConnection then previewConnection:Disconnect() previewConnection = nil end
end

local function addPositionAtMouse()
    if not State.AddingPosition then return end
    
    local mouse = player:GetMouse()
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {
        workspace:FindFirstChild("Towers"),
        workspace:FindFirstChild("NPCs"),
        workspace:FindFirstChild("ClientUnits"),
        workspace:FindFirstChild("Paths"),
        workspace.CurrentCamera,
        player.Character,
        UI.previewCircle,
        UI.previewOutline
    }
    for _, m in pairs(markers) do table.insert(rayParams.FilterDescendantsInstances, m) end
    
    local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 1000, rayParams)
    
    if ray then
        local pos = ray.Position
        
        local isValid, reason = checkPositionValid(State.SelectedTower, pos, false)
        
        if not isValid then
            UI.ModeText.Text = tr("mode_place_no")
            UI.ModeSubText.Text = reason
            UI.ModeIndicator.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            return
        end
        
        addPlaceAction(State.SelectedTower, pos.X, pos.Y, pos.Z)
        updateActionsDisplay()
        updateMarkers()
        
        local placeCount = 0
        for _, action in ipairs(Strategy.Actions) do
            if action.type == ActionType.PLACE then placeCount = placeCount + 1 end
        end
        
        UI.ModeText.Text = tr("mode_added", placeCount)
        UI.ModeIndicator.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        task.delay(0.5, function()
            if State.AddingPosition then
                UI.ModeText.Text = tr("mode_add")
            end
        end)
    end
end

-- ========== EVENTS ==========

UI.LangBtn.MouseButton1Click:Connect(function()
    Settings.Language = (Settings.Language == "RU") and "EN" or "RU"
    applyLanguage()
    if updateStatus then updateStatus() end
    if updateActionsDisplay then updateActionsDisplay() end
end)

UI.StartBtn.MouseButton1Click:Connect(function()
    if State.Running then return end
    if #Strategy.Actions == 0 then
        State.LastLog = "❌ Добавь действия!"
        updateStatus()
        return
    end
    stopAddPositionMode()
    task.spawn(runStrategy)
end)

UI.PauseBtn.MouseButton1Click:Connect(function()
    if State.Running then
        State.Paused = not State.Paused
        UI.PauseBtn.Text = State.Paused and tr("pause_go") or tr("pause")
        UI.PauseBtn.BackgroundColor3 = State.Paused and Color3.fromRGB(0, 180, 100) or Color3.fromRGB(200, 150, 50)
        updateStatus()
    end
end)

UI.StopBtn.MouseButton1Click:Connect(function()
    State.Running = false
    State.Paused = false
    stopAllLoops()
    UI.PauseBtn.Text = tr("pause")
    UI.PauseBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
    State.LastLog = "⏹ Остановлено"
    updateStatus()
end)

UI.GlobalChainBtn.MouseButton1Click:Connect(function()
    Settings.GlobalAutoChain = not Settings.GlobalAutoChain
    if Settings.GlobalAutoChain then
        UI.GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        UI.GlobalChainBtn.Text = tr("global_chain_on")
        startGlobalAutoChain()
        State.LastLog = "🔗 Global Auto Chain включен"
    else
        UI.GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 60)
        UI.GlobalChainBtn.Text = tr("global_chain_off")
        stopGlobalAutoChain()
        State.LastLog = "🔗 Global Auto Chain выключен"
    end
    updateStatus()
end)

UI.GlobalDJBtn.MouseButton1Click:Connect(function()
    Settings.GlobalAutoDJ = not Settings.GlobalAutoDJ
    if Settings.GlobalAutoDJ then
        UI.GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
        UI.GlobalDJBtn.Text = tr("global_dj_on")
        startGlobalAutoDJ()
        State.LastLog = "🎵 Global Auto DJ включен"
    else
        UI.GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 80)
        UI.GlobalDJBtn.Text = tr("global_dj_off")
        stopGlobalAutoDJ()
        State.LastLog = "🎵 Global Auto DJ выключен"
    end
    updateStatus()
end)

-- Global Auto Skip toggle
UI.GlobalSkipBtn.MouseButton1Click:Connect(function()
    Settings.GlobalAutoSkip = not Settings.GlobalAutoSkip
    if Settings.GlobalAutoSkip then
        UI.GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
        UI.GlobalSkipBtn.Text = tr("global_skip_on")
        startGlobalAutoSkip()
        State.LastLog = "⏭ Global Auto Skip включен"
    else
        UI.GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 60)
        UI.GlobalSkipBtn.Text = tr("global_skip_off")
        stopGlobalAutoSkip()
        State.LastLog = "⏭ Global Auto Skip выключен"
    end
    updateStatus()
end)

-- Action buttons
ActionBtns.PLACE.MouseButton1Click:Connect(function()
    if State.AddingPosition then stopAddPositionMode() else startAddPositionMode() end
end)

ActionBtns.UPGRADE.MouseButton1Click:Connect(function()
    addUpgradeAction(tonumber(UI.InputBox1.Text) or 1, tonumber(UI.InputBoxPath.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.UPG_PATH2.MouseButton1Click:Connect(function()
    addUpgradeAction(tonumber(UI.InputBox1.Text) or 1, 2)
    updateActionsDisplay()
end)

ActionBtns.UPGRADE_TO.MouseButton1Click:Connect(function()
    addUpgradeToAction(tonumber(UI.InputBox1.Text) or 1, tonumber(UI.InputBox3.Text) or 1, tonumber(UI.InputBoxPath.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.UPGRADE_MAX.MouseButton1Click:Connect(function()
    addUpgradeMaxAction(tonumber(UI.InputBox1.Text) or 1, tonumber(UI.InputBoxPath.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.MULTI_UPG.MouseButton1Click:Connect(function()
    local fromIdx = tonumber(UI.InputBox1.Text) or 1
    local toIdx = tonumber(UI.InputBox2.Text) or 6
    local targetLv = tonumber(UI.InputBox3.Text) or 3
    local filterName = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or ""
    local path = tonumber(UI.InputBoxPath.Text) or 1
    
    addMultiUpgradeAction(fromIdx, toIdx, targetLv, filterName, path)
    updateActionsDisplay()
    State.LastLog = string.format("🔄 Добавлен MULTI UPG #%d-#%d → Lv%d", fromIdx, toIdx, targetLv)
    updateStatus()
end)

ActionBtns.SELL.MouseButton1Click:Connect(function()
    addSellAction(tonumber(UI.InputBox1.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.SELL_ALL.MouseButton1Click:Connect(function()
    addSellAllAction()
    updateActionsDisplay()
end)

ActionBtns.SET_TARGET.MouseButton1Click:Connect(function()
    local target = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or "First"
    addSetTargetAction(tonumber(UI.InputBox1.Text) or 1, target)
    updateActionsDisplay()
end)

ActionBtns.ABILITY.MouseButton1Click:Connect(function()
    local ability = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or "Call Of Arms"
    addAbilityAction(tonumber(UI.InputBox1.Text) or 1, ability, {}, false)
    updateActionsDisplay()
end)

ActionBtns.ABILITY_LOOP.MouseButton1Click:Connect(function()
    local ability = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or "Call Of Arms"
    addAbilityAction(tonumber(UI.InputBox1.Text) or 1, ability, {}, true)
    updateActionsDisplay()
end)

ActionBtns.SET_OPTION.MouseButton1Click:Connect(function()
    local optText = UI.InputBoxText.Text
    local optName, optValue = "Unit 1", "Riot Guard"
    if optText:find("=") then
        local parts = optText:split("=")
        optName = parts[1]:match("^%s*(.-)%s*$") or optName
        optValue = parts[2]:match("^%s*(.-)%s*$") or optValue
    elseif optText ~= "" then
        optName = optText
    end
    addSetOptionAction(tonumber(UI.InputBox1.Text) or 1, optName, optValue, tonumber(UI.InputBox4.Text) or 0)
    updateActionsDisplay()
end)

ActionBtns.WAIT_WAVE.MouseButton1Click:Connect(function()
    addWaitWaveAction(tonumber(UI.InputBox4.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.WAIT_TIME.MouseButton1Click:Connect(function()
    addWaitTimeAction(tonumber(UI.InputBox3.Text) or 5)
    updateActionsDisplay()
end)

ActionBtns.WAIT_CASH.MouseButton1Click:Connect(function()
    addWaitCashAction(tonumber(UI.InputBox5.Text) or 1000)
    updateActionsDisplay()
end)

ActionBtns.VOTE_SKIP.MouseButton1Click:Connect(function()
    local startW = tonumber(UI.InputBox4.Text) or 1
    local endW = tonumber(UI.InputBox2.Text) or startW
    addVoteSkipAction(startW, endW)
    updateActionsDisplay()
end)

ActionBtns.AUTO_CHAIN.MouseButton1Click:Connect(function()
    local text = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or "1,2,3"
    local indices = {}
    for num in text:gmatch("%d+") do
        table.insert(indices, tonumber(num))
    end
    if #indices > 0 then
        addAutoChainAction(indices)
        updateActionsDisplay()
    end
end)

ActionBtns.AUTO_CHAIN_OFF.MouseButton1Click:Connect(function()
    addAutoChainOffAction()
    updateActionsDisplay()
end)

ActionBtns.TIME_SCALE.MouseButton1Click:Connect(function()
    local value = tonumber((UI.InputBox3.Text or ""):gsub(",", ".")) or 1
    local text = (UI.InputBoxText.Text or ""):lower()
    local unlock = text:find("unlock") or text:find("u")
    addTimeScaleAction(value, unlock and true or false)
    updateActionsDisplay()
end)

ActionBtns.UNLOCK_TS.MouseButton1Click:Connect(function()
    addUnlockTimeScaleAction()
    updateActionsDisplay()
end)

ActionBtns.SET_TGT_W.MouseButton1Click:Connect(function()
    local target = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or "First"
    addSetTargetAtWaveAction(tonumber(UI.InputBox1.Text) or 1, target, tonumber(UI.InputBox4.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.SELL_AT_W.MouseButton1Click:Connect(function()
    addSellAtWaveAction(tonumber(UI.InputBox1.Text) or 1, tonumber(UI.InputBox4.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.SELL_FARMS.MouseButton1Click:Connect(function()
    addSellFarmsAtWaveAction(tonumber(UI.InputBox4.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.AUTO_DJ.MouseButton1Click:Connect(function()
    local text = (UI.InputBoxText.Text or ""):lower()
    local enabled = not (text == "off" or text == "0" or text == "false")
    addAutoDJAction(enabled)
    updateActionsDisplay()
end)

ActionBtns.CHAIN_CAR.MouseButton1Click:Connect(function()
    local text = UI.InputBoxText.Text ~= "" and UI.InputBoxText.Text or "1,2,3"
    local indices = {}
    for num in text:gmatch("%d+") do
        table.insert(indices, tonumber(num))
    end
    if #indices > 0 then
        addAutoChainCaravanAction(indices)
        updateActionsDisplay()
    end
end)

ActionBtns.AUTO_NECRO.MouseButton1Click:Connect(function()
    local text = (UI.InputBoxText.Text or ""):lower()
    local enabled = not (text == "off" or text == "0" or text == "false")
    addAutoNecroAction(enabled)
    updateActionsDisplay()
end)

ActionBtns.AUTO_MERC.MouseButton1Click:Connect(function()
    local text = (UI.InputBoxText.Text or ""):lower()
    local enabled = not (text == "off" or text == "0" or text == "false")
    local dist = tonumber((UI.InputBox3.Text or ""):gsub(",", ".")) or 195
    addAutoMercenaryAction(dist, enabled)
    updateActionsDisplay()
end)

ActionBtns.AUTO_MIL.MouseButton1Click:Connect(function()
    local text = (UI.InputBoxText.Text or ""):lower()
    local enabled = not (text == "off" or text == "0" or text == "false")
    local dist = tonumber((UI.InputBox3.Text or ""):gsub(",", ".")) or 195
    addAutoMilitaryAction(dist, enabled)
    updateActionsDisplay()
end)

ActionBtns.PICKUP_MODE.MouseButton1Click:Connect(function()
    local text = (UI.InputBoxText.Text or ""):lower()
    local mode = (text:find("path") and "Pathfinding") or "Instant"
    addAutoPickupsModeAction(mode)
    updateActionsDisplay()
end)

ActionBtns.AUTO_DJ_OFF.MouseButton1Click:Connect(function()
    addAutoDJAction(false)
    updateActionsDisplay()
end)

ActionBtns.AUTO_NECRO_OFF.MouseButton1Click:Connect(function()
    addAutoNecroAction(false)
    updateActionsDisplay()
end)

ActionBtns.AUTO_MERC_OFF.MouseButton1Click:Connect(function()
    local dist = tonumber((UI.InputBox3.Text or ""):gsub(",", ".")) or 195
    addAutoMercenaryAction(dist, false)
    updateActionsDisplay()
end)

ActionBtns.AUTO_MIL_OFF.MouseButton1Click:Connect(function()
    local dist = tonumber((UI.InputBox3.Text or ""):gsub(",", ".")) or 195
    addAutoMilitaryAction(dist, false)
    updateActionsDisplay()
end)

-- НОВОЕ: Loadout кнопка
ActionBtns.LOADOUT.MouseButton1Click:Connect(function()
    local loadoutText = UI.InputBoxLoadout.Text
    if loadoutText == "" then
        State.LastLog = "❌ Введи башни для loadout!"
        updateStatus()
        return
    end
    
    local towers = {}
    for tower in loadoutText:gmatch("[^,]+") do
        local trimmed = tower:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(towers, trimmed)
        end
    end
    
    if #towers > 0 then
        addLoadoutAction(towers)
        updateActionsDisplay()
        State.LastLog = "📦 Loadout добавлен: " .. #towers .. " башен"
        updateStatus()
    end
end)

ActionBtns.CLEAR.MouseButton1Click:Connect(function()
    Strategy.Actions = {}
    Strategy.PlacedTowers = {}
    Strategy.CurrentAction = 1
    stopAllLoops()
    updateActionsDisplay()
    updateMarkers()
    State.LastLog = "🗑 Очищено"
    updateStatus()
end)

-- Save/Load
UI.SaveBtn.MouseButton1Click:Connect(function()
    local name = UI.ConfigNameBox.Text
    if name == "" then
        State.LastLog = "❌ Введи имя конфига!"
        updateStatus()
        return
    end
    local success, msg = saveStrategy(name)
    State.LastLog = msg
    updateStatus()
    if success then
        updateConfigList()
    end
end)

UI.RefreshBtn.MouseButton1Click:Connect(function()
    updateConfigList()
    State.LastLog = "🔄 Список обновлён"
    updateStatus()
end)

-- Export/Import
UI.ExportCodeBtn.MouseButton1Click:Connect(function()
    local code = generateCode()
    if setclipboard then
        setclipboard(code)
        State.LastLog = "📋 Код скопирован!"
    else
        State.LastLog = "⚠ Нет clipboard"
        print(code)
    end
    updateStatus()
end)

UI.ExportJsonBtn.MouseButton1Click:Connect(function()
    local json = exportStrategy()
    if setclipboard then
        setclipboard(json)
        State.LastLog = "📋 JSON скопирован!"
    else
        State.LastLog = "⚠ Нет clipboard"
        print(json)
    end
    updateStatus()
end)

UI.ImportBtn.MouseButton1Click:Connect(function()
    if getclipboard then
        local clip = getclipboard()
        if importStrategy(clip) then
            State.LastLog = "📥 Импорт: " .. #Strategy.Actions .. " действий"
            updateActionsDisplay()
            updateMarkers()
        else
            State.LastLog = "❌ Ошибка импорта"
        end
    else
        State.LastLog = "⚠ Нет clipboard"
    end
    updateStatus()
end)

UI.CloseBtn.MouseButton1Click:Connect(function()
    UI.MainFrame.Visible = false
    stopAddPositionMode()
end)

UI.ToggleBtn.MouseButton1Click:Connect(function()
    UI.MainFrame.Visible = not UI.MainFrame.Visible
    if UI.MainFrame.Visible then
        createTowerButtons()
        updateActionsDisplay()
        updateStatus()
        updateMarkers()
        updateConfigList()
    else
        stopAddPositionMode()
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    
    if input.KeyCode == Enum.KeyCode.P then
        UI.MainFrame.Visible = not UI.MainFrame.Visible
        if UI.MainFrame.Visible then
            createTowerButtons()
            updateActionsDisplay()
            updateStatus()
            updateMarkers()
            updateConfigList()
        else
            stopAddPositionMode()
        end
        return
    end
    
    if State.AddingPosition then
        if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Q then
            stopAddPositionMode()
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            addPositionAtMouse()
        end
    end
end)

-- Status update loop
task.spawn(function()
    while true do
        if UI.MainFrame.Visible or State.Running then
            updateStatus()
            if State.Running then
                updateActionsDisplay()
                updateMarkers()
            end
        end
        task.wait(0.5)
    end
end)

-- Drag
local dragging, dragStart, startPos
UI.Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = UI.MainFrame.Position
    end
end)
UI.Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        UI.MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- Init
createTowerButtons()
updateStatus()
updateConfigList()
updateActionsDisplay()

print("==========================================")
print("⚡ STRATEGY BUILDER v14.0 - FIXED")
print("==========================================")
print("P = открыть меню")
print("")
print("ФИКСЫ v14.0:")
print("  ✅ Деньги теперь показываются")
print("  ✅ Загрузка конфига обновляет UI сразу")
print("  ✅ Стоимость башен показывается")
print("  ✅ Текст не обрезается")
print("  ✅ Добавлен LOADOUT для смены башен")
print("")
print("LOADOUT использование:")
print("  Введи в поле Loadout: Scout,Sniper,Demoman")
print("  Нажми 📦LOAD")
print("==========================================")

-- ========== FULL AUTO FARM SYSTEM v4 ==========

local TeleportService = game:GetService("TeleportService")
local TDS_GAME_ID = 3260590327

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- ========== НАСТРОЙКИ ==========

AutoFarmSettings = {
    Enabled = false,
    AutoStart = false,
    
    -- Режим игры
    Difficulty = "Molten",  -- Normal, Molten, Fallen, Hardcore, Pizza Party, Badlands, Polluted
    
    -- Задержки
    DelayBeforeLobby = 3,
    DelayBeforeQueue = 5,
}

-- Маппинг режимов (как в том скрипте)
local ModeMapping = {
    ["Hardcore"] = { mode = "hardcore" },
    ["Pizza Party"] = { mode = "halloween" },
    ["Badlands"] = { mode = "badlands" },
    ["Polluted"] = { mode = "polluted" },
    -- Обычные режимы
    ["Normal"] = { difficulty = "Normal", mode = "survival" },
    ["Molten"] = { difficulty = "Molten", mode = "survival" },
    ["Fallen"] = { difficulty = "Fallen", mode = "survival" },
}

-- ========== ОПРЕДЕЛЕНИЕ СОСТОЯНИЯ ==========

local function identifyGameState()
    if playerGui:FindFirstChild("ReactLobbyHud") then
        return "LOBBY"
    elseif playerGui:FindFirstChild("ReactUniversalHotbar") then
        return "GAME"
    end
    return "UNKNOWN"
end

currentGameState = identifyGameState()
print("🎮 Состояние: " .. currentGameState)

-- ========== ФУНКЦИИ ЛОББИ ==========

-- Запуск матчмейкинга (как в том скрипте)
local function startMatchmaking(difficulty)
    local lobbyHud = playerGui:FindFirstChild("ReactLobbyHud")
    if not lobbyHud then return false end
    
    local modeData = ModeMapping[difficulty]
    if not modeData then
        modeData = { difficulty = difficulty, mode = "survival" }
    end
    
    local payload
    if modeData.mode and not modeData.difficulty then
        -- Специальные режимы (Hardcore, Pizza Party и т.д.)
        payload = {
            mode = modeData.mode,
            count = 1
        }
    else
        -- Обычные режимы (Normal, Molten, Fallen)
        payload = {
            difficulty = modeData.difficulty or difficulty,
            mode = modeData.mode or "survival",
            count = 1
        }
    end
    
    local success = false
    repeat
        local ok, result = pcall(function()
            return RemoteFunc:InvokeServer("Multiplayer", "v2:start", payload)
        end)
        
        if ok and result then
            success = true
            print("✅ Матчмейкинг запущен: " .. difficulty)
        else
            task.wait(0.5)
        end
    until success
    
    return success
end

-- Готовность в лобби
local function lobbyReadyUp()
    pcall(function()
        RemoteEvent:FireServer("LobbyVoting", "Ready")
    end)
end

-- Скип волны / голосование
local function runVoteSkip()
    pcall(function()
        RemoteFunc:InvokeServer("Voting", "Skip")
    end)
end

-- Ожидание и готовность в матче
local function matchReadyUp()
    local voteUI = playerGui:WaitForChild("ReactOverridesVote", 30)
    local mainFrame = voteUI and voteUI:WaitForChild("Frame", 30)
    if not mainFrame then return end
    
    -- Ждём появления кнопки ready
    local voteReady = nil
    local timeout = 30
    local elapsed = 0
    
    while not voteReady and elapsed < timeout do
        local voteNode = mainFrame:FindFirstChild("votes")
        if voteNode then
            local container = voteNode:FindFirstChild("container")
            if container then
                voteReady = container:FindFirstChild("ready")
            end
        end
        if not voteReady then
            task.wait(0.5)
            elapsed = elapsed + 0.5
        end
    end
    
    if voteReady then
        repeat task.wait(0.1) until voteReady.Visible == true
        runVoteSkip()
        print("✅ Матч готов, скип нажат")
    end
end

-- ========== ФУНКЦИИ ИГРЫ ==========

-- Отправка в лобби
local function sendToLobby()
    task.wait(1)
    pcall(function()
        local lobbyRemote = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Teleport"):WaitForChild("RE:backToLobby")
        lobbyRemote:FireServer()
    end)
end

-- Ожидание конца игры
local function waitForGameEnd()
    local rewardsSection
    repeat
        task.wait(1)
        
        local root = playerGui:FindFirstChild("ReactGameNewRewards")
        local frame = root and root:FindFirstChild("Frame")
        local gameOver = frame and frame:FindFirstChild("gameOver")
        local rewardsScreen = gameOver and gameOver:FindFirstChild("RewardsScreen")
        rewardsSection = rewardsScreen and rewardsScreen:FindFirstChild("RewardsSection")
        
    until rewardsSection
    
    return true
end

-- Проверка: мы в лобби?
local function isInLobby()
    return playerGui:FindFirstChild("ReactLobbyHud") ~= nil
end

-- Проверка: мы в игре?
local function isInGame()
    return playerGui:FindFirstChild("ReactUniversalHotbar") ~= nil
end

-- Проверка: игра окончена?
local function isGameEnded()
    local root = playerGui:FindFirstChild("ReactGameNewRewards")
    if not root then return false end
    
    local frame = root:FindFirstChild("Frame")
    local gameOver = frame and frame:FindFirstChild("gameOver")
    local rewardsScreen = gameOver and gameOver:FindFirstChild("RewardsScreen")
    return rewardsScreen and rewardsScreen:FindFirstChild("RewardsSection") ~= nil
end

-- ========== ANTI-AFK ==========

local function startAntiAFK()
    local GC = getconnections or get_signal_cons
    
    if GC then
        pcall(function()
            for _, v in pairs(GC(player.Idled)) do
                if v.Disable then v:Disable()
                elseif v.Disconnect then v:Disconnect() end
            end
        end)
    end
    
    player.Idled:Connect(function()
        local VirtualUser = game:GetService("VirtualUser")
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    
    print("✅ Anti-AFK активирован")
end

-- ========== REJOIN ON DISCONNECT ==========

local function startRejoinOnDisconnect()
    game.Players.PlayerRemoving:Connect(function(plr)
        if plr == player then
            TeleportService:Teleport(TDS_GAME_ID, plr)
        end
    end)
    print("✅ Auto-rejoin on disconnect активирован")
end

-- ========== ГЛАВНЫЙ ЦИКЛ AUTO FARM ==========

local autoFarmRunning = false
local autoStartTriggered = false

local function startAutoFarmLoop()
    if autoFarmRunning then return end
    autoFarmRunning = true
    
    task.spawn(function()
        print("🚀 AUTO FARM LOOP STARTED")
        print("   Режим: " .. AutoFarmSettings.Difficulty)
        
        while AutoFarmSettings.Enabled and autoFarmRunning do
            
            -- === ЛОББИ ===
            if isInLobby() then
                State.LastLog = "📍 В лобби. Запуск " .. AutoFarmSettings.Difficulty .. "..."
                updateStatus()
                
                task.wait(AutoFarmSettings.DelayBeforeQueue)
                
                -- Запускаем матчмейкинг
                if AutoFarmSettings.Enabled then
                    startMatchmaking(AutoFarmSettings.Difficulty)
                    
                    -- Ждём пока попадём в игру
                    local timeout = 120
                    local elapsed = 0
                    while isInLobby() and elapsed < timeout and AutoFarmSettings.Enabled do
                        State.LastLog = "⏳ Поиск матча... " .. elapsed .. "s"
                        updateStatus()
                        task.wait(2)
                        elapsed = elapsed + 2
                    end
                end
                
            -- === В ИГРЕ ===
            elseif isInGame() then
                
                -- Игра только началась
                if not isGameEnded() then
                    
                    -- Ждём ready и скипаем
                    task.spawn(function()
                        matchReadyUp()
                    end)
                    
                    -- Авто-старт стратегии
                    if AutoFarmSettings.AutoStart and not State.Running and not autoStartTriggered then
                        if #Strategy.Actions > 0 then
                            State.LastLog = "▶ Авто-старт стратегии!"
                            updateStatus()
                            autoStartTriggered = true
                            task.wait(3)
                            task.spawn(runStrategy)
                        end
                    end
                    
                    -- Ждём конца игры
                    State.LastLog = "🎮 Игра идёт... Ожидание завершения"
                    updateStatus()
                    
                    while isInGame() and not isGameEnded() and AutoFarmSettings.Enabled do
                        task.wait(2)
                    end
                end
                
                -- Игра окончена
                if isGameEnded() then
                    State.LastLog = "🏁 Игра окончена! Возврат в лобби..."
                    updateStatus()
                    autoStartTriggered = false
                    
                    -- Останавливаем стратегию
                    State.Running = false
                    stopAllLoops()
                    
                    task.wait(AutoFarmSettings.DelayBeforeLobby)
                    sendToLobby()
                    
                    -- Ждём пока попадём в лобби
                    while not isInLobby() and AutoFarmSettings.Enabled do
                        task.wait(1)
                    end
                end
            end
            
            task.wait(1)
        end
        
        autoFarmRunning = false
        print("⏹ AUTO FARM LOOP STOPPED")
    end)
end

local function stopAutoFarmLoop()
    autoFarmRunning = false
    AutoFarmSettings.Enabled = false
end

-- ========== UI ==========

-- Увеличиваем UI.GlobalSection
UI.GlobalSection.Size = UDim2.new(1, 0, 0, 124)

-- Перемещаем существующие кнопки
UI.GlobalSkipBtn.Position = UDim2.new(0.5, 0, 0, 32)

-- === AUTO FARM кнопка ===
UI.AutoFarmBtn = Instance.new("TextButton")
UI.AutoFarmBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.AutoFarmBtn.Position = UDim2.new(0, 5, 0, 32)
UI.AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
UI.AutoFarmBtn.Text = tr("auto_farm_off")
UI.AutoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
UI.AutoFarmBtn.TextSize = 9
UI.AutoFarmBtn.Font = Enum.Font.GothamBold
UI.AutoFarmBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.AutoFarmBtn).CornerRadius = UDim.new(0, 5)

-- === AUTO START кнопка ===
UI.AutoStartBtn = Instance.new("TextButton")
UI.AutoStartBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.AutoStartBtn.Position = UDim2.new(0, 5, 0, 60)
UI.AutoStartBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
UI.AutoStartBtn.Text = tr("auto_start_off")
UI.AutoStartBtn.TextColor3 = Color3.new(1, 1, 1)
UI.AutoStartBtn.TextSize = 9
UI.AutoStartBtn.Font = Enum.Font.GothamBold
UI.AutoStartBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.AutoStartBtn).CornerRadius = UDim.new(0, 5)

-- === РЕЖИМ кнопка ===
UI.ModeBtn = Instance.new("TextButton")
UI.ModeBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.ModeBtn.Position = UDim2.new(0.5, 0, 0, 60)
UI.ModeBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
UI.ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
UI.ModeBtn.TextColor3 = Color3.new(1, 1, 1)
UI.ModeBtn.TextSize = 9
UI.ModeBtn.Font = Enum.Font.GothamBold
UI.ModeBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.ModeBtn).CornerRadius = UDim.new(0, 5)

-- === СТАТУС ===
UI.FarmStatusLabel = Instance.new("TextLabel")
UI.FarmStatusLabel.Size = UDim2.new(0.98, -5, 0, 24)
UI.FarmStatusLabel.Position = UDim2.new(0, 5, 0, 88)
UI.FarmStatusLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
UI.FarmStatusLabel.Text = tr("farm_status_prefix") .. currentGameState
UI.FarmStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
UI.FarmStatusLabel.TextSize = 9
UI.FarmStatusLabel.Font = Enum.Font.Gotham
UI.FarmStatusLabel.Parent = UI.GlobalSection
Instance.new("UICorner", UI.FarmStatusLabel).CornerRadius = UDim.new(0, 5)

-- Список режимов для переключения
local ModeList = {"Normal", "Molten", "Fallen", "Hardcore", "Pizza Party", "Badlands", "Polluted"}
local currentModeIndex = 2  -- Molten по умолчанию

-- ========== СОБЫТИЯ ==========

UI.AutoFarmBtn.MouseButton1Click:Connect(function()
    AutoFarmSettings.Enabled = not AutoFarmSettings.Enabled
    
    if AutoFarmSettings.Enabled then
        UI.AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        UI.AutoFarmBtn.Text = tr("auto_farm_on")
        State.LastLog = "🔄 Auto Farm ВКЛ: " .. AutoFarmSettings.Difficulty
        startAutoFarmLoop()
    else
        UI.AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        UI.AutoFarmBtn.Text = tr("auto_farm_off")
        State.LastLog = "🔄 Auto Farm ВЫКЛ"
        stopAutoFarmLoop()
    end
    updateStatus()
end)

UI.AutoStartBtn.MouseButton1Click:Connect(function()
    AutoFarmSettings.AutoStart = not AutoFarmSettings.AutoStart
    
    if AutoFarmSettings.AutoStart then
        UI.AutoStartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        UI.AutoStartBtn.Text = tr("auto_start_on")
        State.LastLog = "▶ Auto Start ВКЛ"
    else
        UI.AutoStartBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
        UI.AutoStartBtn.Text = tr("auto_start_off")
        State.LastLog = "▶ Auto Start ВЫКЛ"
    end
    updateStatus()
end)

UI.ModeBtn.MouseButton1Click:Connect(function()
    -- Переключаем на следующий режим
    currentModeIndex = currentModeIndex + 1
    if currentModeIndex > #ModeList then
        currentModeIndex = 1
    end
    
    AutoFarmSettings.Difficulty = ModeList[currentModeIndex]
    UI.ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
    State.LastLog = "🗺 Режим: " .. AutoFarmSettings.Difficulty
    updateStatus()
end)

-- Обновление статуса
task.spawn(function()
    while true do
        task.wait(2)
        
        local state = "❓"
        if isInLobby() then
            state = "📍 LOBBY"
        elseif isInGame() then
            if isGameEnded() then
                state = "🏁 GAME ENDED"
            else
                state = "🎮 IN GAME | Wave " .. getCurrentWave()
            end
        end
        
        local farmStatus = AutoFarmSettings.Enabled and "🟢" or "⚫"
        UI.FarmStatusLabel.Text = farmStatus .. " " .. state .. " | " .. AutoFarmSettings.Difficulty
    end
end)

-- ========== ЗАПУСК ==========

startAntiAFK()
startRejoinOnDisconnect()

print("==========================================")
print("🚀 FULL AUTO FARM SYSTEM v4 LOADED")
print("==========================================")
print("Режимы: Normal, Molten, Fallen, Hardcore,")
print("        Pizza Party, Badlands, Polluted")
print("")
print("Как использовать:")
print("  1. Загрузи стратегию")
print("  2. Выбери режим (кнопка 🗺)")
print("  3. Включи AUTO START: ON")
print("  4. Включи AUTO FARM: ON")
print("  5. AFK! 🎮")
print("==========================================")

-- ========== AUTO PICKUPS SYSTEM ==========

local autoPickupsRunning = false
local autoPickupsEnabled = false

-- Проверка что предмет не в войде
local function isVoidItem(obj)
    return math.abs(obj.Position.Y) > 999999
end

-- Получить HumanoidRootPart игрока
local function getRoot()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Функция авто-сбора
local function startAutoPickups()
    if autoPickupsRunning then return end
    autoPickupsRunning = true

    task.spawn(function()
        print("🎁 Auto Pickups запущен!")

        while autoPickupsRunning and autoPickupsEnabled do
            local pickupsFolder = workspace:FindFirstChild("Pickups")
            local hrp = getRoot()

            if pickupsFolder and hrp then
                local char = hrp.Parent
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")

                local function moveToPos(targetPos)
                    if not humanoid then return false end
                    local function moveDirect(pos)
                        humanoid:MoveTo(pos)
                        local startT = os.clock()
                        while os.clock() - startT < 2 do
                            if not autoPickupsRunning or not autoPickupsEnabled then
                                return false
                            end
                            if (hrp.Position - pos).Magnitude < 4 then
                                return true
                            end
                            task.wait(0.1)
                        end
                        return (hrp.Position - pos).Magnitude < 4
                    end

                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2,
                        AgentHeight = 6,
                        AgentCanJump = true,
                        AgentJumpHeight = 7,
                        AgentMaxSlope = 45
                    })
                    local ok = pcall(function()
                        path:ComputeAsync(hrp.Position, targetPos)
                    end)
                    if ok and path.Status == Enum.PathStatus.Success then
                        for _, wp in ipairs(path:GetWaypoints()) do
                            if not autoPickupsRunning or not autoPickupsEnabled then
                                return false
                            end
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                humanoid.Jump = true
                            end
                            if not moveDirect(wp.Position) then
                                return false
                            end
                        end
                        return true
                    end
                    return moveDirect(targetPos)
                end

                for _, item in ipairs(pickupsFolder:GetChildren()) do
                    if not autoPickupsRunning or not autoPickupsEnabled then break end

                    -- Собираем предметы
                    if item:IsA("MeshPart") or item:IsA("Part") or item:IsA("BasePart") then
                        if not isVoidItem(item) then
                            pcall(function()
                                if AutoPickupsMode == "Pathfinding" then
                                    local targetPos = item.Position + Vector3.new(0, 3, 0)
                                    moveToPos(targetPos)
                                    task.wait(0.2)
                                else
                                    -- Сохраняем позицию
                                    local oldPos = hrp.CFrame

                                    -- Телепортируемся к предмету
                                    hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                                    task.wait(0.2)

                                    -- Возвращаемся назад
                                    hrp.CFrame = oldPos
                                    task.wait(0.3)
                                end
                            end)
                        end
                    end
                end
            end

            task.wait(1)
        end

        autoPickupsRunning = false
        print("🎁 Auto Pickups остановлен")
    end)
end

local function stopAutoPickups()
    autoPickupsRunning = false
    autoPickupsEnabled = false
end

-- ========== UI ДЛЯ AUTO PICKUPS ==========

-- Увеличиваем UI.GlobalSection
UI.GlobalSection.Size = UDim2.new(1, 0, 0, 152)

-- Кнопка AUTO PICKUPS
UI.AutoPickupsBtn = Instance.new("TextButton")
UI.AutoPickupsBtn.Size = UDim2.new(0.48, -3, 0, 24)
UI.AutoPickupsBtn.Position = UDim2.new(0, 5, 0, 116)
UI.AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 80)
UI.AutoPickupsBtn.Text = "🎁 PICKUPS: OFF"
UI.AutoPickupsBtn.TextColor3 = Color3.new(1, 1, 1)
UI.AutoPickupsBtn.TextSize = 9
UI.AutoPickupsBtn.Font = Enum.Font.GothamBold
UI.AutoPickupsBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.AutoPickupsBtn).CornerRadius = UDim.new(0, 5)

-- Кнопка для статуса/инфо
UI.PickupsStatusLabel = Instance.new("TextLabel")
UI.PickupsStatusLabel.Size = UDim2.new(0.48, -3, 0, 24)
UI.PickupsStatusLabel.Position = UDim2.new(0.5, 0, 0, 116)
UI.PickupsStatusLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
UI.PickupsStatusLabel.Text = tr("pickups_collected", 0)
UI.PickupsStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
UI.PickupsStatusLabel.TextSize = 9
UI.PickupsStatusLabel.Font = Enum.Font.Gotham
UI.PickupsStatusLabel.Parent = UI.GlobalSection
Instance.new("UICorner", UI.PickupsStatusLabel).CornerRadius = UDim.new(0, 5)

-- Счётчик собранных предметов
pickupsCollected = 0

UI.AutoPickupsBtn.MouseButton1Click:Connect(function()
    autoPickupsEnabled = not autoPickupsEnabled

    if autoPickupsEnabled then
        UI.AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
        UI.AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
        startAutoPickups()
        State.LastLog = "🎁 Auto Pickups ВКЛ"
    else
        UI.AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 80)
        UI.AutoPickupsBtn.Text = "🎁 PICKUPS: OFF"
        stopAutoPickups()
        State.LastLog = "🎁 Auto Pickups ВЫКЛ"
    end
    updateStatus()
end)

-- ========== ЗАГРУЗКА НАСТРОЕК AUTO PICKUPS ==========

do
    local autoCfg = getAutoCfg()
    if autoCfg and autoCfg.GlobalAutoPickups then
        autoPickupsEnabled = true
        UI.AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
        UI.AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
        startAutoPickups()
        print("✅ Auto Pickups: ON")
    end
end

print("==========================================")
print("🎁 AUTO PICKUPS SYSTEM LOADED")
print("   Собирает: SnowCharm, Lorebook и др.")
print("==========================================")

-- ========== AUTO LOAD CONFIG ==========

-- Проверяем настройки из autoexec
local autoCfg = getAutoCfg()
if autoCfg then
    print("🔧 Найдены настройки автофарма!")
    
    -- Загружаем конфиг
    if autoCfg.ConfigName and autoCfg.ConfigName ~= "" then
        local configName = autoCfg.ConfigName
        if type(configName) ~= "string" then
            warn("⚠️ ConfigName не строка: " .. tostring(configName))
        else
        
        task.wait(1)  -- Ждём инициализацию
        
        local success, msg = safeAutoLoadStrategy(configName)
        if success then
            print("✅ Конфиг загружен: " .. configName)
            State.LastLog = "✅ Конфиг: " .. configName
            updateActionsDisplay()
            updateMarkers()
        else
            warn("❌ Ошибка загрузки конфига: " .. tostring(msg))
            State.LastLog = "❌ " .. tostring(msg)
        end
        updateStatus()
        end
    end
    
    -- Устанавливаем режим
    if autoCfg.Difficulty then
        AutoFarmSettings.Difficulty = autoCfg.Difficulty
        
        -- Обновляем индекс
        for i, mode in ipairs(ModeList) do
            if mode == AutoFarmSettings.Difficulty then
                currentModeIndex = i
                break
            end
        end
        
        UI.ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
        print("✅ Режим: " .. AutoFarmSettings.Difficulty)
    end
    
    -- Включаем AUTO START
    if autoCfg.AutoStart then
        AutoFarmSettings.AutoStart = true
        UI.AutoStartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        UI.AutoStartBtn.Text = tr("auto_start_on")
        print("✅ Auto Start: ON")
    end
    
    -- Включаем AUTO FARM
    if autoCfg.Enabled then
        task.wait(2)  -- Небольшая задержка
        
        AutoFarmSettings.Enabled = true
        UI.AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        UI.AutoFarmBtn.Text = tr("auto_farm_on")
        startAutoFarmLoop()
        print("✅ Auto Farm: ON")
    end
    
    State.LastLog = "🚀 Автофарм запущен: " .. (AutoFarmSettings.Difficulty or "?")
    
        -- Auto Skip
    if autoCfg.GlobalAutoSkip then
        Settings.GlobalAutoSkip = true
        UI.GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
        UI.GlobalSkipBtn.Text = tr("global_skip_on")
        startGlobalAutoSkip()
        print("✅ Global Auto Skip: ON")
    end
    
    -- Auto Chain
    if autoCfg.GlobalAutoChain then
        Settings.GlobalAutoChain = true
        UI.GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        UI.GlobalChainBtn.Text = tr("global_chain_on")
        startGlobalAutoChain()
        print("✅ Global Auto Chain: ON")
    end
    
    -- Auto DJ
    if autoCfg.GlobalAutoDJ then
        Settings.GlobalAutoDJ = true
        UI.GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
        UI.GlobalDJBtn.Text = tr("global_dj_on")
        startGlobalAutoDJ()
        print("✅ Global Auto DJ: ON")
    end
    
    if autoCfg.GlobalAutoPickups then
        autoPickupsEnabled = true
        UI.AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
        UI.AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
        startAutoPickups()
        print("✅ Auto Pickups: ON")
    end
    
    updateStatus()
else
    local rawCfg = rawget(_G, "TDS_AutoFarm")
    if rawCfg ~= nil then
        warn("⚠️ _G.TDS_AutoFarm не таблица: " .. tostring(rawCfg))
    end
end

print("==========================================")
print("🚀 READY FOR AFK FARMING!")
print("==========================================")

-- ========== СИСТЕМА КОНФИГОВ АВТОФАРМА ==========

local AUTOFARM_FOLDER = "TDS_AutoFarm_Configs"
local SCRIPT_URL = "https://raw.githubusercontent.com/mcmcmcfdfdffd/nulallll/refs/heads/main/null.lua"  -- ЗАМЕНИ НА СВОЮ!

-- Создаём папку для конфигов автофарма
if isfolder and not isfolder(AUTOFARM_FOLDER) then
    makefolder(AUTOFARM_FOLDER)
end

-- Настройки queue_on_teleport
QueueSettings = {
    Enabled = false,
    ConfigName = "",
}

-- Получить список конфигов автофарма
local function getAutoFarmConfigs()
    local files = {}
    pcall(function()
        if isfolder(AUTOFARM_FOLDER) then
            local allFiles = listfiles(AUTOFARM_FOLDER)
            for _, filePath in ipairs(allFiles) do
                local fileName = filePath:match("([^/\\]+)%.json$")
                if fileName then
                    table.insert(files, fileName)
                end
            end
        end
    end)
    table.sort(files)
    return files
end

-- Настройка queue_on_teleport
local function setupQueueOnTeleport(configName)
    if not QueueSettings.Enabled then return end
    
    local scriptCode = [[
        if not game:IsLoaded() then
            game.Loaded:Wait()
        end
        
        task.wait(5)
        
        local player = game:GetService("Players").LocalPlayer
        local playerGui = player:WaitForChild("PlayerGui", 30)
        
        local timeout = 30
        local elapsed = 0
        while elapsed < timeout do
            if playerGui:FindFirstChild("ReactUniversalHotbar") or 
               playerGui:FindFirstChild("ReactLobbyHud") then
                break
            end
            task.wait(1)
            elapsed = elapsed + 1
        end
        
        task.wait(2)
        
        if game.PlaceId == 3260590327 or game.PlaceId == 5591597781 then
            _G.TDS_AutoFarm_LoadConfig = "CONFIG_NAME_PLACEHOLDER"
            loadstring(game:HttpGet("SCRIPT_URL_PLACEHOLDER"))()
        end
    ]]
    
    scriptCode = scriptCode:gsub("CONFIG_NAME_PLACEHOLDER", configName)
    scriptCode = scriptCode:gsub("SCRIPT_URL_PLACEHOLDER", SCRIPT_URL)
    
    if queue_on_teleport then
        queue_on_teleport(scriptCode)
    elseif queueonteleport then
        queueonteleport(scriptCode)
    end
    
    print("✅ Queue on teleport настроен для: " .. configName)
end

-- Сохранить конфиг автофарма
local function saveAutoFarmConfig(name)
    if not name or name == "" then 
        State.LastLog = "❌ Введи имя конфига!"
        updateStatus()
        return false 
    end
    
    local config = {
        name = name,
        version = "1.0",
        
        -- Настройки автофарма
        Enabled = true,
        AutoStart = AutoFarmSettings.AutoStart,
        StrategyName = Strategy.Name or "",
        Difficulty = AutoFarmSettings.Difficulty,
        
        -- Глобальные функции
        GlobalAutoSkip = Settings.GlobalAutoSkip,
        GlobalAutoChain = Settings.GlobalAutoChain,
        GlobalAutoDJ = Settings.GlobalAutoDJ,
        GlobalAutoPickups = autoPickupsEnabled,
        
        -- Queue on teleport
        QueueEnabled = true,
    }
    
    local filePath = AUTOFARM_FOLDER .. "/" .. name .. ".json"
    
    pcall(function()
        writefile(filePath, HttpService:JSONEncode(config))
    end)
    
    print("💾 Конфиг автофарма сохранён: " .. name)
    State.LastLog = "💾 Сохранено: " .. name
    updateStatus()
    return true
end

-- Загрузить конфиг автофарма
local function loadAutoFarmConfig(name)
    if not name or name == "" then return false end
    
    local filePath = AUTOFARM_FOLDER .. "/" .. name .. ".json"
    
    if not isfile(filePath) then
        State.LastLog = "❌ Конфиг не найден: " .. name
        updateStatus()
        return false
    end
    
    local success, err = pcall(function()
        local json = readfile(filePath)
        local config = HttpService:JSONDecode(json)
        
        -- Загружаем стратегию если указана
        if config.StrategyName and config.StrategyName ~= "" then
            local success, msg = safeLoadStrategy(config.StrategyName)
            if success then
                updateActionsDisplay()
                updateMarkers()
            else
                State.LastLog = "❌ " .. tostring(msg)
            end
        end
        
        -- Применяем режим
        if config.Difficulty then
            AutoFarmSettings.Difficulty = config.Difficulty
            for i, mode in ipairs(ModeList) do
                if mode == config.Difficulty then
                    currentModeIndex = i
                    break
                end
            end
            UI.ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
        end
        
        -- Auto Start
        if config.AutoStart then
            AutoFarmSettings.AutoStart = true
            UI.AutoStartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
            UI.AutoStartBtn.Text = tr("auto_start_on")
        end
        
        -- Auto Skip
        if config.GlobalAutoSkip then
            Settings.GlobalAutoSkip = true
            UI.GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
            UI.GlobalSkipBtn.Text = tr("global_skip_on")
            startGlobalAutoSkip()
        end
        
        -- Auto Chain
        if config.GlobalAutoChain then
            Settings.GlobalAutoChain = true
            UI.GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
            UI.GlobalChainBtn.Text = tr("global_chain_on")
            startGlobalAutoChain()
        end
        
        -- Auto DJ
        if config.GlobalAutoDJ then
            Settings.GlobalAutoDJ = true
            UI.GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
            UI.GlobalDJBtn.Text = tr("global_dj_on")
            startGlobalAutoDJ()
        end
        
        -- Auto Pickups
        if config.GlobalAutoPickups then
            autoPickupsEnabled = true
            UI.AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
            UI.AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
            startAutoPickups()
        end
        
        -- Queue on teleport
        QueueSettings.Enabled = config.QueueEnabled or false
        QueueSettings.ConfigName = name
        
        if QueueSettings.Enabled then
            if UI.QueueToggleBtn then
            UI.QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
            UI.QueueToggleBtn.Text = tr("queue_on")
            end
            setupQueueOnTeleport(name)
        end
        
        -- Auto Farm (последним)
        if config.Enabled then
            task.wait(1)
            AutoFarmSettings.Enabled = true
            UI.AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
            UI.AutoFarmBtn.Text = tr("auto_farm_on")
            startAutoFarmLoop()
        end
    end)
    
    if success then
    print("📂 Конфиг автофарма загружен: " .. name)
    State.LastLog = "📂 Загружено: " .. name
else
    State.LastLog = "❌ Ошибка: " .. tostring(err):sub(1, 50)
    print("❌ ПОЛНАЯ ОШИБКА:", err)  -- В консоль полный текст
end
    updateStatus()
    
    return success
end

-- Удалить конфиг автофарма
local function deleteAutoFarmConfig(name)
    if not name or name == "" then return false end
    
    local filePath = AUTOFARM_FOLDER .. "/" .. name .. ".json"
    
    if isfile(filePath) then
        pcall(function() delfile(filePath) end)
        State.LastLog = "🗑 Удалено: " .. name
        updateStatus()
        return true
    end
    
    return false
end

-- Отключить queue_on_teleport
local function disableQueueOnTeleport()
    if queue_on_teleport then
        queue_on_teleport("")
    elseif queueonteleport then
        queueonteleport("")
    end
    print("❌ Queue on teleport отключён")
end

-- ========== UI ДЛЯ КОНФИГА АВТОФАРМА ==========

-- Увеличиваем UI.GlobalSection чтобы влезло всё
UI.GlobalSection.Size = UDim2.new(1, 0, 0, 224)

-- Перемещаем статус пикапов
UI.PickupsStatusLabel.Position = UDim2.new(0.5, 0, 0, 116)

-- Разделитель
UI.AFSeparator = Instance.new("Frame")
UI.AFSeparator.Size = UDim2.new(0.96, 0, 0, 2)
UI.AFSeparator.Position = UDim2.new(0.02, 0, 0, 146)
UI.AFSeparator.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
UI.AFSeparator.BorderSizePixel = 0
UI.AFSeparator.Parent = UI.GlobalSection

-- Заголовок секции
UI.AutoFarmConfigTitle = Instance.new("TextLabel")
UI.AutoFarmConfigTitle.Size = UDim2.new(1, -10, 0, 12)
UI.AutoFarmConfigTitle.Position = UDim2.new(0, 5, 0, 152)
UI.AutoFarmConfigTitle.BackgroundTransparency = 1
UI.AutoFarmConfigTitle.Text = tr("autofarm_config_title")
UI.AutoFarmConfigTitle.TextColor3 = Color3.fromRGB(255, 180, 100)
UI.AutoFarmConfigTitle.TextSize = 9
UI.AutoFarmConfigTitle.Font = Enum.Font.GothamBold
UI.AutoFarmConfigTitle.TextXAlignment = Enum.TextXAlignment.Left
UI.AutoFarmConfigTitle.Parent = UI.GlobalSection

-- Поле для имени конфига
UI.AutoFarmConfigNameBox = Instance.new("TextBox")
UI.AutoFarmConfigNameBox.Size = UDim2.new(0.55, -8, 0, 20)
UI.AutoFarmConfigNameBox.Position = UDim2.new(0, 5, 0, 166)
UI.AutoFarmConfigNameBox.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
UI.AutoFarmConfigNameBox.Text = ""
UI.AutoFarmConfigNameBox.PlaceholderText = tr("autofarm_config_placeholder")
UI.AutoFarmConfigNameBox.TextColor3 = Color3.new(1, 1, 1)
UI.AutoFarmConfigNameBox.TextSize = 9
UI.AutoFarmConfigNameBox.Font = Enum.Font.Gotham
UI.AutoFarmConfigNameBox.Parent = UI.GlobalSection
Instance.new("UICorner", UI.AutoFarmConfigNameBox).CornerRadius = UDim.new(0, 5)

-- Кнопка SAVE
UI.SaveAutoFarmBtn = Instance.new("TextButton")
UI.SaveAutoFarmBtn.Size = UDim2.new(0.22, -3, 0, 20)
UI.SaveAutoFarmBtn.Position = UDim2.new(0.55, 0, 0, 166)
UI.SaveAutoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
UI.SaveAutoFarmBtn.Text = "💾"
UI.SaveAutoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
UI.SaveAutoFarmBtn.TextSize = 11
UI.SaveAutoFarmBtn.Font = Enum.Font.GothamBold
UI.SaveAutoFarmBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.SaveAutoFarmBtn).CornerRadius = UDim.new(0, 5)

-- Кнопка REFRESH
UI.RefreshAutoFarmBtn = Instance.new("TextButton")
UI.RefreshAutoFarmBtn.Size = UDim2.new(0.22, -3, 0, 20)
UI.RefreshAutoFarmBtn.Position = UDim2.new(0.77, 0, 0, 166)
UI.RefreshAutoFarmBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 140)
UI.RefreshAutoFarmBtn.Text = "🔄"
UI.RefreshAutoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
UI.RefreshAutoFarmBtn.TextSize = 11
UI.RefreshAutoFarmBtn.Font = Enum.Font.GothamBold
UI.RefreshAutoFarmBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.RefreshAutoFarmBtn).CornerRadius = UDim.new(0, 5)

-- Скролл для списка конфигов
UI.AutoFarmConfigScroll = Instance.new("ScrollingFrame")
UI.AutoFarmConfigScroll.Size = UDim2.new(0.65, -8, 0, 22)
UI.AutoFarmConfigScroll.Position = UDim2.new(0, 5, 0, 190)
UI.AutoFarmConfigScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
UI.AutoFarmConfigScroll.ScrollBarThickness = 3
UI.AutoFarmConfigScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
UI.AutoFarmConfigScroll.ScrollingDirection = Enum.ScrollingDirection.X
UI.AutoFarmConfigScroll.Parent = UI.GlobalSection
Instance.new("UICorner", UI.AutoFarmConfigScroll).CornerRadius = UDim.new(0, 5)

UI.AutoFarmConfigLayout = Instance.new("UIListLayout", UI.AutoFarmConfigScroll)
UI.AutoFarmConfigLayout.FillDirection = Enum.FillDirection.Horizontal
UI.AutoFarmConfigLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", UI.AutoFarmConfigScroll).PaddingLeft = UDim.new(0, 3)

-- Кнопка QUEUE ON/OFF
UI.QueueToggleBtn = Instance.new("TextButton")
UI.QueueToggleBtn.Size = UDim2.new(0.33, -5, 0, 22)
UI.QueueToggleBtn.Position = UDim2.new(0.66, 0, 0, 190)
UI.QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
UI.QueueToggleBtn.Text = tr("queue_off")
UI.QueueToggleBtn.TextColor3 = Color3.new(1, 1, 1)
UI.QueueToggleBtn.TextSize = 8
UI.QueueToggleBtn.Font = Enum.Font.GothamBold
UI.QueueToggleBtn.Parent = UI.GlobalSection
Instance.new("UICorner", UI.QueueToggleBtn).CornerRadius = UDim.new(0, 5)

-- Обновление списка конфигов автофарма
local function updateAutoFarmConfigList()
    for _, child in pairs(UI.AutoFarmConfigScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local files = getAutoFarmConfigs()
    
    for _, fileName in ipairs(files) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 80, 0, 20)
        btn.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
        btn.Text = "⚙️ " .. fileName:sub(1, 8)
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.TextSize = 8
        btn.Font = Enum.Font.GothamBold
        btn.Parent = UI.AutoFarmConfigScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        -- ЛКМ = загрузить
        btn.MouseButton1Click:Connect(function()
            loadAutoFarmConfig(fileName)
            UI.AutoFarmConfigNameBox.Text = fileName
        end)
        
        -- ПКМ = удалить
        btn.MouseButton2Click:Connect(function()
            deleteAutoFarmConfig(fileName)
            updateAutoFarmConfigList()
        end)
    end
end

-- ========== СОБЫТИЯ ==========

UI.SaveAutoFarmBtn.MouseButton1Click:Connect(function()
    local name = UI.AutoFarmConfigNameBox.Text
    if saveAutoFarmConfig(name) then
        updateAutoFarmConfigList()
        if QueueSettings.Enabled then
            setupQueueOnTeleport(name)
        end
    end
end)

UI.RefreshAutoFarmBtn.MouseButton1Click:Connect(function()
    updateAutoFarmConfigList()
    State.LastLog = "🔄 Список обновлён"
    updateStatus()
end)

UI.QueueToggleBtn.MouseButton1Click:Connect(function()
    QueueSettings.Enabled = not QueueSettings.Enabled
    
    if QueueSettings.Enabled then
        UI.QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        UI.QueueToggleBtn.Text = tr("queue_on")
        
        local configName = UI.AutoFarmConfigNameBox.Text
        if configName ~= "" then
            setupQueueOnTeleport(configName)
            State.LastLog = "🔄 Queue ON: " .. configName
        else
            State.LastLog = "⚠️ Сначала сохрани конфиг!"
        end
    else
        UI.QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        UI.QueueToggleBtn.Text = tr("queue_off")
        disableQueueOnTeleport()
        State.LastLog = "🔄 Queue OFF"
    end
    updateStatus()
end)

-- Загружаем конфиг если указан в _G
if _G.TDS_AutoFarm_LoadConfig then
    task.wait(0.5)
    loadAutoFarmConfig(_G.TDS_AutoFarm_LoadConfig)
    
    -- Обновляем UI кнопки Queue после загрузки
    if QueueSettings.Enabled and UI.QueueToggleBtn then
        UI.QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        UI.QueueToggleBtn.Text = tr("queue_on")
    end
end

-- Инициализация
updateAutoFarmConfigList()

print("==========================================")
print("⚙️ AUTOFARM CONFIG SYSTEM LOADED")
print("")
print("2 типа конфигов:")
print("  📋 Стратегии - действия (Place, Upgrade)")
print("  ⚙️ Автофарм - настройки бота")
print("")
print("Queue on teleport:")
print("  🔄 QUEUE: ON - скрипт загрузится после ТП")
print("==========================================")

