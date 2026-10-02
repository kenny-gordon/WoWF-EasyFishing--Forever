local MIN_DOUBLE_CLICK = 0.05
local MAX_DOUBLE_CLICK = 0.4
local lastClickTime    = 0
local pendingClearTimer = nil
local clearBindingOnMouseUp = false

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

local DB_DEFAULTS = {
    enableDoubleClick = true,
    enableAutoLure    = true,
    enableSound       = true,
    disableClickToMoveWhileFishing = false,
    doubleClickDelay  = 0.4,
    doubleClickButton = "LeftButton", -- see BUTTON_OPTIONS below
    castClickMode     = "DoubleClick",
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

local LURES = { 6529, 6530, 6811, 7307, 6532, 6533 }

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
    for _, lureID in ipairs(LURES) do
        local count = GetItemCountWrapper(lureID)
        if count > 0 then
            table.insert(available, { id = lureID, count = count })
        end
    end
    return available
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
        UpdateAutoInteractSetting()

        -- ------------------------------------------------------------------
        -- Options panel
        -- ------------------------------------------------------------------
        local panel = CreateFrame("Frame", "EasyFishingOptionsPanel", UIParent)
        panel.name  = "EasyFishing: Forever"

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("EasyFishing: Forever")

        local divider = panel:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        divider:SetSize(550, 1)
        divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)

        local function SectionHeader(text, anchor, yOff)
            local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOff)
            fs:SetTextColor(1, 0.82, 0)
            fs:SetText(text)
            return fs
        end

        local function MakeCheckbox(label, desc, anchor, yOffset, dbKey)
            local cb = CreateFrame("CheckButton", "EasyFishingCB_" .. dbKey,
                panel, "InterfaceOptionsCheckButtonTemplate")
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
                end
            end)
            return cb
        end

        local secCast = SectionHeader("Casting", divider, -14)

        local cbDC = MakeCheckbox(
            "Enable Click-to-Cast",
            "Cast using the selected mouse button and click mode while holding a fishing pole.",
            secCast, -4, "enableDoubleClick")

        local modeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        modeLabel:SetPoint("TOPLEFT", cbDC, "BOTTOMLEFT", 26, -10)
        modeLabel:SetText("Cast Click Mode")

        local UpdateSliderState
        local modeDropdown = CreateFrame("Frame", "EasyFishingCastModeDropdown",
            panel, "UIDropDownMenuTemplate")
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
        local btnLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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
            panel, "UIDropDownMenuTemplate")
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
        local sliderLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        sliderLabel:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -16)
        sliderLabel:SetText("Double-Click Window")

        local sliderDesc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sliderDesc:SetPoint("TOPLEFT", sliderLabel, "BOTTOMLEFT", 0, -4)
        sliderDesc:SetTextColor(0.7, 0.7, 0.7)
        sliderDesc:SetText("How quickly you must double-click. Lower = faster.")

        local slider = CreateFrame("Slider", "EasyFishingDelaySlider",
            panel, "OptionsSliderTemplate")
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
        MakeCheckbox(
            "Automatically Apply Lure",
            "When your pole has no lure, the first selected cast action applies the weakest available lure. Repeat the selected click pattern to cast Fishing.",
            secLure, -4, "enableAutoLure")

        local secMovement = SectionHeader("Movement", secLure, -46)
        local cbDisableClickToMove = MakeCheckbox(
            "Disable Click-to-Move While Fishing",
            "Temporarily turns off Click-to-Move while a fishing pole is equipped and click-to-cast is enabled, then restores its previous setting.",
            secMovement, -4, "disableClickToMoveWhileFishing")

        -- Sound -------------------------------------------------------------
        local secSound = SectionHeader("Sound", cbDisableClickToMove, -10)
        MakeCheckbox(
            "Enable Sound Automation",
            "Turns on sound (and background sound) when you start fishing, then restores your original settings when done.",
            secSound, -4, "enableSound")

        -- Register with the options UI --------------------------------------
        if InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        elseif Settings and Settings.RegisterCanvasLayoutCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(category)
        end

        -- ------------------------------------------------------------------
        -- Global mouse handler
        -- ------------------------------------------------------------------
        local clickFrame = CreateFrame("Frame")
        clickFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        clickFrame:RegisterEvent("GLOBAL_MOUSE_UP")
        clickFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        clickFrame:SetScript("OnEvent", function(_, evt, buttonName)
            if evt == "PLAYER_REGEN_DISABLED" then
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
local userBGSetting = nil

soundFrame:SetScript("OnEvent", function(_, event, unit)
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        local expectedName = GetFishingSpellName()
        local channelName  = UnitChannelInfo("player")
        if channelName ~= expectedName then return end

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

    end
end)