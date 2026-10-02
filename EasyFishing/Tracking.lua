local _, EF = ...
EF = EF or _G.EasyFishing

local FISHING_SESSION_IDLE = 120
local GetFishingSkill = EF.GetFishingSkill
local GetFishingSpellName = EF.GetFishingSpellName
local GetCVarBG = EF.GetCVarBG
local SetCVarBG = EF.SetCVarBG
local GetCVarSound = EF.GetCVarSound
local SetCVarSound = EF.SetCVarSound
local isFishing = false

local fishingSession = nil
local fishingSessionEndTimer = nil

local fishWatcher = CreateFrame("Frame", "EasyFishingFishWatcher", UIParent, "BackdropTemplate")
fishWatcher:SetSize(360, 148)
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
    fishWatcher:SetBackdropColor(0.015, 0.02, 0.02, 0.9)
    fishWatcher:SetBackdropBorderColor(0.45, 0.35, 0.16, 1)
end

local fishWatcherTitle = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
fishWatcherTitle:SetPoint("TOPLEFT", fishWatcher, "TOPLEFT", 10, -10)
fishWatcherTitle:SetWidth(130)
fishWatcherTitle:SetJustifyH("LEFT")
fishWatcherTitle:SetText("FISH WATCHER")

local fishWatcherZone = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherZone:SetPoint("TOPRIGHT", fishWatcher, "TOPRIGHT", -10, -10)
fishWatcherZone:SetWidth(210)
fishWatcherZone:SetJustifyH("RIGHT")
fishWatcherZone:SetWordWrap(false)

local fishWatcherDivider = fishWatcher:CreateTexture(nil, "ARTWORK")
fishWatcherDivider:SetColorTexture(0.45, 0.35, 0.16, 0.65)
fishWatcherDivider:SetSize(340, 1)
fishWatcherDivider:SetPoint("TOPLEFT", fishWatcher, "TOPLEFT", 10, -29)

local fishWatcherMetricValues = {}
local metricNames = { "SKILL", "TIME", "CASTS", "SKILL GAINS" }
for index, metricName in ipairs(metricNames) do
    local xOffset = 10 + (index - 1) * 82
    local label = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", fishWatcherDivider, "BOTTOMLEFT", xOffset - 10, -8)
    label:SetWidth(78)
    label:SetJustifyH("LEFT")
    label:SetText(metricName)

    local value = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    value:SetWidth(78)
    value:SetJustifyH("LEFT")
    value:SetTextColor(1, 0.82, 0)
    fishWatcherMetricValues[index] = value
end

local fishWatcherSummary = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherSummary:SetPoint("TOPLEFT", fishWatcherMetricValues[1], "BOTTOMLEFT", 0, -7)
fishWatcherSummary:SetWidth(340)
fishWatcherSummary:SetJustifyH("LEFT")
fishWatcherSummary:SetWordWrap(true)

local fishWatcherLastCatchLabel = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
fishWatcherLastCatchLabel:SetPoint("TOPLEFT", fishWatcherSummary, "BOTTOMLEFT", 0, -7)
fishWatcherLastCatchLabel:SetWidth(76)
fishWatcherLastCatchLabel:SetJustifyH("LEFT")
fishWatcherLastCatchLabel:SetText("LAST CATCH")

local fishWatcherLastCatch = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherLastCatch:SetPoint("TOPLEFT", fishWatcherLastCatchLabel, "TOPLEFT", 82, 0)
fishWatcherLastCatch:SetWidth(258)
fishWatcherLastCatch:SetJustifyH("LEFT")
fishWatcherLastCatch:SetWordWrap(true)

local fishWatcherBreakdownLabel = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
fishWatcherBreakdownLabel:SetPoint("TOPLEFT", fishWatcherLastCatch, "BOTTOMLEFT", -82, -6)
fishWatcherBreakdownLabel:SetText("THIS SESSION'S CATCHES")

local fishWatcherBreakdown = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherBreakdown:SetPoint("TOPLEFT", fishWatcherBreakdownLabel, "BOTTOMLEFT", 0, -2)
fishWatcherBreakdown:SetWidth(340)
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

local function GetWorldPosition(mapID, position)
    if not C_Map or not C_Map.GetWorldPosFromMapPos then return end
    local continentID, worldPosition = C_Map.GetWorldPosFromMapPos(mapID, position)
    if not continentID or not worldPosition then return end

    local worldX, worldY
    if worldPosition.GetXY then
        worldX, worldY = worldPosition:GetXY()
    else
        worldX, worldY = worldPosition.x, worldPosition.y
    end
    if type(worldX) ~= "number" or type(worldY) ~= "number" then return end
    return continentID, worldX, worldY
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

    local continentID, worldX, worldY = GetWorldPosition(mapID, position)
    local cellX = math.min(199, math.max(0, math.floor(x * 200)))
    local cellY = math.min(199, math.max(0, math.floor(y * 200)))
    local spotKey = string.format("%d:%d:%d", mapID, cellX, cellY)
    local spot = zoneStats.spots[spotKey]

    if not spot and continentID then
        for candidateKey, candidate in pairs(zoneStats.spots) do
            if type(candidate) == "table" and candidate.mapID == mapID
                and candidate.continentID == continentID then
                local candidateX, candidateY = candidate.worldX, candidate.worldY
                if not candidateX or not candidateY then
                    local oldPosition = { x = candidate.x, y = candidate.y }
                    local oldContinentID
                    oldContinentID, candidateX, candidateY = GetWorldPosition(mapID, oldPosition)
                    if oldContinentID ~= continentID then
                        candidateX, candidateY = nil, nil
                    else
                        candidate.continentID = oldContinentID
                        candidate.worldX = candidateX
                        candidate.worldY = candidateY
                    end
                end
                if candidateX and candidateY then
                    local deltaX = worldX - candidateX
                    local deltaY = worldY - candidateY
                    if deltaX * deltaX + deltaY * deltaY <= 225 then
                        spotKey = candidateKey
                        spot = candidate
                        break
                    end
                end
            end
        end
    end

    if type(spot) ~= "table" then
        spot = {
            mapID = mapID,
            x = x,
            y = y,
            continentID = continentID,
            worldX = worldX,
            worldY = worldY,
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
    fishWatcherZone:SetText(zoneName)
    local elapsedSeconds = math.max(1, GetTime() - fishingSession.startedAt)
    local itemsPerHour = fishingSession.totalItems * 3600 / elapsedSeconds
    local fishingSkill = EF.GetFishingSkill()
    fishWatcherMetricValues[1]:SetText(fishingSkill and tostring(fishingSkill) or "?")
    fishWatcherMetricValues[2]:SetText(FormatFishingTime(elapsedSeconds))
    fishWatcherMetricValues[3]:SetText(tostring(fishingSession.casts))
    fishWatcherMetricValues[4]:SetText(tostring(fishingSession.skillUps))
    fishWatcherSummary:SetText(string.format(
        "%.1f items per hour  |  This session: %d items  |  This zone: %d items",
        itemsPerHour, fishingSession.totalItems, zoneItems))
    fishWatcherLastCatch:SetText(fishingSession.lastCatch or "None yet")
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
    fishWatcherBreakdown:SetText(#catchSummary > 0 and table.concat(catchSummary, ", ") or "None yet")
    local wrappedHeight = math.max(0, fishWatcherSummary:GetStringHeight() - 12)
        + math.max(0, fishWatcherLastCatch:GetStringHeight() - 12)
        + math.max(0, fishWatcherBreakdown:GetStringHeight() - 12)
    fishWatcher:SetHeight(148 + wrappedHeight)
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
            stats.lastCatchItemID = itemID
            stats.lastCatchItemLink = itemLink
            stats.lastCatchName = itemName
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


local soundFrame = CreateFrame("Frame")
soundFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
soundFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
soundFrame:RegisterEvent("PLAYER_STARTED_MOVING")
soundFrame:RegisterEvent("PLAYER_LOGOUT")
soundFrame:RegisterEvent("LOOT_OPENED")
soundFrame:RegisterEvent("SKILL_LINES_CHANGED")
soundFrame:RegisterEvent("CHAT_MSG_SKILL")
local userBGSetting = nil

local function RestoreFishingSoundSettings()
    if EasyFishingDB and EasyFishingDB.userSoundSetting ~= nil then
        SetCVarSound(EasyFishingDB.userSoundSetting)
        EasyFishingDB.userSoundSetting = nil
    end
    if userBGSetting ~= nil then
        SetCVarBG(userBGSetting)
        userBGSetting = nil
    end
end

soundFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGOUT" then
        isFishing = false
        RestoreFishingSoundSettings()
        return
    elseif event == "LOOT_OPENED" then
        RecordFishingLoot()
        return
    elseif event == "PLAYER_STARTED_MOVING" then
        if fishingSession then
            fishingSession.lastActivityAt = GetTime()
            isFishing = false
            RestoreFishingSoundSettings()
            EndFishingSession()
        end
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

        isFishing = true
        StartFishingSession()
        if fishingSession then
            fishingSession.lastActivityAt = GetTime()
        end
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
        UpdateFishWatcher()

        RestoreFishingSoundSettings()
        if fishingSession then
            fishingSession.lastActivityAt = GetTime()
        end
        ScheduleFishingSessionEnd()

    end
end)
EF.FishWatcher = fishWatcher
EF.EnsureFishingStats = EnsureFishingStats
EF.EnsureZoneFishingStats = EnsureZoneFishingStats
EF.FormatFishingTime = FormatFishingTime
EF.UpdateFishWatcher = UpdateFishWatcher
EF.EndFishingSession = EndFishingSession