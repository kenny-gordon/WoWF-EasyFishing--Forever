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
fishWatcher:SetSize(320, 110)
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
fishWatcherTitle:SetWidth(300)
fishWatcherTitle:SetJustifyH("LEFT")

local fishWatcherSummary = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherSummary:SetPoint("TOPLEFT", fishWatcherTitle, "BOTTOMLEFT", 0, -4)
fishWatcherSummary:SetWidth(300)
fishWatcherSummary:SetJustifyH("LEFT")

local fishWatcherLastCatch = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherLastCatch:SetPoint("TOPLEFT", fishWatcherSummary, "BOTTOMLEFT", 0, -3)
fishWatcherLastCatch:SetWidth(300)
fishWatcherLastCatch:SetJustifyH("LEFT")

local fishWatcherBreakdown = fishWatcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fishWatcherBreakdown:SetPoint("TOPLEFT", fishWatcherLastCatch, "BOTTOMLEFT", 0, -3)
fishWatcherBreakdown:SetWidth(300)
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
    fishWatcherTitle:SetText("Fishing Watcher - " .. zoneName)
    local elapsedSeconds = math.max(1, GetTime() - fishingSession.startedAt)
    local itemsPerHour = fishingSession.totalItems * 3600 / elapsedSeconds
    local fishingSkill = EF.GetFishingSkill()
    fishWatcherSummary:SetText(string.format(
        "Fishing skill %s | Time %s\nCasts %d | Skill-ups %d | %.1f items/hr\nSession %d items | Zone %d",
        fishingSkill and tostring(fishingSkill) or "?",
        FormatFishingTime(elapsedSeconds), fishingSession.casts,
        fishingSession.skillUps, itemsPerHour, fishingSession.totalItems, zoneItems))
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
    local recordedCatch = false

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
            recordedCatch = true
        end
    end

    if recordedCatch and EasyFishingDB and EasyFishingDB.enableCatchAlert
        and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE and PlaySound then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "SFX")
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
EF.FishWatcher = fishWatcher
EF.EnsureFishingStats = EnsureFishingStats
EF.EnsureZoneFishingStats = EnsureZoneFishingStats
EF.FormatFishingTime = FormatFishingTime
EF.UpdateFishWatcher = UpdateFishWatcher
EF.EndFishingSession = EndFishingSession