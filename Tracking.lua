local _, EF = ...
EF = EF or _G.EasyFishing

local FISHING_SESSION_IDLE = 120
local GetFishingSkill = EF.GetFishingSkill
local GetFishingSpellName = EF.GetFishingSpellName
local GetCVarBG = EF.GetCVarBG
local SetCVarBG = EF.SetCVarBG
local GetCVarSound = EF.GetCVarSound
local SetCVarSound = EF.SetCVarSound
local GetCVarMasterSound = EF.GetCVarMasterSound
local SetCVarMasterSound = EF.SetCVarMasterSound
local isFishing = false

local fishingSession = nil
local fishingSessionEndTimer = nil
local fishWatcherExpanded = false
local SetFishWatcherExpanded

local fishWatcher = CreateFrame("Frame", "EasyFishingFishWatcher", UIParent, "BackdropTemplate")
fishWatcher:SetSize(380, 108)
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
    fishWatcher:SetBackdropColor(0, 0, 0, 0.9)
    fishWatcher:SetBackdropBorderColor(1, 1, 1, 1)
end

local fishWatcherIcon = fishWatcher:CreateTexture(nil, "ARTWORK")
fishWatcherIcon:SetSize(16, 16)
fishWatcherIcon:SetPoint("TOPLEFT", 12, -10)
fishWatcherIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
local fishWatcherTitle = fishWatcher:CreateFontString("EasyFishingWatcherTitle", "OVERLAY", "GameFontNormal")
fishWatcherTitle:SetPoint("LEFT", fishWatcherIcon, "RIGHT", 6, 0)
fishWatcherTitle:SetWidth(130)
fishWatcherTitle:SetJustifyH("LEFT")
fishWatcherTitle:SetText("EasyFishing")

local fishWatcherStatus = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherStatus:SetPoint("TOPRIGHT", fishWatcher, "TOPRIGHT", -34, -12)
fishWatcherStatus:SetWidth(130)
fishWatcherStatus:SetJustifyH("RIGHT")
local fishWatcherDetails = CreateFrame("Frame", nil, fishWatcher)
fishWatcherDetails:SetSize(380, 260)
fishWatcherDetails:SetPoint("TOPLEFT", fishWatcher, "TOPLEFT")
fishWatcherDetails:Hide()
SetFishWatcherExpanded = function(expanded)
    fishWatcherExpanded = not not (expanded and fishingSession and EasyFishingDB
        and EasyFishingDB.showFishWatcher)
    fishWatcherDetails:SetShown(fishWatcherExpanded)
    fishWatcher:SetClampedToScreen(not fishWatcherExpanded)
    fishWatcher:SetHeight(fishWatcherExpanded and 280 or 108)
    return fishWatcherExpanded
end
EF.SetFishWatcherExpanded = SetFishWatcherExpanded
EF.IsFishWatcherExpanded = function() return fishWatcherExpanded end

local fishWatcherZone = fishWatcherDetails:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherZone:SetPoint("TOPLEFT", fishWatcherDetails, "TOPLEFT", 12, -32)
fishWatcherZone:SetWidth(356)
fishWatcherZone:SetJustifyH("LEFT")
fishWatcherZone:SetWordWrap(false)

local fishWatcherDivider = fishWatcherDetails:CreateTexture(nil, "ARTWORK")
fishWatcherDivider:SetColorTexture(0.55, 0.55, 0.55, 0.5)
fishWatcherDivider:SetSize(356, 1)
fishWatcherDivider:SetPoint("TOPLEFT", fishWatcherDetails, "TOPLEFT", 12, -52)

local fishWatcherMetricValues = {}
local metricNames = { "Skill", "Time", "Casts", "Skill Gains" }
for index, metricName in ipairs(metricNames) do
    local xOffset = (index - 1) * 89
    local label = fishWatcherDetails:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", fishWatcherDivider, "BOTTOMLEFT", xOffset, -8)
    label:SetWidth(83)
    label:SetJustifyH("LEFT")
    label:SetText(metricName)

    local value = fishWatcherDetails:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    value:SetWidth(83)
    value:SetWordWrap(false)
    value:SetJustifyH("LEFT")
    value:SetTextColor(1, 0.82, 0)
    fishWatcherMetricValues[index] = value
end

local fishWatcherSummary = fishWatcherDetails:CreateFontString(
    "EasyFishingWatcherSummary", "OVERLAY", "GameFontHighlightSmall")
fishWatcherSummary:SetPoint("TOPLEFT", fishWatcherDetails, "TOPLEFT", 12, -106)
fishWatcherSummary:SetWidth(356)
fishWatcherSummary:SetJustifyH("CENTER")
fishWatcherSummary:SetWordWrap(false)

local fishWatcherLastCatchLabel = fishWatcherDetails:CreateFontString(
    "EasyFishingWatcherLatestLabel", "OVERLAY", "GameFontDisableSmall")
fishWatcherLastCatchLabel:SetPoint("TOPLEFT", fishWatcherDetails, "TOPLEFT", 12, -136)
fishWatcherLastCatchLabel:SetWidth(356)
fishWatcherLastCatchLabel:SetJustifyH("CENTER")
fishWatcherLastCatchLabel:SetText("Latest Catch")

local function CreateWatcherCatchRow(name, yOffset)
    local row = CreateFrame("Button", name, fishWatcherDetails)
    row:SetSize(356, 22)
    row:SetPoint("TOPLEFT", fishWatcherDetails, "TOPLEFT", 12, yOffset)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 0, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.text:SetWidth(252)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.count:SetPoint("RIGHT", 0, 0)
    row.count:SetWidth(68)
    row.count:SetJustifyH("RIGHT")
    row.count:SetWordWrap(false)
    row:SetScript("OnClick", function(self)
        if self.itemLink and HandleModifiedItemClick and HandleModifiedItemClick(self.itemLink) then return end
        if self.itemID and EF.OpenFishJournal then EF.OpenFishJournal(self.itemID) end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink then GameTooltip:SetHyperlink(self.itemLink) else GameTooltip:SetText(self.itemName) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function SetWatcherCatch(row, itemID, itemLink, name, count, inlineCount)
    row.itemID, row.itemLink, row.itemName = itemID, itemLink, name
    row:SetEnabled(itemID ~= nil)
    row.text:SetWidth(inlineCount and 320 or 252)
    row.text:SetText(name and inlineCount and string.format("%s  x%d", name, count or 0) or name or "None yet")
    local color = itemID and 1 or 0.6
    row.text:SetTextColor(color, color, color)
    row.count:SetText(not inlineCount and count and ("x" .. count) or "")
    row.count:SetShown(not inlineCount and count ~= nil)
    local icon
    if itemID then
        local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
        if getInfo then
            local _, _, _, _, texture = getInfo(itemID)
            icon = texture
        end
    end
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_Fish_02")
    row.icon:SetShown(itemID ~= nil)
end
local fishWatcherLastCatch = CreateWatcherCatchRow("EasyFishingWatcherLatest", -152)

local fishWatcherBreakdownLabel = fishWatcherDetails:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
fishWatcherBreakdownLabel:SetPoint("TOPLEFT", fishWatcherDetails, "TOPLEFT", 12, -184)
fishWatcherBreakdownLabel:SetWidth(356)
fishWatcherBreakdownLabel:SetText("Session Catches")
local fishWatcherCatchRows = {
    CreateWatcherCatchRow("EasyFishingWatcherCatch1", -200),
    CreateWatcherCatchRow("EasyFishingWatcherCatch2", -224),
}

fishWatcher:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() then
        self:StartMoving()
    end
end)
fishWatcher:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local characterDB = EF.GetCharacterDB()

    local centerX, centerY = self:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    characterDB.fishWatcherX = centerX - parentX
    characterDB.fishWatcherY = centerY - parentY
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "CENTER", characterDB.fishWatcherX, characterDB.fishWatcherY)
end)
fishWatcher:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 5)
    GameTooltip:SetText("Fishing Watcher")
    GameTooltip:AddLine("Middle-click and drag to move", 1, 1, 1)
    GameTooltip:Show()
end)
fishWatcher:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function EnsureFishingStats()
    local characterDB = EF.GetCharacterDB()
    if type(characterDB.fishingStats) ~= "table" then
        characterDB.fishingStats = {}
    end
    local stats = characterDB.fishingStats
    stats.totalItems = tonumber(stats.totalItems) or 0
    stats.totalSessions = tonumber(stats.totalSessions) or 0
    stats.totalCasts = tonumber(stats.totalCasts) or 0
    stats.totalFishingSeconds = tonumber(stats.totalFishingSeconds) or 0
    stats.totalSkillUps = tonumber(stats.totalSkillUps) or 0
    stats.rateTrackedCasts = tonumber(stats.rateTrackedCasts) or 0
    stats.successfulCasts = tonumber(stats.successfulCasts) or 0
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
    zoneStats.rateTrackedCasts = tonumber(zoneStats.rateTrackedCasts) or 0
    zoneStats.successfulCasts = tonumber(zoneStats.successfulCasts) or 0
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

local function FindFishingSpot(zoneStats, mapID, x, y)
    local position = CreateVector2D and CreateVector2D(x, y) or { x = x, y = y }
    local continentID, worldX, worldY = GetWorldPosition(mapID, position)
    local cellX = math.min(199, math.max(0, math.floor(x * 200)))
    local cellY = math.min(199, math.max(0, math.floor(y * 200)))
    local spotKey = string.format("%d:%d:%d", mapID, cellX, cellY)
    local nearestKey, nearestSpot, nearestDistance
    for candidateKey, candidate in pairs(zoneStats.spots) do
        if type(candidate) == "table" and candidate.mapID == mapID
            and type(candidate.x) == "number" and type(candidate.y) == "number" then
            if candidate.x == x and candidate.y == y then
                return candidateKey, candidate, continentID, worldX, worldY
            end
            if continentID then
                local candidateContinent, candidateX, candidateY = candidate.continentID,
                    candidate.worldX, candidate.worldY
                if not candidateContinent or not candidateX or not candidateY then
                    local oldPosition = CreateVector2D and CreateVector2D(candidate.x, candidate.y)
                        or { x = candidate.x, y = candidate.y }
                    candidateContinent, candidateX, candidateY = GetWorldPosition(mapID, oldPosition)
                    candidate.continentID, candidate.worldX, candidate.worldY = candidateContinent,
                        candidateX, candidateY
                end
                if candidateContinent == continentID then
                    local distance = (worldX - candidateX) ^ 2 + (worldY - candidateY) ^ 2
                    if distance <= 225 and (not nearestDistance or distance < nearestDistance) then
                        nearestKey, nearestSpot, nearestDistance = candidateKey, candidate, distance
                    end
                end
            end
        end
    end
    if nearestSpot then return nearestKey, nearestSpot, continentID, worldX, worldY end
    local baseKey, suffix = spotKey, 1
    while zoneStats.spots[spotKey] ~= nil do
        spotKey = baseKey .. ":" .. suffix
        suffix = suffix + 1
    end
    return spotKey, nil, continentID, worldX, worldY
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
    local spotKey, spot, continentID, worldX, worldY = FindFishingSpot(zoneStats, mapID, x, y)

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
    local timestamp = GetServerTime and GetServerTime()
    if timestamp and date then
        item.datesByDay = type(item.datesByDay) == "table" and item.datesByDay or {}
        local day = date("!%Y-%m-%d", timestamp)
        item.datesByDay[day] = (tonumber(item.datesByDay[day]) or 0) + quantity
    end
    spot.totalItems = (tonumber(spot.totalItems) or 0) + quantity
    local hour = GetGameTime()
    local bucket = math.floor(hour / 6)
    item.timeBuckets[bucket] = (tonumber(item.timeBuckets[bucket]) or 0) + quantity
end

local function GetFishJournal()
    local fishByID = {}
    local stats = EnsureFishingStats()
    for itemID, item in pairs(stats.itemsByID) do
        if type(item) == "table" then
            local key = tostring(itemID)
            fishByID[key] = { id = key, name = item.name or ("Item " .. key), count = 0,
                lifetimeCount = tonumber(item.count) or 0, locations = {}, timeBuckets = {}, datesByDay = {} }
        end
    end
    for zoneName, zone in pairs(stats.zones) do
        if type(zone) == "table" and type(zone.spots) == "table" then
            for _, spot in pairs(zone.spots) do
                if type(spot) == "table" and type(spot.itemsByID) == "table" then
                    for itemID, item in pairs(spot.itemsByID) do
                        if type(item) == "table" then
                            local key = tostring(itemID)
                            local fish = fishByID[key]
                            if not fish then
                                fish = { id = key, name = item.name or ("Item " .. key), count = 0,
                                    locations = {}, timeBuckets = {}, datesByDay = {} }
                                fishByID[key] = fish
                            end
                            local count = tonumber(item.count) or 0
                            fish.count = fish.count + count
                            table.insert(fish.locations, { zone = zoneName, spot = spot, count = count })
                            for bucket, amount in pairs(item.timeBuckets or {}) do
                                fish.timeBuckets[bucket] = (fish.timeBuckets[bucket] or 0) + (tonumber(amount) or 0)
                            end
                            for day, amount in pairs(item.datesByDay or {}) do
                                fish.datesByDay[day] = (fish.datesByDay[day] or 0) + (tonumber(amount) or 0)
                            end
                        end
                    end
                end
            end
        end
    end
    local journal = {}
    for _, fish in pairs(fishByID) do
        fish.locationCount = fish.count
        fish.lifetimeCount = fish.lifetimeCount or 0
        fish.count = math.max(fish.count, fish.lifetimeCount)
        table.sort(fish.locations, function(first, second)
            if first.count == second.count then return first.zone < second.zone end
            return first.count > second.count
        end)
        table.insert(journal, fish)
    end
    table.sort(journal, function(first, second)
        if first.count == second.count then return first.name < second.name end
        return first.count > second.count
    end)
    return journal
end

local function FormatFishingTime(seconds)
    local totalSeconds = math.max(0, math.floor(seconds))
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local remainingSeconds = totalSeconds % 60
    return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
end

local function GetFishingSessionElapsed()
    if not fishingSession then return 0 end
    local elapsed = tonumber(fishingSession.elapsedSeconds) or 0
    if isFishing and fishingSession.activeSince then
        elapsed = elapsed + math.max(0, GetTime() - fishingSession.activeSince)
    end
    return elapsed
end

local function AccumulateActiveFishingTime()
    if not fishingSession or not fishingSession.activeSince then return end
    fishingSession.elapsedSeconds = (tonumber(fishingSession.elapsedSeconds) or 0)
        + math.max(0, GetTime() - fishingSession.activeSince)
    fishingSession.activeSince = nil
end

local function UpdateFishWatcher()
    if not fishingSession or not EasyFishingDB or not EasyFishingDB.showFishWatcher then
        fishWatcherDetails:Hide()
        fishWatcher:Hide()
        if EF.UpdateFishingControls then EF.UpdateFishingControls() end
        return
    end

    local zoneName = GetRealZoneText() or fishingSession.zone
    local stats = EnsureFishingStats()
    local zoneStats = EnsureZoneFishingStats(stats, zoneName)
    local zoneItems = zoneStats.totalItems
    fishWatcherZone:SetText(zoneName)
    local paused = EF.IsFishingPaused()
    fishWatcherStatus:SetText(paused and "Paused" or (InCombatLockdown() and "In combat"
        or (isFishing and "Fishing" or (EF.IsLootOpen() and "Looting" or "Idle"))))
    fishWatcherStatus:SetTextColor(paused and 0.6 or 1, paused and 0.6 or 1, paused and 0.6 or 1)
    local elapsedSeconds = math.max(1, GetFishingSessionElapsed())
    local itemsPerHour = fishingSession.totalItems * 3600 / elapsedSeconds
    local fishingSkill = EF.GetFishingSkill()
    fishWatcherMetricValues[1]:SetText(fishingSkill and tostring(fishingSkill) or "?")
    fishWatcherMetricValues[2]:SetText(FormatFishingTime(elapsedSeconds))
    fishWatcherMetricValues[3]:SetText(tostring(fishingSession.casts))
    fishWatcherMetricValues[4]:SetText(tostring(fishingSession.skillUps))
    local gearBonus, activeLureBonus = EF.GetFishingBonusStatus()
    local lureBonusText = EF.GetLureStatus().active
        and (activeLureBonus and ("Lure +" .. activeLureBonus) or "Lure ?") or "Lure +0"
    fishWatcherSummary:SetText(string.format("Session %d  |  Zone %d  |  %.1f/h  |  Gear +%d  |  %s",
        fishingSession.totalItems, zoneItems, itemsPerHour, gearBonus, lureBonusText))
    SetWatcherCatch(fishWatcherLastCatch, fishingSession.lastCatchItemID,
        fishingSession.lastCatchItemLink, fishingSession.lastCatch, fishingSession.lastCatchQuantity, true)
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
    fishWatcherBreakdownLabel:SetText(#sessionItems > 2
        and string.format("Session Catches  (+%d more)", #sessionItems - 2) or "Session Catches")
    for index, row in ipairs(fishWatcherCatchRows) do
        local item = sessionItems[index]
        SetWatcherCatch(row, item and item.id, item and item.link, item and item.name, item and item.count)
        row:SetShown(item ~= nil or index == 1)
    end
    fishWatcherDetails:Show()
    if EF.UpdateFishingControls then EF.UpdateFishingControls() else fishWatcher:Show() end
end

local function EndFishingSession()
    if fishingSessionEndTimer then
        fishingSessionEndTimer:Cancel()
        fishingSessionEndTimer = nil
    end
    if fishingSession then
        AccumulateActiveFishingTime()
        local duration = GetFishingSessionElapsed()
        local stats = EnsureFishingStats()
        local zoneStats = EnsureZoneFishingStats(stats, fishingSession.zone)
        stats.totalFishingSeconds = stats.totalFishingSeconds + duration
        zoneStats.fishingSeconds = zoneStats.fishingSeconds + duration
    end
    fishingSession = nil
    SetFishWatcherExpanded(false)
    fishWatcherDetails:Hide()
    if EF.UpdateFishingControls then EF.UpdateFishingControls() else fishWatcher:Hide() end
end

local function ResetFishingHistory()
    if isFishing or UnitChannelInfo("player") or InCombatLockdown() then
        print("EasyFishing: stop fishing and leave combat before resetting this character's history.")
        return false
    end
    EndFishingSession()
    local characterDB = EF.GetCharacterDB()
    characterDB.fishingStats = nil
    characterDB.lastFishingSpot = nil
    EnsureFishingStats()
    UpdateFishWatcher()
    if EF.RefreshJournal then EF.RefreshJournal() end
    return true
end

local function GetFishingSessionTime()
    if not fishingSession then return nil, 0 end
    return fishingSession.zone, GetFishingSessionElapsed()
end

local function StartFishingSession()
    local zoneName = GetRealZoneText() or "Unknown zone"
    if fishingSession and fishingSession.zone ~= zoneName then
        EndFishingSession()
    end
    if fishingSessionEndTimer then
        fishingSessionEndTimer:Cancel()
        fishingSessionEndTimer = nil
    end
    if not fishingSession then
        local stats = EnsureFishingStats()
        local zoneStats = EnsureZoneFishingStats(stats, zoneName)
        stats.totalSessions = stats.totalSessions + 1
        zoneStats.sessions = zoneStats.sessions + 1
        fishingSession = {
            elapsedSeconds = 0,
            zone = zoneName,
            totalItems = 0,
            lastCatch = nil,
            itemsByID = {},
            casts = 0,
            skillUps = 0,
            lastSkill = GetFishingSkill(),
        }
    end
    local castTime = GetTime()
    local stats = EnsureFishingStats()
    local sessionZoneStats = EnsureZoneFishingStats(stats, fishingSession.zone)
    fishingSession.activeSince = castTime
    fishingSession.casts = fishingSession.casts + 1
    fishingSession.lootRecordedForCast = false
    fishingSession.lootRecordedSlots = {}
    sessionZoneStats.casts = sessionZoneStats.casts + 1
    stats.totalCasts = stats.totalCasts + 1
    stats.rateTrackedCasts = stats.rateTrackedCasts + 1
    sessionZoneStats.rateTrackedCasts = sessionZoneStats.rateTrackedCasts + 1
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

    local successfulCast = false
    for lootSlot = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(lootSlot)
        local itemID = itemLink and tonumber(itemLink:match("|Hitem:(%d+)"))
        local _, itemName, slotQuantity = GetLootSlotInfo(lootSlot)
        local slotKey = tostring(lootSlot) .. ":" .. tostring(itemID)
        local observedQuantity = tonumber(slotQuantity) or 1
        local quantity = observedQuantity - (fishingSession.lootRecordedSlots[slotKey] or 0)
        if itemID and quantity > 0 then
            successfulCast = true
            fishingSession.lootRecordedSlots[slotKey] = observedQuantity
            itemName = itemName or GetItemInfo(itemID) or ("Item " .. itemID)

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
            sessionItem.id, sessionItem.link = itemID, itemLink
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
            fishingSession.lastCatchItemID = itemID
            fishingSession.lastCatchItemLink = itemLink
            fishingSession.lastCatchQuantity = observedQuantity
            stats.lastCatchItemID = itemID
            stats.lastCatchItemLink = itemLink
            stats.lastCatchName = itemName
        end
    end

    if successfulCast then
        if not fishingSession.lootRecordedForCast then
            fishingSession.lootRecordedForCast = true
            stats.successfulCasts = stats.successfulCasts + 1
            zoneStats.successfulCasts = zoneStats.successfulCasts + 1
        end
    end

    UpdateFishWatcher()
end

fishWatcher:SetScript("OnUpdate", function(self, elapsed)
    self.updateElapsed = (self.updateElapsed or 0) + elapsed
    if fishWatcherExpanded and self.updateElapsed >= 1 then
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
soundFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
soundFrame:RegisterEvent("PLAYER_LOGOUT")
soundFrame:RegisterEvent("LOOT_OPENED")
soundFrame:RegisterEvent("LOOT_READY")
soundFrame:RegisterEvent("SKILL_LINES_CHANGED")
soundFrame:RegisterEvent("CHAT_MSG_SKILL")
local userBGSetting = nil

local function RestoreFishingSoundSettings()
    if EasyFishingDB and EasyFishingDB.userMasterSoundSetting ~= nil then
        SetCVarMasterSound(EasyFishingDB.userMasterSoundSetting)
        EasyFishingDB.userMasterSoundSetting = nil
    end
    if EasyFishingDB and EasyFishingDB.userSoundSetting ~= nil then
        SetCVarSound(EasyFishingDB.userSoundSetting)
        EasyFishingDB.userSoundSetting = nil
    end
    if userBGSetting ~= nil then
        SetCVarBG(userBGSetting)
        userBGSetting = nil
    end
end

local function UpdateFishingSoundSettings()
    if not isFishing or not EasyFishingDB or not EasyFishingDB.enableSound then
        RestoreFishingSoundSettings()
        return
    end
    local masterSound = GetCVarMasterSound()
    if masterSound ~= nil and masterSound ~= "1" then
        if EasyFishingDB.userMasterSoundSetting == nil then EasyFishingDB.userMasterSoundSetting = masterSound end
        SetCVarMasterSound("1")
    end
    local curSound = GetCVarSound()
    if curSound ~= "1" then
        if EasyFishingDB.userSoundSetting == nil then
            EasyFishingDB.userSoundSetting = curSound
        end
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

soundFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGOUT" then
        AccumulateActiveFishingTime()
        isFishing = false
        RestoreFishingSoundSettings()
        EndFishingSession()
        return
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        RecordFishingLoot()
        return
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if fishingSession and not EF.IsFishingPoleEquipped() then
            AccumulateActiveFishingTime()
            isFishing = false
            RestoreFishingSoundSettings()
            EndFishingSession()
        end
        return
    elseif event == "PLAYER_STARTED_MOVING" then
        if fishingSession then
            AccumulateActiveFishingTime()
            isFishing = false
            RestoreFishingSoundSettings()
            UpdateFishWatcher()
            ScheduleFishingSessionEnd()
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
        UpdateFishingSoundSettings()

    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if not isFishing then return end
        AccumulateActiveFishingTime()
        isFishing = false
        UpdateFishWatcher()

        RestoreFishingSoundSettings()
        ScheduleFishingSessionEnd()

    end
end)
EF.FishWatcher = fishWatcher
EF.EnsureFishingStats = EnsureFishingStats
EF.EnsureZoneFishingStats = EnsureZoneFishingStats
EF.FindFishingSpot = FindFishingSpot
EF.GetFishJournal = GetFishJournal
EF.FormatFishingTime = FormatFishingTime
EF.UpdateFishWatcher = UpdateFishWatcher
EF.EndFishingSession = EndFishingSession
EF.ResetFishingHistory = ResetFishingHistory
EF.GetFishingSessionTime = GetFishingSessionTime
EF.UpdateFishingSoundSettings = UpdateFishingSoundSettings
EF.RestoreFishingSoundSettings = RestoreFishingSoundSettings
EF.GetFishingSessionLatestCatch = function()
    if not fishingSession then return nil end
    return fishingSession.lastCatch, fishingSession.lastCatchQuantity
end
