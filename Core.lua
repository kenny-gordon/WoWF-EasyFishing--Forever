local addonName, EF = ...
EF = EF or {}
_G.EasyFishing = EF
local DATA = EF.Data

local MIN_DOUBLE_CLICK = 0.05
local MAX_DOUBLE_CLICK = 0.4
local lastClickTime = 0
local pendingClearTimer = nil
local clearBindingOnMouseUp = false
local lootOpen = false
local fishingPaused = false
local activeFishingLureID = nil
local clickDiagnostics = {
    mouseDowns = 0,
    mouseUps = 0,
    bindingsArmed = 0,
    bindingsExpired = 0,
    securePreClicks = 0,
    secureReadyClicks = 0,
    securePostClicks = 0,
    lastBlocker = "No selected mouse click observed yet.",
}

local DB_DEFAULTS = {
    enableDoubleClick = true,
    enableAutoLure = true,
    preferStrongestLure = false,
    enableSound = true,
    disableClickToMoveWhileFishing = false,
    showFishWatcher = true,
    autoExpandFishWatcher = false,
    doubleClickDelay = 0.4,
    doubleClickButton = "LeftButton",
    castClickMode = "DoubleClick",
    showFishingControls = true,
    showMinimapButton = true,
}

local CHARACTER_DB_MIGRATION_KEYS = {
    "fishWatcherX",
    "fishWatcherY",
    "fishingStats",
    "fishingOutfitSetID",
    "previousFishingSetID",
    "lastFishingSpot",
}

local function GetCharacterDB()
    if type(EasyFishingCharDB) ~= "table" then
        EasyFishingCharDB = {}
    end
    return EasyFishingCharDB
end

local function InitializeCharacterDB()
    if type(EasyFishingDB) ~= "table" then EasyFishingDB = {} end
    local characterDB = GetCharacterDB()
    for _, key in ipairs(CHARACTER_DB_MIGRATION_KEYS) do
        if characterDB[key] == nil and EasyFishingDB[key] ~= nil then
            characterDB[key] = EasyFishingDB[key]
        end
        EasyFishingDB[key] = nil
    end
    for key, default in pairs({ fishWatcherX = 0, fishWatcherY = 160, windowX = 0, windowY = 0,
        controlsX = 0, controlsY = -220 }) do
        local value = tonumber(characterDB[key])
        characterDB[key] = value and value == value and math.abs(value) < math.huge and value or default
    end
    return characterDB
end

local BUTTON_OPTIONS = {
    { key = "LeftButton", binding = "BUTTON1", label = "Left Mouse" },
    { key = "RightButton", binding = "BUTTON2", label = "Right Mouse" },
    { key = "MiddleButton", binding = "BUTTON3", label = "Middle Mouse" },
    { key = "Button4", binding = "BUTTON4", label = "Mouse Button 4" },
    { key = "Button5", binding = "BUTTON5", label = "Mouse Button 5" },
}

local CAST_MODE_OPTIONS = {
    { value = "SingleClick", label = "Single Click" },
    { value = "DoubleClick", label = "Double Click" },
}

local BUTTON_BY_KEY = {}
for _, option in ipairs(BUTTON_OPTIONS) do
    BUTTON_BY_KEY[option.key] = option
end

local function GetButtonOption(key)
    return BUTTON_BY_KEY[key] or BUTTON_BY_KEY[DB_DEFAULTS.doubleClickButton]
end

local function InitializeSettings()
    if type(EasyFishingDB) ~= "table" then EasyFishingDB = {} end
    for key, default in pairs(DB_DEFAULTS) do
        if type(EasyFishingDB[key]) ~= type(default) then
            EasyFishingDB[key] = default
        end
    end
    if not BUTTON_BY_KEY[EasyFishingDB.doubleClickButton] then
        EasyFishingDB.doubleClickButton = DB_DEFAULTS.doubleClickButton
    end
    if EasyFishingDB.castClickMode ~= "SingleClick" and EasyFishingDB.castClickMode ~= "DoubleClick" then
        EasyFishingDB.castClickMode = DB_DEFAULTS.castClickMode
    end
    local delay = EasyFishingDB.doubleClickDelay
    if delay ~= delay then delay = DB_DEFAULTS.doubleClickDelay end
    EasyFishingDB.doubleClickDelay = math.max(0.1, math.min(0.8, delay))
end

local function IsFishingPoleEquipped()
    local mainHand = GetInventoryItemID("player", DATA.MAIN_HAND_SLOT)
    if not mainHand then return false end
    local _, classID, subclassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(mainHand)
    elseif GetItemInfoInstant then
        _, _, _, _, _, classID, subclassID = GetItemInfoInstant(mainHand)
    elseif GetItemInfo then
        _, _, _, _, _, _, _, _, _, _, _, classID, subclassID = GetItemInfo(mainHand)
    end
    return classID == DATA.FISHING_ITEM_CLASS_ID and DATA.FISHING_POLE_SUBCLASS_IDS[subclassID]
end

local function GetFishingSpellName()
    local name
    if C_Spell and C_Spell.GetSpellName then
        for _, spellID in ipairs(DATA.FISHING_SPELL_IDS) do
            name = C_Spell.GetSpellName(spellID)
            if name then break end
        end
    elseif GetSpellInfo then
        for _, spellID in ipairs(DATA.FISHING_SPELL_IDS) do
            name = GetSpellInfo(spellID)
            if name then break end
        end
    end
    return name or "Fishing"
end

local function IsFishingChannelActive()
    return UnitChannelInfo("player") == GetFishingSpellName()
end

local function IsMouseOverWorld()
    if type(GetMouseFoci) == "function" then
        local foci = GetMouseFoci()
        if type(foci) == "table" and #foci > 0 then
            return foci[1] == WorldFrame
        end
    end
    if WorldFrame and type(WorldFrame.IsMouseMotionFocus) == "function"
        and WorldFrame:IsMouseMotionFocus() then
        return true
    end
    if type(GetMouseFocus) == "function" then
        return GetMouseFocus() == WorldFrame
    end
    return false
end


local function GetFishingSkill()
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local _, _, _, fishingIndex = GetProfessions()
        if fishingIndex then
            local _, _, skillLevel, maximumSkill = GetProfessionInfo(fishingIndex)
            if type(skillLevel) == "number" then
                return skillLevel, tonumber(maximumSkill)
            end
        end
    end

    if not GetNumSkillLines or not GetSkillLineInfo then return nil end
    local fishingName = GetFishingSpellName()
    for index = 1, GetNumSkillLines() do
        local skillName, isHeader, _, rank, _, _, maximumSkill = GetSkillLineInfo(index)
        if not isHeader and skillName == fishingName and type(rank) == "number" then
            return rank, tonumber(maximumSkill)
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
    for _, lure in ipairs(DATA.LURES) do
        local count = GetItemCountWrapper(lure.id)
        if count > 0 and skill >= lure.minimumSkill then
            table.insert(available, { id = lure.id, count = count, bonus = lure.bonus or 0 })
        end
    end
    table.sort(available, function(first, second)
        if first.bonus == second.bonus then
            return first.id < second.id
        end
        return first.bonus < second.bonus
    end)
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
    local setID = tonumber(GetCharacterDB().fishingOutfitSetID)
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

    if UseFishingEquipmentSet(setID) then
        GetCharacterDB().previousFishingSetID = currentSetID
        local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
        print("EasyFishing: equipped " .. (setName or "fishing gear") .. ".")
    end
end

local function RestorePreviousEquipmentSet()
    local characterDB = GetCharacterDB()
    local setID = tonumber(characterDB.previousFishingSetID)
    if not setID then
        print("EasyFishing: there is no saved equipment set to restore.")
        return
    end
    if UseFishingEquipmentSet(setID) then
        characterDB.previousFishingSetID = nil
        local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
        print("EasyFishing: restored " .. (setName or "your previous gear") .. ".")
    end
end

local function ToggleFishingOutfit()
    local fishingSetID = tonumber(GetCharacterDB().fishingOutfitSetID)
    if not fishingSetID then
        print("EasyFishing: select a fishing equipment set first.")
        return
    end

    if GetEquippedEquipmentSetID() == fishingSetID then
        RestorePreviousEquipmentSet()
    else
        EquipFishingOutfit()
    end
end

local function GetAutoLureID()
    if not EasyFishingDB or not EasyFishingDB.enableAutoLure then return nil end
    if not IsFishingPoleEquipped() then return nil end

    local hasMainHandEnchant = GetWeaponEnchantInfo()
    if hasMainHandEnchant then return nil end

    local availableLures = GetAvailableLures()
    local preferStrongest = EasyFishingDB and EasyFishingDB.preferStrongestLure
    local lure = preferStrongest and availableLures[#availableLures] or availableLures[1]
    return lure and lure.id
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

local function GetCVarMasterSound()
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar("Sound_EnableAllSound") end
    return GetCVar("Sound_EnableAllSound")
end

local function SetCVarMasterSound(value)
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar("Sound_EnableAllSound", value)
    else SetCVar("Sound_EnableAllSound", value) end
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
        and not fishingPaused
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
local castOwner = CreateFrame("Frame", "EasyFishingCastOwner", UIParent, "SecureHandlerStateTemplate")
castOwner:SetAttribute("_onstate-efcombat", [[
    if newstate == "combat" then self:ClearBindings() end
]])
if RegisterStateDriver then
    RegisterStateDriver(castOwner, "efcombat", "[combat] combat; safe")
end

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
    "Button", "EasyFishingAutoLureButton", UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
autoLureButton:SetSize(1, 1)
autoLureButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, -10)
autoLureButton:SetAlpha(0)
autoLureButton:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
autoLureButton:SetAttribute("useOnKeyDown", true)
autoLureButton:Show()

local keyboardCastButton = CreateFrame(
    "Button", "EasyFishingKeyboardCastButton", UIParent, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
keyboardCastButton:SetSize(1, 1)
keyboardCastButton:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, -10)
keyboardCastButton:SetAlpha(0)
keyboardCastButton:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
keyboardCastButton:Show()

for _, button in ipairs({ autoLureButton, keyboardCastButton }) do
    button:SetAttribute("_onstate-efcombat", [[
        if newstate == "combat" then self:SetAttribute("type", nil) end
    ]])
    if RegisterStateDriver then
        RegisterStateDriver(button, "efcombat", "[combat] combat; safe")
    end
end

local function CanStartFishing()
    return not fishingPaused and not lootOpen and not InCombatLockdown()
        and not UnitChannelInfo("player")
        and (not UnitCastingInfo or not UnitCastingInfo("player"))
        and GetUnitSpeed("player") == 0 and IsFishingPoleEquipped()
end

local function PrepareCastAction(button)
    local lureID = GetAutoLureID()
    button:SetAttribute("type", lureID and "item" or "spell")
    button:SetAttribute("item", lureID and ("item:" .. lureID) or nil)
    button:SetAttribute("target-slot", lureID and DATA.MAIN_HAND_SLOT or nil)
    button:SetAttribute("spell", not lureID and GetFishingSpellName() or nil)
end

local function RememberAppliedLure(button)
    if not button or not button.GetAttribute or button:GetAttribute("type") ~= "item" then return end
    local item = button:GetAttribute("item")
    activeFishingLureID = type(item) == "string" and tonumber(item:match("^item:(%d+)$")) or nil
end

local function GetFishingBonusStatus()
    local gearBonus = 0
    local equippedSlots = { DATA.MAIN_HAND_SLOT, 1, 8 }
    for _, slotID in ipairs(equippedSlots) do
        local itemID = type(GetInventoryItemID) == "function" and GetInventoryItemID("player", slotID)
        if itemID then
            for _, boost in ipairs(DATA.FISHING_BOOSTS) do
                if boost.id == itemID and (boost.category == "Pole" or boost.category == "Gear") then
                    gearBonus = gearBonus + (boost.bonus or 0)
                    break
                end
            end
        end
    end

    local hasMainHandEnchant, _, _, enchantID = GetWeaponEnchantInfo()
    local appliedLure
    if not hasMainHandEnchant then
        activeFishingLureID = nil
    else
        for _, lure in ipairs(DATA.LURES) do
            if lure.enchantID and lure.enchantID == enchantID then
                activeFishingLureID = lure.id
                break
            end
        end
        for _, lure in ipairs(DATA.LURES) do
            if lure.id == activeFishingLureID then
                appliedLure = lure
                break
            end
        end
    end
    return gearBonus, hasMainHandEnchant and appliedLure and appliedLure.bonus or nil,
        appliedLure and appliedLure.name or nil
end

local function UpdateKeyboardCastAction()
    if InCombatLockdown() then return end
    if CanStartFishing() then
        PrepareCastAction(keyboardCastButton)
    else
        keyboardCastButton:SetAttribute("type", nil)
    end
end
keyboardCastButton:SetScript("PreClick", UpdateKeyboardCastAction)
keyboardCastButton:SetScript("PostClick", RememberAppliedLure)
local GetMouseFishingStatus
autoLureButton:SetScript("PreClick", function(self)
    clickDiagnostics.securePreClicks = clickDiagnostics.securePreClicks + 1
    if InCombatLockdown() then return end
    if not CanStartFishing() or not IsMouseOverWorld() or UnitExists("mouseover") then
        clickDiagnostics.lastBlocker = "Secure click rejected: " .. GetMouseFishingStatus()
        self:SetAttribute("type", nil)
        ClearBinding()
    elseif self:GetAttribute("type") then
        clickDiagnostics.secureReadyClicks = clickDiagnostics.secureReadyClicks + 1
    end
end)
autoLureButton:SetScript("PostClick", function(self, _, down)
    clickDiagnostics.securePostClicks = clickDiagnostics.securePostClicks + 1
    local singleClick = EasyFishingDB.castClickMode == "SingleClick"
    if (singleClick and not down) or (not singleClick and down) then
        RememberAppliedLure(self)
        ClearBinding()
    end
end)

local function SetFishingPaused(value)
    fishingPaused = not not value
    ClearBinding()
    UpdateAutoInteractSetting()
    UpdateKeyboardCastAction()
    if EF.UpdateFishingControls then EF.UpdateFishingControls() end
end

local function ResetAccountSettings()
    if InCombatLockdown() or UnitChannelInfo("player") then
        print("EasyFishing: stop fishing and leave combat before restoring settings.")
        return false
    end
    if EF.RestoreFishingSoundSettings then EF.RestoreFishingSoundSettings() end
    EasyFishingDB = {}
    InitializeSettings()
    MAX_DOUBLE_CLICK = DB_DEFAULTS.doubleClickDelay
    SetFishingPaused(false)
    if EF.RefreshOptions then EF.RefreshOptions() end
    if EF.UpdateFishingControls then EF.UpdateFishingControls() end
    if EF.UpdateFishingSoundSettings then EF.UpdateFishingSoundSettings() end
    if EF.UpdateFishWatcher then EF.UpdateFishWatcher() end
    if EF.UpdateMinimapButton then EF.UpdateMinimapButton() end
    return true
end

local function GetLureStatus()
    local active, remainingMS = GetWeaponEnchantInfo()
    if not IsFishingPoleEquipped() then active, remainingMS = false, 0 end
    local available, count = GetAvailableLures(), 0
    for _, lure in ipairs(available) do count = count + lure.count end
    return {
        active = not not active,
        seconds = math.max(0, (tonumber(remainingMS) or 0) / 1000),
        count = count,
        nextLureID = GetAutoLureID(),
    }
end

local function BindCastAction(buttonName)
    if not CanStartFishing() then return end
    local option = GetButtonOption(buttonName)
    PrepareCastAction(autoLureButton)
    autoLureButton:SetAttribute("useOnKeyDown", EasyFishingDB.castClickMode ~= "SingleClick")

    SetOverrideBindingClick(
        castOwner, true, option.binding, autoLureButton:GetName(), "LeftButton")
    clickDiagnostics.bindingsArmed = clickDiagnostics.bindingsArmed + 1
    clickDiagnostics.lastBlocker = "Binding armed; waiting for the configured click."
end

GetMouseFishingStatus = function()
    if not EasyFishingDB.enableDoubleClick then return "Click-to-Cast is disabled." end
    if fishingPaused then return "Fishing is paused. Use /ef resume." end
    if InCombatLockdown() then return "Casting is blocked in combat." end
    if lootOpen then return "Casting is blocked while loot is open." end
    if not IsFishingPoleEquipped() then return "No fishing pole detected in the main hand." end
    if UnitChannelInfo("player") or UnitCastingInfo and UnitCastingInfo("player") then
        return "A spell is already being cast or channeled."
    end
    if GetUnitSpeed("player") > 0 then return "Stand still to cast." end
    if UnitExists("mouseover") then return "Move the cursor away from units to cast." end
    if not IsMouseOverWorld() then return "Move the cursor over the game world, not a UI control." end
    local lureID = GetAutoLureID()
    local button = GetButtonOption(EasyFishingDB.doubleClickButton).label
    local clickPattern = EasyFishingDB.castClickMode == "SingleClick" and "single-click " or "double-click "
    local ready = "Ready: " .. clickPattern .. button .. "."
    if lureID then return ready .. " Next action applies lure " .. lureID .. "." end
    return ready .. " Next action casts Fishing."
end


EF.MIN_DOUBLE_CLICK = MIN_DOUBLE_CLICK
EF.DB_DEFAULTS = DB_DEFAULTS
EF.InitializeSettings = InitializeSettings
EF.GetCharacterDB = GetCharacterDB
EF.InitializeCharacterDB = InitializeCharacterDB
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
EF.ToggleFishingOutfit = ToggleFishingOutfit
EF.GetCVarBG = GetCVarBG
EF.SetCVarBG = SetCVarBG
EF.GetCVarSound = GetCVarSound
EF.SetCVarSound = SetCVarSound
EF.GetCVarMasterSound = GetCVarMasterSound
EF.SetCVarMasterSound = SetCVarMasterSound
EF.UpdateAutoInteractSetting = UpdateAutoInteractSetting
EF.RestoreAutoInteractSetting = RestoreAutoInteractSetting
EF.ClearBinding = ClearBinding
EF.CancelPendingTimer = CancelPendingTimer
EF.BindCastAction = BindCastAction
EF.IsLootOpen = function() return lootOpen end
EF.IsFishingPaused = function() return fishingPaused end
EF.SetFishingPaused = SetFishingPaused
EF.ResetAccountSettings = ResetAccountSettings
EF.CanStartFishing = CanStartFishing
EF.GetLureStatus = GetLureStatus
EF.GetFishingBonusStatus = GetFishingBonusStatus
EF.GetMouseFishingStatus = GetMouseFishingStatus
EF.GetClickDiagnostics = function()
    local legacyFocus = type(GetMouseFocus) == "function" and GetMouseFocus()
    local foci = type(GetMouseFoci) == "function" and GetMouseFoci() or {}
    local focusNames = {}
    if type(foci) == "table" then
        for index = 1, math.min(#foci, 4) do
            local frame = foci[index]
            local name = frame and type(frame.GetName) == "function" and frame:GetName()
            table.insert(focusNames, name or "unnamed")
        end
    end
    local legacyName = legacyFocus and type(legacyFocus.GetName) == "function"
        and legacyFocus:GetName() or nil
    local worldMotionFocus = WorldFrame and type(WorldFrame.IsMouseMotionFocus) == "function"
        and tostring(WorldFrame:IsMouseMotionFocus()) or "unavailable"
    return string.format("Mouse down/up: %d/%d  |  armed: %d  |  expired: %d  |  secure pre/ready/post: %d/%d/%d\nLast click: %s\nFocus: legacy=%s  stack=%s  world-motion=%s",
        clickDiagnostics.mouseDowns, clickDiagnostics.mouseUps, clickDiagnostics.bindingsArmed,
        clickDiagnostics.bindingsExpired, clickDiagnostics.securePreClicks,
        clickDiagnostics.secureReadyClicks, clickDiagnostics.securePostClicks,
        clickDiagnostics.lastBlocker, legacyName or "none",
        #focusNames > 0 and table.concat(focusNames, ",") or "empty", worldMotionFocus)
end
EF.UpdateKeyboardCastAction = UpdateKeyboardCastAction
_G.BINDING_HEADER_EASYFISHING = "EasyFishing: Forever"
_G["BINDING_NAME_CLICK EasyFishingKeyboardCastButton:LeftButton"] = "Cast Fishing / Apply Lure"
EF.SetDoubleClickDelay = function(value) MAX_DOUBLE_CLICK = value end
EF.GetDoubleClickDelay = function() return MAX_DOUBLE_CLICK end

function EF.InitializeClickHandling()
    if WorldFrame and type(WorldFrame.EnableMouseMotion) == "function" then
        WorldFrame:EnableMouseMotion(true)
    end
    local clickFrame = CreateFrame("Frame")
    clickFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
    clickFrame:RegisterEvent("GLOBAL_MOUSE_UP")
    clickFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    clickFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    clickFrame:RegisterEvent("LOOT_OPENED")
    clickFrame:RegisterEvent("LOOT_READY")
    clickFrame:RegisterEvent("LOOT_CLOSED")
    for _, event in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
        "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_DELAYED", "SKILL_LINES_CHANGED",
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
        clickFrame:RegisterEvent(event)
    end
    UpdateKeyboardCastAction()
    clickFrame:SetScript("OnEvent", function(_, evt, buttonName)
        if evt == "LOOT_READY" or evt == "LOOT_OPENED" or evt == "LOOT_CLOSED" then
            lootOpen = evt ~= "LOOT_CLOSED"
            ClearBinding()
            UpdateKeyboardCastAction()
            return
        end
        if evt == "PLAYER_REGEN_DISABLED" or evt == "PLAYER_REGEN_ENABLED" then
            ClearBinding()
            UpdateKeyboardCastAction()
            return
        end
        if evt ~= "GLOBAL_MOUSE_DOWN" and evt ~= "GLOBAL_MOUSE_UP" then
            if evt:find("^UNIT_") and buttonName ~= "player" then return end
            ClearBinding()
            UpdateKeyboardCastAction()
            return
        end

        if buttonName == EasyFishingDB.doubleClickButton then
            if evt == "GLOBAL_MOUSE_DOWN" then
                clickDiagnostics.mouseDowns = clickDiagnostics.mouseDowns + 1
                clickDiagnostics.lastBlocker = GetMouseFishingStatus()
            else
                clickDiagnostics.mouseUps = clickDiagnostics.mouseUps + 1
            end
        end

        if evt == "GLOBAL_MOUSE_UP" then
            if clearBindingOnMouseUp then
                clearBindingOnMouseUp = false
                CancelPendingTimer()
                pendingClearTimer = C_Timer.NewTimer(0, ClearBinding)
                return
            end

            if buttonName ~= EasyFishingDB.doubleClickButton or lastClickTime <= 0 then
                return
            end

            if GetTime() - lastClickTime > MAX_DOUBLE_CLICK
                or lootOpen
                or fishingPaused
                or not EasyFishingDB.enableDoubleClick
                or InCombatLockdown()
                or IsFishingChannelActive()
                or not IsFishingPoleEquipped()
                or not IsMouseOverWorld()
                or UnitExists("mouseover")
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
            or lootOpen
            or fishingPaused
            or InCombatLockdown()
            or IsFishingChannelActive()
            or not IsFishingPoleEquipped()
            or not IsMouseOverWorld()
            or UnitExists("mouseover")
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
                clickDiagnostics.bindingsExpired = clickDiagnostics.bindingsExpired + 1
                clickDiagnostics.lastBlocker = "Double-click window expired before the second press."
                if not InCombatLockdown() then
                    ClearOverrideBindings(castOwner)
                end
                lastClickTime = 0
            end)
        end
    end)
end