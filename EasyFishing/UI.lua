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
local ToggleFishingOutfit = EF.ToggleFishingOutfit
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

local activeTomTomWaypointID
local function SetTomTomWaypoint(spot, label)
    local tomTom = rawget(_G, "TomTom")
    if type(tomTom) ~= "table" or type(tomTom.AddWaypoint) ~= "function" then
        return false
    end

    if activeTomTomWaypointID and type(tomTom.RemoveWaypoint) == "function" then
        pcall(tomTom.RemoveWaypoint, tomTom, activeTomTomWaypointID)
    end
    local ok, waypointID = pcall(tomTom.AddWaypoint, tomTom,
        spot.mapID, spot.x, spot.y, {
            title = label,
            from = "EasyFishing",
            persistent = false,
            minimap = true,
            world = true,
        })
    if not ok or not waypointID then
        return false
    end
    activeTomTomWaypointID = waypointID
    if type(tomTom.SetCrazyArrow) == "function" then
        pcall(tomTom.SetCrazyArrow, tomTom, waypointID, 15, label)
    end
    return true
end

local function ShareFishingLocation()
    local spot = EF.GetCharacterDB().lastFishingSpot
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
    if spot then SetTomTomWaypoint(spot, spot.label or "Fishing location") end

    local hyperlink = C_Map and C_Map.GetUserWaypointHyperlink and C_Map.GetUserWaypointHyperlink()
    if not hyperlink or hyperlink == "" then
        print("EasyFishing: select an atlas location or set a map waypoint first.")
        return
    end
    local label = spot and spot.label and (spot.label .. " ") or ""
    OpenChatWithLinks(label .. hyperlink)
end

local function ShareFishingOutfit()
    local setID = tonumber(EF.GetCharacterDB().fishingOutfitSetID)
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
        EF.InitializeCharacterDB()
        local characterDB = EF.GetCharacterDB()
        EF.SetDoubleClickDelay(EasyFishingDB.doubleClickDelay)
        EF.EnsureFishingStats()
        EF.FishWatcher:ClearAllPoints()
        EF.FishWatcher:SetPoint("CENTER", UIParent, "CENTER",
            characterDB.fishWatcherX, characterDB.fishWatcherY)
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

        local guideTab = CreateFrame("Button", "EasyFishingOptionsGuideTab", panel, "PanelTopTabButtonTemplate")
        guideTab:SetSize(86, 32)
        guideTab:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -366, -10)
        guideTab:SetText("Guide")

        local locationsTab = CreateFrame("Button", "EasyFishingOptionsLocationsTab", panel, "PanelTopTabButtonTemplate")
        locationsTab:SetSize(86, 32)
        locationsTab:SetPoint("LEFT", guideTab, "RIGHT", 4, 0)
        locationsTab:SetText("Locations")

        local statisticsTab = CreateFrame("Button", "EasyFishingOptionsStatisticsTab", panel, "PanelTopTabButtonTemplate")
        statisticsTab:SetSize(86, 32)
        statisticsTab:SetPoint("LEFT", locationsTab, "RIGHT", 4, 0)
        statisticsTab:SetText("Statistics")

        local settingsTab = CreateFrame("Button", "EasyFishingOptionsSettingsTab", panel, "PanelTopTabButtonTemplate")
        settingsTab:SetSize(86, 32)
        settingsTab:SetPoint("LEFT", statisticsTab, "RIGHT", 4, 0)
        settingsTab:SetText("Settings")
        local optionPageTabs = {
            settings = settingsTab,
            stats = statisticsTab,
            atlas = locationsTab,
            guide = guideTab,
        }
        local function SelectOptionsPageTab(pageName)
            for name, tab in pairs(optionPageTabs) do
                local isSelected = name == pageName
                if isSelected then
                    PanelTemplates_SelectTab(tab)
                else
                    PanelTemplates_DeselectTab(tab)
                end
            end
        end
        SelectOptionsPageTab("settings")

        local PAGE_CONTENT_WIDTH = 620

        local function PageHeader(page, text)
            local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", 16, -16)
            title:SetText(text)

            local rule = page:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(0.42, 0.34, 0.17, 0.6)
            rule:SetSize(PAGE_CONTENT_WIDTH, 1)
            rule:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
            return rule
        end

        local function ContentHeading(parent, text, anchor, relativePoint, xOffset, yOffset, width)
            local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
            heading:SetPoint("TOPLEFT", anchor, relativePoint, xOffset, yOffset)
            heading:SetTextColor(1, 0.82, 0)
            heading:SetText(text)

            local rule = parent:CreateTexture(nil, "ARTWORK")
            rule:SetColorTexture(0.42, 0.34, 0.17, 0.6)
            rule:SetSize(width, 1)
            rule:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -3)
            return heading
        end

        local function UpdateScrollBarVisibility(scrollFrame)
            local scrollBar = scrollFrame.ScrollBar
            if not scrollBar and scrollFrame.GetName then
                scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
            end
            if not scrollBar then return end

            if scrollFrame:GetVerticalScrollRange() > 0 then
                scrollBar:Show()
            else
                scrollBar:Hide()
            end
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
            "Use the selected mouse button and click pattern over the game world while holding a fishing pole. UI buttons and menus will not cast.",
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
            "If your pole has no lure, your first click applies an eligible lure. Choose whether to conserve stock or use your strongest available lure below.",
            secLure, -4, "enableAutoLure")

        local cbStrongestLure = MakeCheckbox(
            "Use Strongest Available Lure",
            "Prefer the highest-bonus eligible lure instead of conserving stronger lures.",
            cbAutoLure, -4, "preferStrongestLure")

        local secTracking = SectionHeader("Tracking", cbStrongestLure, -10)
        MakeCheckbox(
            "Show Fish Watcher",
            "Show the Watcher during an active fishing session. It hides when you move away or after two minutes without a cast.",
            secTracking, -4, "showFishWatcher")

        local secMovement = RightSectionHeader("Movement", -14)
        local cbDisableClickToMove = MakeCheckbox(
            "Pause Click-to-Move With Pole",
            "Turns off auto-interact movement while the fishing pole is equipped and Click-to-Cast is on, then restores your previous setting when the pole is removed.",
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
        outfitHint:SetText("Choose a saved fishing set. Toggle Gear swaps it with your previous set; /ef toggle also works in an action-bar macro.")

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
                    info.checked = tonumber(characterDB.fishingOutfitSetID) == setID
                    info.func = function()
                        characterDB.fishingOutfitSetID = setID
                        UIDropDownMenu_SetText(outfitDropdown, name)
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info)
                    if tonumber(characterDB.fishingOutfitSetID) == setID then
                        selectedOutfitName = name
                    end
                end
            end
        end)
        for _, setID in ipairs(GetEquipmentSetIDs()) do
            if tonumber(characterDB.fishingOutfitSetID) == setID then
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

        local toggleOutfitButton = CreateFrame("Button", nil, settingsPage, "UIPanelButtonTemplate")
        toggleOutfitButton:SetSize(92, 22)
        toggleOutfitButton:SetPoint("LEFT", restoreOutfitButton, "RIGHT", 4, 0)
        toggleOutfitButton:SetText("Toggle Gear")
        toggleOutfitButton:SetScript("OnClick", ToggleFishingOutfit)

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

        local statisticsSummaryRule = statisticsPage:CreateTexture(nil, "ARTWORK")
        statisticsSummaryRule:SetColorTexture(0.42, 0.34, 0.17, 0.6)
        statisticsSummaryRule:SetSize(PAGE_CONTENT_WIDTH, 1)
        statisticsSummaryRule:SetPoint("TOPLEFT", metricValues[1], "BOTTOMLEFT", 0, -4)

        local statisticsSummary = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        statisticsSummary:SetPoint("TOPLEFT", statisticsSummaryRule, "BOTTOMLEFT", 0, -4)
        statisticsSummary:SetWidth(PAGE_CONTENT_WIDTH)
        statisticsSummary:SetJustifyH("CENTER")

        local statisticsCaveat = statisticsPage:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        statisticsCaveat:SetPoint("BOTTOMLEFT", statisticsPage, "BOTTOMLEFT", 16, 18)
        statisticsCaveat:SetWidth(PAGE_CONTENT_WIDTH - 32)
        statisticsCaveat:SetWordWrap(true)
        statisticsCaveat:SetText("Only items shown in the client's Fishing loot window are counted.")

        local zoneStatsTitle = ContentHeading(
            statisticsPage, "Items by Zone", statisticsSummary, "BOTTOMLEFT", 0, -24, 300)

        local zoneStatsList = CreateFrame("Frame", nil, statisticsPage)
        zoneStatsList:SetPoint("TOPLEFT", zoneStatsTitle, "BOTTOMLEFT", 0, -10)
        zoneStatsList:SetSize(300, 300)

        local zoneStatsEmpty = zoneStatsList:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        zoneStatsEmpty:SetPoint("TOPLEFT", zoneStatsList, "TOPLEFT", 0, 0)
        zoneStatsEmpty:SetText("No zone totals recorded yet.")
        local zoneStatsRows = {}
        local zoneStatsMore = zoneStatsList:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        zoneStatsMore:SetWidth(292)

        local itemStatsTitle = ContentHeading(
            statisticsPage, "Top Catches", zoneStatsTitle, "TOPLEFT", 310, 0, 300)

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

            row.background = row:CreateTexture(nil, "BACKGROUND")
            row.background:SetAllPoints(row)

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
                row.background:SetColorTexture(0.55, 0.48, 0.3, index % 2 == 0 and 0.07 or 0.025)
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
            local catchRate = stats.rateTrackedCasts > 0
                and string.format("%.1f%% catch rate", math.min(100,
                    stats.successfulCasts * 100 / stats.rateTrackedCasts))
                or "catch rate collecting"
            statisticsSummary:SetText(string.format(
                "Lifetime: %d sessions  |  %d %s  |  %.1f items per hour  |  %s",
                stats.totalSessions, zoneCount, zoneCount == 1 and "zone" or "zones",
                stats.totalFishingSeconds > 0 and stats.totalItems * 3600 / stats.totalFishingSeconds or 0,
                catchRate))
            local zoneEntries, moreZones = BuildStatsEntries(stats.zones, 5)
            RenderStatisticsRows(zoneStatsList, zoneStatsRows, zoneStatsEmpty, zoneStatsMore,
                zoneEntries, moreZones, zoneEntries[1] and zoneEntries[1].count or 0,
                function(entry)
                    return string.format("%d items", entry.count)
                end,
                function(entry)
                    local zone = entry.data
                    local trackedCasts = tonumber(zone.rateTrackedCasts) or 0
                    local zoneCatchRate = trackedCasts > 0
                        and string.format("  |  %.1f%% caught", math.min(100,
                            (tonumber(zone.successfulCasts) or 0) * 100 / trackedCasts))
                        or ""
                    return string.format("%d sessions  |  %d casts  |  %s%s",
                        tonumber(zone.sessions) or 0, tonumber(zone.casts) or 0,
                        EF.FormatFishingTime(tonumber(zone.fishingSeconds) or 0), zoneCatchRate)
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
        locationsDescription:SetWidth(210)
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
        local RefreshLocationsPage
        local OpenLocationTransfer

        local function EncodeTransferField(value)
            return tostring(value or "")
                :gsub("%%", "%%25")
                :gsub("\t", "%%09")
                :gsub("\r", "%%0D")
                :gsub("\n", "%%0A")
        end

        local function DecodeTransferField(value)
            return value:gsub("%%(%x%x)", function(hex)
                return string.char(tonumber(hex, 16))
            end)
        end

        local function SplitTransferFields(line)
            local fields = {}
            local startIndex = 1
            while true do
                local separator = line:find("\t", startIndex, true)
                if not separator then
                    table.insert(fields, line:sub(startIndex))
                    break
                end
                table.insert(fields, line:sub(startIndex, separator - 1))
                startIndex = separator + 1
            end
            return fields
        end

        local function ExportFishingLocations()
            local lines = { "EFS2" }
            local recordCount = 0
            local stats = EF.EnsureFishingStats()
            local zoneNames = {}
            for zoneName in pairs(stats.zones) do
                table.insert(zoneNames, zoneName)
            end
            table.sort(zoneNames)

            for _, zoneName in ipairs(zoneNames) do
                local zone = stats.zones[zoneName]
                local spotKeys = {}
                for spotKey in pairs(zone.spots or {}) do
                    table.insert(spotKeys, spotKey)
                end
                table.sort(spotKeys)
                for _, spotKey in ipairs(spotKeys) do
                    local spot = zone.spots[spotKey]
                    if type(spot) == "table" and tonumber(spot.mapID)
                        and tonumber(spot.x) and tonumber(spot.y) then
                        recordCount = recordCount + 1
                        if recordCount > 2000 then
                            return nil, "Export is limited to 2,000 locations."
                        end
                        local itemIDs = {}
                        for itemID in pairs(spot.itemsByID or {}) do
                            table.insert(itemIDs, tostring(itemID))
                        end
                        table.sort(itemIDs)
                        local items = {}
                        for _, itemID in ipairs(itemIDs) do
                            local item = spot.itemsByID[itemID]
                            local buckets = item.timeBuckets or {}
                            table.insert(items, table.concat({
                                itemID,
                                math.max(0, math.floor(tonumber(item.count) or 0)),
                                math.max(0, math.floor(tonumber(buckets[0]) or 0)),
                                math.max(0, math.floor(tonumber(buckets[1]) or 0)),
                                math.max(0, math.floor(tonumber(buckets[2]) or 0)),
                                math.max(0, math.floor(tonumber(buckets[3]) or 0)),
                            }, ":"))
                        end
                        table.insert(lines, table.concat({
                            EncodeTransferField(zoneName),
                            tostring(math.floor(tonumber(spot.mapID))),
                            string.format("%.8f", tonumber(spot.x)),
                            string.format("%.8f", tonumber(spot.y)),
                            EncodeTransferField(spot.subzone),
                            EncodeTransferField(spot.label),
                            spot.favorite and "1" or "0",
                            table.concat(items, ","),
                        }, "\t"))
                    end
                end
            end
            local exportText = table.concat(lines, "\n")
            if #exportText > 2000000 then
                return nil, "Export text is too large to transfer in one copy."
            end
            return exportText
        end

        local function ParseFishingLocationExport(text)
            if type(text) ~= "string" or #text > 2000000 then
                return nil, "Export text is invalid or too large."
            end
            local imported = {}
            local lineNumber = 0
            for line in (text .. "\n"):gmatch("(.-)\n") do
                line = line:gsub("\r$", "")
                if line ~= "" then
                    lineNumber = lineNumber + 1
                    if lineNumber == 1 then
                        if line ~= "EFS2" then
                            return nil, "This is not a supported EasyFishing spots export."
                        end
                    else
                        if lineNumber > 2001 then
                            return nil, "The export contains too many locations."
                        end
                        local fields = SplitTransferFields(line)
                        if #fields ~= 8 then
                            return nil, "Invalid location record on line " .. lineNumber .. "."
                        end
                        local zoneName = DecodeTransferField(fields[1])
                        local mapID = tonumber(fields[2])
                        local x, y = tonumber(fields[3]), tonumber(fields[4])
                        local subzone = DecodeTransferField(fields[5])
                        local label = DecodeTransferField(fields[6])
                        if zoneName == "" or #zoneName > 255 or #subzone > 255
                            or #label > 48
                            or not mapID or mapID < 1 or mapID > 50000 or mapID ~= math.floor(mapID)
                            or not x or not y or x ~= x or y ~= y
                            or x < 0 or x > 1 or y < 0 or y > 1
                            or (fields[7] ~= "0" and fields[7] ~= "1") then
                            return nil, "Invalid location data on line " .. lineNumber .. "."
                        end

                        local spot = {
                            mapID = mapID,
                            x = x,
                            y = y,
                            subzone = subzone,
                            label = label ~= "" and label or nil,
                            favorite = fields[7] == "1" or nil,
                            totalItems = 0,
                            itemsByID = {},
                        }
                        if #fields[8] > 100000 then
                            return nil, "Fish data is too large on line " .. lineNumber .. "."
                        end
                        local itemEntryCount = 0
                        for encodedItem in fields[8]:gmatch("[^,]+") do
                            itemEntryCount = itemEntryCount + 1
                            if itemEntryCount > 512 then
                                return nil, "Too many fish types on line " .. lineNumber .. "."
                            end
                            local values = {}
                            for value in (encodedItem .. ":"):gmatch("(.-):") do
                                table.insert(values, value)
                            end
                            if #values ~= 6 then
                                return nil, "Invalid fish data on line " .. lineNumber .. "."
                            end
                            local itemID = tonumber(values[1])
                            local count = tonumber(values[2])
                            if not itemID or itemID < 1 or itemID > 20000000
                                or itemID ~= math.floor(itemID)
                                or not count or count < 1 or count > 1000000000
                                or count ~= math.floor(count) then
                                return nil, "Invalid fish data on line " .. lineNumber .. "."
                            end
                            if spot.itemsByID[tostring(itemID)] then
                                return nil, "Duplicate fish data on line " .. lineNumber .. "."
                            end
                            local timeBuckets = {}
                            for bucket = 0, 3 do
                                local bucketCount = tonumber(values[bucket + 3])
                                if not bucketCount or bucketCount < 0 or bucketCount > 1000000000
                                    or bucketCount ~= math.floor(bucketCount) then
                                    return nil, "Invalid time data on line " .. lineNumber .. "."
                                end
                                timeBuckets[bucket] = bucketCount
                            end
                            spot.itemsByID[tostring(itemID)] = {
                                name = GetItemInfo(itemID) or ("Item " .. itemID),
                                count = count,
                                timeBuckets = timeBuckets,
                            }
                            spot.totalItems = spot.totalItems + count
                        end
                        if spot.totalItems == 0 then
                            return nil, "A location has no fish records on line " .. lineNumber .. "."
                        end
                        table.insert(imported, { zone = zoneName, spot = spot })
                    end
                end
            end
            if lineNumber == 0 then
                return nil, "The export is empty."
            end
            return imported
        end

        local function ImportFishingLocations(text)
            local imported, errorMessage = ParseFishingLocationExport(text)
            if not imported then return nil, errorMessage end

            local stats = EF.EnsureFishingStats()
            local added, merged = 0, 0
            for _, entry in ipairs(imported) do
                local zone = EF.EnsureZoneFishingStats(stats, entry.zone)
                local spot = entry.spot
                local cellX = math.min(199, math.max(0, math.floor(spot.x * 200)))
                local cellY = math.min(199, math.max(0, math.floor(spot.y * 200)))
                local spotKey = string.format("%d:%d:%d", spot.mapID, cellX, cellY)
                local existing = zone.spots[spotKey]
                if type(existing) ~= "table" then
                    zone.spots[spotKey] = spot
                    added = added + 1
                else
                    existing.favorite = existing.favorite or spot.favorite
                    existing.label = existing.label or spot.label
                    if not existing.subzone or existing.subzone == "" then
                        existing.subzone = spot.subzone
                    end
                    existing.itemsByID = existing.itemsByID or {}
                    for itemID, item in pairs(spot.itemsByID) do
                        local current = existing.itemsByID[itemID]
                        if type(current) ~= "table" then
                            existing.itemsByID[itemID] = item
                        else
                            current.count = math.max(tonumber(current.count) or 0, item.count)
                            current.name = current.name or item.name
                            current.timeBuckets = current.timeBuckets or {}
                            for bucket = 0, 3 do
                                current.timeBuckets[bucket] = math.max(
                                    tonumber(current.timeBuckets[bucket]) or 0,
                                    item.timeBuckets[bucket])
                            end
                        end
                    end
                    existing.totalItems = 0
                    for _, item in pairs(existing.itemsByID) do
                        existing.totalItems = existing.totalItems + (tonumber(item.count) or 0)
                    end
                    merged = merged + 1
                end
            end
            return added, merged
        end

        local transferFrame = CreateFrame("Frame", "EasyFishingLocationTransfer", UIParent, "BackdropTemplate")
        transferFrame:SetSize(560, 430)
        transferFrame:SetPoint("CENTER")
        transferFrame:SetFrameStrata("DIALOG")
        transferFrame:SetClampedToScreen(true)
        transferFrame:EnableMouse(true)
        transferFrame:SetMovable(true)
        transferFrame:RegisterForDrag("LeftButton")
        transferFrame:SetScript("OnDragStart", transferFrame.StartMoving)
        transferFrame:SetScript("OnDragStop", transferFrame.StopMovingOrSizing)
        transferFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        transferFrame:SetBackdropColor(0.02, 0.025, 0.025, 0.96)
        transferFrame:SetBackdropBorderColor(0.48, 0.38, 0.2, 1)
        transferFrame:Hide()

        local transferTitle = transferFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        transferTitle:SetPoint("TOPLEFT", transferFrame, "TOPLEFT", 18, -16)
        transferTitle:SetText("Fishing Location Transfer")

        local transferHelp = transferFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        transferHelp:SetPoint("TOPLEFT", transferTitle, "BOTTOMLEFT", 0, -8)
        transferHelp:SetWidth(510)
        transferHelp:SetJustifyH("LEFT")
        transferHelp:SetText("Export to copy your saved spots. Paste a versioned export here and import it; matching locations merge without double-counting.")

        local transferClose = CreateFrame("Button", nil, transferFrame, "UIPanelCloseButton")
        transferClose:SetPoint("TOPRIGHT", transferFrame, "TOPRIGHT", -4, -4)
        transferClose:SetScript("OnClick", function() transferFrame:Hide() end)

        local transferScroll = CreateFrame("ScrollFrame", nil, transferFrame, "UIPanelScrollFrameTemplate")
        transferScroll:SetPoint("TOPLEFT", transferHelp, "BOTTOMLEFT", 0, -10)
        transferScroll:SetSize(520, 300)
        local transferEditBox = CreateFrame("EditBox", nil, transferScroll)
        transferEditBox:SetMultiLine(true)
        transferEditBox:SetAutoFocus(false)
        transferEditBox:SetFontObject(ChatFontNormal)
        transferEditBox:SetWidth(500)
        transferEditBox:SetHeight(280)
        transferEditBox:SetMaxLetters(2000000)
        transferEditBox:SetTextInsets(8, 8, 8, 8)
        transferEditBox:SetScript("OnTextChanged", function(self)
            local visualLines = 0
            for line in (self:GetText() .. "\n"):gmatch("(.-)\n") do
                visualLines = visualLines + math.max(1, math.ceil(#line / 68))
            end
            self:SetHeight(math.max(280, visualLines * 15 + 16))
            transferScroll:UpdateScrollChildRect()
        end)
        transferEditBox:SetScript("OnEscapePressed", function() transferFrame:Hide() end)
        transferScroll:SetScrollChild(transferEditBox)

        local transferStatus = transferFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        transferStatus:SetPoint("BOTTOMLEFT", transferFrame, "BOTTOMLEFT", 18, 19)
        transferStatus:SetWidth(310)
        transferStatus:SetJustifyH("LEFT")

        local exportSpotsButton = CreateFrame("Button", nil, transferFrame, "UIPanelButtonTemplate")
        exportSpotsButton:SetSize(76, 22)
        exportSpotsButton:SetPoint("BOTTOMRIGHT", transferFrame, "BOTTOMRIGHT", -174, 13)
        exportSpotsButton:SetText("Export")
        exportSpotsButton:SetScript("OnClick", function()
            local exportText, errorMessage = ExportFishingLocations()
            if not exportText then
                transferStatus:SetText(errorMessage)
                return
            end
            transferEditBox:SetText(exportText)
            transferEditBox:SetFocus()
            transferEditBox:HighlightText()
            transferStatus:SetText("Export selected. Press Ctrl+C to copy it.")
        end)

        local importSpotsButton = CreateFrame("Button", nil, transferFrame, "UIPanelButtonTemplate")
        importSpotsButton:SetSize(76, 22)
        importSpotsButton:SetPoint("LEFT", exportSpotsButton, "RIGHT", 4, 0)
        importSpotsButton:SetText("Import")
        importSpotsButton:SetScript("OnClick", function()
            local added, mergedOrError = ImportFishingLocations(transferEditBox:GetText())
            if not added then
                transferStatus:SetText(mergedOrError)
                return
            end
            transferStatus:SetText(string.format("Added %d locations; merged %d existing.", added, mergedOrError))
            RefreshLocationsPage(locationsScroll:GetVerticalScroll())
        end)

        local closeTransferButton = CreateFrame("Button", nil, transferFrame, "UIPanelButtonTemplate")
        closeTransferButton:SetSize(76, 22)
        closeTransferButton:SetPoint("LEFT", importSpotsButton, "RIGHT", 4, 0)
        closeTransferButton:SetText("Close")
        closeTransferButton:SetScript("OnClick", function() transferFrame:Hide() end)

        OpenLocationTransfer = function()
            transferFrame:Show()
            transferEditBox:SetText("")
            transferStatus:SetText("Export to copy locations, or paste an export and import it.")
            transferEditBox:SetFocus()
        end

        local spotTransferButton = CreateFrame("Button", nil, locationsPage, "UIPanelButtonTemplate")
        spotTransferButton:SetSize(102, 22)
        spotTransferButton:SetPoint("RIGHT", atlasZoneDropdown, "LEFT", -4, 0)
        spotTransferButton:SetText("Import / Export")
        spotTransferButton:SetScript("OnClick", OpenLocationTransfer)

        local locationSearch = CreateFrame("EditBox", "EasyFishingLocationSearch",
            locationsPage, "InputBoxTemplate")
        locationSearch:SetSize(134, 20)
        locationSearch:SetPoint("RIGHT", spotTransferButton, "LEFT", -6, 0)
        locationSearch:SetAutoFocus(false)
        locationSearch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Search fishing locations")
            GameTooltip:AddLine("Matches zones, areas, fish names, and item IDs.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        locationSearch:SetScript("OnLeave", function() GameTooltip:Hide() end)
        locationSearch:SetScript("OnTextChanged", function(_, userInput)
            if userInput and RefreshLocationsPage then
                RefreshLocationsPage()
            end
        end)

        local locationRows = {}
        local expandedAreas = {}
        StaticPopupDialogs["EASYFISHING_RENAME_SPOT"] = {
            text = "Enter a name for this fishing location:",
            button1 = ACCEPT,
            button2 = CANCEL,
            hasEditBox = true,
            maxLetters = 48,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(self)
                self.editBox:SetText(self.data.spot.label or "")
                self.editBox:SetFocus()
                self.editBox:HighlightText()
            end,
            OnAccept = function(self)
                if not self.data or not self.data.spot then return end
                local label = self.editBox:GetText():match("^%s*(.-)%s*$")
                self.data.spot.label = label ~= "" and label or nil
                RefreshLocationsPage(self.data.scroll)
            end,
            EditBoxOnEnterPressed = function(self)
                StaticPopup_OnClick(self:GetParent(), 1)
            end,
        }
        local function SpotMatchesSearch(zoneName, spot)
            local query = (locationSearch:GetText() or ""):lower():match("^%s*(.-)%s*$")
            if query == "" then return true end
            if zoneName:lower():find(query, 1, true)
                or (spot.subzone or ""):lower():find(query, 1, true)
                or (spot.label or ""):lower():find(query, 1, true) then
                return true
            end
            for itemID, item in pairs(spot.itemsByID or {}) do
                local itemName = type(item) == "table" and item.name or ""
                if tostring(itemID):find(query, 1, true)
                    or (itemName:lower():find(query, 1, true)) then
                    return true
                end
            end
            return false
        end
        RefreshLocationsPage = function(scrollOffset)
            for _, row in ipairs(locationRows) do
                row:Hide()
            end

            local spots = {}
            local stats = EF.EnsureFishingStats()
            for zoneName, zoneStats in pairs(stats.zones) do
                if atlasZoneFilter == "All zones" or atlasZoneFilter == "Favorites"
                    or zoneName == atlasZoneFilter then
                    for _, spot in pairs(zoneStats.spots or {}) do
                        if type(spot) == "table" and type(spot.itemsByID) == "table"
                            and (atlasZoneFilter ~= "Favorites" or spot.favorite)
                            and SpotMatchesSearch(zoneName, spot) then
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
                if atlasZoneFilter == "Favorites" then
                    locationsDescription:SetText("No matching favorites yet. Favorite a recorded location to keep it here.")
                elseif atlasZoneFilter == "All zones" then
                    locationsDescription:SetText("No fishing locations recorded yet. Your first confirmed catch will add one.")
                else
                    locationsDescription:SetText("No fishing locations recorded in " .. atlasZoneFilter .. " yet.")
                end
                locationsContent:SetHeight(1)
                locationsScroll:SetVerticalScroll(0)
                locationsScroll:UpdateScrollChildRect()
                UpdateScrollBarVisibility(locationsScroll)
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
            UpdateScrollBarVisibility(locationsScroll)
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
                    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
                    row.coordinateLabel:SetWidth(100)
                    row.coordinateLabel:SetPoint("TOPRIGHT", row, "TOPRIGHT", -36, -8)
                    row.coordinateLabel:SetJustifyH("RIGHT")
                    row.coordinateLabel:SetTextColor(0.72, 0.76, 0.76)

                    row.favoriteButton = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    row.favoriteButton:SetSize(22, 22)
                    row.favoriteButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -3)
                    row.favoriteButton:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Favorite location")
                        GameTooltip:AddLine("Show it in the Favorites filter.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    row.favoriteButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
                    row.favoriteButton:Hide()
                    row.areaLabel:SetText(areaLabel)
                    row.coordinateLabel:SetText((expandedAreas[group.key] and "- " or "+ ")
                        .. #group.spots .. " locations")
                    row.catchLabel:SetText(string.format("%d items recorded", group.totalItems))
                    row:SetBackdropColor(0.08, 0.07, 0.04, 0.82)
                    row:SetBackdropBorderColor(0.42, 0.34, 0.16, 1)
                else
                    row.favoriteButton:SetChecked(not not spot.favorite)
                    row.favoriteButton:SetScript("OnClick", function(button)
                        spot.favorite = button:GetChecked() and true or nil
                        RefreshLocationsPage(locationsScroll:GetVerticalScroll())
                    end)
                    row.favoriteButton:Show()
                    row.areaLabel:SetText(spot.label or (entry.index and ("Location " .. entry.index) or areaLabel))
                    row.coordinateLabel:SetText(string.format("%.1f, %.1f", spot.x * 100, spot.y * 100))
                    row.catchLabel:SetText(#fishSummary > 0 and table.concat(fishSummary, "  |  ") or "No item counts")
                    row:SetBackdropColor(0.04, 0.05, 0.05, 0.72)
                    row:SetBackdropBorderColor(0.24, 0.27, 0.27, 1)
                end
                row:SetScript("OnClick", function(_, button)
                    if entry.kind == "spot" and button == "RightButton" then
                        StaticPopup_Show("EASYFISHING_RENAME_SPOT", nil, nil, {
                            spot = spot,
                            scroll = locationsScroll:GetVerticalScroll(),
                        })
                        return
                    end
                    if entry.kind == "area" then
                        if button == "RightButton" then return end
                        local currentScroll = locationsScroll:GetVerticalScroll()
                        expandedAreas[group.key] = not expandedAreas[group.key]
                        RefreshLocationsPage(currentScroll)
                        return
                    end
                    local nativeWaypointSet = false
                    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint
                        and UiMapPoint and UiMapPoint.CreateFromCoordinates
                        and C_Map.CanSetUserWaypointOnMap(spot.mapID) then
                        local point = UiMapPoint.CreateFromCoordinates(spot.mapID, spot.x, spot.y)
                        nativeWaypointSet = point and C_Map.SetUserWaypoint(point) or false
                    end
                    local locationLabel = areaLabel
                        .. (entry.index and (" / Location " .. entry.index) or "")
                    local tomTomWaypointSet = SetTomTomWaypoint(spot, locationLabel)
                    if not nativeWaypointSet and not tomTomWaypointSet then
                        print("EasyFishing: neither the map nor TomTom can set a waypoint here.")
                        return
                    end
                    characterDB.lastFishingSpot = {
                        mapID = spot.mapID,
                        x = spot.x,
                        y = spot.y,
                        label = locationLabel,
                    }
                    if nativeWaypointSet and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                    end
                    if nativeWaypointSet and WorldMapFrame and WorldMapFrame.SetMapID then
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
                        GameTooltip:AddLine("Left-click to set a waypoint; right-click to rename.",
                            0.75, 0.75, 0.75, true)
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
            local zones = { "All zones", "Favorites" }
            local zoneNames = {}
            for zoneName in pairs(EF.EnsureFishingStats().zones) do
                table.insert(zoneNames, zoneName)
            end
            table.sort(zoneNames)
            for _, zoneName in ipairs(zoneNames) do
                table.insert(zones, zoneName)
            end
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

        local trainingTitle = ContentHeading(
            guideTrainingView, "Training and Leveling", guideTrainingView, "TOPLEFT", 0, 0, 300)
        local campTitle = ContentHeading(
            guideTrainingView, "Lures and Campsite Crafts", guideTrainingView, "TOPLEFT", 320, 0, 300)

        local trainingRankRows = {}
        for index, rank in ipairs(EF.Data.FISHING_RANKS) do
            local row = CreateFrame("Frame", nil, guideTrainingView)
            row.rank = rank
            row:SetSize(300, 80)
            row:SetPoint("TOPLEFT", trainingTitle, "BOTTOMLEFT", 0, -8 - ((index - 1) * 86))

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

            row.progressBack = row:CreateTexture(nil, "BACKGROUND")
            row.progressBack:SetColorTexture(0.20, 0.18, 0.13, 0.85)
            row.progressBack:SetSize(292, 4)
            row.progressBack:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, -4)

            row.progress = row:CreateTexture(nil, "ARTWORK")
            row.progress:SetColorTexture(0.92, 0.63, 0.12, 1)
            row.progress:SetSize(2, 4)
            row.progress:SetPoint("BOTTOMLEFT", row.progressBack, "BOTTOMLEFT", 0, 0)
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

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.detail:SetWidth(185)
            row.detail:SetJustifyH("LEFT")
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

        local campCraftTitle = ContentHeading(
            guideTrainingView, "Campsite Recipes", lureRows[#lureRows], "BOTTOMLEFT", 0, -8, 300)

        local campRows = {}
        for index, campItem in ipairs(EF.Data.FISHING_CAMP_ITEMS) do
            local row = CreateFrame("Frame", nil, guideTrainingView)
            row.campItem = campItem
            row:SetSize(300, 28)
            row:SetPoint("TOPLEFT", campCraftTitle, "BOTTOMLEFT", 0, -6 - ((index - 1) * 30))
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            row.icon:SetTexture(GetItemTexture(campItem.id) or "Interface\\Icons\\INV_Misc_QuestionMark")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
            row.name:SetWidth(185)
            row.name:SetJustifyH("LEFT")
            row.name:SetText(campItem.name)

            row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.count:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
            row.count:SetWidth(78)
            row.count:SetJustifyH("RIGHT")

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.detail:SetWidth(185)
            row.detail:SetJustifyH("LEFT")
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

        local gearTitle = ContentHeading(
            guideGearView, "Fishing Skill Bonuses", guideGearView, "TOPLEFT", 0, 0, 300)

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
            row.name:SetWordWrap(false)
            row.name:SetText(boost.displayName or boost.name)

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

        local rewardsTitle = ContentHeading(
            guideGearView, "Find Fish and Quest Rewards", guideGearView, "TOPLEFT", 320, 0, 300)

        local findFish = EF.Data.FISHING_ABILITIES[1]
        local rewardEntries = {
            {
                kind = "ability",
                id = findFish.id,
                iconType = "spell",
                name = findFish.name,
                value = "Spellbook",
                detail = "Skill 1+  |  Pools on minimap  |  " .. findFish.cooldown .. " cooldown",
                details = findFish.details,
            },
        }
        for _, quest in ipairs(EF.Data.FISHING_QUEST_REWARDS) do
            table.insert(rewardEntries, {
                kind = "quest",
                id = quest.rewardItemID or quest.rewardSpellID,
                iconType = quest.rewardSpellID and "spell" or "item",
                name = quest.rewardName or quest.reward,
                value = quest.rewardValue or "Reward",
                detail = quest.sourceLabel or quest.name,
                quest = quest,
            })
        end

        local rewardScroll = CreateFrame("ScrollFrame", "EasyFishingQuestRewardsScroll",
            guideGearView, "UIPanelScrollFrameTemplate")
        rewardScroll:SetPoint("TOPLEFT", rewardsTitle, "BOTTOMLEFT", 0, -8)
        rewardScroll:SetSize(300, math.min(#rewardEntries, 9) * 36)
        local rewardContent = CreateFrame("Frame", nil, rewardScroll)
        rewardContent:SetSize(280, #rewardEntries * 36)
        rewardScroll:SetScrollChild(rewardContent)

        local rewardRows = {}
        for index, entry in ipairs(rewardEntries) do
            local row = CreateFrame("Button", nil, rewardContent)
            row:SetSize(278, 34)
            row:SetPoint("TOPLEFT", rewardContent, "TOPLEFT", 0, -((index - 1) * 36))
            row:EnableMouse(true)

            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(24, 24)
            row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
            local rewardIcon = entry.iconType == "spell"
                and GetSpellIcon(entry.id) or GetItemTexture(entry.id)
            row.icon:SetTexture(rewardIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
            row.name:SetWidth(160)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.name:SetText(entry.name)

            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
            row.value:SetWidth(82)
            row.value:SetJustifyH("RIGHT")
            row.value:SetText(entry.value)
            row.value:SetTextColor(1, 0.82, 0)

            row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
            row.detail:SetWidth(244)
            row.detail:SetJustifyH("LEFT")
            row.detail:SetText(entry.detail)

            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if entry.kind == "ability" then
                    GameTooltip:SetText(entry.name)
                    GameTooltip:AddLine(entry.details, 1, 1, 1, true)
                    GameTooltip:AddLine("Cooldown: " .. entry.value, 0.75, 0.75, 0.75)
                    GameTooltip:AddLine("Click to open the spellbook.", 0.75, 0.75, 0.75)
                else
                    GameTooltip:SetText(entry.quest.name)
                    GameTooltip:AddLine(entry.quest.details, 1, 1, 1, true)
                    GameTooltip:AddLine("Reward: " .. entry.quest.reward, 0.75, 0.75, 0.75, true)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            if entry.kind == "ability" then
                row:SetScript("OnClick", function()
                    if type(ToggleSpellBook) == "function" then
                        ToggleSpellBook(BOOKTYPE_SPELL or "spell")
                    elseif SpellBookFrame then
                        SpellBookFrame:Show()
                    else
                        print("EasyFishing: the spellbook is unavailable on this client.")
                    end
                end)
            end
            rewardRows[index] = row
        end
        rewardScroll:UpdateScrollChildRect()
        UpdateScrollBarVisibility(rewardScroll)
        rewardScroll:SetVerticalScroll(0)

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
        trainerHeaderSide:SetPoint("TOPLEFT", trainerHeaderName, "TOPLEFT", 170, 0)
        trainerHeaderSide:SetText("Faction")

        local trainerHeaderLocation = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderLocation:SetPoint("TOPLEFT", trainerHeaderName, "TOPLEFT", 242, 0)
        trainerHeaderLocation:SetText("Town / Zone")

        local trainerHeaderCoordinates = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderCoordinates:SetPoint("TOPLEFT", trainerHeaderName, "TOPLEFT", 432, 0)
        trainerHeaderCoordinates:SetText("Coordinates")

        local trainerHeaderWaypoint = guideTrainersView:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        trainerHeaderWaypoint:SetPoint("TOPLEFT", trainerHeaderName, "TOPLEFT", 500, 0)
        trainerHeaderWaypoint:SetText("Map")

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
                    trainer.location or "", trainer.zone, trainer.level))
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
            UpdateScrollBarVisibility(trainerScroll)
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
                    row.name:SetWidth(155)
                    row.name:SetJustifyH("LEFT")
                    row.name:SetWordWrap(false)

                    row.role = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.role:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
                    row.role:SetWidth(155)
                    row.role:SetJustifyH("LEFT")
                    row.role:SetTextColor(0.72, 0.72, 0.72)

                    row.side = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.side:SetPoint("TOPLEFT", row, "TOPLEFT", 170, -12)
                    row.side:SetWidth(66)
                    row.side:SetJustifyH("LEFT")

                    row.location = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.location:SetPoint("TOPLEFT", row, "TOPLEFT", 242, -3)
                    row.location:SetWidth(180)
                    row.location:SetJustifyH("LEFT")
                    row.location:SetWordWrap(false)

                    row.zone = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.zone:SetPoint("TOPLEFT", row.location, "BOTTOMLEFT", 0, -1)
                    row.zone:SetWidth(180)
                    row.zone:SetJustifyH("LEFT")
                    row.zone:SetTextColor(0.72, 0.72, 0.72)
                    row.zone:SetWordWrap(false)

                    row.coordinates = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.coordinates:SetPoint("TOPLEFT", row, "TOPLEFT", 432, -12)
                    row.coordinates:SetWidth(64)
                    row.coordinates:SetJustifyH("RIGHT")

                    row.waypointButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.waypointButton:SetSize(84, 22)
                    row.waypointButton:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -8)
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
                row.location:SetText(trainer.location and trainer.location ~= ""
                    and trainer.location or trainer.zone)
                row.zone:SetText(trainer.location and trainer.location ~= "" and trainer.zone or "")
                row.coordinates:SetText(trainer.x and trainer.y
                    and string.format("%.1f, %.1f", trainer.x, trainer.y) or "Not listed")
                local hasWaypoint = tonumber(trainer.mapID)
                    and tonumber(trainer.x) and tonumber(trainer.y)
                    and trainer.x >= 0 and trainer.x <= 100
                    and trainer.y >= 0 and trainer.y <= 100
                if hasWaypoint then
                    local npc = trainer
                    row.waypointButton:SetText("Waypoint")
                    row.waypointButton:Enable()
                    row.waypointButton:SetScript("OnClick", function()
                        local x, y = npc.x / 100, npc.y / 100
                        local nativeWaypointSet = false
                        if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint
                            and UiMapPoint and UiMapPoint.CreateFromCoordinates
                            and C_Map.CanSetUserWaypointOnMap(npc.mapID) then
                            local point = UiMapPoint.CreateFromCoordinates(npc.mapID, x, y)
                            nativeWaypointSet = point and C_Map.SetUserWaypoint(point) or false
                        end
                        local label = npc.name .. " - " .. (npc.location or npc.zone)
                        local tomTomWaypointSet = SetTomTomWaypoint({
                            mapID = npc.mapID,
                            x = x,
                            y = y,
                        }, label)
                        if nativeWaypointSet and C_SuperTrack
                            and C_SuperTrack.SetSuperTrackedUserWaypoint then
                            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                        end
                        if not nativeWaypointSet and not tomTomWaypointSet then
                            print("EasyFishing: neither the map nor TomTom can set this NPC waypoint.")
                        end
                    end)
                    row.waypointButton:SetScript("OnEnter", function(button)
                        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Set waypoint for " .. npc.name)
                        GameTooltip:AddLine(string.format("Approximate zone coordinates: %.1f, %.1f",
                            npc.x, npc.y), 0.75, 0.75, 0.75)
                        GameTooltip:Show()
                    end)
                    row.waypointButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
                else
                    row.waypointButton:SetText("No map")
                    row.waypointButton:Disable()
                    row.waypointButton:SetScript("OnClick", nil)
                    row.waypointButton:SetScript("OnEnter", function(button)
                        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Waypoint unavailable")
                        GameTooltip:AddLine("No verified map ID and coordinates are available for this NPC.",
                            0.75, 0.75, 0.75, true)
                        GameTooltip:Show()
                    end)
                    row.waypointButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
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
                local currentRank
                for _, row in ipairs(trainingRankRows) do
                    if skill >= row.rank.minimumSkill
                        and (not row.rank.nextTraining or skill < row.rank.nextTraining) then
                        currentRank = row.rank
                        break
                    end
                end
                if currentRank then
                    local nextStep = currentRank.nextTraining
                        and string.format("  |  Next rank at %d", currentRank.nextTraining)
                        or (skill >= currentRank.maximumSkill and "  |  Skill cap reached" or "")
                    guideSkillText:SetText(string.format("Fishing skill: %d  |  %s (%s)%s",
                        skill, currentRank.name, currentRank.range, nextStep))
                elseif skill < EF.Data.FISHING_RANKS[1].minimumSkill then
                    guideSkillText:SetText(string.format("Fishing skill: %d  |  Learn Apprentice at skill 1", skill))
                else
                    guideSkillText:SetText(string.format("Fishing skill: %d", skill))
                end
            else
                guideSkillText:SetText("Fishing skill is unavailable. Train Fishing to see your current bracket and next step.")
            end

            for _, row in ipairs(trainingRankRows) do
                local isCurrent = skill and skill >= row.rank.minimumSkill
                    and (not row.rank.nextTraining or skill < row.rank.nextTraining)
                local isComplete = skill and skill >= row.rank.maximumSkill and not isCurrent
                local progress = skill and math.max(0, math.min(1,
                    (skill - row.rank.minimumSkill) / (row.rank.maximumSkill - row.rank.minimumSkill))) or 0
                row.progress:SetWidth(math.max(2, 292 * progress))
                if isCurrent then
                    row.status:Show()
                    row.title:SetTextColor(1, 0.82, 0)
                    row.range:SetTextColor(1, 0.82, 0)
                    row.detail:SetTextColor(1, 1, 1)
                    row.status:SetText("CURRENT")
                    row.status:SetTextColor(1, 0.82, 0)
                    row.progress:SetColorTexture(0.96, 0.68, 0.14, 1)
                elseif isComplete then
                    row.status:Show()
                    row.status:SetText("DONE")
                    row.status:SetTextColor(0.55, 0.78, 0.38)
                    row.title:SetTextColor(0.72, 0.82, 0.62)
                    row.range:SetTextColor(0.72, 0.82, 0.62)
                    row.detail:SetTextColor(0.78, 0.82, 0.74)
                    row.progress:SetColorTexture(0.42, 0.7, 0.28, 0.7)
                else
                    row.status:Hide()
                    row.title:SetTextColor(0.72, 0.72, 0.72)
                    row.range:SetTextColor(0.72, 0.72, 0.72)
                    row.detail:SetTextColor(0.78, 0.78, 0.78)
                    row.progress:SetColorTexture(0.4, 0.34, 0.22, 0.55)
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
            SelectOptionsPageTab("settings")
            statisticsPage:Hide()
            locationsPage:Hide()
            guidePage:Hide()
            settingsPage:Show()
        end)
        statisticsTab:SetScript("OnClick", function()
            SelectOptionsPageTab("stats")
            settingsPage:Hide()
            locationsPage:Hide()
            guidePage:Hide()
            RefreshStatisticsPage()
            statisticsPage:Show()
        end)
        locationsTab:SetScript("OnClick", function()
            SelectOptionsPageTab("atlas")
            settingsPage:Hide()
            statisticsPage:Hide()
            guidePage:Hide()
            RefreshLocationsPage()
            locationsPage:Show()
        end)
        guideTab:SetScript("OnClick", function()
            SelectOptionsPageTab("guide")
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
            if page == "stats" or page == "atlas" or page == "guide" then
                SelectOptionsPageTab(page)
            else
                page = "settings"
                SelectOptionsPageTab(page)
            end
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
                ShowOptionsPage("guide")
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
            elseif command == "toggle" then
                ToggleFishingOutfit()
            else
                print("EasyFishing commands: /ef [menu|stats|atlas|guide|watch|equip|restore|toggle|link fish|link location|link gear]")
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

