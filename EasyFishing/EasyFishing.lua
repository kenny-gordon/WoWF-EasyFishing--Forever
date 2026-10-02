local MIN_DOUBLE_CLICK = 0.05
local MAX_DOUBLE_CLICK = 0.4
local lastClickTime    = 0
local ignoreLureUntil  = 0
local pendingClearTimer = nil

-- ---------------------------------------------------------------------------
-- Saved variables
-- ---------------------------------------------------------------------------

local DB_DEFAULTS = {
    enableDoubleClick = true,
    enableLureMenu    = true,
    enableSound       = true,
    doubleClickDelay  = 0.4,
    doubleClickButton = "RightButton", -- see BUTTON_OPTIONS below
}

-- All mouse buttons we can bind to. `binding` is the WoW key name used by
-- SetOverrideBindingSpell; `key` is what GLOBAL_MOUSE_DOWN reports.
local BUTTON_OPTIONS = {
    { key = "RightButton",  binding = "BUTTON2", label = "Right Mouse" },
    { key = "LeftButton",   binding = "BUTTON1", label = "Left Mouse" },
    { key = "MiddleButton", binding = "BUTTON3", label = "Middle Mouse" },
    { key = "Button4",      binding = "BUTTON4", label = "Mouse Button 4" },
    { key = "Button5",      binding = "BUTTON5", label = "Mouse Button 5" },
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

local LURES = { 6532, 7307, 6530, 6533, 6811, 6529 }

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

local function GetIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    elseif GetItemIcon then
        return GetItemIcon(itemID)
    end
    return select(10, GetItemInfo(itemID))
end

-- ---------------------------------------------------------------------------
-- Lure menu
-- ---------------------------------------------------------------------------

local lureMenu = CreateFrame("Frame", "EasyFishingLureMenu", UIParent, "BackdropTemplate")
lureMenu:SetFrameStrata("DIALOG")
lureMenu:SetClampedToScreen(true)
lureMenu:Hide()
tinsert(UISpecialFrames, "EasyFishingLureMenu")

if lureMenu.SetBackdrop then
    lureMenu:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    lureMenu:SetBackdropColor(0, 0, 0, 1)
    lureMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
end

local lureButtons = {}

local lureMenuCloseBtn = CreateFrame("Button", nil, lureMenu)
lureMenuCloseBtn:SetSize(20, 20)
lureMenuCloseBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
lureMenuCloseBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
lureMenuCloseBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
lureMenuCloseBtn:SetScript("OnClick", function()
    ignoreLureUntil = GetTime() + 300
    lureMenu:Hide()
end)
lureMenuCloseBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -5)
    GameTooltip:SetText("Ignore Lures")
    GameTooltip:AddLine("Fish without lures for the next 5 minutes.", 1, 1, 1, true)
    GameTooltip:Show()
end)
lureMenuCloseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function UpdateLureMenu(availableLures)
    for _, btn in ipairs(lureButtons) do
        btn:Hide()
    end

    if #availableLures == 0 then
        lureMenu:Hide()
        return false
    end

    local btnSize = 28
    local padding = 5
    local width   = (#availableLures * btnSize) + ((#availableLures + 1) * padding)
    lureMenu:SetSize(width, btnSize + 2 * padding)

    lureMenuCloseBtn:ClearAllPoints()
    lureMenuCloseBtn:SetPoint("TOPRIGHT", lureMenu, "TOPRIGHT", -3, -3)

    local spellName = GetFishingSpellName()

    for i, lure in ipairs(availableLures) do
        local btn = lureButtons[i]
        if not btn then
            btn = CreateFrame("Button", "EasyFishingLureBtn" .. i, lureMenu, "SecureActionButtonTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:RegisterForClicks("AnyUp", "AnyDown")

            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = tex
            btn:SetNormalTexture("")

            if btn.CreateMaskTexture then
                local mask = btn:CreateMaskTexture()
                mask:SetTexture(
                    "Interface\\CharacterFrame\\TempPortraitAlphaMask",
                    "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(btn.icon)
                btn.icon:AddMaskTexture(mask)

                btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
                btn:GetHighlightTexture():SetBlendMode("ADD")
                btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
            else
                btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
                btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
            end

            local font = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
            font:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            btn.Count = font

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -5)
                GameTooltip:SetItemByID(self.itemID)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            table.insert(lureButtons, btn)
        end

        btn.itemID = lure.id
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", lureMenu, "LEFT",
            padding + (i - 1) * (btnSize + padding), 0)

        btn.icon:SetTexture(GetIcon(lure.id))
        btn:SetAttribute("type", "macro")
        -- Apply the lure, then actually cast Fishing (not just "use main hand")
        btn:SetAttribute("macrotext",
            "/use item:" .. lure.id .. "\n/cast " .. spellName)
        btn:SetScript("PostClick", function()
            lureMenu:Hide()
        end)
        btn.Count:SetText(lure.count > 1 and lure.count or "")
        btn:Show()
    end
    return true
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
end

local isFishing = false

-- ---------------------------------------------------------------------------
-- Main frame
-- ---------------------------------------------------------------------------

local mainFrame = CreateFrame("Frame")
mainFrame:RegisterEvent("PLAYER_LOGIN")

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Initialise saved variables
        EasyFishingDB = EasyFishingDB or {}
        for k, v in pairs(DB_DEFAULTS) do
            if EasyFishingDB[k] == nil then
                EasyFishingDB[k] = v
            end
        end
        MAX_DOUBLE_CLICK = EasyFishingDB.doubleClickDelay

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
                end
            end)
            return cb
        end

        local secCast = SectionHeader("Casting", divider, -14)

        local cbDC = MakeCheckbox(
            "Enable Double-Click to Fish",
            "Double-click the selected mouse button anywhere while holding a fishing pole to instantly cast Fishing.",
            secCast, -4, "enableDoubleClick")

        -- Button picker -----------------------------------------------------
        local btnLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        btnLabel:SetPoint("TOPLEFT", cbDC, "BOTTOMLEFT", 26, -10)
        btnLabel:SetText("Double-Click Button")

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

        local function UpdateSliderState(enabled)
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
        UpdateSliderState(EasyFishingDB.enableDoubleClick)

        local origClick = cbDC:GetScript("OnClick")
        cbDC:SetScript("OnClick", function(me, ...)
            if origClick then origClick(me, ...) end
            UpdateSliderState(me:GetChecked())
        end)

        -- Lure menu ---------------------------------------------------------
        local secLure = SectionHeader("Lure Menu", slider, -24)
        MakeCheckbox(
            "Enable Smart Lure Menu",
            "After casting, if no lure is applied a quick-select menu appears near your cursor.",
            secLure, -4, "enableLureMenu")

        -- Sound -------------------------------------------------------------
        local secSound = SectionHeader("Sound", secLure, -46)
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
        clickFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        clickFrame:SetScript("OnEvent", function(_, evt, buttonName)
            if evt == "PLAYER_REGEN_DISABLED" then
                ClearBinding()
                if lureMenu:IsShown() then lureMenu:Hide() end
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

            if not EasyFishingDB.enableDoubleClick then return end
            if InCombatLockdown() then return end
            if not IsFishingPoleEquipped() then return end
            if UnitExists("mouseover") then return end
            if UnitExists("target") then return end
            if GetUnitSpeed("player") > 0 then return end

            local now   = GetTime()
            local delta = now - lastClickTime
            local opt   = GetButtonOption(selectedKey)

            if lastClickTime > 0
                and delta >= MIN_DOUBLE_CLICK
                and delta <= MAX_DOUBLE_CLICK then
                -- Second click: binding will fire the spell. Reset synchronously.
                lastClickTime = 0
                CancelPendingTimer()
                C_Timer.After(0, function()
                    if not InCombatLockdown() then
                        ClearOverrideBindings(castOwner)
                    end
                end)
            else
                -- First click: arm the binding so the *next* click casts.
                lastClickTime = now
                SetOverrideBindingSpell(castOwner, true, opt.binding, GetFishingSpellName())

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
-- Sound + lure menu automation
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

        -- Lure menu
        if EasyFishingDB.enableLureMenu and not InCombatLockdown() then
            local hasLure = GetWeaponEnchantInfo()
            local nowTime = GetTime()
            if hasLure then
                ignoreLureUntil = 0
            end
            if not hasLure and nowTime > ignoreLureUntil then
                local lures = GetAvailableLures()
                if #lures > 0 and UpdateLureMenu(lures) then
                    local x, y = GetCursorPosition()
                    local scale = UIParent:GetEffectiveScale()
                    lureMenu:ClearAllPoints()
                    lureMenu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                        (x / scale) + 40, (y / scale) - 20)
                    lureMenu:Show()
                end
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