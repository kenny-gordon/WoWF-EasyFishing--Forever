local addonName, EF = ...

local function AddText(parent, font, width, anchor, relativePoint, x, y)
    local text = parent:CreateFontString(nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", anchor, relativePoint, x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function SetTooltip(frame, title, detail)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if detail then GameTooltip:AddLine(detail, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function GetItemIcon(itemID)
    local icon
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, _, icon = C_Item.GetItemInfoInstant(tonumber(itemID) or itemID)
    elseif type(GetItemInfoInstant) == "function" then
        _, _, _, _, icon = GetItemInfoInstant(tonumber(itemID) or itemID)
    end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function FishingState()
    if EF.IsFishingPaused() then return "Fishing paused" end
    if InCombatLockdown() then return "In combat" end
    if EF.IsLootOpen() then return "Looting" end
    if not EF.IsFishingPoleEquipped() then return "No fishing pole equipped" end
    if EF.IsFishingChannelActive() then return "Fishing" end
    if UnitCastingInfo and UnitCastingInfo("player") or UnitChannelInfo("player") then return "Casting" end
    if GetUnitSpeed("player") > 0 then return "Moving" end
    local button = EF.GetButtonOption(EasyFishingDB.doubleClickButton).label
    local clickPattern = EasyFishingDB.castClickMode == "SingleClick" and "Single-click " or "Double-click "
    return clickPattern .. button
end

local function UpdateScrollLayout(scroll)
    scroll:UpdateScrollChildRect()
    if scroll.ScrollBar then scroll.ScrollBar:SetShown(scroll:GetVerticalScrollRange() > 0) end
end

local function GetFishAlmanacEntries()
    local fishList = EF.GetFishJournal()
    local fishByID = {}
    for _, fish in ipairs(fishList) do
        fish.caught = (tonumber(fish.lifetimeCount) or 0) > 0
            or (tonumber(fish.locationCount) or 0) > 0
        fishByID[fish.id] = fish
    end
    for _, entry in ipairs(EF.Data.FISH_ALMANAC or {}) do
        local key = tostring(entry.id)
        local fish = fishByID[key]
        if not fish then
            fish = {
                id = key,
                name = entry.name,
                count = 0,
                lifetimeCount = 0,
                locationCount = 0,
                locations = {},
                timeBuckets = {},
                datesByDay = {},
                caught = false,
            }
            fishByID[key] = fish
            table.insert(fishList, fish)
        end
        fish.almanac = entry
        if not fish.name or fish.name:match("^Item %d+$") then fish.name = entry.name end
    end
    table.sort(fishList, function(first, second)
        if first.caught ~= second.caught then return first.caught end
        if first.count == second.count then return first.name < second.name end
        return first.count > second.count
    end)
    return fishList
end

function EF.CreateJournalPage(window)
    local page = CreateFrame("Frame", "EasyFishingJournalPage", window)
    page:Hide()
    local heading = AddText(page, "GameFontNormalLarge", 200, page, "TOPLEFT", 16, -16)
    heading:SetText("Fish Almanac")
    local search = CreateFrame("EditBox", "EasyFishingJournalSearch", page, "InputBoxTemplate")
    search:SetSize(192, 20)
    search:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -12)
    search:SetAutoFocus(false)
    search:SetMaxLetters(80)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local fishScroll = CreateFrame("ScrollFrame", "EasyFishingJournalFishScroll", page, "UIPanelScrollFrameTemplate")
    fishScroll:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -12)
    fishScroll:SetSize(190, 420)
    local fishContent = CreateFrame("Frame", nil, fishScroll)
    fishContent:SetSize(184, 1)
    fishScroll:SetScrollChild(fishContent)

    local fishIcon = page:CreateTexture(nil, "ARTWORK")
    fishIcon:SetSize(32, 32)
    fishIcon:SetPoint("TOPLEFT", page, "TOPLEFT", 238, -14)
    local title = AddText(page, "GameFontNormalLarge", 370, page, "TOPLEFT", 278, -16)
    local summary = AddText(page, "GameFontHighlightSmall", 410, title, "BOTTOMLEFT", 0, -10)
    summary:SetWordWrap(true)
    title:SetWordWrap(false)
    local whereButton = CreateFrame("Button", "EasyFishingJournalWhereButton", page, "UIPanelButtonTemplate")
    whereButton:SetSize(132, 24)
    whereButton:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
    whereButton:SetText("Where to Catch")
    SetTooltip(whereButton, "Where to Catch", "Open the reported habitat and show your recorded hotspots.")
    local locationScroll = CreateFrame("ScrollFrame", "EasyFishingJournalLocationScroll", page, "UIPanelScrollFrameTemplate")
    locationScroll:SetPoint("TOPLEFT", whereButton, "BOTTOMLEFT", 0, -10)
    locationScroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -32, 60)
    local locationContent = CreateFrame("Frame", nil, locationScroll)
    locationContent:SetSize(392, 1)
    locationScroll:SetScrollChild(locationContent)
    local caveat = AddText(page, "GameFontDisableSmall", 620, page, "BOTTOMLEFT", 16, 28)
    caveat:SetText("Recorded catches are observations, not guaranteed availability. Dates use UTC; time buckets use server time.")
    caveat:SetWordWrap(true)

    local fishRows, locationRows, selectedID, displayedID = {}, {}, nil, nil
    local selectedFish
    local RefreshJournal
    local function ShowFish(fish)
        selectedFish = fish
        whereButton:SetEnabled(fish ~= nil)
        for _, row in ipairs(locationRows) do row:Hide() end
        if not fish or displayedID ~= fish.id then locationScroll:SetVerticalScroll(0) end
        displayedID = fish and fish.id or nil
        if not fish then
            fishIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            fishIcon:SetDesaturated(false)
            fishIcon:SetAlpha(1)
            title:SetText(search:GetText():match("%S") and "No matching fish" or "No recorded catches")
            summary:SetText("")
            locationContent:SetHeight(1)
            UpdateScrollLayout(locationScroll)
            return
        end
        selectedID = fish.id
        fishIcon:SetTexture(GetItemIcon(fish.id))
        fishIcon:SetDesaturated(not fish.caught)
        fishIcon:SetAlpha(fish.caught and 1 or 0.35)
        title:SetText(fish.name)
        title:SetWordWrap(false)
        if not fish.caught then
            local entry = fish.almanac
            summary:SetText(string.format("No personal catches yet\nReported waters: %s\n%s\nSource: %s. Exact hotspots appear after recorded catches.",
                entry.zones or entry.zone, entry.hint, entry.source))
            locationContent:SetHeight(1)
            UpdateScrollLayout(locationScroll)
            return
        end
        local details = { string.format("Character catches: %d  |  At saved locations: %d\n%d locations",
            fish.lifetimeCount, fish.locationCount, #fish.locations) }
        local zoneCounts, zones = {}, {}
        for _, entry in ipairs(fish.locations) do
            zoneCounts[entry.zone] = (zoneCounts[entry.zone] or 0) + entry.count
        end
        for zone, count in pairs(zoneCounts) do
            table.insert(zones, { name = zone, count = count })
        end
        table.sort(zones, function(first, second)
            if first.count == second.count then return first.name < second.name end
            return first.count > second.count
        end)
        local zoneShares = {}
        for index = 1, math.min(4, #zones) do
            local zone = zones[index]
            table.insert(zoneShares, string.format("%s %.1f%%", zone.name,
                zone.count * 100 / fish.locationCount))
        end
        if #zones > 4 then table.insert(zoneShares, string.format("+%d more", #zones - 4)) end
        if #zoneShares > 0 then
            table.insert(details, "Zone share: " .. table.concat(zoneShares, "  |  "))
        end
        local times = {}
        for bucket = 0, 3 do
            local count = fish.timeBuckets[bucket] or 0
            if count > 0 then table.insert(times, string.format("%02d-%02d: %d", bucket * 6, bucket * 6 + 6, count)) end
        end
        if #times > 0 then table.insert(details, "Server time: " .. table.concat(times, "  |  ")) end
        local days, months = {}, {}
        for day, count in pairs(fish.datesByDay) do
            table.insert(days, day)
            local month = day:sub(1, 7)
            months[month] = (months[month] or 0) + count
        end
        table.sort(days)
        if #days > 0 then
            table.insert(details, "Catch dates (UTC): " .. days[1] .. " to " .. days[#days])
            local datedCatches = {}
            for day, count in pairs(fish.datesByDay) do
                table.insert(datedCatches, { day = day, count = count })
            end
            table.sort(datedCatches, function(first, second) return first.day > second.day end)
            local recentDays = {}
            for index = 1, math.min(5, #datedCatches) do
                local entry = datedCatches[index]
                table.insert(recentDays, string.format("%s (%d)", entry.day, entry.count))
            end
            table.insert(details, "Recent catches: " .. table.concat(recentDays, "  |  "))
            local monthNames = {}
            for month in pairs(months) do table.insert(monthNames, month) end
            table.sort(monthNames)
            local recentMonths = {}
            for index = math.max(1, #monthNames - 2), #monthNames do
                local month = monthNames[index]
                table.insert(recentMonths, month .. ": " .. months[month])
            end
            table.insert(details, "Recent months: " .. table.concat(recentMonths, "  |  "))
        else
            table.insert(details, "No catch dates recorded yet")
        end
        summary:SetText(table.concat(details, "\n"))
        for index, entry in ipairs(fish.locations) do
            local row = locationRows[index]
            if not row then
                row = CreateFrame("Button", nil, locationContent, "UIPanelButtonTemplate")
                row:SetSize(390, 38)
                row:GetFontString():SetWidth(374)
                row:GetFontString():SetWordWrap(false)
                locationRows[index] = row
            end
            local spot = entry.spot
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", locationContent, "TOPLEFT", 0, -((index - 1) * 42))
            local percent = fish.locationCount > 0 and entry.count * 100 / fish.locationCount or 0
            row:SetText(string.format("%s  %.1f, %.1f  |  %d (%.1f%%)", entry.zone,
                (spot.x or 0) * 100, (spot.y or 0) * 100, entry.count, percent))
            row:SetScript("OnClick", function()
                EF.SetFishingWaypoint(spot, fish.name .. " - " .. entry.zone)
            end)
            SetTooltip(row, spot.label or entry.zone,
                string.format("%s\n%d of %d saved-location catches (%.1f%%)", spot.subzone or "",
                    entry.count, fish.locationCount, percent))
            row:Show()
        end
        locationContent:SetHeight(math.max(1, #fish.locations * 42))
        UpdateScrollLayout(locationScroll)
    end

    RefreshJournal = function()
        for _, row in ipairs(fishRows) do row:Hide() end
        local query = (search:GetText() or ""):lower():match("^%s*(.-)%s*$")
        local fishList = {}
        for _, fish in ipairs(GetFishAlmanacEntries()) do
            local habitatText = fish.almanac
                and (fish.almanac.zone .. " " .. fish.almanac.habitat .. " "
                    .. (fish.almanac.zones or "") .. " " .. fish.almanac.hint) or ""
            if query == "" or fish.name:lower():find(query, 1, true)
                or fish.id:find(query, 1, true) or habitatText:lower():find(query, 1, true) then
                table.insert(fishList, fish)
            end
        end
        local selected
        for index, fish in ipairs(fishList) do
            local row = fishRows[index]
            if not row then
                row = CreateFrame("Button", nil, fishContent)
                row:SetSize(182, 32)
                row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(22, 22)
                row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
                row.nameText:SetWidth(105)
                row.nameText:SetJustifyH("LEFT")
                row.nameText:SetWordWrap(false)
                row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.countText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                row.countText:SetWidth(36)
                row.countText:SetJustifyH("RIGHT")
                fishRows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", fishContent, "TOPLEFT", 0, -((index - 1) * 36))
            row.fishID = fish.id
            row.caught = fish.caught
            row.icon:SetTexture(GetItemIcon(fish.id))
            row.icon:SetDesaturated(not fish.caught)
            row.icon:SetAlpha(fish.caught and 1 or 0.35)
            row.nameText:SetText(fish.name)
            row.nameText:SetTextColor(fish.id == selectedID and 1 or 0.9,
                fish.id == selectedID and 0.82 or 0.9, fish.id == selectedID and 0 or 0.9)
            row.countText:SetText(fish.caught and tostring(fish.count) or "")
            row:SetScript("OnClick", function() selectedID = fish.id; RefreshJournal() end)
            if fish.caught then
                SetTooltip(row, fish.name, string.format("Item %s  |  %d character catches  |  %d at saved locations",
                    fish.id, fish.lifetimeCount, fish.locationCount))
            else
                SetTooltip(row, fish.name, "Not caught yet. " .. fish.almanac.hint .. "\n" .. fish.almanac.source)
            end
            row:Show()
            if fish.id == selectedID then selected = fish end
        end
        selected = selected or fishList[1]
        for index, row in ipairs(fishRows) do
            if fishList[index] then row:SetEnabled(not selected or fishList[index].id ~= selected.id) end
        end
        fishContent:SetHeight(math.max(1, #fishList * 36))
        UpdateScrollLayout(fishScroll)
        ShowFish(selected)
    end
    whereButton:SetScript("OnClick", function()
        if selectedFish then EF.ShowFishAlmanacMap(selectedFish) end
    end)
    search:SetScript("OnTextChanged", function() fishScroll:SetVerticalScroll(0); RefreshJournal() end)
    page:SetScript("OnShow", RefreshJournal)
    page:RegisterEvent("LOOT_READY")
    page:RegisterEvent("LOOT_OPENED")
    page:SetScript("OnEvent", function() if page:IsShown() then RefreshJournal() end end)
    EF.RefreshJournal = RefreshJournal
    EF.OpenFishJournal = function(itemID)
        selectedID = tostring(itemID)
        search:SetText("")
        search:ClearFocus()
        EF.OpenWindow("journal")
        RefreshJournal()
    end
    return page
end

function EF.InitializeFishingTools()
    local characterDB = EF.GetCharacterDB()
    local controls = CreateFrame("Frame", "EasyFishingControls", UIParent, "BackdropTemplate")
    controls:SetSize(350, 96)
    controls:SetFrameStrata("MEDIUM")
    controls:SetClampedToScreen(true)
    controls:SetMovable(true)
    controls:EnableMouse(true)
    controls:RegisterForDrag("MiddleButton")
    controls:SetPoint("CENTER", UIParent, "CENTER", characterDB.controlsX or 0, characterDB.controlsY or -220)
    controls:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    controls:SetBackdropColor(0, 0, 0, 0.9)
    controls:SetBackdropBorderColor(1, 1, 1, 1)
    controls:SetScript("OnDragStart", function(self) self:StartMoving() end)
    controls:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local centerX, centerY = self:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        characterDB.controlsX, characterDB.controlsY = centerX - parentX, centerY - parentY
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", characterDB.controlsX, characterDB.controlsY)
    end)
    SetTooltip(controls, "EasyFishing", "Middle-click and drag to move")
    local titleIcon = controls:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(16, 16)
    titleIcon:SetPoint("TOPLEFT", controls, "TOPLEFT", 12, -10)
    titleIcon:SetTexture("Interface\\Icons\\Trade_Fishing")
    local title = AddText(controls, "GameFontNormal", 104, titleIcon, "TOPRIGHT", 6, 0)
    title:SetText("EASYFISHING")
    local state = controls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    state:SetPoint("TOPRIGHT", controls, "TOPRIGHT", -12, -12)
    state:SetWidth(194)
    state:SetJustifyH("RIGHT")
    state:SetWordWrap(false)
    local divider = controls:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.55, 0.55, 0.55, 0.5)
    divider:SetSize(326, 1)
    divider:SetPoint("TOPLEFT", controls, "TOPLEFT", 12, -34)
    local enchantText = AddText(controls, "GameFontHighlightSmall", 190, divider, "BOTTOMLEFT", 0, -9)
    enchantText:SetWordWrap(false)
    local lureText = controls:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lureText:SetPoint("TOPRIGHT", controls, "TOPRIGHT", -12, -46)
    lureText:SetWidth(132)
    lureText:SetJustifyH("RIGHT")
    lureText:SetWordWrap(false)
    local pauseButton
    for index, entry in ipairs({
        { label = "Pause", tooltip = "Pause EasyFishing casts", action = function() EF.SetFishingPaused(not EF.IsFishingPaused()) end },
        { label = "Toggle Gear", tooltip = "Swap fishing gear and previous gear", action = EF.ToggleFishingOutfit },
        { label = "Open", tooltip = "Open fishing tools", action = function() EF.OpenWindow("home") end },
    }) do
        local button = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
        button:SetSize(102, 24)
        button:SetPoint("BOTTOMLEFT", controls, "BOTTOMLEFT", 12 + (index - 1) * 112, 10)
        button:SetText(entry.label)
        button:SetScript("OnClick", entry.action)
        SetTooltip(button, entry.label, entry.tooltip)
        if index == 1 then pauseButton = button end
    end
    local broker, iconLibrary
    function EF.UpdateFishingControls()
        local toolWindow = _G.EasyFishingWindow
        local optionsWindow = (SettingsPanel and SettingsPanel:IsShown())
            or (InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown())
        controls:SetShown(EasyFishingDB.showFishingControls
            and not (toolWindow and toolWindow:IsShown()) and not optionsWindow)
        local status = FishingState()
        state:SetText(status)
        if EF.IsFishingPaused() or InCombatLockdown() or EF.IsLootOpen()
            or not EF.IsFishingPoleEquipped() or GetUnitSpeed("player") > 0 then
            state:SetTextColor(1, 0.45, 0.35)
        elseif status == "Fishing" then
            state:SetTextColor(0.35, 1, 0.35)
        else
            state:SetTextColor(1, 0.82, 0)
        end
        pauseButton:SetText(EF.IsFishingPaused() and "Resume" or "Pause")
        local lure = EF.GetLureStatus()
        if not EF.IsFishingPoleEquipped() then
            enchantText:SetText("Equip a fishing pole")
        elseif lure.active then
            enchantText:SetText(string.format("Pole enchant  %02d:%02d",
                math.floor(lure.seconds / 60), math.floor(lure.seconds % 60)))
        else
            enchantText:SetText("Pole enchant  None")
        end
        lureText:SetText(string.format("Eligible lures  %d", lure.count))
        if broker then broker.text = status end
    end
    local toolWindow = _G.EasyFishingWindow
    if toolWindow then
        toolWindow:HookScript("OnShow", EF.UpdateFishingControls)
        toolWindow:HookScript("OnHide", EF.UpdateFishingControls)
    end
    local updateFrame = CreateFrame("Frame", "EasyFishingToolsUpdate")
    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed >= 1 then self.elapsed = 0; EF.UpdateFishingControls() end
    end)
    EF.UpdateFishingControls()

    local function LauncherClick(_, button)
        if button == "RightButton" then
            EF.OpenOptions("settings")
        elseif button == "MiddleButton" then
            EF.ToggleFishingOutfit()
        elseif _G.EasyFishingWindow:IsShown() then
            _G.EasyFishingWindow:Hide()
        else
            EF.OpenWindow("home")
        end
    end
    local function LauncherTooltip(tooltip)
        tooltip:SetText("EasyFishing: Forever")
        tooltip:AddLine(FishingState(), 1, 1, 1)
        tooltip:AddLine("Left: window  |  Right: options  |  Middle: gear", 1, 1, 1)
    end
    local libStub = _G.LibStub
    local brokerLibrary = libStub and libStub.GetLibrary and libStub:GetLibrary("LibDataBroker-1.1", true)
    if brokerLibrary then
        broker = brokerLibrary:NewDataObject("EasyFishing", {
            type = "data source", text = FishingState(), label = "EasyFishing",
            icon = "Interface\\AddOns\\" .. addonName .. "\\EasyFishing.tga",
            OnClick = LauncherClick, OnTooltipShow = LauncherTooltip,
        })
        iconLibrary = libStub:GetLibrary("LibDBIcon-1.0", true)
    end
    characterDB.minimap = type(characterDB.minimap) == "table" and characterDB.minimap or {}
    local savedAngle = tonumber(characterDB.minimap.minimapPos) or 220
    if savedAngle ~= savedAngle or math.abs(savedAngle) == math.huge then savedAngle = 220 end
    characterDB.minimap.minimapPos = savedAngle % 360
    local minimapButton
    if iconLibrary then
        characterDB.minimap.hide = not EasyFishingDB.showMinimapButton
        iconLibrary:Register("EasyFishing", broker, characterDB.minimap)
    elseif Minimap then
        minimapButton = CreateFrame("Button", "EasyFishingMinimapButton", Minimap)
        minimapButton:SetSize(32, 32)
        minimapButton:SetFrameStrata("MEDIUM")
        minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
        minimapButton:RegisterForDrag("LeftButton")
        local icon = minimapButton:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("CENTER")
        icon:SetTexture("Interface\\AddOns\\" .. addonName .. "\\EasyFishing.tga")
        local border = minimapButton:CreateTexture(nil, "OVERLAY")
        border:SetSize(48, 48)
        border:SetPoint("CENTER")
        border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        minimapButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        local function PositionLauncher()
            local angle = math.rad(characterDB.minimap.minimapPos)
            local radius = Minimap:GetWidth() / 2 + 8
            minimapButton:ClearAllPoints()
            minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
        end
        PositionLauncher()
        minimapButton:SetScript("OnClick", LauncherClick)
        minimapButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT"); LauncherTooltip(GameTooltip); GameTooltip:Show()
        end)
        minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        minimapButton:SetScript("OnDragStart", function(self) self.dragging = true end)
        minimapButton:SetScript("OnDragStop", function(self) self.dragging = false end)
        minimapButton:SetScript("OnUpdate", function(self)
            if not self.dragging then return end
            local cursorX, cursorY = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            characterDB.minimap.minimapPos = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
            PositionLauncher()
        end)
    end
    function EF.UpdateMinimapButton()
        local visible = EasyFishingDB.showMinimapButton
        characterDB.minimap.hide = not visible
        if iconLibrary then
            if visible then iconLibrary:Show("EasyFishing") else iconLibrary:Hide("EasyFishing") end
        elseif minimapButton then minimapButton:SetShown(visible) end
    end
    EF.UpdateMinimapButton()
end