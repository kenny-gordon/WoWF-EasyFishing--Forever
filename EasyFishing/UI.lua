local _, EF = ...
EF = EF or _G.EasyFishing

local DB_DEFAULTS = EF.DB_DEFAULTS
local BUTTON_OPTIONS = EF.BUTTON_OPTIONS
local CAST_MODE_OPTIONS = EF.CAST_MODE_OPTIONS
local GetButtonOption = EF.GetButtonOption
local ClearBinding = EF.ClearBinding
local GetEquipmentSetIDs = EF.GetEquipmentSetIDs
local EquipFishingOutfit = EF.EquipFishingOutfit
local RestorePreviousEquipmentSet = EF.RestorePreviousEquipmentSet
local mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
mainFrame:RegisterEvent("PLAYER_LOGOUT")

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGOUT" then
        EF.RestoreAutoInteractSetting()
        EF.EndFishingSession()
        return
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_EQUIPMENT_CHANGED" then
        EF.UpdateAutoInteractSetting()
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
        EF.SetDoubleClickDelay(EasyFishingDB.doubleClickDelay)
        EF.EnsureFishingStats()
        EF.FishWatcher:ClearAllPoints()
        EF.FishWatcher:SetPoint("CENTER", UIParent, "CENTER",
            EasyFishingDB.fishWatcherX, EasyFishingDB.fishWatcherY)
        EF.UpdateAutoInteractSetting()

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

        local function RightSectionHeader(text, yOff)
            local fs = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 270, yOff)
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
                    EF.SetDoubleClickDelay(EasyFishingDB.doubleClickDelay)
                    if not me:GetChecked() then
                        ClearBinding()
                    end
                    EF.UpdateAutoInteractSetting()
                elseif dbKey == "disableClickToMoveWhileFishing" then
                    EF.UpdateAutoInteractSetting()
                elseif dbKey == "showFishWatcher" then
                    EF.UpdateFishWatcher()
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
            EF.SetDoubleClickDelay(rounded)
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
        local secMovement = RightSectionHeader("Movement", -14)
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
        local cbCatchAlert = MakeCheckbox(
            "Play Catch Alert",
            "Play a short sound when the client confirms a fishing catch.",
            cbSound, -4, "enableCatchAlert")

        local secOutfit = SectionHeader("Fishing Outfit", cbCatchAlert, -10)
        local outfitHint = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        outfitHint:SetPoint("TOPLEFT", secOutfit, "BOTTOMLEFT", 0, -4)
        outfitHint:SetWidth(260)
        outfitHint:SetJustifyH("LEFT")
        outfitHint:SetText("Choose a saved equipment set. EasyFishing remembers the previous saved set so you can restore it.")

        local outfitDropdown = CreateFrame("Frame", "EasyFishingOutfitDropdown",
            settingsPage, "UIDropDownMenuTemplate")
        outfitDropdown:SetPoint("TOPLEFT", outfitHint, "BOTTOMLEFT", -16, -6)
        UIDropDownMenu_SetWidth(outfitDropdown, 170)
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
        equipOutfitButton:SetSize(92, 22)
        equipOutfitButton:SetPoint("TOPLEFT", outfitDropdown, "BOTTOMLEFT", 16, -2)
        equipOutfitButton:SetText("Equip")
        equipOutfitButton:SetScript("OnClick", EquipFishingOutfit)

        local restoreOutfitButton = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
        restoreOutfitButton:SetSize(92, 22)
        restoreOutfitButton:SetPoint("LEFT", equipOutfitButton, "RIGHT", 4, 0)
        restoreOutfitButton:SetText("Restore")
        restoreOutfitButton:SetScript("OnClick", RestorePreviousEquipmentSet)

        local statisticsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        statisticsTitle:SetPoint("TOPLEFT", 16, -16)
        statisticsTitle:SetText("Fishing Statistics")

        local statisticsSummary = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            local statisticsSummary = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        statisticsSummary:SetPoint("TOPLEFT", statisticsTitle, "BOTTOMLEFT", 0, -8)
        statisticsSummary:SetWidth(550)
        statisticsSummary:SetJustifyH("LEFT")

        local statisticsCaveat = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        statisticsCaveat:SetPoint("TOPLEFT", statisticsSummary, "BOTTOMLEFT", 0, -4)
        statisticsCaveat:SetWidth(550)
        statisticsCaveat:SetWordWrap(true)
        statisticsCaveat:SetText("Fishing loot is recorded only when the client identifies the loot window as fishing loot.")

        local zoneStatsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        zoneStatsTitle:SetPoint("TOPLEFT", statisticsCaveat, "BOTTOMLEFT", 0, -18)
        zoneStatsTitle:SetText("Recorded Items by Zone")

        local zoneStatsText = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        local zoneStatsText = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        zoneStatsText:SetPoint("TOPLEFT", zoneStatsTitle, "BOTTOMLEFT", 0, -6)
        zoneStatsText:SetWidth(550)
        zoneStatsText:SetJustifyH("LEFT")
        zoneStatsText:SetWordWrap(true)

        local itemStatsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        itemStatsTitle:SetPoint("TOPLEFT", zoneStatsText, "BOTTOMLEFT", 0, -14)
        itemStatsTitle:SetText("Most Recorded Items")

        local itemStatsText = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        local itemStatsText = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        itemStatsText:SetPoint("TOPLEFT", itemStatsTitle, "BOTTOMLEFT", 0, -6)
        itemStatsText:SetWidth(550)
        itemStatsText:SetJustifyH("LEFT")
        itemStatsText:SetWordWrap(true)

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
            local stats = EF.EnsureFishingStats()
            local zoneCount = 0
            for _ in pairs(stats.zones) do
                zoneCount = zoneCount + 1
            end
            statisticsSummary:SetText(string.format(
                "Lifetime sessions: %d | Casts: %d | Fishing time: %s\nSkill-ups: %d | Recorded items: %d | Zones fished: %d",
                stats.totalSessions, stats.totalCasts,
                EF.FormatFishingTime(stats.totalFishingSeconds), stats.totalSkillUps,
                stats.totalItems, zoneCount))
            zoneStatsText:SetText(BuildStatsLines(
                stats.zones, "No zone totals recorded yet.", 10, function(entry)
                    local zone = entry.data
                    return string.format("%s: %d items | %d sessions | %d casts | %s time | %d skill-ups",
                        entry.name, entry.count, zone.sessions, zone.casts,
                        EF.FormatFishingTime(zone.fishingSeconds), zone.skillUps)
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
            local stats = EF.EnsureFishingStats()
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
            locationsContent:SetHeight(math.max(1, #spots * 54))
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
                    row = CreateFrame("Button", nil, locationsContent, "BackdropTemplate")
                    row:SetSize(530, 50)
                    row:SetBackdrop({
                        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true,
                        tileSize = 16,
                        edgeSize = 10,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 },
                    })
                    row:SetBackdropColor(0.04, 0.05, 0.05, 0.72)
                    row:SetBackdropBorderColor(0.24, 0.27, 0.27, 1)

                    row.areaLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    row.areaLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -7)
                    row.areaLabel:SetWidth(360)
                    row.areaLabel:SetJustifyH("LEFT")
                    row.areaLabel:SetWordWrap(false)

                    row.coordinateLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.coordinateLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -8)
                    row.coordinateLabel:SetWidth(130)
                    row.coordinateLabel:SetJustifyH("RIGHT")
                    row.coordinateLabel:SetTextColor(0.72, 0.76, 0.76)

                    row.catchLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.catchLabel:SetPoint("TOPLEFT", row.areaLabel, "BOTTOMLEFT", 0, -2)
                    row.catchLabel:SetWidth(506)
                    row.catchLabel:SetJustifyH("LEFT")
                    row.catchLabel:SetTextColor(0.82, 0.84, 0.82)
                    row.catchLabel:SetWordWrap(false)
                    locationRows[index] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", locationsContent, "TOPLEFT", 0, -((index - 1) * 54))
                row.areaLabel:SetText(entry.zone .. " / " .. areaName)
                row.coordinateLabel:SetText(string.format("%.1f, %.1f", spot.x * 100, spot.y * 100))
                row.catchLabel:SetText(#fishSummary > 0 and table.concat(fishSummary, "  |  ") or "No item counts")
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
                    self:SetBackdropColor(0.10, 0.12, 0.11, 0.9)
                    self:SetBackdropBorderColor(0.78, 0.58, 0.18, 1)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                                    row:SetScript("OnLeave", function(self)
                                        self:SetBackdropColor(0.04, 0.05, 0.05, 0.72)
                                        self:SetBackdropBorderColor(0.24, 0.27, 0.27, 1)
                                        GameTooltip:Hide()
                                    end)
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
                EF.UpdateFishWatcher()
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
        EF.InitializeClickHandling()
    end
end)

-- ---------------------------------------------------------------------------
-- Fishing session sound automation
-- ---------------------------------------------------------------------------

