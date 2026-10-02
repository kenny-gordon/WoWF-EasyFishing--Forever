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
local GetFishingSkill = EF.GetFishingSkill

local function OpenChatWithLinks(text)
    if not text or text == "" then
        print("EasyFishing: nothing to link yet.")
    elseif type(ChatFrame_OpenChat) == "function" then
        ChatFrame_OpenChat(text)
    elseif type(ChatEdit_InsertLink) == "function" then
        ChatEdit_InsertLink(text)
    else
        print("EasyFishing: chat link insertion is unavailable.")
    end
end

local function GetItemHyperlink(itemID)
    if not itemID then return nil end
    if type(GetItemInfo) == "function" then
        local _, itemLink = GetItemInfo(itemID)
        if itemLink then return itemLink end
    end
    if C_Item and C_Item.GetItemLink then
        return C_Item.GetItemLink(itemID)
    end
end

local function GetOwnedItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID) or 0
    elseif type(GetItemCount) == "function" then
        return GetItemCount(itemID) or 0
    end
    return 0
end

local function GetItemTexture(itemID)
    local _, _, _, _, icon
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
    elseif type(GetItemInfoInstant) == "function" then
        _, _, _, _, icon = GetItemInfoInstant(itemID)
    end
    return icon
end

local function GetSpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    elseif type(GetSpellTexture) == "function" then
        return GetSpellTexture(spellID)
    end
end

local function ShareLastFish()
    local stats = EF.EnsureFishingStats()
    if not stats.lastCatchItemLink then
        print("EasyFishing: catch a fish before linking it.")
        return
    end
    OpenChatWithLinks(stats.lastCatchItemLink)
end

local function ShareFishingLocation()
    local spot = EasyFishingDB.lastFishingSpot
    if spot and C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint
        and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and C_Map.CanSetUserWaypointOnMap(spot.mapID) then
        local point = UiMapPoint.CreateFromCoordinates(spot.mapID, spot.x, spot.y)
        if point then
            C_Map.SetUserWaypoint(point)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end
    end

    local hyperlink = C_Map and C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
    if not hyperlink or hyperlink == "" then
        print("EasyFishing: select an atlas location or set a map waypoint first.")
        return
    end
    local label = spot and spot.label and (spot.label .. " ") or ""
    OpenChatWithLinks(label .. hyperlink)
end

local function ShareFishingOutfit()
    local setID = tonumber(EasyFishingDB.fishingOutfitSetID)
    if not setID or not C_EquipmentSet or not C_EquipmentSet.GetItemIDs then
        print("EasyFishing: select an available fishing outfit first.")
        return
    end

    local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
    local setItems = C_EquipmentSet.GetItemIDs(setID) or {}
    local links = { "Fishing outfit " .. (setName or "") .. ":" }
    for _, slotID in ipairs(EF.Data.CHAT_GEAR_SLOT_IDS) do
        local itemLink = GetItemHyperlink(setItems[slotID])
        if itemLink then
            table.insert(links, itemLink)
        end
    end
    if #links == 1 then
        print("EasyFishing: outfit items are not cached yet; try again in a moment.")
        return
    end
    OpenChatWithLinks(table.concat(links, " "))
end

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

        local guidePage = CreateFrame("Frame", nil, panel)
        guidePage:SetAllPoints(panel)
        guidePage:Hide()

        local settingsTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        settingsTab:SetSize(86, 22)
        settingsTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -366, -10)
        settingsTab:SetText("Settings")

        local statisticsTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        statisticsTab:SetSize(86, 22)
        statisticsTab:SetPoint("LEFT", settingsTab, "RIGHT", 4, 0)
        statisticsTab:SetText("Statistics")

        local locationsTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        locationsTab:SetSize(86, 22)
        locationsTab:SetPoint("LEFT", statisticsTab, "RIGHT", 4, 0)
        locationsTab:SetText("Locations")

        local guideTab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        guideTab:SetSize(86, 22)
        guideTab:SetPoint("LEFT", locationsTab, "RIGHT", 4, 0)
        guideTab:SetText("Guide")

        local PAGE_CONTENT_WIDTH = 620

        local function PageHeader(page, text)
            local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 16, -16)
            title:SetText(text)

            local rule = page:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(0.4, 0.4, 0.4, 0.6)
            rule:SetSize(PAGE_CONTENT_WIDTH, 1)
            rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
            return rule
        end

        local divider = PageHeader(settingsPage, "EasyFishing: Forever")

        local function SectionHeader(text, anchor, yOff)
            local fs = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
            fs:SetTextColor(1, 0.82, 0)
            fs:SetText(text)
            return fs
        end

        local function RightSectionHeader(text, yOff)
            local fs = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 300, yOff)
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
            "Use the selected mouse button and click pattern to cast while holding a fishing pole.",
            secCast, -4, "enableDoubleClick")

        local modeLabel = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        modeLabel:SetPoint("TOPLEFT", cbDC, "BOTTOMLEFT", 26, -10)
        modeLabel:SetText("Click Pattern")

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
        btnLabel:SetText("Cast Mouse Button")
        btnLabel:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Right-click casting")
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
        sliderLabel:SetText("Double-Click Delay")

        local sliderDesc = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sliderDesc:SetPoint("TOPLEFT", sliderLabel, "BOTTOMLEFT", 0, -4)
        sliderDesc:SetTextColor(0.7, 0.7, 0.7)
        sliderDesc:SetText("Maximum time between the two clicks.")

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
            "Apply Lure Automatically",
            "If your pole has no lure, your first click applies the weakest lure your Fishing skill allows. Click again with the selected pattern to cast.",
            secLure, -4, "enableAutoLure")

        local secTracking = SectionHeader("Tracking", cbAutoLure, -10)
        MakeCheckbox(
            "Show Fish Watcher",
            "Show the current fishing zone, session time, item count, and most recent catch.",
            secTracking, -4, "showFishWatcher")

        local secMovement = RightSectionHeader("Movement", -14)
        local cbDisableClickToMove = MakeCheckbox(
            "Pause Click-to-Move While Fishing",
            "Turns off Click-to-Move while your fishing pole is equipped and Click-to-Cast is on, then restores the previous setting.",
            secMovement, -4, "disableClickToMoveWhileFishing")

        -- Sound -------------------------------------------------------------
        local secSound = SectionHeader("Sound", cbDisableClickToMove, -10)
        local cbSound = MakeCheckbox(
            "Turn Sound On While Fishing",
            "Turns on Sound Effects and Background Sound while you fish, then restores your previous settings.",
            secSound, -4, "enableSound")

        local secOutfit = SectionHeader("Fishing Outfit", cbSound, -10)
        local outfitHint = settingsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        outfitHint:SetPoint("TOPLEFT", secOutfit, "BOTTOMLEFT", 0, -4)
        outfitHint:SetWidth(260)
        outfitHint:SetJustifyH("LEFT")
        outfitHint:SetText("Choose a saved equipment set for fishing. Restore your previous set when finished.")

        local outfitDropdown = CreateFrame("Frame", "EasyFishingOutfitDropdown",
            settingsPage, "UIDropDownMenuTemplate")
        outfitDropdown:SetPoint("TOPLEFT", outfitHint, "BOTTOMLEFT", -16, -6)
        UIDropDownMenu_SetWidth(outfitDropdown, 170)
        local selectedOutfitName = "Select a gear set"
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
        equipOutfitButton:SetText("Equip Gear")
        equipOutfitButton:SetScript("OnClick", EquipFishingOutfit)

        local restoreOutfitButton = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
        restoreOutfitButton:SetSize(92, 22)
        restoreOutfitButton:SetPoint("LEFT", equipOutfitButton, "RIGHT", 4, 0)
        restoreOutfitButton:SetText("Restore Gear")
        restoreOutfitButton:SetScript("OnClick", RestorePreviousEquipmentSet)

        local statisticsDivider = PageHeader(statisticsPage, "Fishing Statistics")

        local metricValues = {}
        local metricLabels = { "Items Caught", "Casts", "Fishing Time", "Skill Gains" }
        for index, labelText in ipairs(metricLabels) do
            local xOffset = (index - 1) * 150
            local label = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            label:SetPoint("TOPLEFT", statisticsDivider, "BOTTOMLEFT", xOffset, -14)
            label:SetWidth(145)
            label:SetJustifyH("LEFT")
            label:SetTextColor(0.76, 0.78, 0.78)
            label:SetText(labelText)

            local value = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
            value:SetWidth(145)
            value:SetJustifyH("LEFT")
            value:SetText("0")
            metricValues[index] = value
        end

        local statisticsSummary = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        statisticsSummary:SetPoint("TOPLEFT", metricValues[1], "BOTTOMLEFT", 0, -4)
        statisticsSummary:SetWidth(PAGE_CONTENT_WIDTH)
        statisticsSummary:SetJustifyH("LEFT")

        local statisticsCaveat = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        statisticsCaveat:SetPoint("BOTTOMLEFT", statisticsPage, "BOTTOMLEFT", 16, 18)
        statisticsCaveat:SetWidth(PAGE_CONTENT_WIDTH - 32)
        statisticsCaveat:SetWordWrap(true)
        statisticsCaveat:SetText("Only items shown in the client's Fishing loot window are counted.")

        local zoneStatsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        zoneStatsTitle:SetPoint("TOPLEFT", statisticsSummary, "BOTTOMLEFT", 0, -24)
        zoneStatsTitle:SetText("Items by Zone")

        local zoneStatsList = CreateFrame("Frame", nil, statisticsPage)
        zoneStatsList:SetPoint("TOPLEFT", zoneStatsTitle, "BOTTOMLEFT", 0, -10)
        zoneStatsList:SetSize(300, 300)

        local zoneStatsEmpty = zoneStatsList:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        zoneStatsEmpty:SetPoint("TOPLEFT", zoneStatsList, "TOPLEFT", 0, 0)
        zoneStatsEmpty:SetText("No zone totals recorded yet.")
        local zoneStatsRows = {}
        local zoneStatsMore = zoneStatsList:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        zoneStatsMore:SetWidth(292)

        local itemStatsTitle = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        itemStatsTitle:SetPoint("TOPLEFT", zoneStatsTitle, "TOPLEFT", 310, 0)
        itemStatsTitle:SetText("Top Catches")

        local itemStatsList = CreateFrame("Frame", nil, statisticsPage)
        itemStatsList:SetPoint("TOPLEFT", itemStatsTitle, "BOTTOMLEFT", 0, -10)
        itemStatsList:SetSize(300, 300)

        local itemStatsEmpty = itemStatsList:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        itemStatsEmpty:SetPoint("TOPLEFT", itemStatsList, "TOPLEFT", 0, 0)
        itemStatsEmpty:SetText("No catches recorded yet.")
        local itemStatsRows = {}
        local itemStatsMore = itemStatsList:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        itemStatsMore:SetWidth(292)

        local function BuildStatsEntries(items, limit)
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

            local moreCount = math.max(0, #entries - limit)
            for index = #entries, limit + 1, -1 do
                entries[index] = nil
            end
            return entries, moreCount
        end

        local function CreateStatisticsRow(parent)
            local row = CreateFrame("Frame", nil, parent)
            row:SetSize(300, 48)

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.name:SetWidth(190)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)

            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
            row.value:SetWidth(100)
            row.value:SetJustifyH("RIGHT")
            row.value:SetTextColor(1, 0.82, 0)

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
            row.detail:SetWidth(292)
            row.detail:SetJustifyH("LEFT")

            row.barBack = row:CreateTexture(nil, "BACKGROUND")
            row.barBack:SetColorTexture(0.22, 0.19, 0.12, 0.65)
            row.barBack:SetSize(292, 3)
            row.barBack:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

            row.bar = row:CreateTexture(nil, "ARTWORK")
            row.bar:SetColorTexture(0.85, 0.62, 0.18, 0.9)
            row.bar:SetSize(2, 3)
            row.bar:SetPoint("BOTTOMLEFT", row.barBack, "BOTTOMLEFT", 0, 0)
            return row
        end

        local function RenderStatisticsRows(parent, rows, emptyText, moreText,
            entries, moreCount, maxCount, formatValue, formatDetail)
            if #entries == 0 then
                emptyText:Show()
                moreText:Hide()
                for _, row in ipairs(rows) do row:Hide() end
                return
            end

            emptyText:Hide()
            for index, entry in ipairs(entries) do
                local row = rows[index]
                if not row then
                    row = CreateStatisticsRow(parent)
                    rows[index] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * 56))
                row.name:SetText(entry.name)
                row.value:SetText(formatValue(entry))
                row.detail:SetText(formatDetail(entry))
                row.bar:SetWidth(math.max(2, 292 * entry.count / math.max(1, maxCount)))
                row:Show()
            end
            for index = #entries + 1, #rows do
                rows[index]:Hide()
            end
            if moreCount > 0 then
                moreText:SetText(string.format("+ %d more", moreCount))
                moreText:ClearAllPoints()
                moreText:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(#entries * 56))
                moreText:Show()
            else
                moreText:Hide()
            end
        end

        local function RefreshStatisticsPage()
            local stats = EF.EnsureFishingStats()
            local zoneCount = 0
            for _ in pairs(stats.zones) do
                zoneCount = zoneCount + 1
            end
            metricValues[1]:SetText(tostring(stats.totalItems))
            metricValues[2]:SetText(tostring(stats.totalCasts))
            metricValues[3]:SetText(EF.FormatFishingTime(stats.totalFishingSeconds))
            metricValues[4]:SetText(tostring(stats.totalSkillUps))
            statisticsSummary:SetText(string.format(
                "Lifetime: %d sessions  |  %d %s  |  %.1f items per hour",
                stats.totalSessions, zoneCount, zoneCount == 1 and "zone" or "zones",
                stats.totalFishingSeconds > 0 and stats.totalItems * 3600 / stats.totalFishingSeconds or 0))
            local zoneEntries, moreZones = BuildStatsEntries(stats.zones, 5)
            RenderStatisticsRows(zoneStatsList, zoneStatsRows, zoneStatsEmpty, zoneStatsMore,
                zoneEntries, moreZones, zoneEntries[1] and zoneEntries[1].count or 0,
                function(entry)
                    return string.format("%d items", entry.count)
                end,
                function(entry)
                    local zone = entry.data
                    return string.format("%d sessions  |  %d casts  |  %s",
                        tonumber(zone.sessions) or 0, tonumber(zone.casts) or 0,
                        EF.FormatFishingTime(tonumber(zone.fishingSeconds) or 0))
                end)

            local itemEntries, moreItems = BuildStatsEntries(stats.itemsByID, 5)
            RenderStatisticsRows(itemStatsList, itemStatsRows, itemStatsEmpty, itemStatsMore,
                itemEntries, moreItems, itemEntries[1] and itemEntries[1].count or 0,
                function(entry)
                    return string.format("%d caught", entry.count)
                end,
                function(entry)
                    local share = stats.totalItems > 0 and entry.count * 100 / stats.totalItems or 0
                    return string.format("%.1f%% of all items", share)
                end)
        end

        local locationsDivider = PageHeader(locationsPage, "Fishing Locations")

        local locationsDescription = locationsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        locationsDescription:SetPoint("TOPLEFT", locationsDivider, "BOTTOMLEFT", 0, -14)
        locationsDescription:SetWidth(400)
        locationsDescription:SetJustifyH("LEFT")
        locationsDescription:SetWordWrap(true)
        locationsDescription:SetText("Your recorded fishing locations, grouped by area. Expand an area to see each location, then click one to set a map waypoint.")

        local atlasZoneFilter = "All zones"
        local atlasZoneDropdown = CreateFrame("Frame", "EasyFishingAtlasZoneDropdown",
            locationsPage, "UIDropDownMenuTemplate")
        atlasZoneDropdown:SetPoint("TOPRIGHT", locationsDivider, "BOTTOMRIGHT", 16, -8)
        UIDropDownMenu_SetWidth(atlasZoneDropdown, 145)
        UIDropDownMenu_SetText(atlasZoneDropdown, atlasZoneFilter)

        local locationsScroll = CreateFrame("ScrollFrame", "EasyFishingAtlasScrollFrame",
            locationsPage, "UIPanelScrollFrameTemplate")
        locationsScroll:SetPoint("TOPLEFT", locationsDivider, "BOTTOMLEFT", 0, -68)
        locationsScroll:SetSize(PAGE_CONTENT_WIDTH, 420)
        local locationsContent = CreateFrame("Frame", nil, locationsScroll)
        locationsContent:SetSize(590, 1)
        locationsScroll:SetScrollChild(locationsContent)

        local locationRows = {}
        local expandedAreas = {}
        local RefreshLocationsPage
        RefreshLocationsPage = function(scrollOffset)
            for _, row in ipairs(locationRows) do
                row:Hide()
            end

            local spots = {}
            local stats = EF.EnsureFishingStats()
            for zoneName, zoneStats in pairs(stats.zones) do
                if atlasZoneFilter == "All zones" or zoneName == atlasZoneFilter then
                    for _, spot in pairs(zoneStats.spots or {}) do
                        if type(spot) == "table" and type(spot.itemsByID) == "table" then
                            table.insert(spots, { zone = zoneName, spot = spot })
                        end
                    end
                end
            end
            local groupsByKey = {}
            local groups = {}
            for _, entry in ipairs(spots) do
                local subzone = type(entry.spot.subzone) == "string" and entry.spot.subzone or ""
                local areaName = subzone ~= "" and subzone or entry.zone
                local groupKey = entry.zone .. "\001" .. areaName
                local group = groupsByKey[groupKey]
                if not group then
                    group = {
                        key = groupKey,
                        zone = entry.zone,
                        area = areaName,
                        spots = {},
                        totalItems = 0,
                    }
                    groupsByKey[groupKey] = group
                    table.insert(groups, group)
                end
                table.insert(group.spots, entry.spot)
                group.totalItems = group.totalItems + (tonumber(entry.spot.totalItems) or 0)
            end
            table.sort(groups, function(first, second)
                if first.totalItems == second.totalItems then
                    if first.zone == second.zone then
                        return first.area < second.area
                    end
                    return first.zone < second.zone
                end
                return first.totalItems > second.totalItems
            end)
            for _, group in ipairs(groups) do
                table.sort(group.spots, function(first, second)
                    local firstCount = tonumber(first.totalItems) or 0
                    local secondCount = tonumber(second.totalItems) or 0
                    if firstCount == secondCount then
                        if first.x == second.x then return (first.y or 0) < (second.y or 0) end
                        return (first.x or 0) < (second.x or 0)
                    end
                    return firstCount > secondCount
                end)
            end

            if #groups == 0 then
                if atlasZoneFilter == "All zones" then
                    locationsDescription:SetText("No fishing locations recorded yet. Your first confirmed catch will add one.")
                else
                    locationsDescription:SetText("No fishing locations recorded in " .. atlasZoneFilter .. " yet.")
                end
                locationsContent:SetHeight(1)
                locationsScroll:SetVerticalScroll(0)
                locationsScroll:UpdateScrollChildRect()
                return
            end
            locationsDescription:SetText(string.format(
                "Your catches grouped by area. Expand an area to view saved locations, then select one for a map waypoint. Showing %d areas and %d locations.",
                #groups, #spots))

            local displayRows = {}
            for _, group in ipairs(groups) do
                if #group.spots > 1 then
                    table.insert(displayRows, { kind = "area", group = group })
                    if expandedAreas[group.key] then
                        for spotIndex, spot in ipairs(group.spots) do
                            table.insert(displayRows, {
                                kind = "spot",
                                group = group,
                                spot = spot,
                                index = spotIndex,
                            })
                        end
                    end
                else
                    table.insert(displayRows, {
                        kind = "spot",
                        group = group,
                        spot = group.spots[1],
                    })
                end
            end
            locationsContent:SetHeight(math.max(1, #displayRows * 54))
            locationsScroll:UpdateScrollChildRect()
            locationsScroll:SetVerticalScroll(scrollOffset or 0)

            for index, entry in ipairs(displayRows) do
                local group = entry.group
                local spot = entry.spot
                local fish, fishSummary = {}, {}
                if spot then
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

                    for fishIndex = 1, math.min(#fish, 2) do
                        table.insert(fishSummary, string.format("%s x%d", fish[fishIndex].name, fish[fishIndex].count))
                    end
                    if #fish > 2 then
                        table.insert(fishSummary, string.format("+%d more", #fish - 2))
                    end
                end
                local areaLabel = group.area == group.zone
                    and group.zone or (group.zone .. " / " .. group.area)
                local row = locationRows[index]
                if not row then
                    row = CreateFrame("Button", nil, locationsContent, "BackdropTemplate")
                    row:SetSize(580, 50)
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
                    row.areaLabel:SetWidth(390)
                    row.areaLabel:SetJustifyH("LEFT")
                    row.areaLabel:SetWordWrap(false)

                    row.coordinateLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.coordinateLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -8)
                    row.coordinateLabel:SetWidth(130)
                    row.coordinateLabel:SetJustifyH("RIGHT")
                    row.coordinateLabel:SetTextColor(0.72, 0.76, 0.76)

                    row.catchLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.catchLabel:SetPoint("TOPLEFT", row.areaLabel, "BOTTOMLEFT", 0, -2)
                    row.catchLabel:SetWidth(556)
                    row.catchLabel:SetJustifyH("LEFT")
                    row.catchLabel:SetTextColor(0.82, 0.84, 0.82)
                    row.catchLabel:SetWordWrap(false)
                    locationRows[index] = row
                end
                row:ClearAllPoints()
                local isNestedSpot = entry.kind == "spot" and entry.index ~= nil
                row:SetSize(isNestedSpot and 568 or 580, 50)
                row:SetPoint("TOPLEFT", locationsContent, "TOPLEFT", isNestedSpot and 12 or 0,
                    -((index - 1) * 54))
                if entry.kind == "area" then
                    row.areaLabel:SetText(areaLabel)
                    row.coordinateLabel:SetText((expandedAreas[group.key] and "- " or "+ ")
                        .. #group.spots .. " locations")
                    row.catchLabel:SetText(string.format("%d items recorded", group.totalItems))
                    row:SetBackdropColor(0.08, 0.07, 0.04, 0.82)
                    row:SetBackdropBorderColor(0.42, 0.34, 0.16, 1)
                else
                    row.areaLabel:SetText(entry.index and ("Location " .. entry.index) or areaLabel)
                    row.coordinateLabel:SetText(string.format("%.1f, %.1f", spot.x * 100, spot.y * 100))
                    row.catchLabel:SetText(#fishSummary > 0 and table.concat(fishSummary, "  |  ") or "No item counts")
                    row:SetBackdropColor(0.04, 0.05, 0.05, 0.72)
                    row:SetBackdropBorderColor(0.24, 0.27, 0.27, 1)
                end
                row:SetScript("OnClick", function()
                    if entry.kind == "area" then
                        local currentScroll = locationsScroll:GetVerticalScroll()
                        expandedAreas[group.key] = not expandedAreas[group.key]
                        RefreshLocationsPage(currentScroll)
                        return
                    end
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
                    EasyFishingDB.lastFishingSpot = {
                        mapID = spot.mapID,
                        x = spot.x,
                        y = spot.y,
                        label = areaLabel .. (entry.index and (" / Location " .. entry.index) or ""),
                    }
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
                    if entry.kind == "area" then
                        GameTooltip:SetText(areaLabel)
                        GameTooltip:AddLine(expandedAreas[group.key]
                            and "Click to hide recorded locations."
                            or "Click to show recorded locations.", 1, 1, 1, true)
                    else
                        GameTooltip:SetText("Fish caught at this location")
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
                        GameTooltip:AddLine("Coordinates are approximate, not exact fishing-pool boundaries.", 0.75, 0.75, 0.75, true)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    if entry.kind == "area" then
                        self:SetBackdropColor(0.08, 0.07, 0.04, 0.82)
                        self:SetBackdropBorderColor(0.42, 0.34, 0.16, 1)
                    else
                        self:SetBackdropColor(0.04, 0.05, 0.05, 0.72)
                        self:SetBackdropBorderColor(0.24, 0.27, 0.27, 1)
                    end
                    GameTooltip:Hide()
                end)
                row:Show()
            end
        end

        UIDropDownMenu_Initialize(atlasZoneDropdown, function()
            local zones = { "All zones" }
            for zoneName in pairs(EF.EnsureFishingStats().zones) do
                table.insert(zones, zoneName)
            end
            table.sort(zones, function(first, second)
                if first == "All zones" then return true end
                if second == "All zones" then return false end
                return first < second
            end)
            for _, zoneName in ipairs(zones) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = zoneName
                info.checked = atlasZoneFilter == zoneName
                info.func = function()
                    atlasZoneFilter = zoneName
                    UIDropDownMenu_SetText(atlasZoneDropdown, zoneName)
                    CloseDropDownMenus()
                    RefreshLocationsPage()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        local guideDivider = PageHeader(guidePage, "Fishing Guide")

        local guideSkillText = guidePage:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        guideSkillText:SetPoint("TOPLEFT", guideDivider, "BOTTOMLEFT", 0, -14)
        guideSkillText:SetWidth(PAGE_CONTENT_WIDTH)
        guideSkillText:SetJustifyH("LEFT")
        guideSkillText:SetWordWrap(true)

        local guideTrainingTab = CreateFrame("Button", nil, guidePage, "UIPanelButtonTemplate")
        guideTrainingTab:SetSize(112, 22)
        guideTrainingTab:SetPoint("TOPLEFT", guideSkillText, "BOTTOMLEFT", 0, -12)
        guideTrainingTab:SetText("Training")

        local guideTrainersTab = CreateFrame("Button", nil, guidePage, "UIPanelButtonTemplate")
        guideTrainersTab:SetSize(128, 22)
        guideTrainersTab:SetPoint("LEFT", guideTrainingTab, "RIGHT", 6, 0)
        guideTrainersTab:SetText("Fishing NPCs")

        local guideGearTab = CreateFrame("Button", nil, guidePage, "UIPanelButtonTemplate")
        guideGearTab:SetSize(132, 22)
        guideGearTab:SetPoint("LEFT", guideTrainersTab, "RIGHT", 6, 0)
        guideGearTab:SetText("Gear & Rewards")

        local guideTrainingIndicator = guidePage:CreateTexture(nil, "ARTWORK")
        guideTrainingIndicator:SetColorTexture(1, 0.82, 0, 0.9)
        guideTrainingIndicator:SetSize(100, 2)
        guideTrainingIndicator:SetPoint("BOTTOMLEFT", guideTrainingTab, "BOTTOMLEFT", 6, 2)

        local guideTrainersIndicator = guidePage:CreateTexture(nil, "ARTWORK")
        guideTrainersIndicator:SetColorTexture(1, 0.82, 0, 0.9)
        guideTrainersIndicator:SetSize(116, 2)
        guideTrainersIndicator:SetPoint("BOTTOMLEFT", guideTrainersTab, "BOTTOMLEFT", 6, 2)
        guideTrainersIndicator:Hide()

        local guideGearIndicator = guidePage:CreateTexture(nil, "ARTWORK")
        guideGearIndicator:SetColorTexture(1, 0.82, 0, 0.9)
        guideGearIndicator:SetSize(120, 2)
        guideGearIndicator:SetPoint("BOTTOMLEFT", guideGearTab, "BOTTOMLEFT", 6, 2)
        guideGearIndicator:Hide()

        local guideTrainingView = CreateFrame("Frame", nil, guidePage)
        guideTrainingView:SetPoint("TOPLEFT", guideTrainingTab, "BOTTOMLEFT", 0, -10)
        guideTrainingView:SetSize(PAGE_CONTENT_WIDTH, 380)

        local guideTrainersView = CreateFrame("Frame", nil, guidePage)
        guideTrainersView:SetAllPoints(guideTrainingView)
        guideTrainersView:Hide()

        local guideGearView = CreateFrame("Frame", nil, guidePage)
        guideGearView:SetAllPoints(guideTrainingView)
        guideGearView:Hide()

        local trainingTitle = guideTrainingView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainingTitle:SetPoint("TOPLEFT", guideTrainingView, "TOPLEFT", 0, 0)
        trainingTitle:SetTextColor(1, 0.82, 0)
        trainingTitle:SetText("Training and Leveling")

        local campTitle = guideTrainingView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        campTitle:SetPoint("TOPLEFT", guideTrainingView, "TOPLEFT", 320, 0)
        campTitle:SetTextColor(1, 0.82, 0)
        campTitle:SetText("Lures and Campsite Crafts")

        local trainingRankRows = {}
        for index, rank in ipairs(EF.Data.FISHING_RANKS) do
            local row = CreateFrame("Frame", nil, guideTrainingView)
            row.rank = rank
            row:SetSize(300, 80)
            row:SetPoint("TOPLEFT", trainingTitle, "BOTTOMLEFT", 0, -8 - ((index - 1) * 82))

            row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.title:SetText(rank.name)

            row.status = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            row.status:SetPoint("LEFT", row.title, "RIGHT", 6, 0)
            row.status:SetText("CURRENT")
            row.status:SetTextColor(1, 0.82, 0)
            row.status:Hide()

            row.range = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.range:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            row.range:SetText(rank.range)

            row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
            row.detail:SetWidth(300)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetWordWrap(true)
            row.detail:SetText(rank.detail)

            if index < #EF.Data.FISHING_RANKS then
                row.rule = row:CreateTexture(nil, "ARTWORK")
                row.rule:SetColorTexture(0.35, 0.35, 0.35, 0.45)
                row.rule:SetSize(300, 1)
                row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            end
            trainingRankRows[index] = row
        end

        local lureRows = {}
        for index, lure in ipairs(EF.Data.LURES) do
            local row = CreateFrame("Frame", nil, guideTrainingView)
            row.lure = lure
            row:SetSize(300, 28)
            row:SetPoint("TOPLEFT", campTitle, "BOTTOMLEFT", 0, -6 - ((index - 1) * 30))
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.icon:SetTexture(GetItemTexture(lure.id) or "Interface\\Icons\\INV_Misc_QuestionMark")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
            row.name:SetWidth(185)
            row.name:SetJustifyH("LEFT")
            row.name:SetText(lure.name)

            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
            row.count:SetWidth(78)
            row.count:SetJustifyH("RIGHT")

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.detail:SetText(string.format("+%d Fishing  |  Skill %d+", lure.bonus, lure.minimumSkill))

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(lure.name)
                GameTooltip:AddLine(string.format("Adds %d Fishing skill", lure.bonus), 1, 1, 1)
                GameTooltip:AddLine(string.format("Requires Fishing skill %d", lure.minimumSkill), 0.75, 0.75, 0.75)
                GameTooltip:AddLine(string.format("In bags: %d", self.itemCount or 0), 0.75, 0.75, 0.75)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            lureRows[index] = row
        end

        local campCraftTitle = guideTrainingView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        campCraftTitle:SetPoint("TOPLEFT", lureRows[#lureRows], "BOTTOMLEFT", 0, -8)
        campCraftTitle:SetTextColor(1, 0.82, 0)
        campCraftTitle:SetText("Campsite Recipes")

        local campRows = {}
        for index, campItem in ipairs(EF.Data.FISHING_CAMP_ITEMS) do
            local row = CreateFrame("Frame", nil, guideTrainingView)
            row.campItem = campItem
            row:SetSize(300, 30)
            row:SetPoint("TOPLEFT", campCraftTitle, "BOTTOMLEFT", 0, -6 - ((index - 1) * 32))
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.icon:SetTexture(GetItemTexture(campItem.id) or "Interface\\Icons\\INV_Misc_QuestionMark")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
            row.name:SetWidth(185)
            row.name:SetText(campItem.name)

            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            row.count:SetWidth(78)
            row.count:SetJustifyH("RIGHT")

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.detail:SetText(string.format("Craft skill %d  |  %s", campItem.craftSkill, campItem.source))

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(campItem.name)
                GameTooltip:AddLine(campItem.details, 1, 1, 1, true)
                if campItem.recipe then
                    GameTooltip:AddLine("Recipe: " .. campItem.recipe, 0.75, 0.75, 0.75, true)
                end
                GameTooltip:AddLine(string.format("In bags: %d", self.itemCount or 0), 0.75, 0.75, 0.75)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            campRows[index] = row
        end

        local gearTitle = guideGearView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        gearTitle:SetPoint("TOPLEFT", guideGearView, "TOPLEFT", 0, 0)
        gearTitle:SetTextColor(1, 0.82, 0)
        gearTitle:SetText("Fishing Skill Bonuses")

        local gearRows = {}
        for index, boost in ipairs(EF.Data.FISHING_BOOSTS) do
            local row = CreateFrame("Frame", nil, guideGearView)
            row.boost = boost
            row:SetSize(300, 34)
            row:SetPoint("TOPLEFT", gearTitle, "BOTTOMLEFT", 0, -8 - ((index - 1) * 36))
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            local icon = boost.iconType == "spell"
                and GetSpellIcon(boost.id) or GetItemTexture(boost.id)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
            row.name:SetWidth(175)
            row.name:SetJustifyH("LEFT")
            row.name:SetText(boost.name)

            row.bonus = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.bonus:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            row.bonus:SetWidth(82)
            row.bonus:SetJustifyH("RIGHT")
            row.bonus:SetText(string.format("+%d Fishing", boost.bonus))
            row.bonus:SetTextColor(1, 0.82, 0)

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.detail:SetWidth(245)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetText(string.format("Skill %d+  |  %s", boost.minimumSkill, boost.source))

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(boost.name)
                GameTooltip:AddLine(string.format("Adds %d Fishing skill", boost.bonus), 1, 1, 1)
                GameTooltip:AddLine(string.format("Requires Fishing skill %d", boost.minimumSkill), 0.75, 0.75, 0.75)
                GameTooltip:AddLine("Source: " .. boost.source, 0.75, 0.75, 0.75, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            gearRows[index] = row
        end

        local rewardsTitle = guideGearView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        rewardsTitle:SetPoint("TOPLEFT", guideGearView, "TOPLEFT", 320, 0)
        rewardsTitle:SetTextColor(1, 0.82, 0)
        rewardsTitle:SetText("Find Fish and Quest Rewards")

        local findFish = EF.Data.FISHING_ABILITIES[1]
        local findFishRow = CreateFrame("Frame", nil, guideGearView)
        findFishRow:SetSize(300, 42)
        findFishRow:SetPoint("TOPLEFT", rewardsTitle, "BOTTOMLEFT", 0, -8)
        findFishRow:EnableMouse(true)

        local findFishIcon = findFishRow:CreateTexture(nil, "ARTWORK")
        findFishIcon:SetSize(24, 24)
        findFishIcon:SetPoint("TOPLEFT", findFishRow, "TOPLEFT", 0, -2)
        findFishIcon:SetTexture(GetSpellIcon(findFish.id)
            or "Interface\\Icons\\INV_Misc_QuestionMark")

        local findFishName = findFishRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        findFishName:SetPoint("TOPLEFT", findFishIcon, "TOPRIGHT", 6, 0)
        findFishName:SetText(findFish.name)

        local findFishDetail = findFishRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        findFishDetail:SetPoint("TOPLEFT", findFishName, "BOTTOMLEFT", 0, -1)
        findFishDetail:SetWidth(265)
        findFishDetail:SetText("Shows nearby fishing pools on your minimap.")

        findFishRow:SetScript("OnEnter", function()
            GameTooltip:SetOwner(findFishRow, "ANCHOR_RIGHT")
            GameTooltip:SetText(findFish.name)
            GameTooltip:AddLine(findFish.details, 1, 1, 1, true)
            GameTooltip:AddLine("Requires Fishing skill 1; 1.5-second cooldown.", 0.75, 0.75, 0.75)
            GameTooltip:Show()
        end)
        findFishRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local rewardScroll = CreateFrame("ScrollFrame", "EasyFishingQuestRewardsScroll",
            guideGearView, "UIPanelScrollFrameTemplate")
        rewardScroll:SetPoint("TOPLEFT", findFishRow, "BOTTOMLEFT", -2, -8)
        rewardScroll:SetSize(300, 290)
        local rewardContent = CreateFrame("Frame", nil, rewardScroll)
        rewardContent:SetSize(280, #EF.Data.FISHING_QUEST_REWARDS * 46)
        rewardScroll:SetScrollChild(rewardContent)

        local rewardRows = {}
        for index, quest in ipairs(EF.Data.FISHING_QUEST_REWARDS) do
            local row = CreateFrame("Frame", nil, rewardContent)
            row:SetSize(278, 42)
            row:SetPoint("TOPLEFT", rewardContent, "TOPLEFT", 0, -((index - 1) * 46))
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.icon:SetTexture(quest.rewardItemID and GetItemTexture(quest.rewardItemID)
                or "Interface\\Icons\\INV_Misc_QuestionMark")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
            row.name:SetWidth(242)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.name:SetText(quest.name)

            row.reward = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.reward:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.reward:SetWidth(242)
            row.reward:SetJustifyH("LEFT")
            row.reward:SetWordWrap(false)
            row.reward:SetText(quest.reward)

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(quest.name)
                GameTooltip:AddLine(quest.details, 1, 1, 1, true)
                GameTooltip:AddLine("Reward: " .. quest.reward, 0.75, 0.75, 0.75, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            rewardRows[index] = row
        end

        local trainerFilter = "All"
        local trainerIntro = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        trainerIntro:SetPoint("TOPLEFT", guideTrainersView, "TOPLEFT", 0, -4)
        trainerIntro:SetWidth(360)
        trainerIntro:SetJustifyH("LEFT")

        local trainerFactionDropdown = CreateFrame("Frame", "EasyFishingTrainerFactionDropdown",
            guideTrainersView, "UIDropDownMenuTemplate")
        trainerFactionDropdown:SetPoint("TOPRIGHT", guideTrainersView, "TOPRIGHT", 16, 2)
        UIDropDownMenu_SetWidth(trainerFactionDropdown, 135)
        UIDropDownMenu_SetText(trainerFactionDropdown, "All factions")

        local trainerSearch = CreateFrame("EditBox", nil, guideTrainersView, "SearchBoxTemplate")
        trainerSearch:SetPoint("TOPLEFT", trainerIntro, "BOTTOMLEFT", 0, -8)
        trainerSearch:SetSize(220, 20)
        trainerSearch:SetAutoFocus(false)
        trainerSearch:SetMaxLetters(40)

        local trainerHeaderName = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderName:SetPoint("TOPLEFT", trainerSearch, "BOTTOMLEFT", 6, -10)
        trainerHeaderName:SetText("NPC / Role")

        local trainerHeaderSide = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderSide:SetPoint("TOPLEFT", trainerHeaderName, "TOPLEFT", 171, 0)
        trainerHeaderSide:SetText("Faction")

        local trainerHeaderLocation = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderLocation:SetPoint("TOPLEFT", trainerHeaderName, "TOPLEFT", 247, 0)
        trainerHeaderLocation:SetText("Zone / Area")

        local trainerHeaderCoordinates = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderCoordinates:SetPoint("TOPRIGHT", trainerHeaderName, "TOPLEFT", 572, 0)
        trainerHeaderCoordinates:SetText("Coordinates")

        local trainerScroll = CreateFrame("ScrollFrame", "EasyFishingTrainerScrollFrame",
            guideTrainersView, "UIPanelScrollFrameTemplate")
        trainerScroll:SetPoint("TOPLEFT", trainerHeaderName, "BOTTOMLEFT", -6, -6)
        trainerScroll:SetSize(PAGE_CONTENT_WIDTH, 300)
        local trainerContent = CreateFrame("Frame", nil, trainerScroll)
        trainerContent:SetSize(590, 1)
        trainerScroll:SetScrollChild(trainerContent)

        local trainerEmptyText = trainerContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        trainerEmptyText:SetPoint("TOPLEFT", trainerContent, "TOPLEFT", 10, -10)
        trainerEmptyText:SetText("No fishing NPCs match. Try another search or faction.")
        trainerEmptyText:Hide()

        local trainerRows = {}
        local function RefreshTrainerList()
            for _, row in ipairs(trainerRows) do
                row:Hide()
            end

            local trainers = {}
            local query = (trainerSearch:GetText() or ""):lower():match("^%s*(.-)%s*$") or ""
            for _, trainer in ipairs(EF.Data.FISHING_NPCS) do
                local matchesFaction = trainerFilter == "All" or trainer.side == trainerFilter
                    or (trainer.side == "Both" and trainerFilter ~= "Neutral")
                local searchText = string.lower(string.format("%s %s %s %s %s %d",
                    trainer.name, trainer.role, trainer.side,
                    trainer.location, trainer.zone, trainer.level))
                if matchesFaction and (query == "" or string.find(searchText, query, 1, true)) then
                    table.insert(trainers, trainer)
                end
            end
            table.sort(trainers, function(first, second)
                if first.zone == second.zone then
                    return first.name < second.name
                end
                return first.zone < second.zone
            end)

            trainerIntro:SetText(string.format("%d of %d Fishing NPCs. Search by name, role, town, or zone.",
                #trainers, #EF.Data.FISHING_NPCS))
            trainerContent:SetHeight(math.max(40, #trainers * 40))
            if #trainers == 0 then
                trainerEmptyText:Show()
            else
                trainerEmptyText:Hide()
            end
            trainerScroll:UpdateScrollChildRect()
            trainerScroll:SetVerticalScroll(0)

            for index, trainer in ipairs(trainers) do
                local row = trainerRows[index]
                if not row then
                    row = CreateFrame("Frame", nil, trainerContent)
                    row:SetSize(590, 38)

                    row.background = row:CreateTexture(nil, "BACKGROUND")
                    row.background:SetAllPoints(row)

                    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
                    row.name:SetWidth(165)
                    row.name:SetJustifyH("LEFT")

                    row.role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.role:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
                    row.role:SetWidth(165)
                    row.role:SetJustifyH("LEFT")
                    row.role:SetTextColor(0.72, 0.72, 0.72)

                    row.side = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.side:SetPoint("TOPLEFT", row, "TOPLEFT", 177, -7)
                    row.side:SetWidth(68)
                    row.side:SetJustifyH("LEFT")

                    row.location = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.location:SetPoint("TOPLEFT", row, "TOPLEFT", 253, -7)
                    row.location:SetWidth(225)
                    row.location:SetJustifyH("LEFT")

                    row.coordinates = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.coordinates:SetPoint("TOPRIGHT", row, "TOPRIGHT", -12, -7)
                    row.coordinates:SetWidth(100)
                    row.coordinates:SetJustifyH("RIGHT")
                    trainerRows[index] = row
                end

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", trainerContent, "TOPLEFT", 0, -((index - 1) * 40))
                row.background:SetColorTexture(0.55, 0.48, 0.3, index % 2 == 0 and 0.07 or 0.025)
                row.name:SetText(trainer.name)
                row.role:SetText(string.format("%s  |  Level %d", trainer.role, trainer.level))
                row.side:SetText(trainer.side == "Both" and "Shared" or trainer.side)
                if trainer.side == "Alliance" then
                    row.side:SetTextColor(0.45, 0.72, 1)
                elseif trainer.side == "Horde" then
                    row.side:SetTextColor(1, 0.45, 0.35)
                else
                    row.side:SetTextColor(1, 0.82, 0)
                end
                row.location:SetText(trainer.location .. ", " .. trainer.zone)
                row.coordinates:SetText(trainer.x and trainer.y
                    and string.format("%.1f, %.1f", trainer.x, trainer.y) or "Not listed")
                row:Show()
            end
        end

        local originalSearchChanged = trainerSearch:GetScript("OnTextChanged")
        trainerSearch:SetScript("OnTextChanged", function(self, ...)
            if originalSearchChanged then
                originalSearchChanged(self, ...)
            end
            RefreshTrainerList()
        end)

        UIDropDownMenu_Initialize(trainerFactionDropdown, function()
            local options = {
                { label = "All factions", value = "All" },
                { label = "Alliance", value = "Alliance" },
                { label = "Horde", value = "Horde" },
                { label = "Neutral", value = "Neutral" },
            }
            for _, option in ipairs(options) do
                local value, label = option.value, option.label
                local info = UIDropDownMenu_CreateInfo()
                info.text = label
                info.checked = trainerFilter == value
                info.func = function()
                    trainerFilter = value
                    UIDropDownMenu_SetText(trainerFactionDropdown, label)
                    CloseDropDownMenus()
                    RefreshTrainerList()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        local guideSource = guidePage:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        guideSource:SetPoint("BOTTOMLEFT", guidePage, "BOTTOMLEFT", 16, 18)
        guideSource:SetWidth(PAGE_CONTENT_WIDTH)
        guideSource:SetJustifyH("LEFT")
        guideSource:SetText("Source: Wowhead Forever Fishing and Camping guides, Patch 1.60.1. Trainer coordinates are zone-map estimates. Forever is in beta; routes and data may change.")

        local function RefreshForeverGuide()
            local skill = GetFishingSkill()
            if skill then
                local guidance
                if skill < 25 then
                    guidance = "Apprentice: use Shiny Bauble below 25 in starter zones. Next training at 75."
                elseif skill < 75 then
                    guidance = "Apprentice: starter zones reach a 100% catch rate at 25. Next training at 75."
                elseif skill < 150 then
                    guidance = "Journeyman: capital cities reach a 100% catch rate at 75. Train Expert at 150 from Old Man Heming."
                elseif skill < 225 then
                    guidance = "Expert: Buy The Bass and You in Booty Bay for 1 gold. Fishing skill plus gear and lure bonuses must reach 225 for a 100% catch rate in Dustwallow Marsh or Stranglethorn Vale. Artisan requires skill 225 and character level 35."
                elseif skill < 300 then
                    guidance = "Artisan: Nat Pagle's quest requires character level 35 and skill 225. The guide has no complete 225-300 route."
                else
                    guidance = "Artisan skill cap reached. The guide has no detailed leveling route above 225."
                end
                guideSkillText:SetText(string.format("Fishing skill: %d\n%s", skill, guidance))
            else
                guideSkillText:SetText("Fishing skill is unavailable. Train Fishing to see your current bracket and next step.")
            end

            for _, row in ipairs(trainingRankRows) do
                local isCurrent = skill and skill >= row.rank.minimumSkill
                    and (not row.rank.nextTraining or skill < row.rank.nextTraining)
                if isCurrent then
                    row.status:Show()
                    row.title:SetTextColor(1, 0.82, 0)
                    row.range:SetTextColor(1, 0.82, 0)
                    row.detail:SetTextColor(1, 1, 1)
                else
                    row.status:Hide()
                    row.title:SetTextColor(0.72, 0.72, 0.72)
                    row.range:SetTextColor(0.72, 0.72, 0.72)
                    row.detail:SetTextColor(0.78, 0.78, 0.78)
                end
            end

            for _, row in ipairs(lureRows) do
                local count = GetOwnedItemCount(row.lure.id)
                local usable = skill and skill >= row.lure.minimumSkill
                row.itemCount = count
                row.count:SetText(string.format("In bags: %d", count))
                row.icon:SetDesaturated(count == 0 or not usable)
                if count > 0 and usable then
                    row.name:SetTextColor(1, 0.82, 0)
                    row.count:SetTextColor(0.35, 1, 0.35)
                elseif count > 0 then
                    row.name:SetTextColor(0.72, 0.72, 0.72)
                    row.count:SetTextColor(0.72, 0.72, 0.72)
                else
                    row.name:SetTextColor(0.62, 0.62, 0.62)
                    row.count:SetTextColor(0.62, 0.62, 0.62)
                end
            end

            for _, row in ipairs(campRows) do
                local count = GetOwnedItemCount(row.campItem.id)
                row.itemCount = count
                row.count:SetText(string.format("In bags: %d", count))
                row.icon:SetDesaturated(count == 0)
                if count > 0 then
                    row.name:SetTextColor(1, 0.82, 0)
                    row.count:SetTextColor(0.35, 1, 0.35)
                else
                    row.name:SetTextColor(0.72, 0.72, 0.72)
                    row.count:SetTextColor(0.62, 0.62, 0.62)
                end
            end

        end

        local function SelectGuideView(viewName)
            local showTraining = viewName == "training"
            local showTrainers = viewName == "npcs"
            local showGear = viewName == "gear"

            if showTraining then
                guideTrainingView:Show()
            else
                guideTrainingView:Hide()
            end
            if showTrainers then
                guideTrainersView:Show()
            else
                guideTrainersView:Hide()
            end
            if showGear then
                guideGearView:Show()
            else
                guideGearView:Hide()
            end

            if showTrainers then
                guideTrainingIndicator:Hide()
                guideTrainersIndicator:Show()
                guideGearIndicator:Hide()
                guideTrainingTab:GetFontString():SetTextColor(1, 1, 1)
                guideTrainersTab:GetFontString():SetTextColor(1, 0.82, 0)
                guideGearTab:GetFontString():SetTextColor(1, 1, 1)
            elseif showGear then
                guideTrainingIndicator:Hide()
                guideTrainersIndicator:Hide()
                guideGearIndicator:Show()
                guideTrainingTab:GetFontString():SetTextColor(1, 1, 1)
                guideTrainersTab:GetFontString():SetTextColor(1, 1, 1)
                guideGearTab:GetFontString():SetTextColor(1, 0.82, 0)
            else
                guideTrainingIndicator:Show()
                guideTrainersIndicator:Hide()
                guideGearIndicator:Hide()
                guideTrainingTab:GetFontString():SetTextColor(1, 0.82, 0)
                guideTrainersTab:GetFontString():SetTextColor(1, 1, 1)
                guideGearTab:GetFontString():SetTextColor(1, 1, 1)
            end
        end

        guideTrainingTab:SetScript("OnClick", function()
            SelectGuideView("training")
        end)
        guideTrainersTab:SetScript("OnClick", function()
            SelectGuideView("npcs")
            RefreshTrainerList()
        end)
        guideGearTab:SetScript("OnClick", function()
            SelectGuideView("gear")
        end)
        SelectGuideView("training")
        RefreshTrainerList()

        settingsTab:SetScript("OnClick", function()
            statisticsPage:Hide()
            locationsPage:Hide()
            guidePage:Hide()
            settingsPage:Show()
        end)
        statisticsTab:SetScript("OnClick", function()
            settingsPage:Hide()
            locationsPage:Hide()
            guidePage:Hide()
            RefreshStatisticsPage()
            statisticsPage:Show()
        end)
        locationsTab:SetScript("OnClick", function()
            settingsPage:Hide()
            statisticsPage:Hide()
            guidePage:Hide()
            RefreshLocationsPage()
            locationsPage:Show()
        end)
        guideTab:SetScript("OnClick", function()
            settingsPage:Hide()
            statisticsPage:Hide()
            locationsPage:Hide()
            RefreshForeverGuide()
            guidePage:Show()
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
            guidePage:Hide()
            if page == "stats" then
                RefreshStatisticsPage()
                statisticsPage:Show()
            elseif page == "atlas" then
                RefreshLocationsPage()
                locationsPage:Show()
            elseif page == "guide" then
                RefreshForeverGuide()
                guidePage:Show()
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
            elseif command == "guide" then
                ShowOptionsPage("guide")
            elseif command == "link fish" then
                ShareLastFish()
            elseif command == "link location" then
                ShareFishingLocation()
            elseif command == "link gear" then
                ShareFishingOutfit()
            elseif command == "watch" then
                EasyFishingDB.showFishWatcher = not EasyFishingDB.showFishWatcher
                EF.UpdateFishWatcher()
                print("EasyFishing: Fish Watcher " .. (EasyFishingDB.showFishWatcher and "shown" or "hidden") .. ".")
            elseif command == "equip" then
                EquipFishingOutfit()
            elseif command == "restore" then
                RestorePreviousEquipmentSet()
            else
                print("EasyFishing commands: /ef [menu|stats|atlas|guide|watch|equip|restore|link fish|link location|link gear]")
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

