local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

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
    if TowerReplicator then return end
    
    print("⏳ Загрузка модулей...")
    
    -- TowerReplicator
    pcall(function()
        if ReplicatedStorage:FindFirstChild("Client") then
            local modules = ReplicatedStorage.Client:FindFirstChild("Modules")
            if modules then
                -- НОВЫЙ ПУТЬ
                local replicators = modules:FindFirstChild("Replicators")
                if replicators and replicators:FindFirstChild("TowerReplicator") then
                    TowerReplicator = require(replicators.TowerReplicator)
                    print("✅ TowerReplicator")
                end
            end
        end
    end)
    
    -- SharedGameFunctions, SharedGameConstants, Asset
    pcall(function()
        if ReplicatedStorage:FindFirstChild("Shared") then
            local modules = ReplicatedStorage.Shared:FindFirstChild("Modules")
            if modules then
                if modules:FindFirstChild("SharedGameFunctions") then
                    SharedGameFunctions = require(modules.SharedGameFunctions)
                    print("✅ SharedGameFunctions")
                end
                if modules:FindFirstChild("SharedGameConstants") then
                    SharedGameConstants = require(modules.SharedGameConstants)
                    print("✅ SharedGameConstants")
                end
                if modules:FindFirstChild("Asset") then
                    Asset = require(modules.Asset)
                    print("✅ Asset")
                end
            end
        end
    end)
    
    -- InventoryStore
    pcall(function()
        local stores = ReplicatedStorage:FindFirstChild("Client")
        if stores then
            local path1 = stores:FindFirstChild("Interfaces")
            if path1 then
                local path2 = path1:FindFirstChild("NewInterface")
                if path2 then
                    local path3 = path2:FindFirstChild("Stores")
                    if path3 and path3:FindFirstChild("Inventory") then
                        InventoryStore = require(path3.Inventory)
                        print("✅ InventoryStore")
                    end
                end
            end
        end
    end)
    
    -- TowerIcons
    pcall(function()
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if shared then
            local data = shared:FindFirstChild("Data")
            if data then
                local icons = data:FindFirstChild("Icons")
                if icons then
                    TowerIcons = require(icons).Towers
                    print("✅ TowerIcons")
                end
            end
        end
    end)
    
    print("✅ Загрузка модулей завершена!")
end

-- СРАЗУ ЗАГРУЖАЕМ МОДУЛИ (НЕ В ФОНЕ!)
task.spawn(function()
    task.wait(2)
    loadModules()
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
    ABILITY = "ABILITY",
    ABILITY_LOOP = "ABILITY_LOOP",
    SET_OPTION = "SET_OPTION",
    WAIT_WAVE = "WAIT_WAVE",
    WAIT_TIME = "WAIT_TIME",
    WAIT_CASH = "WAIT_CASH",
    VOTE_SKIP = "VOTE_SKIP",
    AUTO_CHAIN = "AUTO_CHAIN",
    LOADOUT = "LOADOUT",  -- НОВОЕ
}

-- ========== СТРАТЕГИЯ ==========
local Strategy = {
    Name = "New Strategy",
    Actions = {},
    PlacedTowers = {},
    CurrentAction = 1,
    LoopingAbilities = {},
    AutoChainRunning = false,
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
local AutoFarmBtn, AutoStartBtn, ModeBtn, FarmStatusLabel
local AutoPickupsBtn, PickupsStatusLabel
local AutoFarmConfigTitle, AutoFarmConfigNameBox, QueueToggleBtn
local QueueSettings
local pickupsCollected
local currentGameState

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

-- НОВОЕ: Добавление Loadout действия
local function addLoadoutAction(towers)
    table.insert(Strategy.Actions, createAction(ActionType.LOADOUT, {
        towers = towers or {}
    }))
    return #Strategy.Actions
end

-- ========== ВЫПОЛНЕНИЕ ДЕЙСТВИЙ ==========

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
        
    elseif action.type == ActionType.SET_TARGET then
        local p = action.params
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
        
    elseif action.type == ActionType.VOTE_SKIP then
        local p = action.params
        for wave = p.startWave, p.endWave do
            while State.Running and not State.Paused do
                if getCurrentWave() < wave then
                    task.wait(0.5)
                    continue
                end
                
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
        return true
        
    elseif action.type == ActionType.AUTO_CHAIN then
        local p = action.params
        if #p.towerIndices < 3 then 
            State.LastLog = "⚠️ Chain нужно 3+ башни!"
            return true 
        end
        
        State.LastLog = "🔗 AutoChain запущен"
        Strategy.AutoChainRunning = true
        
        task.spawn(function()
            local idx = 1
            while Strategy.AutoChainRunning and State.Running do
                local towerIndex = p.towerIndices[idx]
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
                if idx > #p.towerIndices then idx = 1 end
            end
        end)
        
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
            continue
        end
        
        local action = Strategy.Actions[Strategy.CurrentAction]
        local success = executeAction(action)
        
        if success then
            Strategy.CurrentAction = Strategy.CurrentAction + 1
        end
        
        task.wait(Settings.ActionDelay)
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
            code = code .. string.format('TDS:AutoChain(%s)\n', table.concat(p.towerIndices, ", "))
            
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

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "StrategyBuilderUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 720)
MainFrame.Position = UDim2.new(1, -530, 0.5, -360)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(255, 130, 70)
MainStroke.Thickness = 1
MainStroke.Transparency = 0.15

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(255, 110, 70)
Header.BorderSizePixel = 0
Header.Parent = MainFrame
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)
local HeaderGradient = Instance.new("UIGradient", Header)
HeaderGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 95, 60)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 95)),
})

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -42, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = tr("title")
Title.TextColor3 = Color3.new(1, 1, 1)
Title.TextSize = 14
Title.Font = Enum.Font.GothamSemibold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -32, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.TextSize = 16
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

local LangBtn = Instance.new("TextButton")
LangBtn.Size = UDim2.new(0, 48, 0, 22)
LangBtn.Position = UDim2.new(1, -86, 0, 8)
LangBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
LangBtn.Text = tr("lang_button")
LangBtn.TextColor3 = Color3.new(1, 1, 1)
LangBtn.TextSize = 10
LangBtn.Font = Enum.Font.GothamBold
LangBtn.Parent = Header
Instance.new("UICorner", LangBtn).CornerRadius = UDim.new(0, 6)

-- Content
local Content = Instance.new("ScrollingFrame")
Content.Size = UDim2.new(1, -14, 1, -46)
Content.Position = UDim2.new(0, 7, 0, 40)
Content.BackgroundTransparency = 1
Content.ScrollBarThickness = 4
Content.AutomaticCanvasSize = Enum.AutomaticSize.Y
Content.Parent = MainFrame

local ContentLayout = Instance.new("UIListLayout", Content)
ContentLayout.Padding = UDim.new(0, 4)

-- ========== STATUS ==========
local StatusSection = Instance.new("Frame")
StatusSection.Size = UDim2.new(1, 0, 0, 54)
StatusSection.BackgroundColor3 = Color3.fromRGB(25, 30, 25)
StatusSection.Parent = Content
Instance.new("UICorner", StatusSection).CornerRadius = UDim.new(0, 8)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -10, 1, -6)
StatusLabel.Position = UDim2.new(0, 5, 0, 3)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = tr("status_ready")
StatusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
StatusLabel.TextSize = 9
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.TextWrapped = true
StatusLabel.Parent = StatusSection

-- ========== CONTROLS ==========
local ControlSection = Instance.new("Frame")
ControlSection.Size = UDim2.new(1, 0, 0, 56)
ControlSection.BackgroundTransparency = 1
ControlSection.Parent = Content

local StartBtn = Instance.new("TextButton")
StartBtn.Size = UDim2.new(0.32, -2, 1, 0)
StartBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
StartBtn.Text = tr("start")
StartBtn.TextColor3 = Color3.new(1, 1, 1)
StartBtn.TextSize = 11
StartBtn.Font = Enum.Font.GothamBold
StartBtn.Parent = ControlSection
Instance.new("UICorner", StartBtn).CornerRadius = UDim.new(0, 6)

local PauseBtn = Instance.new("TextButton")
PauseBtn.Size = UDim2.new(0.32, -2, 1, 0)
PauseBtn.Position = UDim2.new(0.33, 0, 0, 0)
PauseBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
PauseBtn.Text = tr("pause")
PauseBtn.TextColor3 = Color3.new(1, 1, 1)
PauseBtn.TextSize = 11
PauseBtn.Font = Enum.Font.GothamBold
PauseBtn.Parent = ControlSection
Instance.new("UICorner", PauseBtn).CornerRadius = UDim.new(0, 6)

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(0.32, -2, 1, 0)
StopBtn.Position = UDim2.new(0.66, 0, 0, 0)
StopBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
StopBtn.Text = tr("stop")
StopBtn.TextColor3 = Color3.new(1, 1, 1)
StopBtn.TextSize = 11
StopBtn.Font = Enum.Font.GothamBold
StopBtn.Parent = ControlSection
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 6)

-- ========== GLOBAL AUTO TOGGLES ==========
local GlobalSection = Instance.new("Frame")
GlobalSection.Size = UDim2.new(1, 0, 0, 64)
GlobalSection.BackgroundColor3 = Color3.fromRGB(30, 25, 35)
GlobalSection.Parent = Content
Instance.new("UICorner", GlobalSection).CornerRadius = UDim.new(0, 8)

local GlobalChainBtn = Instance.new("TextButton")
GlobalChainBtn.Size = UDim2.new(0.48, -3, 0, 24)
GlobalChainBtn.Position = UDim2.new(0, 5, 0, 4)
GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 60)
GlobalChainBtn.Text = tr("global_chain_off")
GlobalChainBtn.TextColor3 = Color3.new(1, 1, 1)
GlobalChainBtn.TextSize = 9
GlobalChainBtn.Font = Enum.Font.GothamBold
GlobalChainBtn.Parent = GlobalSection
Instance.new("UICorner", GlobalChainBtn).CornerRadius = UDim.new(0, 5)

local GlobalDJBtn = Instance.new("TextButton")
GlobalDJBtn.Size = UDim2.new(0.48, -3, 0, 24)
GlobalDJBtn.Position = UDim2.new(0.5, 0, 0, 4)
GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 80)
GlobalDJBtn.Text = tr("global_dj_off")
GlobalDJBtn.TextColor3 = Color3.new(1, 1, 1)
GlobalDJBtn.TextSize = 9
GlobalDJBtn.Font = Enum.Font.GothamBold
GlobalDJBtn.Parent = GlobalSection
Instance.new("UICorner", GlobalDJBtn).CornerRadius = UDim.new(0, 5)

-- НОВОЕ: AUTO SKIP кнопка по центру снизу
local GlobalSkipBtn = Instance.new("TextButton")
GlobalSkipBtn.Size = UDim2.new(0.48, -3, 0, 24)
GlobalSkipBtn.Position = UDim2.new(0.5, 0, 0, 32)
GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 60)
GlobalSkipBtn.Text = tr("global_skip_off")
GlobalSkipBtn.TextColor3 = Color3.new(1, 1, 1)
GlobalSkipBtn.TextSize = 9
GlobalSkipBtn.Font = Enum.Font.GothamBold
GlobalSkipBtn.Parent = GlobalSection
Instance.new("UICorner", GlobalSkipBtn).CornerRadius = UDim.new(0, 5)

-- ========== TOWER SELECT ==========
local TowerSection = Instance.new("Frame")
TowerSection.Size = UDim2.new(1, 0, 0, 68)
TowerSection.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
TowerSection.Parent = Content
Instance.new("UICorner", TowerSection).CornerRadius = UDim.new(0, 8)

local TowerTitle = Instance.new("TextLabel")
TowerTitle.Size = UDim2.new(1, -10, 0, 12)
TowerTitle.Position = UDim2.new(0, 5, 0, 2)
TowerTitle.BackgroundTransparency = 1
TowerTitle.Text = tr("tower_default", State.SelectedTower or "Scout")
TowerTitle.TextColor3 = Color3.fromRGB(255, 180, 100)
TowerTitle.TextSize = 9
TowerTitle.Font = Enum.Font.GothamBold
TowerTitle.TextXAlignment = Enum.TextXAlignment.Left
TowerTitle.Parent = TowerSection

local TowerScroll = Instance.new("ScrollingFrame")
TowerScroll.Size = UDim2.new(1, -10, 0, 46)
TowerScroll.Position = UDim2.new(0, 5, 0, 16)
TowerScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
TowerScroll.ScrollBarThickness = 3
TowerScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
TowerScroll.ScrollingDirection = Enum.ScrollingDirection.X
TowerScroll.Parent = TowerSection
Instance.new("UICorner", TowerScroll).CornerRadius = UDim.new(0, 5)

local TowerLayout = Instance.new("UIListLayout", TowerScroll)
TowerLayout.FillDirection = Enum.FillDirection.Horizontal
TowerLayout.Padding = UDim.new(0, 2)
Instance.new("UIPadding", TowerScroll).PaddingLeft = UDim.new(0, 3)

-- ========== ALL ACTIONS ==========
local AddSection = Instance.new("Frame")
AddSection.Size = UDim2.new(1, 0, 0, 200)
AddSection.BackgroundColor3 = Color3.fromRGB(30, 25, 40)
AddSection.Parent = Content
Instance.new("UICorner", AddSection).CornerRadius = UDim.new(0, 8)

local AddTitle = Instance.new("TextLabel")
AddTitle.Size = UDim2.new(1, -10, 0, 12)
AddTitle.Position = UDim2.new(0, 5, 0, 2)
AddTitle.BackgroundTransparency = 1
AddTitle.Text = tr("all_actions")
AddTitle.TextColor3 = Color3.fromRGB(200, 150, 255)
AddTitle.TextSize = 9
AddTitle.Font = Enum.Font.GothamBold
AddTitle.TextXAlignment = Enum.TextXAlignment.Left
AddTitle.Parent = AddSection

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
    {name = "CLEAR", text = "🗑CLEAR", color = Color3.fromRGB(100, 50, 50), row = 3, col = 4},
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
    btn.Parent = AddSection
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    ActionBtns[data.name] = btn
end

-- Input Fields
local inputY = startY + 4 * (btnHeight + 3) + 4

local function createInputField(labelText, placeholder, yOffset, width, xOffset)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(width or 0.48, -3, 0, 20)
    frame.Position = UDim2.new(xOffset or 0, 5, 0, yOffset)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    frame.Parent = AddSection
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

local InputBox1 = createInputField("От#", "1", inputY, 0.19, 0)
local InputBox2 = createInputField("До#", "6", inputY, 0.19, 0.20)
local InputBox3 = createInputField("Lv", "3", inputY, 0.19, 0.40)
local InputBox4 = createInputField("Wave", "1", inputY, 0.19, 0.60)
local InputBox5 = createInputField("$", "1000", inputY, 0.19, 0.80)

InputBox1.Text = "1"
InputBox2.Text = "6"
InputBox3.Text = "3"
InputBox4.Text = "1"
InputBox5.Text = "1000"

local InputBoxText = createInputField("Text", "Tower/Ability/Target", inputY + 22, 0.65, 0)
local InputBoxPath = createInputField("Path", "1", inputY + 22, 0.33, 0.66)
InputBoxPath.Text = "1"

-- НОВОЕ: Поле для Loadout
local InputBoxLoadout = createInputField("Loadout", "Scout,Sniper,Demoman", inputY + 44, 0.98, 0)

-- ========== SAVE/LOAD SECTION ==========
local SaveLoadSection = Instance.new("Frame")
SaveLoadSection.Size = UDim2.new(1, 0, 0, 62)
SaveLoadSection.BackgroundColor3 = Color3.fromRGB(25, 30, 40)
SaveLoadSection.Parent = Content
Instance.new("UICorner", SaveLoadSection).CornerRadius = UDim.new(0, 8)

local SaveLoadTitle = Instance.new("TextLabel")
SaveLoadTitle.Size = UDim2.new(1, -10, 0, 12)
SaveLoadTitle.Position = UDim2.new(0, 5, 0, 2)
SaveLoadTitle.BackgroundTransparency = 1
SaveLoadTitle.Text = tr("save_load")
SaveLoadTitle.TextColor3 = Color3.fromRGB(100, 200, 255)
SaveLoadTitle.TextSize = 9
SaveLoadTitle.Font = Enum.Font.GothamBold
SaveLoadTitle.TextXAlignment = Enum.TextXAlignment.Left
SaveLoadTitle.Parent = SaveLoadSection

local ConfigNameBox = Instance.new("TextBox")
ConfigNameBox.Size = UDim2.new(0.55, -8, 0, 20)
ConfigNameBox.Position = UDim2.new(0, 5, 0, 16)
ConfigNameBox.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
ConfigNameBox.Text = ""
ConfigNameBox.PlaceholderText = tr("config_placeholder")
ConfigNameBox.TextColor3 = Color3.new(1, 1, 1)
ConfigNameBox.TextSize = 9
ConfigNameBox.Font = Enum.Font.Gotham
ConfigNameBox.Parent = SaveLoadSection
Instance.new("UICorner", ConfigNameBox).CornerRadius = UDim.new(0, 5)

local SaveBtn = Instance.new("TextButton")
SaveBtn.Size = UDim2.new(0.22, -3, 0, 20)
SaveBtn.Position = UDim2.new(0.55, 0, 0, 16)
SaveBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
SaveBtn.Text = "💾 SAVE"
SaveBtn.TextColor3 = Color3.new(1, 1, 1)
SaveBtn.TextSize = 9
SaveBtn.Font = Enum.Font.GothamBold
SaveBtn.Parent = SaveLoadSection
Instance.new("UICorner", SaveBtn).CornerRadius = UDim.new(0, 5)

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0.22, -3, 0, 20)
RefreshBtn.Position = UDim2.new(0.77, 0, 0, 16)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 140)
RefreshBtn.Text = "🔄"
RefreshBtn.TextColor3 = Color3.new(1, 1, 1)
RefreshBtn.TextSize = 11
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.Parent = SaveLoadSection
Instance.new("UICorner", RefreshBtn).CornerRadius = UDim.new(0, 5)

local ConfigScroll = Instance.new("ScrollingFrame")
ConfigScroll.Size = UDim2.new(1, -10, 0, 22)
ConfigScroll.Position = UDim2.new(0, 5, 0, 38)
ConfigScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
ConfigScroll.ScrollBarThickness = 3
ConfigScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
ConfigScroll.ScrollingDirection = Enum.ScrollingDirection.X
ConfigScroll.Parent = SaveLoadSection
Instance.new("UICorner", ConfigScroll).CornerRadius = UDim.new(0, 5)

local ConfigLayout = Instance.new("UIListLayout", ConfigScroll)
ConfigLayout.FillDirection = Enum.FillDirection.Horizontal
ConfigLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", ConfigScroll).PaddingLeft = UDim.new(0, 3)

-- Forward declarations for UI update functions
local updateActionsDisplay
local updateMarkers
local updateConfigList

updateConfigList = function()
    for _, child in pairs(ConfigScroll:GetChildren()) do
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
        btn.Parent = ConfigScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        btn.MouseButton1Click:Connect(function()
            local success, msg = safeLoadStrategy(fileName)
            State.LastLog = msg
            if success then
                ConfigNameBox.Text = fileName
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
local ActionsSection = Instance.new("Frame")
ActionsSection.Size = UDim2.new(1, 0, 0, 150)
ActionsSection.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
ActionsSection.Parent = Content
Instance.new("UICorner", ActionsSection).CornerRadius = UDim.new(0, 8)

local ActionsTitle = Instance.new("TextLabel")
ActionsTitle.Size = UDim2.new(1, -10, 0, 12)
ActionsTitle.Position = UDim2.new(0, 5, 0, 2)
ActionsTitle.BackgroundTransparency = 1
ActionsTitle.Text = tr("actions_queue", 0)
ActionsTitle.TextColor3 = Color3.fromRGB(255, 200, 100)
ActionsTitle.TextSize = 9
ActionsTitle.Font = Enum.Font.GothamBold
ActionsTitle.TextXAlignment = Enum.TextXAlignment.Left
ActionsTitle.Parent = ActionsSection

local ActionsScroll = Instance.new("ScrollingFrame")
ActionsScroll.Size = UDim2.new(1, -10, 1, -20)
ActionsScroll.Position = UDim2.new(0, 5, 0, 18)
ActionsScroll.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
ActionsScroll.ScrollBarThickness = 3
ActionsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
ActionsScroll.Parent = ActionsSection
Instance.new("UICorner", ActionsScroll).CornerRadius = UDim.new(0, 5)

local ActionsListLayout = Instance.new("UIListLayout", ActionsScroll)
ActionsListLayout.Padding = UDim.new(0, 2)
Instance.new("UIPadding", ActionsScroll).PaddingTop = UDim.new(0, 2)

-- ========== DELAY SETTINGS ==========
local DelaySection = Instance.new("Frame")
DelaySection.Size = UDim2.new(1, 0, 0, 84)
DelaySection.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
DelaySection.Parent = Content
Instance.new("UICorner", DelaySection).CornerRadius = UDim.new(0, 8)

local DelayTitle = Instance.new("TextLabel")
DelayTitle.Size = UDim2.new(1, -10, 0, 12)
DelayTitle.Position = UDim2.new(0, 5, 0, 2)
DelayTitle.BackgroundTransparency = 1
DelayTitle.Text = tr("delay_section")
DelayTitle.TextColor3 = Color3.fromRGB(200, 220, 255)
DelayTitle.TextSize = 9
DelayTitle.Font = Enum.Font.GothamBold
DelayTitle.TextXAlignment = Enum.TextXAlignment.Left
DelayTitle.Parent = DelaySection

local DelayLabels = {}
local DelayInputs = {}

local function createDelayField(labelKey, settingKey, xScale, yOffset, widthScale)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(widthScale, -3, 0, 20)
    frame.Position = UDim2.new(xScale, 5, 0, yOffset)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
    frame.Parent = DelaySection
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
local ExportSection = Instance.new("Frame")
ExportSection.Size = UDim2.new(1, 0, 0, 44)
ExportSection.BackgroundColor3 = Color3.fromRGB(35, 30, 40)
ExportSection.Parent = Content
Instance.new("UICorner", ExportSection).CornerRadius = UDim.new(0, 8)

local ExportCodeBtn = Instance.new("TextButton")
ExportCodeBtn.Size = UDim2.new(0.32, -2, 0, 28)
ExportCodeBtn.Position = UDim2.new(0, 5, 0, 8)
ExportCodeBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 150)
ExportCodeBtn.Text = tr("export_code")
ExportCodeBtn.TextColor3 = Color3.new(1, 1, 1)
ExportCodeBtn.TextSize = 9
ExportCodeBtn.Font = Enum.Font.GothamBold
ExportCodeBtn.Parent = ExportSection
Instance.new("UICorner", ExportCodeBtn).CornerRadius = UDim.new(0, 5)

local ExportJsonBtn = Instance.new("TextButton")
ExportJsonBtn.Size = UDim2.new(0.32, -2, 0, 28)
ExportJsonBtn.Position = UDim2.new(0.33, 0, 0, 8)
ExportJsonBtn.BackgroundColor3 = Color3.fromRGB(100, 80, 150)
ExportJsonBtn.Text = tr("export_json")
ExportJsonBtn.TextColor3 = Color3.new(1, 1, 1)
ExportJsonBtn.TextSize = 9
ExportJsonBtn.Font = Enum.Font.GothamBold
ExportJsonBtn.Parent = ExportSection
Instance.new("UICorner", ExportJsonBtn).CornerRadius = UDim.new(0, 5)

local ImportBtn = Instance.new("TextButton")
ImportBtn.Size = UDim2.new(0.32, -2, 0, 28)
ImportBtn.Position = UDim2.new(0.66, 0, 0, 8)
ImportBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 80)
ImportBtn.Text = tr("import")
ImportBtn.TextColor3 = Color3.new(1, 1, 1)
ImportBtn.TextSize = 9
ImportBtn.Font = Enum.Font.GothamBold
ImportBtn.Parent = ExportSection
Instance.new("UICorner", ImportBtn).CornerRadius = UDim.new(0, 5)

-- ========== TOGGLE ==========
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0, 44, 0, 44)
ToggleBtn.Position = UDim2.new(1, -52, 0.35, 0)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 50)
ToggleBtn.Text = "⚡"
ToggleBtn.TextColor3 = Color3.new(1, 1, 1)
ToggleBtn.TextSize = 20
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.Parent = ScreenGui
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 10)

-- ========== MODE INDICATOR ==========
local ModeIndicator = Instance.new("Frame")
ModeIndicator.Size = UDim2.new(0, 360, 0, 48)
ModeIndicator.Position = UDim2.new(0.5, -180, 0, 10)
ModeIndicator.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
ModeIndicator.Visible = false
ModeIndicator.Parent = ScreenGui
Instance.new("UICorner", ModeIndicator).CornerRadius = UDim.new(0, 10)

local ModeText = Instance.new("TextLabel")
ModeText.Size = UDim2.new(1, -20, 0, 22)
ModeText.Position = UDim2.new(0, 10, 0, 5)
ModeText.BackgroundTransparency = 1
ModeText.Text = tr("mode")
ModeText.TextColor3 = Color3.new(1, 1, 1)
ModeText.TextSize = 13
ModeText.Font = Enum.Font.GothamBold
ModeText.Parent = ModeIndicator

local ModeSubText = Instance.new("TextLabel")
ModeSubText.Size = UDim2.new(1, -20, 0, 18)
ModeSubText.Position = UDim2.new(0, 10, 0, 26)
ModeSubText.BackgroundTransparency = 1
ModeSubText.Text = "..."
ModeSubText.TextColor3 = Color3.fromRGB(200, 255, 200)
ModeSubText.TextSize = 10
ModeSubText.Font = Enum.Font.Gotham
ModeSubText.Parent = ModeIndicator

-- ========== PREVIEW ==========
local previewCircle = Instance.new("Part")
previewCircle.Shape = Enum.PartType.Cylinder
previewCircle.Anchored = true
previewCircle.CanCollide = false
previewCircle.CanQuery = false
previewCircle.CanTouch = false
previewCircle.Material = Enum.Material.Neon
previewCircle.Transparency = 0.5

local previewOutline = Instance.new("Part")
previewOutline.Shape = Enum.PartType.Cylinder
previewOutline.Anchored = true
previewOutline.CanCollide = false
previewOutline.CanQuery = false
previewOutline.CanTouch = false
previewOutline.Material = Enum.Material.Neon
previewOutline.Transparency = 0.3
previewOutline.Color = Color3.fromRGB(255, 255, 255)

local previewBillboard = Instance.new("BillboardGui")
previewBillboard.Size = UDim2.new(0, 150, 0, 40)
previewBillboard.StudsOffset = Vector3.new(0, 2.5, 0)
previewBillboard.AlwaysOnTop = true
previewBillboard.Parent = previewCircle

local previewLabel = Instance.new("TextLabel")
previewLabel.Size = UDim2.new(1, 0, 1, 0)
previewLabel.BackgroundTransparency = 0.2
previewLabel.TextColor3 = Color3.new(1, 1, 1)
previewLabel.TextSize = 10
previewLabel.Font = Enum.Font.GothamBold
previewLabel.TextWrapped = true
previewLabel.Parent = previewBillboard
Instance.new("UICorner", previewLabel).CornerRadius = UDim.new(0, 5)

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
        return "🔗 Chain " .. table.concat(p.towerIndices or {}, ",")
    elseif t == ActionType.LOADOUT then
        return "📦 " .. table.concat(p.towers or {}, ", ")
    end
    return "?"
end

updateActionsDisplay = function()
    for _, child in pairs(ActionsScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    ActionsTitle.Text = tr("actions_queue", #Strategy.Actions)
    
    for i, action in ipairs(Strategy.Actions) do
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, -6, 0, 22)
        frame.BackgroundColor3 = i == Strategy.CurrentAction and State.Running 
            and Color3.fromRGB(50, 70, 35) or Color3.fromRGB(35, 35, 45)
        frame.Parent = ActionsScroll
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
    
    StatusLabel.Text = string.format(
        "%s %s%s%s | 💰$%d | 🌊Wave %d | 🗼%s: %d\n%s: %d/%d | %s",
        status, chainStatus, djStatus, skipStatus, cash, wave, tr("towers_label"), placed,
        tr("action_label"), Strategy.CurrentAction, #Strategy.Actions,
        State.LastLog
    )
    
    StatusSection.BackgroundColor3 = State.Running 
        and (State.Paused and Color3.fromRGB(40, 40, 25) or Color3.fromRGB(20, 45, 20))
        or Color3.fromRGB(25, 30, 25)
end

local function applyLanguage()
    if Title then Title.Text = tr("title") end
    if StartBtn then StartBtn.Text = tr("start") end
    if PauseBtn then PauseBtn.Text = State.Paused and tr("pause_go") or tr("pause") end
    if StopBtn then StopBtn.Text = tr("stop") end
    if TowerTitle then TowerTitle.Text = tr("tower_default", State.SelectedTower or "Scout") end
    if AddTitle then AddTitle.Text = tr("all_actions") end
    if SaveLoadTitle then SaveLoadTitle.Text = tr("save_load") end
    if ConfigNameBox then ConfigNameBox.PlaceholderText = tr("config_placeholder") end
    if ActionsTitle then ActionsTitle.Text = tr("actions_queue", #Strategy.Actions) end
    if ExportCodeBtn then ExportCodeBtn.Text = tr("export_code") end
    if ExportJsonBtn then ExportJsonBtn.Text = tr("export_json") end
    if ImportBtn then ImportBtn.Text = tr("import") end
    if DelayTitle then DelayTitle.Text = tr("delay_section") end
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
    if GlobalChainBtn then
        GlobalChainBtn.Text = Settings.GlobalAutoChain and tr("global_chain_on") or tr("global_chain_off")
    end
    if GlobalDJBtn then
        GlobalDJBtn.Text = Settings.GlobalAutoDJ and tr("global_dj_on") or tr("global_dj_off")
    end
    if GlobalSkipBtn then
        GlobalSkipBtn.Text = Settings.GlobalAutoSkip and tr("global_skip_on") or tr("global_skip_off")
    end
    if AutoFarmBtn and AutoFarmSettings then
        AutoFarmBtn.Text = AutoFarmSettings.Enabled and tr("auto_farm_on") or tr("auto_farm_off")
    end
    if AutoStartBtn and AutoFarmSettings then
        AutoStartBtn.Text = AutoFarmSettings.AutoStart and tr("auto_start_on") or tr("auto_start_off")
    end
    if ModeBtn and AutoFarmSettings then
        ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty or "?")
    end
    if FarmStatusLabel and currentGameState then
        FarmStatusLabel.Text = tr("farm_status_prefix") .. currentGameState
    end
    if PickupsStatusLabel and pickupsCollected then
        PickupsStatusLabel.Text = tr("pickups_collected", pickupsCollected)
    end
    if AutoFarmConfigTitle then AutoFarmConfigTitle.Text = tr("autofarm_config_title") end
    if AutoFarmConfigNameBox then AutoFarmConfigNameBox.PlaceholderText = tr("autofarm_config_placeholder") end
    if QueueToggleBtn and QueueSettings then
        QueueToggleBtn.Text = QueueSettings.Enabled and tr("queue_on") or tr("queue_off")
    end
    if LangBtn then LangBtn.Text = tr("lang_button") end
    if ModeIndicator and not State.AddingPosition then
        ModeText.Text = tr("mode")
        ModeSubText.Text = "..."
    end
end

applyLanguage()

local function createTowerButtons()
    for _, child in pairs(TowerScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    -- ПРОВЕРЯЕМ ЧТО МОДУЛИ ЗАГРУЖЕНЫ
    if not InventoryStore then
        print("❌ InventoryStore не загружен!")
        local errorLabel = Instance.new("TextLabel")
        errorLabel.Size = UDim2.new(1, -10, 1, 0)
        errorLabel.BackgroundTransparency = 1
        errorLabel.Text = "⚠️ Модули не загружены!\nПерезапусти скрипт"
        errorLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        errorLabel.TextSize = 10
        errorLabel.Font = Enum.Font.GothamBold
        errorLabel.Parent = TowerScroll
        return
    end
    
    local unlocked = getUnlockedTowers()
    
    -- ПРОВЕРЯЕМ ЧТО ЕСТЬ БАШНИ
    local count = 0
    for _ in pairs(unlocked) do count = count + 1 end
    
    if count == 0 then
        print("❌ Нет разблокированных башен!")
        local errorLabel = Instance.new("TextLabel")
        errorLabel.Size = UDim2.new(1, -10, 1, 0)
        errorLabel.BackgroundTransparency = 1
        errorLabel.Text = "⚠️ Нет башен в инвентаре"
        errorLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
        errorLabel.TextSize = 10
        errorLabel.Font = Enum.Font.GothamBold
        errorLabel.Parent = TowerScroll
        return
    end
    
    print("🗼 Найдено башен: " .. count)
    
    local sorted = {}
    for name in pairs(unlocked) do table.insert(sorted, name) end
    table.sort(sorted)
    
    for _, towerName in ipairs(sorted) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 42, 0, 42)
        btn.BackgroundColor3 = State.SelectedTower == towerName 
            and Color3.fromRGB(0, 130, 65) or Color3.fromRGB(40, 40, 55)
        btn.Text = ""
        btn.Parent = TowerScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
        
        local icon = Instance.new("ImageLabel")
        icon.Size = UDim2.new(0, 24, 0, 24)
        icon.Position = UDim2.new(0.5, -12, 0, 2)
        icon.BackgroundTransparency = 1
        icon.Parent = btn
        
        -- ЗАГРУЖАЕМ ИКОНКУ
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
            TowerTitle.Text = tr("tower_stats", towerName, bSize, cost)
            createTowerButtons()
        end)
    end
end

-- ========== PREVIEW MODE ==========

local previewConnection

local function updateAddPreview()
    if not State.AddingPosition then 
        previewCircle.Parent = nil
        previewOutline.Parent = nil
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
        previewCircle,
        previewOutline
    }
    for _, m in pairs(markers) do
        table.insert(rayParams.FilterDescendantsInstances, m)
    end
    
    local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 1000, rayParams)
    
    if ray then
        local pos = ray.Position
        local boundarySize = getTowerBoundarySize(State.SelectedTower)
        local diameter = boundarySize * 2
        
        previewCircle.Size = Vector3.new(0.1, diameter, diameter)
        previewCircle.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
        previewCircle.Parent = workspace
        
        previewOutline.Size = Vector3.new(0.05, diameter + 0.15, diameter + 0.15)
        previewOutline.CFrame = CFrame.new(pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
        previewOutline.Parent = workspace
        
        local isValid, reason = checkPositionValid(State.SelectedTower, pos, false)
        local cost = getTowerPlaceCost(State.SelectedTower)
        
        if isValid then
            previewCircle.Color = Color3.fromRGB(0, 255, 100)
            previewLabel.BackgroundColor3 = Color3.fromRGB(0, 120, 50)
            previewLabel.Text = string.format("✓ %s $%d", State.SelectedTower, cost)
            ModeIndicator.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
            ModeText.Text = tr("mode_place_ok")
            ModeSubText.Text = State.SelectedTower .. " | $" .. cost
        else
            previewCircle.Color = Color3.fromRGB(255, 60, 60)
            previewLabel.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
            previewLabel.Text = "✕ " .. reason
            ModeIndicator.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            ModeText.Text = tr("mode_place_no")
            ModeSubText.Text = reason
        end
    else
        previewCircle.Parent = nil
        previewOutline.Parent = nil
    end
end

local function startAddPositionMode()
    State.AddingPosition = true
    ModeIndicator.Visible = true
    ActionBtns.PLACE.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
    ActionBtns.PLACE.Text = tr("place_active")
    previewConnection = RunService.RenderStepped:Connect(updateAddPreview)
end

local function stopAddPositionMode()
    State.AddingPosition = false
    ModeIndicator.Visible = false
    previewCircle.Parent = nil
    previewOutline.Parent = nil
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
        previewCircle,
        previewOutline
    }
    for _, m in pairs(markers) do table.insert(rayParams.FilterDescendantsInstances, m) end
    
    local ray = workspace:Raycast(mouse.UnitRay.Origin, mouse.UnitRay.Direction * 1000, rayParams)
    
    if ray then
        local pos = ray.Position
        
        local isValid, reason = checkPositionValid(State.SelectedTower, pos, false)
        
        if not isValid then
            ModeText.Text = tr("mode_place_no")
            ModeSubText.Text = reason
            ModeIndicator.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
            return
        end
        
        addPlaceAction(State.SelectedTower, pos.X, pos.Y, pos.Z)
        updateActionsDisplay()
        updateMarkers()
        
        local placeCount = 0
        for _, action in ipairs(Strategy.Actions) do
            if action.type == ActionType.PLACE then placeCount = placeCount + 1 end
        end
        
        ModeText.Text = tr("mode_added", placeCount)
        ModeIndicator.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        task.delay(0.5, function()
            if State.AddingPosition then
                ModeText.Text = tr("mode_add")
            end
        end)
    end
end

-- ========== EVENTS ==========

LangBtn.MouseButton1Click:Connect(function()
    Settings.Language = (Settings.Language == "RU") and "EN" or "RU"
    applyLanguage()
    if updateStatus then updateStatus() end
    if updateActionsDisplay then updateActionsDisplay() end
end)

StartBtn.MouseButton1Click:Connect(function()
    if State.Running then return end
    if #Strategy.Actions == 0 then
        State.LastLog = "❌ Добавь действия!"
        updateStatus()
        return
    end
    stopAddPositionMode()
    task.spawn(runStrategy)
end)

PauseBtn.MouseButton1Click:Connect(function()
    if State.Running then
        State.Paused = not State.Paused
        PauseBtn.Text = State.Paused and tr("pause_go") or tr("pause")
        PauseBtn.BackgroundColor3 = State.Paused and Color3.fromRGB(0, 180, 100) or Color3.fromRGB(200, 150, 50)
        updateStatus()
    end
end)

StopBtn.MouseButton1Click:Connect(function()
    State.Running = false
    State.Paused = false
    stopAllLoops()
    PauseBtn.Text = tr("pause")
    PauseBtn.BackgroundColor3 = Color3.fromRGB(200, 150, 50)
    State.LastLog = "⏹ Остановлено"
    updateStatus()
end)

GlobalChainBtn.MouseButton1Click:Connect(function()
    Settings.GlobalAutoChain = not Settings.GlobalAutoChain
    if Settings.GlobalAutoChain then
        GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        GlobalChainBtn.Text = tr("global_chain_on")
        startGlobalAutoChain()
        State.LastLog = "🔗 Global Auto Chain включен"
    else
        GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 60)
        GlobalChainBtn.Text = tr("global_chain_off")
        stopGlobalAutoChain()
        State.LastLog = "🔗 Global Auto Chain выключен"
    end
    updateStatus()
end)

GlobalDJBtn.MouseButton1Click:Connect(function()
    Settings.GlobalAutoDJ = not Settings.GlobalAutoDJ
    if Settings.GlobalAutoDJ then
        GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
        GlobalDJBtn.Text = tr("global_dj_on")
        startGlobalAutoDJ()
        State.LastLog = "🎵 Global Auto DJ включен"
    else
        GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 80)
        GlobalDJBtn.Text = tr("global_dj_off")
        stopGlobalAutoDJ()
        State.LastLog = "🎵 Global Auto DJ выключен"
    end
    updateStatus()
end)

-- Global Auto Skip toggle
GlobalSkipBtn.MouseButton1Click:Connect(function()
    Settings.GlobalAutoSkip = not Settings.GlobalAutoSkip
    if Settings.GlobalAutoSkip then
        GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
        GlobalSkipBtn.Text = tr("global_skip_on")
        startGlobalAutoSkip()
        State.LastLog = "⏭ Global Auto Skip включен"
    else
        GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 60)
        GlobalSkipBtn.Text = tr("global_skip_off")
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
    addUpgradeAction(tonumber(InputBox1.Text) or 1, tonumber(InputBoxPath.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.UPG_PATH2.MouseButton1Click:Connect(function()
    addUpgradeAction(tonumber(InputBox1.Text) or 1, 2)
    updateActionsDisplay()
end)

ActionBtns.UPGRADE_TO.MouseButton1Click:Connect(function()
    addUpgradeToAction(tonumber(InputBox1.Text) or 1, tonumber(InputBox3.Text) or 1, tonumber(InputBoxPath.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.UPGRADE_MAX.MouseButton1Click:Connect(function()
    addUpgradeMaxAction(tonumber(InputBox1.Text) or 1, tonumber(InputBoxPath.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.MULTI_UPG.MouseButton1Click:Connect(function()
    local fromIdx = tonumber(InputBox1.Text) or 1
    local toIdx = tonumber(InputBox2.Text) or 6
    local targetLv = tonumber(InputBox3.Text) or 3
    local filterName = InputBoxText.Text ~= "" and InputBoxText.Text or ""
    local path = tonumber(InputBoxPath.Text) or 1
    
    addMultiUpgradeAction(fromIdx, toIdx, targetLv, filterName, path)
    updateActionsDisplay()
    State.LastLog = string.format("🔄 Добавлен MULTI UPG #%d-#%d → Lv%d", fromIdx, toIdx, targetLv)
    updateStatus()
end)

ActionBtns.SELL.MouseButton1Click:Connect(function()
    addSellAction(tonumber(InputBox1.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.SELL_ALL.MouseButton1Click:Connect(function()
    addSellAllAction()
    updateActionsDisplay()
end)

ActionBtns.SET_TARGET.MouseButton1Click:Connect(function()
    local target = InputBoxText.Text ~= "" and InputBoxText.Text or "First"
    addSetTargetAction(tonumber(InputBox1.Text) or 1, target)
    updateActionsDisplay()
end)

ActionBtns.ABILITY.MouseButton1Click:Connect(function()
    local ability = InputBoxText.Text ~= "" and InputBoxText.Text or "Call Of Arms"
    addAbilityAction(tonumber(InputBox1.Text) or 1, ability, {}, false)
    updateActionsDisplay()
end)

ActionBtns.ABILITY_LOOP.MouseButton1Click:Connect(function()
    local ability = InputBoxText.Text ~= "" and InputBoxText.Text or "Call Of Arms"
    addAbilityAction(tonumber(InputBox1.Text) or 1, ability, {}, true)
    updateActionsDisplay()
end)

ActionBtns.SET_OPTION.MouseButton1Click:Connect(function()
    local optText = InputBoxText.Text
    local optName, optValue = "Unit 1", "Riot Guard"
    if optText:find("=") then
        local parts = optText:split("=")
        optName = parts[1]:match("^%s*(.-)%s*$") or optName
        optValue = parts[2]:match("^%s*(.-)%s*$") or optValue
    elseif optText ~= "" then
        optName = optText
    end
    addSetOptionAction(tonumber(InputBox1.Text) or 1, optName, optValue, tonumber(InputBox4.Text) or 0)
    updateActionsDisplay()
end)

ActionBtns.WAIT_WAVE.MouseButton1Click:Connect(function()
    addWaitWaveAction(tonumber(InputBox4.Text) or 1)
    updateActionsDisplay()
end)

ActionBtns.WAIT_TIME.MouseButton1Click:Connect(function()
    addWaitTimeAction(tonumber(InputBox3.Text) or 5)
    updateActionsDisplay()
end)

ActionBtns.WAIT_CASH.MouseButton1Click:Connect(function()
    addWaitCashAction(tonumber(InputBox5.Text) or 1000)
    updateActionsDisplay()
end)

ActionBtns.VOTE_SKIP.MouseButton1Click:Connect(function()
    local startW = tonumber(InputBox4.Text) or 1
    local endW = tonumber(InputBox2.Text) or startW
    addVoteSkipAction(startW, endW)
    updateActionsDisplay()
end)

ActionBtns.AUTO_CHAIN.MouseButton1Click:Connect(function()
    local text = InputBoxText.Text ~= "" and InputBoxText.Text or "1,2,3"
    local indices = {}
    for num in text:gmatch("%d+") do
        table.insert(indices, tonumber(num))
    end
    if #indices > 0 then
        addAutoChainAction(indices)
        updateActionsDisplay()
    end
end)

-- НОВОЕ: Loadout кнопка
ActionBtns.LOADOUT.MouseButton1Click:Connect(function()
    local loadoutText = InputBoxLoadout.Text
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
SaveBtn.MouseButton1Click:Connect(function()
    local name = ConfigNameBox.Text
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

RefreshBtn.MouseButton1Click:Connect(function()
    updateConfigList()
    State.LastLog = "🔄 Список обновлён"
    updateStatus()
end)

-- Export/Import
ExportCodeBtn.MouseButton1Click:Connect(function()
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

ExportJsonBtn.MouseButton1Click:Connect(function()
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

ImportBtn.MouseButton1Click:Connect(function()
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

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
    stopAddPositionMode()
end)

ToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
    if MainFrame.Visible then
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
        MainFrame.Visible = not MainFrame.Visible
        if MainFrame.Visible then
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
        if MainFrame.Visible or State.Running then
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
Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)
Header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
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

-- Увеличиваем GlobalSection
GlobalSection.Size = UDim2.new(1, 0, 0, 124)

-- Перемещаем существующие кнопки
GlobalSkipBtn.Position = UDim2.new(0.5, 0, 0, 32)

-- === AUTO FARM кнопка ===
AutoFarmBtn = Instance.new("TextButton")
AutoFarmBtn.Size = UDim2.new(0.48, -3, 0, 24)
AutoFarmBtn.Position = UDim2.new(0, 5, 0, 32)
AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AutoFarmBtn.Text = tr("auto_farm_off")
AutoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
AutoFarmBtn.TextSize = 9
AutoFarmBtn.Font = Enum.Font.GothamBold
AutoFarmBtn.Parent = GlobalSection
Instance.new("UICorner", AutoFarmBtn).CornerRadius = UDim.new(0, 5)

-- === AUTO START кнопка ===
AutoStartBtn = Instance.new("TextButton")
AutoStartBtn.Size = UDim2.new(0.48, -3, 0, 24)
AutoStartBtn.Position = UDim2.new(0, 5, 0, 60)
AutoStartBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
AutoStartBtn.Text = tr("auto_start_off")
AutoStartBtn.TextColor3 = Color3.new(1, 1, 1)
AutoStartBtn.TextSize = 9
AutoStartBtn.Font = Enum.Font.GothamBold
AutoStartBtn.Parent = GlobalSection
Instance.new("UICorner", AutoStartBtn).CornerRadius = UDim.new(0, 5)

-- === РЕЖИМ кнопка ===
ModeBtn = Instance.new("TextButton")
ModeBtn.Size = UDim2.new(0.48, -3, 0, 24)
ModeBtn.Position = UDim2.new(0.5, 0, 0, 60)
ModeBtn.BackgroundColor3 = Color3.fromRGB(80, 60, 100)
ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
ModeBtn.TextColor3 = Color3.new(1, 1, 1)
ModeBtn.TextSize = 9
ModeBtn.Font = Enum.Font.GothamBold
ModeBtn.Parent = GlobalSection
Instance.new("UICorner", ModeBtn).CornerRadius = UDim.new(0, 5)

-- === СТАТУС ===
FarmStatusLabel = Instance.new("TextLabel")
FarmStatusLabel.Size = UDim2.new(0.98, -5, 0, 24)
FarmStatusLabel.Position = UDim2.new(0, 5, 0, 88)
FarmStatusLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
FarmStatusLabel.Text = tr("farm_status_prefix") .. currentGameState
FarmStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
FarmStatusLabel.TextSize = 9
FarmStatusLabel.Font = Enum.Font.Gotham
FarmStatusLabel.Parent = GlobalSection
Instance.new("UICorner", FarmStatusLabel).CornerRadius = UDim.new(0, 5)

-- Список режимов для переключения
local ModeList = {"Normal", "Molten", "Fallen", "Hardcore", "Pizza Party", "Badlands", "Polluted"}
local currentModeIndex = 2  -- Molten по умолчанию

-- ========== СОБЫТИЯ ==========

AutoFarmBtn.MouseButton1Click:Connect(function()
    AutoFarmSettings.Enabled = not AutoFarmSettings.Enabled
    
    if AutoFarmSettings.Enabled then
        AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        AutoFarmBtn.Text = tr("auto_farm_on")
        State.LastLog = "🔄 Auto Farm ВКЛ: " .. AutoFarmSettings.Difficulty
        startAutoFarmLoop()
    else
        AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        AutoFarmBtn.Text = tr("auto_farm_off")
        State.LastLog = "🔄 Auto Farm ВЫКЛ"
        stopAutoFarmLoop()
    end
    updateStatus()
end)

AutoStartBtn.MouseButton1Click:Connect(function()
    AutoFarmSettings.AutoStart = not AutoFarmSettings.AutoStart
    
    if AutoFarmSettings.AutoStart then
        AutoStartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        AutoStartBtn.Text = tr("auto_start_on")
        State.LastLog = "▶ Auto Start ВКЛ"
    else
        AutoStartBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
        AutoStartBtn.Text = tr("auto_start_off")
        State.LastLog = "▶ Auto Start ВЫКЛ"
    end
    updateStatus()
end)

ModeBtn.MouseButton1Click:Connect(function()
    -- Переключаем на следующий режим
    currentModeIndex = currentModeIndex + 1
    if currentModeIndex > #ModeList then
        currentModeIndex = 1
    end
    
    AutoFarmSettings.Difficulty = ModeList[currentModeIndex]
    ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
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
        FarmStatusLabel.Text = farmStatus .. " " .. state .. " | " .. AutoFarmSettings.Difficulty
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
                for _, item in ipairs(pickupsFolder:GetChildren()) do
                    if not autoPickupsRunning or not autoPickupsEnabled then break end
                    
                    -- Собираем предметы
                    if item:IsA("MeshPart") or item:IsA("Part") or item:IsA("BasePart") then
                        if not isVoidItem(item) then
                            pcall(function()
                                -- Сохраняем позицию
                                local oldPos = hrp.CFrame
                                
                                -- Телепортируемся к предмету
                                hrp.CFrame = item.CFrame * CFrame.new(0, 3, 0)
                                task.wait(0.2)
                                
                                -- Возвращаемся назад
                                hrp.CFrame = oldPos
                                task.wait(0.3)
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

-- Увеличиваем GlobalSection
GlobalSection.Size = UDim2.new(1, 0, 0, 152)

-- Кнопка AUTO PICKUPS
AutoPickupsBtn = Instance.new("TextButton")
AutoPickupsBtn.Size = UDim2.new(0.48, -3, 0, 24)
AutoPickupsBtn.Position = UDim2.new(0, 5, 0, 116)
AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 80)
AutoPickupsBtn.Text = "🎁 PICKUPS: OFF"
AutoPickupsBtn.TextColor3 = Color3.new(1, 1, 1)
AutoPickupsBtn.TextSize = 9
AutoPickupsBtn.Font = Enum.Font.GothamBold
AutoPickupsBtn.Parent = GlobalSection
Instance.new("UICorner", AutoPickupsBtn).CornerRadius = UDim.new(0, 5)

-- Кнопка для статуса/инфо
PickupsStatusLabel = Instance.new("TextLabel")
PickupsStatusLabel.Size = UDim2.new(0.48, -3, 0, 24)
PickupsStatusLabel.Position = UDim2.new(0.5, 0, 0, 116)
PickupsStatusLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
PickupsStatusLabel.Text = tr("pickups_collected", 0)
PickupsStatusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
PickupsStatusLabel.TextSize = 9
PickupsStatusLabel.Font = Enum.Font.Gotham
PickupsStatusLabel.Parent = GlobalSection
Instance.new("UICorner", PickupsStatusLabel).CornerRadius = UDim.new(0, 5)

-- Счётчик собранных предметов
pickupsCollected = 0

AutoPickupsBtn.MouseButton1Click:Connect(function()
    autoPickupsEnabled = not autoPickupsEnabled
    
    if autoPickupsEnabled then
        AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
        AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
        startAutoPickups()
        State.LastLog = "🎁 Auto Pickups ВКЛ"
    else
        AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 80)
        AutoPickupsBtn.Text = "🎁 PICKUPS: OFF"
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
        AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
        AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
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
        
        ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
        print("✅ Режим: " .. AutoFarmSettings.Difficulty)
    end
    
    -- Включаем AUTO START
    if autoCfg.AutoStart then
        AutoFarmSettings.AutoStart = true
        AutoStartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        AutoStartBtn.Text = tr("auto_start_on")
        print("✅ Auto Start: ON")
    end
    
    -- Включаем AUTO FARM
    if autoCfg.Enabled then
        task.wait(2)  -- Небольшая задержка
        
        AutoFarmSettings.Enabled = true
        AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        AutoFarmBtn.Text = tr("auto_farm_on")
        startAutoFarmLoop()
        print("✅ Auto Farm: ON")
    end
    
    State.LastLog = "🚀 Автофарм запущен: " .. (AutoFarmSettings.Difficulty or "?")
    
        -- Auto Skip
    if autoCfg.GlobalAutoSkip then
        Settings.GlobalAutoSkip = true
        GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
        GlobalSkipBtn.Text = tr("global_skip_on")
        startGlobalAutoSkip()
        print("✅ Global Auto Skip: ON")
    end
    
    -- Auto Chain
    if autoCfg.GlobalAutoChain then
        Settings.GlobalAutoChain = true
        GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
        GlobalChainBtn.Text = tr("global_chain_on")
        startGlobalAutoChain()
        print("✅ Global Auto Chain: ON")
    end
    
    -- Auto DJ
    if autoCfg.GlobalAutoDJ then
        Settings.GlobalAutoDJ = true
        GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
        GlobalDJBtn.Text = tr("global_dj_on")
        startGlobalAutoDJ()
        print("✅ Global Auto DJ: ON")
    end
    
    if autoCfg.GlobalAutoPickups then
        autoPickupsEnabled = true
        AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
        AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
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
local SCRIPT_URL = "https://raw.githubusercontent.com/mcmcmcfdfdffd/nulallll/refs/heads/main/TDS%20(AUTOFARM).lua"  -- ЗАМЕНИ НА СВОЮ!

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
            ModeBtn.Text = tr("mode_btn", AutoFarmSettings.Difficulty)
        end
        
        -- Auto Start
        if config.AutoStart then
            AutoFarmSettings.AutoStart = true
            AutoStartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
            AutoStartBtn.Text = tr("auto_start_on")
        end
        
        -- Auto Skip
        if config.GlobalAutoSkip then
            Settings.GlobalAutoSkip = true
            GlobalSkipBtn.BackgroundColor3 = Color3.fromRGB(180, 150, 0)
            GlobalSkipBtn.Text = tr("global_skip_on")
            startGlobalAutoSkip()
        end
        
        -- Auto Chain
        if config.GlobalAutoChain then
            Settings.GlobalAutoChain = true
            GlobalChainBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
            GlobalChainBtn.Text = tr("global_chain_on")
            startGlobalAutoChain()
        end
        
        -- Auto DJ
        if config.GlobalAutoDJ then
            Settings.GlobalAutoDJ = true
            GlobalDJBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 150)
            GlobalDJBtn.Text = tr("global_dj_on")
            startGlobalAutoDJ()
        end
        
        -- Auto Pickups
        if config.GlobalAutoPickups then
            autoPickupsEnabled = true
            AutoPickupsBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 130)
            AutoPickupsBtn.Text = "🎁 PICKUPS: ON"
            startAutoPickups()
        end
        
        -- Queue on teleport
        QueueSettings.Enabled = config.QueueEnabled or false
        QueueSettings.ConfigName = name
        
        if QueueSettings.Enabled then
            if QueueToggleBtn then
            QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
            QueueToggleBtn.Text = tr("queue_on")
            end
            setupQueueOnTeleport(name)
        end
        
        -- Auto Farm (последним)
        if config.Enabled then
            task.wait(1)
            AutoFarmSettings.Enabled = true
            AutoFarmBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
            AutoFarmBtn.Text = tr("auto_farm_on")
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

-- Увеличиваем GlobalSection чтобы влезло всё
GlobalSection.Size = UDim2.new(1, 0, 0, 224)

-- Перемещаем статус пикапов
PickupsStatusLabel.Position = UDim2.new(0.5, 0, 0, 116)

-- Разделитель
local AFSeparator = Instance.new("Frame")
AFSeparator.Size = UDim2.new(0.96, 0, 0, 2)
AFSeparator.Position = UDim2.new(0.02, 0, 0, 146)
AFSeparator.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
AFSeparator.BorderSizePixel = 0
AFSeparator.Parent = GlobalSection

-- Заголовок секции
AutoFarmConfigTitle = Instance.new("TextLabel")
AutoFarmConfigTitle.Size = UDim2.new(1, -10, 0, 12)
AutoFarmConfigTitle.Position = UDim2.new(0, 5, 0, 152)
AutoFarmConfigTitle.BackgroundTransparency = 1
AutoFarmConfigTitle.Text = tr("autofarm_config_title")
AutoFarmConfigTitle.TextColor3 = Color3.fromRGB(255, 180, 100)
AutoFarmConfigTitle.TextSize = 9
AutoFarmConfigTitle.Font = Enum.Font.GothamBold
AutoFarmConfigTitle.TextXAlignment = Enum.TextXAlignment.Left
AutoFarmConfigTitle.Parent = GlobalSection

-- Поле для имени конфига
AutoFarmConfigNameBox = Instance.new("TextBox")
AutoFarmConfigNameBox.Size = UDim2.new(0.55, -8, 0, 20)
AutoFarmConfigNameBox.Position = UDim2.new(0, 5, 0, 166)
AutoFarmConfigNameBox.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
AutoFarmConfigNameBox.Text = ""
AutoFarmConfigNameBox.PlaceholderText = tr("autofarm_config_placeholder")
AutoFarmConfigNameBox.TextColor3 = Color3.new(1, 1, 1)
AutoFarmConfigNameBox.TextSize = 9
AutoFarmConfigNameBox.Font = Enum.Font.Gotham
AutoFarmConfigNameBox.Parent = GlobalSection
Instance.new("UICorner", AutoFarmConfigNameBox).CornerRadius = UDim.new(0, 5)

-- Кнопка SAVE
local SaveAutoFarmBtn = Instance.new("TextButton")
SaveAutoFarmBtn.Size = UDim2.new(0.22, -3, 0, 20)
SaveAutoFarmBtn.Position = UDim2.new(0.55, 0, 0, 166)
SaveAutoFarmBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
SaveAutoFarmBtn.Text = "💾"
SaveAutoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
SaveAutoFarmBtn.TextSize = 11
SaveAutoFarmBtn.Font = Enum.Font.GothamBold
SaveAutoFarmBtn.Parent = GlobalSection
Instance.new("UICorner", SaveAutoFarmBtn).CornerRadius = UDim.new(0, 5)

-- Кнопка REFRESH
local RefreshAutoFarmBtn = Instance.new("TextButton")
RefreshAutoFarmBtn.Size = UDim2.new(0.22, -3, 0, 20)
RefreshAutoFarmBtn.Position = UDim2.new(0.77, 0, 0, 166)
RefreshAutoFarmBtn.BackgroundColor3 = Color3.fromRGB(80, 100, 140)
RefreshAutoFarmBtn.Text = "🔄"
RefreshAutoFarmBtn.TextColor3 = Color3.new(1, 1, 1)
RefreshAutoFarmBtn.TextSize = 11
RefreshAutoFarmBtn.Font = Enum.Font.GothamBold
RefreshAutoFarmBtn.Parent = GlobalSection
Instance.new("UICorner", RefreshAutoFarmBtn).CornerRadius = UDim.new(0, 5)

-- Скролл для списка конфигов
local AutoFarmConfigScroll = Instance.new("ScrollingFrame")
AutoFarmConfigScroll.Size = UDim2.new(0.65, -8, 0, 22)
AutoFarmConfigScroll.Position = UDim2.new(0, 5, 0, 190)
AutoFarmConfigScroll.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
AutoFarmConfigScroll.ScrollBarThickness = 3
AutoFarmConfigScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
AutoFarmConfigScroll.ScrollingDirection = Enum.ScrollingDirection.X
AutoFarmConfigScroll.Parent = GlobalSection
Instance.new("UICorner", AutoFarmConfigScroll).CornerRadius = UDim.new(0, 5)

local AutoFarmConfigLayout = Instance.new("UIListLayout", AutoFarmConfigScroll)
AutoFarmConfigLayout.FillDirection = Enum.FillDirection.Horizontal
AutoFarmConfigLayout.Padding = UDim.new(0, 4)
Instance.new("UIPadding", AutoFarmConfigScroll).PaddingLeft = UDim.new(0, 3)

-- Кнопка QUEUE ON/OFF
QueueToggleBtn = Instance.new("TextButton")
QueueToggleBtn.Size = UDim2.new(0.33, -5, 0, 22)
QueueToggleBtn.Position = UDim2.new(0.66, 0, 0, 190)
QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
QueueToggleBtn.Text = tr("queue_off")
QueueToggleBtn.TextColor3 = Color3.new(1, 1, 1)
QueueToggleBtn.TextSize = 8
QueueToggleBtn.Font = Enum.Font.GothamBold
QueueToggleBtn.Parent = GlobalSection
Instance.new("UICorner", QueueToggleBtn).CornerRadius = UDim.new(0, 5)

-- Обновление списка конфигов автофарма
local function updateAutoFarmConfigList()
    for _, child in pairs(AutoFarmConfigScroll:GetChildren()) do
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
        btn.Parent = AutoFarmConfigScroll
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        
        -- ЛКМ = загрузить
        btn.MouseButton1Click:Connect(function()
            loadAutoFarmConfig(fileName)
            AutoFarmConfigNameBox.Text = fileName
        end)
        
        -- ПКМ = удалить
        btn.MouseButton2Click:Connect(function()
            deleteAutoFarmConfig(fileName)
            updateAutoFarmConfigList()
        end)
    end
end

-- ========== СОБЫТИЯ ==========

SaveAutoFarmBtn.MouseButton1Click:Connect(function()
    local name = AutoFarmConfigNameBox.Text
    if saveAutoFarmConfig(name) then
        updateAutoFarmConfigList()
        if QueueSettings.Enabled then
            setupQueueOnTeleport(name)
        end
    end
end)

RefreshAutoFarmBtn.MouseButton1Click:Connect(function()
    updateAutoFarmConfigList()
    State.LastLog = "🔄 Список обновлён"
    updateStatus()
end)

QueueToggleBtn.MouseButton1Click:Connect(function()
    QueueSettings.Enabled = not QueueSettings.Enabled
    
    if QueueSettings.Enabled then
        QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        QueueToggleBtn.Text = tr("queue_on")
        
        local configName = AutoFarmConfigNameBox.Text
        if configName ~= "" then
            setupQueueOnTeleport(configName)
            State.LastLog = "🔄 Queue ON: " .. configName
        else
            State.LastLog = "⚠️ Сначала сохрани конфиг!"
        end
    else
        QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        QueueToggleBtn.Text = tr("queue_off")
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
    if QueueSettings.Enabled and QueueToggleBtn then
        QueueToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 120)
        QueueToggleBtn.Text = tr("queue_on")
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

