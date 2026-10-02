local addonName, EF = ...
EF = EF or {}
_G.EasyFishing = EF

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
    enableCatchAlert  = false,
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


EF.MIN_DOUBLE_CLICK = MIN_DOUBLE_CLICK
EF.DB_DEFAULTS = DB_DEFAULTS
EF.BUTTON_OPTIONS = BUTTON_OPTIONS
EF.CAST_MODE_OPTIONS = CAST_MODE_OPTIONS
EF.GetButtonOption = GetButtonOption
EF.IsFishingPoleEquipped = IsFishingPoleEquipped
EF.GetFishingSpellName = GetFishingSpellName
EF.IsFishingChannelActive = IsFishingChannelActive
EF.GetFishingSkill = GetFishingSkill
EF.GetAutoLureID = GetAutoLureID
EF.GetEquipmentSetIDs = GetEquipmentSetIDs
EF.EquipFishingOutfit = EquipFishingOutfit
EF.RestorePreviousEquipmentSet = RestorePreviousEquipmentSet
EF.GetCVarBG = GetCVarBG
EF.SetCVarBG = SetCVarBG
EF.GetCVarSound = GetCVarSound
EF.SetCVarSound = SetCVarSound
EF.UpdateAutoInteractSetting = UpdateAutoInteractSetting
EF.RestoreAutoInteractSetting = RestoreAutoInteractSetting
EF.ClearBinding = ClearBinding
EF.CancelPendingTimer = CancelPendingTimer
EF.BindCastAction = BindCastAction
EF.SetDoubleClickDelay = function(value) MAX_DOUBLE_CLICK = value end
EF.GetDoubleClickDelay = function() return MAX_DOUBLE_CLICK end

function EF.InitializeClickHandling()
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

        local now = GetTime()
        local delta = now - lastClickTime
        if EasyFishingDB.castClickMode == "SingleClick" then
            lastClickTime = 0
            CancelPendingTimer()
            BindCastAction(buttonName)
            clearBindingOnMouseUp = true
            return
        end

        if lastClickTime > 0 and delta >= MIN_DOUBLE_CLICK and delta <= MAX_DOUBLE_CLICK then
            lastClickTime = 0
            CancelPendingTimer()
            clearBindingOnMouseUp = true
        else
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