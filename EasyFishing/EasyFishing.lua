local MIN_DOUBLE_CLICK = 0.05
local MAX_DOUBLE_CLICK = 0.4
local lastClickTime    = 0
local pendingClearTimer = nil
local clearBindingOnMouseUp = false
local FISHING_SESSION_IDLE = 120

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

local DB_DEFAULTS = {
    enableDoubleClick = true,
    enableAutoLure    = true,
    enableSound       = true,
    disableClickToMoveWhileFishing = false,
    showFishWatcher = true,
    doubleClickDelay  = 0.4,
    doubleClickButton = "LeftButton", -- see BUTTON_OPTIONS below
    castClickMode     = "DoubleClick",
    fishWatcherX      = 0,
    fishWatcherY      = 160,
}

-- All mouse buttons we can bind to. `binding` is the WoW key name used by
-- SetOverrideBindingClick; `key` is what GLOBAL_MOUSE_DOWN reports.
local BUTTON_OPTIONS = {
    { key = "LeftButton",   binding = "BUTTON1", label = "Left Mouse" },
    { key = "RightButton",  binding = "BUTTON2", label = "Right Mouse" },
    { key = "MiddleButton", binding = "BUTTON3", label = "Middle Mouse" },
    { key = "Button4",      binding = "BUTTON4", label = "Mouse Button 4" },
    { key = "Button5",      binding = "BUTTON5", label = "Mouse Button 5" },
}

local CAST_MODE_OPTIONS = {
    { value = "SingleClick", label = "Single Click" },
    { value = "DoubleClick", label = "Double Click" },
}

local BUTTON_BY_KEY = {}
for _, opt in ipairs(BUTTON_OPTIONS) do
    BUTTON_BY_KEY[opt.key] = opt
end

local function GetButtonOption(key)
    return BUTTON_BY_KEY[key] or BUTTON_BY_KEY["RightButton"]
end

-- ---------------------------------------------------------------------------
-- Small API wrappers
-- ---------------------------------------------------------------------------

local function IsFishingPoleEquipped()
    local mainHand = GetInventoryItemID("player", 16)
    if not mainHand then return false end
    local classID, subclassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(mainHand)
    elseif GetItemInfoInstant then
        _, _, _, _, _, classID, subclassID = GetItemInfoInstant(mainHand)
    elseif GetItemInfo then
        _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = GetItemInfo(mainHand)
    end
    return classID == 2 and (subclassID == 20 or subclassID == 25)
end

local function GetFishingSpellName()
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(7620) or C_Spell.GetSpellName(131474)
    elseif GetSpellInfo then
        name = GetSpellInfo(7620) or GetSpellInfo(131474)
    end
    return name or "Fishing"
end

local function IsFishingChannelActive()
    return UnitChannelInfo("player") == GetFishingSpellName()
end

local LURES = {
    { id = 6529, minimumSkill = 1 },
    { id = 6530, minimumSkill = 50 },
    { id = 6811, minimumSkill = 50 },
    { id = 6532, minimumSkill = 100 },
    { id = 7307, minimumSkill = 100 },
    { id = 6533, minimumSkill = 100 },
}

local function GetFishingSkill()
    if not GetNumSkillLines or not GetSkillLineInfo then return nil end

    local fishingName = GetFishingSpellName()
    for index = 1, GetNumSkillLines() do
        local skillName, isHeader, _, rank = GetSkillLineInfo(index)
        if not isHeader and skillName == fishingName and type(rank) == "number" then
            return rank
        end
    end
end

local function GetItemCountWrapper(itemID)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID)
    elseif GetItemCount then
        return GetItemCount(itemID)
    end
    return 0
end

local function GetAvailableLures()
    local available = {}
    local skill = GetFishingSkill() or 0
    for _, lure in ipairs(LURES) do
        local count = GetItemCountWrapper(lure.id)
        if count > 0 and skill >= lure.minimumSkill then
            table.insert(available, { id = lure.id, count = count })
        end
    end
    return available
end

local function GetEquipmentSetIDs()
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs
        or not C_EquipmentSet.GetEquipmentSetInfo then
        return {}
    end
    return C_EquipmentSet.GetEquipmentSetIDs() or {}
end

local function GetEquippedEquipmentSetID()
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then
        return nil
    end
    for _, setID in ipairs(GetEquipmentSetIDs()) do
        local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if isEquipped then return setID end
    end
end

local function UseFishingEquipmentSet(setID)
    if InCombatLockdown() then
        print("EasyFishing: equipment sets cannot be changed in combat.")
        return false
    end
    if not C_EquipmentSet or not C_EquipmentSet.UseEquipmentSet then
        print("EasyFishing: equipment sets are unavailable on this client.")
        return false
    end
    if not setID or not C_EquipmentSet.UseEquipmentSet(setID) then
        print("EasyFishing: unable to equip that equipment set.")
        return false
    end
    return true
end

local function EquipFishingOutfit()
    local setID = tonumber(EasyFishingDB and EasyFishingDB.fishingOutfitSetID)
    if not setID then
        print("EasyFishing: select a fishing equipment set first.")
        return
    end

    local currentSetID = GetEquippedEquipmentSetID()
    if currentSetID == setID then return end
    if not currentSetID then
        print("EasyFishing: equip a saved set first so EasyFishing can restore it later.")
        return
    end

    if UseFishingEquipmentSet(setID) and not EasyFishingDB.previousFishingSetID then
        EasyFishingDB.previousFishingSetID = currentSetID
    end
end

local function RestorePreviousEquipmentSet()
    local setID = tonumber(EasyFishingDB and EasyFishingDB.previousFishingSetID)
    if not setID then
        print("EasyFishing: there is no saved equipment set to restore.")
        return
    end
    if UseFishingEquipmentSet(setID) then
        EasyFishingDB.previousFishingSetID = nil
    end
end

local function GetAutoLureID()
    if not EasyFishingDB or not EasyFishingDB.enableAutoLure then return nil end
    if not IsFishingPoleEquipped() then return nil end

    local hasMainHandEnchant = GetWeaponEnchantInfo()
    if hasMainHandEnchant then return nil end

    local availableLures = GetAvailableLures()
    return availableLures[1] and availableLures[1].id
end

-- ---------------------------------------------------------------------------
-- CVar helpers
-- ---------------------------------------------------------------------------

local function GetCVarBG()
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar("Sound_EnableSoundWhenGameIsInBG")
    end
    return GetCVar("Sound_EnableSoundWhenGameIsInBG")
end

local function SetCVarBG(val)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", val)
    else
        SetCVar("Sound_EnableSoundWhenGameIsInBG", val)
    end
end

local function GetCVarSound()
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar("Sound_EnableSFX")
    end
    return GetCVar("Sound_EnableSFX")
end

local function SetCVarSound(val)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("Sound_EnableSFX", val)
    else
        SetCVar("Sound_EnableSFX", val)
    end
end

local savedAutoInteractSetting = nil

local function GetAutoInteractSetting()
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar("autointeract")
    end
    return GetCVar("autointeract")
end

local function SetAutoInteractSetting(value)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar("autointeract", value)
    else
        SetCVar("autointeract", value)
    end
end

local function RestoreAutoInteractSetting()
    if savedAutoInteractSetting ~= nil then
        local previousValue = savedAutoInteractSetting
        savedAutoInteractSetting = nil
        SetAutoInteractSetting(previousValue)
    end
end

local function UpdateAutoInteractSetting()
    local shouldDisable = EasyFishingDB
        and EasyFishingDB.disableClickToMoveWhileFishing
        and EasyFishingDB.enableDoubleClick
        and IsFishingPoleEquipped()

    if shouldDisable then
        local currentValue = GetAutoInteractSetting()
        if currentValue == nil then return end
        if savedAutoInteractSetting == nil then
            savedAutoInteractSetting = currentValue
        end
        if currentValue ~= "0" then
            SetAutoInteractSetting("0")
        end
    else
        RestoreAutoInteractSetting()
    end
end

-- ---------------------------------------------------------------------------
-- Double-click casting
-- ---------------------------------------------------------------------------

-- This frame is used purely as the *owner* of the override binding.
local castOwner = CreateFrame("Frame", "EasyFishingCastOwner", UIParent)

local function CancelPendingTimer()
    if pendingClearTimer then
        pendingClearTimer:Cancel()
        pendingClearTimer = nil
    end
end

local function ClearBinding()
    CancelPendingTimer()
    if not InCombatLockdown() then
        ClearOverrideBindings(castOwner)
    end
    lastClickTime = 0
    clearBindingOnMouseUp = false
end

local autoLureButton = CreateFrame(
    "Button", "EasyFishingAutoLureButton", UIParent, "SecureActionButtonTemplate")
autoLureButton:SetSize(1, 1)
autoLureButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, -10)
autoLureButton:SetAlpha(0)
autoLureButton:RegisterForClicks("LeftButtonDown")
autoLureButton:Show()

local function BindCastAction(buttonName)
    local option = GetButtonOption(buttonName)
    local lureID = GetAutoLureID()

    if lureID then
        autoLureButton:SetAttribute("type", "item")
        autoLureButton:SetAttribute("item", "item:" .. lureID)
        autoLureButton:SetAttribute("target-slot", 16)
        autoLureButton:SetAttribute("spell", nil)
    else
        autoLureButton:SetAttribute("type", "spell")
        autoLureButton:SetAttribute("spell", GetFishingSpellName())
        autoLureButton:SetAttribute("item", nil)
        autoLureButton:SetAttribute("target-slot", nil)
    end

    SetOverrideBindingClick(
        castOwner, true, option.binding, autoLureButton:GetName(), "LeftButton")
end

local isFishing = false

local fishingSession = nil
local fishingSessionEndTimer = nil

local fishWatcher = CreateFrame("Frame", "EasyFishingFishWatcher", UIParent, "BackdropTemplate")
fishWatcher:SetSize(300, 82)
fishWatcher:SetFrameStrata("MEDIUM")
fishWatcher:SetClampedToScreen(true)
fishWatcher:SetMovable(true)
fishWatcher:EnableMouse(true)
fishWatcher:RegisterForDrag("MiddleButton")
fishWatcher:Hide()

if fishWatcher.SetBackdrop then
    fishWatcher:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    fishWatcher:SetBackdropColor(0, 0, 0, 0.8)
    fishWatcher:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
end

local fishWatcherTitle = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
fishWatcherTitle:SetPoint("TOPLEFT", fishWatcher, "TOPLEFT", 10, -8)
fishWatcherTitle:SetWidth(280)
fishWatcherTitle:SetJustifyH("LEFT")

local fishWatcherSummary = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherSummary:SetPoint("TOPLEFT", fishWatcherTitle, "BOTTOMLEFT", 0, -4)
fishWatcherSummary:SetWidth(280)
fishWatcherSummary:SetJustifyH("LEFT")

local fishWatcherLastCatch = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherLastCatch:SetPoint("TOPLEFT", fishWatcherSummary, "BOTTOMLEFT", 0, -3)
fishWatcherLastCatch:SetWidth(280)
fishWatcherLastCatch:SetJustifyH("LEFT")

local fishWatcherBreakdown = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherBreakdown:SetPoint("TOPLEFT", fishWatcherLastCatch, "BOTTOMLEFT", 0, -3)
fishWatcherBreakdown:SetWidth(280)
fishWatcherBreakdown:SetJustifyH("LEFT")
fishWatcherBreakdown:SetWordWrap(true)

fishWatcher:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
        self:StartMoving()
    end
end)
fishWatcher:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if not EasyFishingDB then return end

    local centerX, centerY = self:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    EasyFishingDB.fishWatcherX = centerX - parentX
    EasyFishingDB.fishWatcherY = centerY - parentY
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", EasyFishingDB.fishWatcherX, EasyFishingDB.fishWatcherY)
end)
fishWatcher:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 5)
    GameTooltip:SetText("Fishing Watcher")
    GameTooltip:AddLine("Middle-click and drag to move", 1, 1, 1)
    GameTooltip:Show()
end)
fishWatcher:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function EnsureFishingStats()
    if type(EasyFishingDB.fishingStats) ~= "table" then
        EasyFishingDB.fishingStats = {}
    end
    local stats = EasyFishingDB.fishingStats
    stats.totalItems = tonumber(stats.totalItems) or 0
    stats.totalSessions = tonumber(stats.totalSessions) or 0
    stats.totalCasts = tonumber(stats.totalCasts) or 0
    stats.totalFishingSeconds = tonumber(stats.totalFishingSeconds) or 0
    stats.totalSkillUps = tonumber(stats.totalSkillUps) or 0
    if type(stats.itemsByID) ~= "table" then
        stats.itemsByID = {}
    end
    if type(stats.zones) ~= "table" then
        stats.zones = {}
    end
    return stats
end

local function EnsureZoneFishingStats(stats, zoneName)
    local zoneStats = stats.zones[zoneName]
    if type(zoneStats) ~= "table" then
        zoneStats = {}
        stats.zones[zoneName] = zoneStats
    end
    zoneStats.totalItems = tonumber(zoneStats.totalItems) or 0
    zoneStats.sessions = tonumber(zoneStats.sessions) or 0
    zoneStats.casts = tonumber(zoneStats.casts) or 0
    zoneStats.fishingSeconds = tonumber(zoneStats.fishingSeconds) or 0
    zoneStats.skillUps = tonumber(zoneStats.skillUps) or 0
    if type(zoneStats.itemsByID) ~= "table" then
        zoneStats.itemsByID = {}
    end
    if type(zoneStats.spots) ~= "table" then
        zoneStats.spots = {}
    end
    return zoneStats
end

local function RecordFishingSpot(zoneStats, itemKey, itemName, quantity)
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position or not position.GetXY then return end
    local x, y = position:GetXY()
    if not x or not y then return end

    local cellX = math.min(199, math.max(0, math.floor(x * 200)))
    local cellY = math.min(199, math.max(0, math.floor(y * 200)))
    local spotKey = string.format("%d:%d:%d", mapID, cellX, cellY)
    local spot = zoneStats.spots[spotKey]
    if type(spot) ~= "table" then
        spot = {
            mapID = mapID,
            x = x,
            y = y,
            subzone = GetSubZoneText() or "",
            totalItems = 0,
            itemsByID = {},
        }
        zoneStats.spots[spotKey] = spot
    end

    local item = spot.itemsByID[itemKey]
    if type(item) ~= "table" then
        item = { name = itemName, count = 0, timeBuckets = {} }
        spot.itemsByID[itemKey] = item
    end
    item.name = itemName
    item.count = (tonumber(item.count) or 0) + quantity
    spot.totalItems = (tonumber(spot.totalItems) or 0) + quantity
    local hour = GetGameTime()
    local bucket = math.floor(hour / 6)
    item.timeBuckets[bucket] = (tonumber(item.timeBuckets[bucket]) or 0) + quantity
end

local function FormatFishingTime(seconds)
    local totalSeconds = math.max(0, math.floor(seconds))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local remainingSeconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function UpdateFishWatcher()
    if not fishingSession or not EasyFishingDB or not EasyFishingDB.showFishWatcher then
        fishWatcher:Hide()
        return
    end

    local zoneName = GetRealZoneText() or fishingSession.zone
    local stats = EnsureFishingStats()
    local zoneStats = EnsureZoneFishingStats(stats, zoneName)
    local zoneItems = zoneStats.totalItems
    fishWatcherTitle:SetText("Fishing Watcher - " .. zoneName)
    fishWatcherSummary:SetText(string.format(
        "Time %s | Casts %d | Skill-ups %d\nSession items %d | All-time %d",
        FormatFishingTime(GetTime() - fishingSession.startedAt),
        fishingSession.casts, fishingSession.skillUps,
        fishingSession.totalItems, zoneItems))
    fishWatcherLastCatch:SetText("Last catch: " .. (fishingSession.lastCatch or "None yet"))
    local sessionItems = {}
    for _, item in pairs(fishingSession.itemsByID) do
        table.insert(sessionItems, item)
    end
    table.sort(sessionItems, function(firstItem, secondItem)
        if firstItem.count == secondItem.count then
            return firstItem.name < secondItem.name
        end
        return firstItem.count > secondItem.count
    end)
    local catchSummary = {}
    for index = 1, math.min(#sessionItems, 2) do
        local item = sessionItems[index]
        table.insert(catchSummary, string.format("%s x%d", item.name, item.count))
    end
    if #sessionItems > 2 then
        table.insert(catchSummary, string.format("+%d more", #sessionItems - 2))
    end
    fishWatcherBreakdown:SetText("Items caught this session: " .. (#catchSummary > 0 and table.concat(catchSummary, ", ") or "None yet"))
    fishWatcher:Show()
end

local function EndFishingSession()
    if fishingSessionEndTimer then
        fishingSessionEndTimer:Cancel()
        fishingSessionEndTimer = nil
    end
    if fishingSession then
        local endedAt = fishingSession.lastActivityAt or GetTime()
        local duration = math.max(0, endedAt - fishingSession.startedAt)
        local stats = EnsureFishingStats()
        local zoneStats = EnsureZoneFishingStats(stats, fishingSession.zone)
        stats.totalFishingSeconds = stats.totalFishingSeconds + duration
        zoneStats.fishingSeconds = zoneStats.fishingSeconds + duration
    end
    fishingSession = nil
    fishWatcher:Hide()
end

local function StartFishingSession()
    if fishingSessionEndTimer then
        fishingSessionEndTimer:Cancel()
        fishingSessionEndTimer = nil
    end
    if not fishingSession then
        local stats = EnsureFishingStats()
        local zoneName = GetRealZoneText() or "Unknown zone"
        local zoneStats = EnsureZoneFishingStats(stats, zoneName)
        stats.totalSessions = stats.totalSessions + 1
        zoneStats.sessions = zoneStats.sessions + 1
        fishingSession = {
            startedAt = GetTime(),
            zone = zoneName,
            totalItems = 0,
            lastCatch = nil,
            itemsByID = {},
            casts = 0,
            skillUps = 0,
            lastActivityAt = GetTime(),
            lastSkill = GetFishingSkill(),
        }
    end
    local castTime = GetTime()
    local sessionZoneStats = EnsureZoneFishingStats(
        EnsureFishingStats(), fishingSession.zone)
    fishingSession.casts = fishingSession.casts + 1
    fishingSession.lastActivityAt = castTime
    sessionZoneStats.casts = sessionZoneStats.casts + 1
    EnsureFishingStats().totalCasts = EnsureFishingStats().totalCasts + 1
    UpdateFishWatcher()
end

local function UpdateFishingSkillUps()
    if not fishingSession then return end
    local currentSkill = GetFishingSkill()
    local previousSkill = fishingSession.lastSkill
    if not currentSkill then return end

    fishingSession.lastSkill = currentSkill
    if previousSkill and currentSkill > previousSkill then
        local gained = currentSkill - previousSkill
        fishingSession.skillUps = fishingSession.skillUps + gained
        local stats = EnsureFishingStats()
        local zoneStats = EnsureZoneFishingStats(stats, fishingSession.zone)
        stats.totalSkillUps = stats.totalSkillUps + gained
        zoneStats.skillUps = (tonumber(zoneStats.skillUps) or 0) + gained
        UpdateFishWatcher()
    end
end

local function ScheduleFishingSessionEnd()
    if fishingSessionEndTimer then
        fishingSessionEndTimer:Cancel()
    end
    fishingSessionEndTimer = C_Timer.NewTimer(FISHING_SESSION_IDLE, function()
        fishingSessionEndTimer = nil
        if not isFishing then
            EndFishingSession()
        end
    end)
end

local function RecordFishingLoot()
    if not fishingSession or type(IsFishingLoot) ~= "function" or not IsFishingLoot() then
        return
    end

    local stats = EnsureFishingStats()
    local zoneName = GetRealZoneText() or "Unknown zone"
    local zoneStats = EnsureZoneFishingStats(stats, zoneName)

    for lootSlot = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(lootSlot)
        local itemID = itemLink and tonumber(itemLink:match("|Hitem:(%d+)"))
        if itemID then
            local _, itemName, quantity = GetLootSlotInfo(lootSlot)
            itemName = itemName or GetItemInfo(itemID) or ("Item " .. itemID)
            quantity = tonumber(quantity) or 1

            local itemKey = tostring(itemID)
            local totalItem = stats.itemsByID[itemKey]
            if type(totalItem) ~= "table" then
                totalItem = { name = itemName, count = 0 }
                stats.itemsByID[itemKey] = totalItem
            end
            totalItem.name = itemName
            totalItem.count = (tonumber(totalItem.count) or 0) + quantity

            local sessionItem = fishingSession.itemsByID[itemKey]
            if type(sessionItem) ~= "table" then
                sessionItem = { name = itemName, count = 0 }
                fishingSession.itemsByID[itemKey] = sessionItem
            end
            sessionItem.name = itemName
            sessionItem.count = sessionItem.count + quantity

            local zoneItem = zoneStats.itemsByID[itemKey]
            if type(zoneItem) ~= "table" then
                zoneItem = { name = itemName, count = 0 }
                zoneStats.itemsByID[itemKey] = zoneItem
            end
            zoneItem.name = itemName
            zoneItem.count = (tonumber(zoneItem.count) or 0) + quantity

            RecordFishingSpot(zoneStats, itemKey, itemName, quantity)

            stats.totalItems = stats.totalItems + quantity
            zoneStats.totalItems = zoneStats.totalItems + quantity
            fishingSession.totalItems = fishingSession.totalItems + quantity
            fishingSession.lastCatch = itemName
        end
    end

    UpdateFishWatcher()
end

fishWatcher:SetScript("OnUpdate", function(self, elapsed)
    self.updateElapsed = (self.updateElapsed or 0) + elapsed
    if self.updateElapsed >= 1 then
        self.updateElapsed = 0
        UpdateFishWatcher()
    end
end)

-- ---------------------------------------------------------------------------
-- Main frame
-- ---------------------------------------------------------------------------

local mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
mainFrame:RegisterEvent("PLAYER_LOGOUT")

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGOUT" then
        RestoreAutoInteractSetting()
        EndFishingSession()
        return
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
        UpdateAutoInteractSetting()
        return
    elseif event ~= "PLAYER_LOGIN" then
        return
    end

    if event == "PLAYER_LOGIN" then
        -- Initialise saved variables
        EasyFishingDB = EasyFishingDB or {}
        for k, v in pairs(DB_DEFAULTS) do
            if EasyFishingDB[k] == nil then
                EasyFishingDB[k] = v
            end
        end
        MAX_DOUBLE_CLICK = EasyFishingDB.doubleClickDelay
        EnsureFishingStats()
        fishWatcher:ClearAllPoints()
        fishWatcher:SetPoint("CENTER", UIParent, "CENTER",
            EasyFishingDB.fishWatcherX, EasyFishingDB.fishWatcherY)
        UpdateAutoInteractSetting()

        -- ------------------------------------------------------------------
        -- Options panel
        -- ------------------------------------------------------------------
        local panel = CreateFrame("Frame", "EasyFishingOptionsPanel", UIParent)
        panel.name  = "EasyFishing: Forever"

        local settingsPage = CreateFrame("Frame", nil, panel)
        settingsPage:SetAllPoints(panel)

        local statisticsPage = CreateFrame("Frame", nil, panel)
        statisticsPage:SetAllPoints(panel)
        statisticsPage:Hide()

        local locationsPage = CreateFrame("Frame", nil, panel)
        locationsPage:SetAllPoints(panel)
        locationsPage:Hide()

        local settingsTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        settingsTab:SetSize(86, 22)
        settingsTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -270, -10)
        settingsTab:SetText("Settings")

        local statisticsTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        statisticsTab:SetSize(86, 22)
        statisticsTab:SetPoint("LEFT", settingsTab, "RIGHT", 4, 0)
        statisticsTab:SetText("Statistics")

        local locationsTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        locationsTab:SetSize(86, 22)
        locationsTab:SetPoint("LEFT", statisticsTab, "RIGHT", 4, 0)
        locationsTab:SetText("Locations")

        local title = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("EasyFishing: Forever")

        local divider = settingsPage:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        divider:SetSize(550, 1)
        divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

        local function SectionHeader(text, anchor, yOff)
            local fs = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
            fs:SetTextColor(1, 0.82, 0)
            fs:SetText(text)
            return fs
        end

        local function MakeCheckbox(label, desc, anchor, yOffset, dbKey)
            local cb = CreateFrame("CheckButton", "EasyFishingCB_" .. dbKey,
            settingsPage, "InterfaceOptionsCheckButtonTemplate")
            cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
            cb.Text:SetText(label)
            if desc then
                cb:SetScript("OnEnter", function(me)
                    GameTooltip:SetOwner(me, "ANCHOR_RIGHT")
                    GameTooltip:SetText(label, 1, 1, 1)
                    GameTooltip:AddLine(desc, nil, nil, nil, true)
                    GameTooltip:Show()
                end)
                cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            cb:SetChecked(EasyFishingDB[dbKey])
            cb:SetScript("OnClick", function(me)
                EasyFishingDB[dbKey] = me:GetChecked()
                if dbKey == "enableDoubleClick" then
                    MAX_DOUBLE_CLICK = EasyFishingDB.doubleClickDelay
                    if not me:GetChecked() then
                        ClearBinding()
                    end
                    UpdateAutoInteractSetting()
                elseif dbKey == "disableClickToMoveWhileFishing" then
                    UpdateAutoInteractSetting()
                elseif dbKey == "showFishWatcher" then
                    UpdateFishWatcher()
                end
            end)
            return cb
        end

        local secCast = SectionHeader("Casting", divider, -14)

        local cbDC = MakeCheckbox(
            "Enable Click-to-Cast",
            "Cast using the selected mouse button and click mode while holding a fishing pole.",
            secCast, -4, "enableDoubleClick")

        local modeLabel = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        modeLabel:SetPoint("TOPLEFT", cbDC, "BOTTOMLEFT", 26, -10)
        modeLabel:SetText("Cast Click Mode")

        local UpdateSliderState
        local modeDropdown = CreateFrame("Frame", "EasyFishingCastModeDropdown",
            settingsPage, "UIDropDownMenuTemplate")
        modeDropdown:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", -16, -4)
        UIDropDownMenu_SetWidth(modeDropdown, 150)
        local function GetCastModeLabel(value)
            for _, option in ipairs(CAST_MODE_OPTIONS) do
                if option.value == value then return option.label end
            end
            return "Double Click"
        end
        UIDropDownMenu_SetText(modeDropdown, GetCastModeLabel(EasyFishingDB.castClickMode))
        UIDropDownMenu_Initialize(modeDropdown, function()
            for _, option in ipairs(CAST_MODE_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.label
                info.checked = EasyFishingDB.castClickMode == option.value
                info.func = function()
                    EasyFishingDB.castClickMode = option.value
                    UIDropDownMenu_SetText(modeDropdown, option.label)
                    CloseDropDownMenus()
                    ClearBinding()
                    UpdateSliderState(
                        EasyFishingDB.enableDoubleClick and option.value == "DoubleClick")
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        -- Button picker -----------------------------------------------------
        local btnLabel = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        btnLabel:SetPoint("TOPLEFT", modeDropdown, "BOTTOMLEFT", 16, -10)
        btnLabel:SetText("Cast Button")
        btnLabel:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click-to-Move")
            GameTooltip:AddLine(
                "Right-click casting may conflict with Click-to-Move. Left Mouse is the default; choose another button if needed.",
                1, 1, 1, true)
            GameTooltip:Show()
        end)
        btnLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local dropdown = CreateFrame("Frame", "EasyFishingButtonDropdown",
            settingsPage, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", btnLabel, "BOTTOMLEFT", -16, -4)
        UIDropDownMenu_SetWidth(dropdown, 150)
        UIDropDownMenu_SetText(dropdown, GetButtonOption(EasyFishingDB.doubleClickButton).label)

        UIDropDownMenu_Initialize(dropdown, function()
            for _, opt in ipairs(BUTTON_OPTIONS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text    = opt.label
                info.checked = EasyFishingDB.doubleClickButton == opt.key
                info.func    = function()
                    EasyFishingDB.doubleClickButton = opt.key
                    UIDropDownMenu_SetText(dropdown, opt.label)
                    CloseDropDownMenus()
                    -- Changing the button invalidates any pending binding.
                    ClearBinding()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        -- Delay slider ------------------------------------------------------
        local sliderLabel = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        sliderLabel:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -16)
        sliderLabel:SetText("Double-Click Window")

        local sliderDesc = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sliderDesc:SetPoint("TOPLEFT", sliderLabel, "BOTTOMLEFT", 0, -4)
        sliderDesc:SetTextColor(0.7, 0.7, 0.7)
        sliderDesc:SetText("How quickly you must double-click. Lower = faster.")

        local slider = CreateFrame("Slider", "EasyFishingDelaySlider",
            settingsPage, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", sliderDesc, "BOTTOMLEFT", 0, -18)
        slider:SetMinMaxValues(0.1, 0.8)
        slider:SetValueStep(0.05)
        slider:SetWidth(220)
        slider:SetValue(EasyFishingDB.doubleClickDelay)
        slider.Low:SetText("0.1s")
        slider.High:SetText("0.8s")
        slider.Text:SetText(string.format("%.2fs", EasyFishingDB.doubleClickDelay))
        slider:SetScript("OnValueChanged", function(me, val)
            local rounded = math.floor(val * 20 + 0.5) / 20
            EasyFishingDB.doubleClickDelay = rounded
            MAX_DOUBLE_CLICK = rounded
            me.Text:SetText(string.format("%.2fs", rounded))
        end)

        UpdateSliderState = function(enabled)
            if enabled then
                slider:Enable()
                sliderLabel:SetTextColor(1, 1, 1)
                sliderDesc:SetTextColor(0.7, 0.7, 0.7)
                slider.Low:SetTextColor(1, 1, 1)
                slider.High:SetTextColor(1, 1, 1)
            else
                slider:Disable()
                sliderLabel:SetTextColor(0.4, 0.4, 0.4)
                sliderDesc:SetTextColor(0.4, 0.4, 0.4)
                slider.Low:SetTextColor(0.4, 0.4, 0.4)
                slider.High:SetTextColor(0.4, 0.4, 0.4)
            end
        end
        UpdateSliderState(
            EasyFishingDB.enableDoubleClick and EasyFishingDB.castClickMode == "DoubleClick")

        local origClick = cbDC:GetScript("OnClick")
        cbDC:SetScript("OnClick", function(me, ...)
            if origClick then origClick(me, ...) end
            UpdateSliderState(
                me:GetChecked() and EasyFishingDB.castClickMode == "DoubleClick")
        end)

        local secLure = SectionHeader("Lures", slider, -24)
        local cbAutoLure = MakeCheckbox(
            "Automatically Apply Lure",
            "When your pole has no lure, the first selected cast action applies the weakest lure allowed by your Fishing skill. Repeat the selected click pattern to cast Fishing.",
            secLure, -4, "enableAutoLure")

        local secTracking = SectionHeader("Tracking", cbAutoLure, -10)
        MakeCheckbox(
            "Show Fish Watcher",
            "Show the current fishing zone, session time, item count, and most recent catch.",
            secTracking, -4, "showFishWatcher")

        local secMovement = SectionHeader("Movement", secTracking, -46)
        local cbDisableClickToMove = MakeCheckbox(
            "Disable Click-to-Move While Fishing",
            "Temporarily turns off Click-to-Move while a fishing pole is equipped and click-to-cast is enabled, then restores its previous setting.",
            secMovement, -4, "disableClickToMoveWhileFishing")

        -- Sound -------------------------------------------------------------
        local secSound = SectionHeader("Sound", cbDisableClickToMove, -10)
        local cbSound = MakeCheckbox(
            "Enable Sound Automation",
            "Turns on sound (and background sound) when you start fishing, then restores your original settings when done.",
            secSound, -4, "enableSound")

        local secOutfit = SectionHeader("Fishing Outfit", cbSound, -10)
        local outfitHint = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        outfitHint:SetPoint("TOPLEFT", secOutfit, "BOTTOMLEFT", 0, -4)
        outfitHint:SetWidth(540)
        outfitHint:SetJustifyH("LEFT")
        outfitHint:SetText("Choose a saved equipment set. EasyFishing remembers the previous saved set so you can restore it.")

        local outfitDropdown = CreateFrame("Frame", "EasyFishingOutfitDropdown",
            settingsPage, "UIDropDownMenuTemplate")
        outfitDropdown:SetPoint("TOPLEFT", outfitHint, "BOTTOMLEFT", -16, -6)
        UIDropDownMenu_SetWidth(outfitDropdown, 150)
        local selectedOutfitName = "Select an outfit"
        UIDropDownMenu_Initialize(outfitDropdown, function()
            local equipmentSetIDs = GetEquipmentSetIDs()
            if #equipmentSetIDs == 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "No saved equipment sets"
                info.disabled = true
                UIDropDownMenu_AddButton(info)
                return
            end
            for _, setID in ipairs(equipmentSetIDs) do
                local name = C_EquipmentSet.GetEquipmentSetInfo(setID)
                if name then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = name
                    info.checked = tonumber(EasyFishingDB.fishingOutfitSetID) == setID
                    info.func = function()
                        EasyFishingDB.fishingOutfitSetID = setID
                        UIDropDownMenu_SetText(outfitDropdown, name)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info)
                    if tonumber(EasyFishingDB.fishingOutfitSetID) == setID then
                        selectedOutfitName = name
                    end
                end
            end
        end)
        for _, setID in ipairs(GetEquipmentSetIDs()) do
            if tonumber(EasyFishingDB.fishingOutfitSetID) == setID then
                selectedOutfitName = C_EquipmentSet.GetEquipmentSetInfo(setID)
                break
            end
        end
        UIDropDownMenu_SetText(outfitDropdown, selectedOutfitName)

        local equipOutfitButton = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
        equipOutfitButton:SetSize(108, 22)
        equipOutfitButton:SetPoint("LEFT", outfitDropdown, "RIGHT", -4, 0)
        equipOutfitButton:SetText("Equip")
        equipOutfitButton:SetScript("OnClick", EquipFishingOutfit)

        local restoreOutfitButton = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
        restoreOutfitButton:SetSize(108, 22)
        restoreOutfitButton:SetPoint("LEFT", equipOutfitButton, "RIGHT", 4, 0)
        restoreOutfitButton:SetText("Restore")
        restoreOutfitButton:SetScript("OnClick", RestorePreviousEquipmentSet)

        local statisticsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        statisticsTitle:SetPoint("TOPLEFT", 16, -16)
        statisticsTitle:SetText("Fishing Statistics")

        local statisticsSummary = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        statisticsSummary:SetPoint("TOPLEFT", statisticsTitle, "BOTTOMLEFT", 0, -8)
        statisticsSummary:SetWidth(550)
        statisticsSummary:SetJustifyH("LEFT")

        local statisticsCaveat = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        statisticsCaveat:SetPoint("TOPLEFT", statisticsSummary, "BOTTOMLEFT", 0, -4)
        statisticsCaveat:SetText("Fishing loot is recorded only when the client identifies the loot window as fishing loot.")

        local zoneStatsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        zoneStatsTitle:SetPoint("TOPLEFT", statisticsCaveat, "BOTTOMLEFT", 0, -18)
        zoneStatsTitle:SetText("Recorded Items by Zone")

        local zoneStatsText = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        zoneStatsText:SetPoint("TOPLEFT", zoneStatsTitle, "BOTTOMLEFT", 0, -6)
        zoneStatsText:SetWidth(550)
        zoneStatsText:SetJustifyH("LEFT")

        local itemStatsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        itemStatsTitle:SetPoint("TOPLEFT", zoneStatsText, "BOTTOMLEFT", 0, -14)
        itemStatsTitle:SetText("Most Recorded Items")

        local itemStatsText = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        itemStatsText:SetPoint("TOPLEFT", itemStatsTitle, "BOTTOMLEFT", 0, -6)
        itemStatsText:SetWidth(550)
        itemStatsText:SetJustifyH("LEFT")

        local function BuildStatsLines(items, emptyText, limit, formatEntry)
            local entries = {}
            for name, data in pairs(items) do
                if type(data) == "table" then
                    table.insert(entries, {
                        name = data.name or name,
                        count = tonumber(data.totalItems or data.count) or 0,
                        data = data,
                    })
                end
            end
            table.sort(entries, function(first, second)
                if first.count == second.count then
                    return first.name < second.name
                end
                return first.count > second.count
            end)

            if #entries == 0 then return emptyText end

            local lines = {}
            for index = 1, math.min(#entries, limit) do
                if formatEntry then
                    lines[index] = formatEntry(entries[index])
                else
                    lines[index] = string.format("%s: %d items", entries[index].name, entries[index].count)
                end
            end
            if #entries > limit then
                table.insert(lines, string.format("...and %d more", #entries - limit))
            end
            return table.concat(lines, "\n")
        end

        local function RefreshStatisticsPage()
            local stats = EnsureFishingStats()
            local zoneCount = 0
            for _ in pairs(stats.zones) do
                zoneCount = zoneCount + 1
            end
            statisticsSummary:SetText(string.format(
                "Lifetime sessions: %d | Casts: %d | Fishing time: %s\nSkill-ups: %d | Recorded items: %d | Zones fished: %d",
                stats.totalSessions, stats.totalCasts,
                FormatFishingTime(stats.totalFishingSeconds), stats.totalSkillUps,
                stats.totalItems, zoneCount))
            zoneStatsText:SetText(BuildStatsLines(
                stats.zones, "No zone totals recorded yet.", 10, function(entry)
                    local zone = entry.data
                    return string.format("%s: %d items | %d sessions | %d casts | %s time | %d skill-ups",
                        entry.name, entry.count, zone.sessions, zone.casts,
                        FormatFishingTime(zone.fishingSeconds), zone.skillUps)
                end))
            itemStatsText:SetText(BuildStatsLines(stats.itemsByID, "No items recorded yet.", 12))
        end

        local locationsTitle = locationsPage:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        locationsTitle:SetPoint("TOPLEFT", 16, -16)
        locationsTitle:SetText("Fish Atlas")

        local locationsDescription = locationsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        locationsDescription:SetPoint("TOPLEFT", locationsTitle, "BOTTOMLEFT", 0, -8)
        locationsDescription:SetWidth(550)
        locationsDescription:SetJustifyH("LEFT")
        locationsDescription:SetText("Observed catches on this character, grouped by area. Click a row to place a waypoint. Locations are approximate and learned while fishing.")

        local locationsScroll = CreateFrame("ScrollFrame", "EasyFishingAtlasScrollFrame",
            locationsPage, "UIPanelScrollFrameTemplate")
        locationsScroll:SetPoint("TOPLEFT", locationsDescription, "BOTTOMLEFT", 0, -8)
        locationsScroll:SetSize(570, 420)
        local locationsContent = CreateFrame("Frame", nil, locationsScroll)
        locationsContent:SetSize(530, 1)
        locationsScroll:SetScrollChild(locationsContent)

        local locationRows = {}
        local function RefreshLocationsPage()
            for _, row in ipairs(locationRows) do
                row:Hide()
            end

            local spots = {}
            local stats = EnsureFishingStats()
            for zoneName, zoneStats in pairs(stats.zones) do
                for _, spot in pairs(zoneStats.spots or {}) do
                    if type(spot) == "table" and type(spot.itemsByID) == "table" then
                        table.insert(spots, { zone = zoneName, spot = spot })
                    end
                end
            end
            table.sort(spots, function(firstSpot, secondSpot)
                if firstSpot.spot.totalItems == secondSpot.spot.totalItems then
                    if firstSpot.zone == secondSpot.zone then
                        return (firstSpot.spot.subzone or "") < (secondSpot.spot.subzone or "")
                    end
                    return firstSpot.zone < secondSpot.zone
                end
                return firstSpot.spot.totalItems > secondSpot.spot.totalItems
            end)

            if #spots == 0 then
                locationsDescription:SetText("No fishing locations recorded yet. Confirmed catches will build this character's observed fish-by-area atlas.")
                locationsContent:SetHeight(1)
                locationsScroll:SetVerticalScroll(0)
                locationsScroll:UpdateScrollChildRect()
                return
            end
            locationsDescription:SetText(string.format(
                "Observed catches on this character, grouped by area. Click a row to place a waypoint. Showing all %d approximate spots.",
                #spots))
            locationsContent:SetHeight(math.max(1, #spots * 27))
            locationsScroll:SetVerticalScroll(0)
            locationsScroll:UpdateScrollChildRect()

            for index, entry in ipairs(spots) do
                local spot = entry.spot
                local fish = {}
                for itemID, item in pairs(spot.itemsByID) do
                    if type(item) == "table" then
                        table.insert(fish, {
                            id = itemID,
                            name = item.name or ("Item " .. itemID),
                            count = tonumber(item.count) or 0,
                            timeBuckets = item.timeBuckets or {},
                        })
                    end
                end
                table.sort(fish, function(firstFish, secondFish)
                    if firstFish.count == secondFish.count then
                        return firstFish.name < secondFish.name
                    end
                    return firstFish.count > secondFish.count
                end)

                local fishSummary = {}
                for fishIndex = 1, math.min(#fish, 2) do
                    table.insert(fishSummary, string.format("%s x%d", fish[fishIndex].name, fish[fishIndex].count))
                end
                if #fish > 2 then
                    table.insert(fishSummary, string.format("+%d more", #fish - 2))
                end
                local areaName = spot.subzone ~= "" and spot.subzone or entry.zone
                local row = locationRows[index]
                if not row then
                    row = CreateFrame("Button", nil, locationsContent, "UIPanelButtonTemplate")
                    row:SetSize(530, 24)
                    locationRows[index] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", locationsContent, "TOPLEFT", 0, -((index - 1) * 27))
                row:SetText(string.format("%s / %s  (%.1f, %.1f)  %s",
                    entry.zone, areaName, spot.x * 100, spot.y * 100,
                    #fishSummary > 0 and table.concat(fishSummary, ", ") or "No item counts"))
                row:SetScript("OnClick", function()
                    if not C_Map or not C_Map.CanSetUserWaypointOnMap
                        or not C_Map.SetUserWaypoint or not UiMapPoint
                        or not UiMapPoint.CreateFromCoordinates
                        or not C_Map.CanSetUserWaypointOnMap(spot.mapID) then
                        print("EasyFishing: a waypoint cannot be set on this map.")
                        return
                    end
                    local point = UiMapPoint.CreateFromCoordinates(spot.mapID, spot.x, spot.y)
                    if not point or not C_Map.SetUserWaypoint(point) then
                        print("EasyFishing: unable to set the fishing waypoint.")
                        return
                    end
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                    end
                    if WorldMapFrame and WorldMapFrame.SetMapID then
                        WorldMapFrame:SetMapID(spot.mapID)
                        if ShowUIPanel then ShowUIPanel(WorldMapFrame) else WorldMapFrame:Show() end
                    end
                end)
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Observed catches at this location")
                    for _, fishItem in ipairs(fish) do
                        GameTooltip:AddLine(string.format("%s: %d", fishItem.name, fishItem.count), 1, 1, 1)
                        local timeParts = {}
                        for bucket = 0, 3 do
                            local count = tonumber(fishItem.timeBuckets[bucket]) or 0
                            if count > 0 then
                                table.insert(timeParts, string.format("%02d-%02d: %d", bucket * 6, bucket * 6 + 6, count))
                            end
                        end
                        if #timeParts > 0 then
                            GameTooltip:AddLine("Server time: " .. table.concat(timeParts, ", "), 0.75, 0.75, 0.75, true)
                        end
                    end
                    GameTooltip:AddLine("Coordinates are approximate catch positions, not verified pool boundaries.", 0.75, 0.75, 0.75, true)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row:Show()
            end
        end

        settingsTab:SetScript("OnClick", function()
            statisticsPage:Hide()
            locationsPage:Hide()
            settingsPage:Show()
        end)
        statisticsTab:SetScript("OnClick", function()
            settingsPage:Hide()
            locationsPage:Hide()
            RefreshStatisticsPage()
            statisticsPage:Show()
        end)
        locationsTab:SetScript("OnClick", function()
            settingsPage:Hide()
            statisticsPage:Hide()
            RefreshLocationsPage()
            locationsPage:Show()
        end)

        -- Register with the options UI --------------------------------------
        local settingsCategory
        if Settings and Settings.RegisterCanvasLayoutCategory then
            settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(settingsCategory)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end

        local function OpenOptions()
            if settingsCategory and Settings and Settings.OpenToCategory then
                Settings.OpenToCategory(settingsCategory:GetID())
            elseif InterfaceOptionsFrame_OpenToCategory then
                InterfaceOptionsFrame_OpenToCategory(panel)
                InterfaceOptionsFrame_OpenToCategory(panel)
            else
                print("EasyFishing: options panel is unavailable on this client.")
            end
        end

        local function ShowOptionsPage(page)
            OpenOptions()
            settingsPage:Hide()
            statisticsPage:Hide()
            locationsPage:Hide()
            if page == "stats" then
                RefreshStatisticsPage()
                statisticsPage:Show()
            elseif page == "atlas" then
                RefreshLocationsPage()
                locationsPage:Show()
            else
                settingsPage:Show()
            end
        end

        SLASH_EASYFISHING1 = "/ef"
        SLASH_EASYFISHING2 = "/easyfishing"
        SlashCmdList.EASYFISHING = function(message)
            local command = (message or ""):lower():match("^%s*(.-)%s*$")
            if command == "" or command == "menu" then
                ShowOptionsPage("settings")
            elseif command == "stats" then
                ShowOptionsPage("stats")
            elseif command == "atlas" or command == "locations" then
                ShowOptionsPage("atlas")
            elseif command == "watch" then
                EasyFishingDB.showFishWatcher = not EasyFishingDB.showFishWatcher
                UpdateFishWatcher()
                print("EasyFishing: Fish Watcher " .. (EasyFishingDB.showFishWatcher and "shown" or "hidden") .. ".")
            elseif command == "equip" then
                EquipFishingOutfit()
            elseif command == "restore" then
                RestorePreviousEquipmentSet()
            else
                print("EasyFishing commands: /ef [menu|stats|atlas|watch|equip|restore]")
            end
        end

        -- ------------------------------------------------------------------
        -- Global mouse handler
        -- ------------------------------------------------------------------
        local clickFrame = CreateFrame("Frame")
        clickFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        clickFrame:RegisterEvent("GLOBAL_MOUSE_UP")
        clickFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        clickFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        clickFrame:SetScript("OnEvent", function(_, evt, buttonName)
            if evt == "PLAYER_REGEN_DISABLED" or evt == "PLAYER_REGEN_ENABLED" then
                ClearBinding()
                return
            end

            if evt == "GLOBAL_MOUSE_UP" then
                if clearBindingOnMouseUp then
                    ClearBinding()
                    return
                end

                if buttonName ~= EasyFishingDB.doubleClickButton or lastClickTime <= 0 then
                    return
                end

                if GetTime() - lastClickTime > MAX_DOUBLE_CLICK
                    or not EasyFishingDB.enableDoubleClick
                    or InCombatLockdown()
                    or IsFishingChannelActive()
                    or not IsFishingPoleEquipped()
                    or UnitExists("mouseover")
                    or UnitExists("target")
                    or GetUnitSpeed("player") > 0 then
                    ClearBinding()
                    return
                end

                BindCastAction(buttonName)
                return
            end

            -- Only GLOBAL_MOUSE_DOWN from here on.
            local selectedKey = EasyFishingDB.doubleClickButton

            if buttonName ~= selectedKey then
                if lastClickTime > 0 then
                    ClearBinding()
                end
                return
            end

            if not EasyFishingDB.enableDoubleClick
                or InCombatLockdown()
                or IsFishingChannelActive()
                or not IsFishingPoleEquipped()
                or UnitExists("mouseover")
                or UnitExists("target")
                or GetUnitSpeed("player") > 0 then
                if lastClickTime > 0 then
                    ClearBinding()
                end
                return
            end

            local now   = GetTime()
            local delta = now - lastClickTime

            if EasyFishingDB.castClickMode == "SingleClick" then
                lastClickTime = 0
                CancelPendingTimer()
                BindCastAction(buttonName)
                clearBindingOnMouseUp = true
                return
            end

            if lastClickTime > 0
                and delta >= MIN_DOUBLE_CLICK
                and delta <= MAX_DOUBLE_CLICK then
                -- The binding performs the pending lure or fishing action.
                lastClickTime = 0
                CancelPendingTimer()
                clearBindingOnMouseUp = true
            else
                -- First click: arm the binding so the next click performs the selected action.
                lastClickTime = now

                CancelPendingTimer()
                pendingClearTimer = C_Timer.NewTimer(MAX_DOUBLE_CLICK, function()
                    pendingClearTimer = nil
                    if not InCombatLockdown() then
                        ClearOverrideBindings(castOwner)
                    end
                    lastClickTime = 0
                end)
            end
        end)

    end
end)

-- ---------------------------------------------------------------------------
-- Fishing session sound automation
-- ---------------------------------------------------------------------------

local soundFrame = CreateFrame("Frame")
soundFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
soundFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
soundFrame:RegisterEvent("LOOT_OPENED")
soundFrame:RegisterEvent("SKILL_LINES_CHANGED")
soundFrame:RegisterEvent("CHAT_MSG_SKILL")
local userBGSetting = nil

soundFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "LOOT_OPENED" then
        RecordFishingLoot()
        return
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        UpdateFishingSkillUps()
        return
    end
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local expectedName = GetFishingSpellName()
        local channelName  = UnitChannelInfo("player")
        if channelName ~= expectedName then return end

        StartFishingSession()
        if fishingSession then
            fishingSession.lastActivityAt = GetTime()
        end
        isFishing = true
        EasyFishingDB = EasyFishingDB or {}

        -- Sound automation
        if EasyFishingDB.enableSound then
            local curSound = GetCVarSound()
            if curSound ~= "1" then
                EasyFishingDB.userSoundSetting = curSound
                SetCVarSound("1")
            end
            local curBG = GetCVarBG()
            if userBGSetting == nil then
                userBGSetting = curBG
            end
            if curBG ~= "1" then
                SetCVarBG("1")
            end
        end

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if not isFishing then return end
        isFishing = false

        if EasyFishingDB then
            if EasyFishingDB.userSoundSetting ~= nil then
                SetCVarSound(EasyFishingDB.userSoundSetting)
                EasyFishingDB.userSoundSetting = nil
            end
        end
        if userBGSetting ~= nil then
            SetCVarBG(userBGSetting)
            userBGSetting = nil
        end
        if fishingSession then
            fishingSession.lastActivityAt = GetTime()
        end
        ScheduleFishingSessionEnd()

    end
end)