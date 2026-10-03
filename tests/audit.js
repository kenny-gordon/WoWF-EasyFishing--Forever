const fs = require('fs');
const path = require('path');
const moduleRoot = process.env.EASYFISHING_TEST_MODULES
    || path.join(process.env.TEMP || require('os').tmpdir(), 'easyfishing-validation', 'node_modules');
const parser = require(path.join(moduleRoot, 'luaparse'));
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(path.join(moduleRoot, 'fengari'));
const root = path.resolve(__dirname, '..');
const manifest = fs.readFileSync(path.join(root, 'EasyFishing.toc'), 'utf8').split(/\r?\n/);
if (manifest.some(line => /(^|[\\/])bindings\.xml$/i.test(line.trim()))) {
    throw new Error('Bindings.xml is loaded separately by WoW and must not be listed as UI XML in the manifest');
}
fs.accessSync(path.join(root, 'Bindings.xml'), fs.constants.R_OK);
const files = manifest.filter(line => line.endsWith('.lua'));

function execute(state, text, label) {
    if (lauxlib.luaL_dostring(state, to_luastring(text)) !== lua.LUA_OK) {
        throw new Error(`${label}: ${to_jsstring(lua.lua_tostring(state, -1))}`);
    }
}

const mock = String.raw`
Addon = {}
Frames, NamedFrames, Timers, Messages = {}, {}, {}, {}
Clock, Skill, Zone, Combat, Moving = 10, 100, 'Zone A', false, 0
Counts = {[6529]=2, [6533]=1}
EquippedItems = {}
CVars = {Sound_EnableAllSound='0',Sound_EnableSFX='0', Sound_EnableSoundWhenGameIsInBG='0', autointeract='1'}
local methods = {}
local childFields = {Text=true, Low=true, High=true, ScrollBar=true}
function CreateFrame(kind, name, parent, template)
    local frame = {kind=kind, frameName=name, parent=parent, scripts={}, events={}, shown=true, text=''}
    setmetatable(frame, {__index=function(self, key)
        if kind == 'FontString' and (key == 'SetScript' or key == 'GetScript') then return nil end
        if childFields[key] then
            local child = CreateFrame('Frame', nil, self)
            rawset(self, key, child)
            return child
        end
        return methods[key]
    end})
    Frames[#Frames+1] = frame
    if name then NamedFrames[name] = frame; _G[name] = frame end
    return frame
end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event, callback)
    local old=self.scripts[event]
    self.scripts[event]=function(self,...) if old then old(self,...) end; callback(self,...) end
end
function methods:CreateTexture() return CreateFrame('Texture', nil, self) end
function methods:CreateFontString(name) return CreateFrame('FontString', name, self) end
function methods:GetFontString()
    if not self.fontString then self.fontString=self:CreateFontString() end
    return self.fontString
end
function methods:SetText(text) self.text = tostring(text or '') end
function methods:SetJustifyH(justify) self.justifyH=justify end
function methods:SetTexture(texture) self.texture = texture end
function methods:SetBackdrop(backdrop) self.backdrop=backdrop end
function methods:SetBackdropColor(...) self.backdropColor={...} end
function methods:SetOwner(owner,anchor) self.owner,self.anchor=owner,anchor end
function methods:GetText() return self.text end
function methods:SetChecked(value) self.checked = not not value end
function methods:GetChecked() return self.checked end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 100 end
function methods:GetHeight() return self.height or 100 end
function methods:GetName() return self.frameName end
function methods:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function methods:ClearFocus() end
function methods:GetCenter() return 400,350 end
function methods:SetScale(scale) self.scale = scale end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale() return self:GetScale() end
function methods:SetPoint(...) self.point = {...} end
function methods:SetEnabled(value) self.enabled = value end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:Hide()
    local changed=self.shown; self.shown=false
    if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:Show()
    local changed = not self.shown
    self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:GetVerticalScrollRange() return 0 end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:SetScrollChild(child) self.scrollChild=child end
function methods:GetStringHeight()
    if TallDescriptions and self.width==300 and type(self.text)=='string' and #self.text>120 then return 120 end
    local lines=1
    if type(self.text)=='string' then for _ in self.text:gmatch('\n') do lines=lines+1 end end
    return lines*12
end
function methods:SetAttribute(key, value) assert(not Combat or SecureState); self[key] = value end
function methods:GetAttribute(key) return self[key] end
function methods:ClearBindings() assert(SecureState); Binding=nil end
function methods:GetParent() return self.parent end
function methods:IsMouseMotionFocus() return self.motionFocus end
function methods:EnableMouseMotion(value) self.mouseMotionEnabled=value end
function methods:SetMapID(mapID) self.mapID=mapID end
for _, key in ipairs({
    'SetFrameStrata','SetClampedToScreen','SetMovable','EnableMouse','RegisterForDrag',
    'SetBackdropBorderColor','SetAlpha','RegisterForClicks',
    'Cancel','SetWordWrap','SetTextColor','SetColorTexture','SetAllPoints',
    'ClearAllPoints','StartMoving','StopMovingOrSizing','SetDesaturated',
    'SetAutoFocus','SetMaxLetters','SetMultiLine','SetFontObject','SetTextInsets',
    'UpdateScrollChildRect','SetFocus','HighlightText','SetValue',
    'SetMinMaxValues','SetValueStep','Raise','AddLine','SetHighlightTexture','SetHyperlink','SetDisabledFontObject'
}) do methods[key] = function() end end
function methods:SetClampedToScreen(value) self.clampedToScreen=value end
UIParent = CreateFrame('Frame'); UIParent:SetSize(1280,720)
WorldFrame = CreateFrame('Frame'); GameTooltip = CreateFrame('Frame')
WorldMapFrame = CreateFrame('Frame')
function ShowUIPanel(frame) MapOpened=frame; frame:Show() end
Minimap = CreateFrame('Frame'); Minimap:SetSize(140,140)
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
ACCEPT, CANCEL = 'Accept','Cancel'
function print(message) Messages[#Messages+1] = message end
function StaticPopup_Show(name) LastPopup=name; return StaticPopupDialogs[name] end
function Emit(event, ...)
    if event=='PLAYER_REGEN_DISABLED' or event=='PLAYER_REGEN_ENABLED' then
        Combat=event=='PLAYER_REGEN_DISABLED'
        for _,frame in ipairs(Frames) do
            local snippet=rawget(frame,'_onstate-efcombat')
            if snippet then
                SecureState=true
                assert(load('local self,newstate=...; '..snippet))(frame,Combat and 'combat' or 'safe')
                SecureState=false
            end
        end
    end
    local count = #Frames
    for index=1,count do
        local frame=Frames[index]
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,event,...) end
    end
end
function GetTime() return Clock end
function GetCursorPosition() return 500,500 end
math.atan2=math.atan
function InCombatLockdown() return Combat end
function GetInventoryItemID(_,slot)
    if slot==16 then return PoleEquipped~=false and (EquippedItems[16] or 6256) or nil end
    return EquippedItems[slot]
end
function GetItemInfoInstant(id) assert(id~=nil); return 6256,'Pole',nil,nil,123,2,20 end
function GetItemInfo(id) return 'Item '..id,'|Hitem:'..id..':0|h[Item]|h' end
function GetItemCount(id) return Counts[id] or 0 end
function GetSpellInfo() return 'Fishing' end
function GetSpellTexture(id) assert(id~=nil); return not MissingSpellTexture and 123 or nil end
function ToggleSpellBook(kind) SpellBookOpened=kind end
function HandleModifiedItemClick(link) if ModifiedItemClick then ChatText=link; return true end end
function GetNumSkillLines() return 1 end
function GetSkillLineInfo()
    local cap=MaxSkill or (Skill<=75 and 75 or Skill<=150 and 150 or Skill<=225 and 225 or 300)
    return 'Fishing',false,nil,Skill,0,0,cap
end
function GetWeaponEnchantInfo() return Enchanted,EnchantMS or 90000 end
function UnitChannelInfo() return Channel end
function UnitExists(unit) return unit=='target' and HasTarget or false end
function GetUnitSpeed() return Moving end
function GetMouseFocus() return WorldFrame end
function ClearOverrideBindings() assert(not Combat); Binding=nil end
function SetOverrideBindingClick(_, _, key) assert(not Combat); Binding=key end
function RegisterStateDriver(frame, state, condition) frame.stateDriver=condition end
function DispatchMouse(button,down)
    Emit(down and 'GLOBAL_MOUSE_DOWN' or 'GLOBAL_MOUSE_UP',button)
    if Binding then
        local action=NamedFrames.EasyFishingAutoLureButton
        action.scripts.PreClick(action,'LeftButton',down)
        if action.type and action.useOnKeyDown==down then
            MouseActions=(MouseActions or 0)+1
        end
        action.scripts.PostClick(action,'LeftButton',down)
    end
end
function GetCVar(key) return CVars[key] end
function SetCVar(key,value) CVars[key]=value end
function GetRealZoneText() return Zone end
function GetSubZoneText() return 'Lake' end
function GetGameTime() return 12,0 end
function GetServerTime() return 1790899200 end
function date() return '2026-10-02' end
function IsFishingLoot() return FishingLoot ~= false end
function GetNumLootItems() return LootCount or 1 end
function GetLootSlotLink(slot)
    if slot==2 then return not MissingSecond and '|Hitem:6292:0|h[Other Fish]|h' or nil end
    return '|Hitem:6291:0|h[Fish]|h'
end
function GetLootSlotInfo(slot) return nil,slot==2 and 'Other Fish' or 'Fish',slot==2 and 1 or 2 end
function ChatFrame_OpenChat(text) ChatText=text end
function CreateVector2D(x,y) return {x=x,y=y,GetXY=function(self) return self.x,self.y end} end
MissingMapArt={}
C_Map = {
    GetBestMapForUnit=function() return 1438 end,
    GetPlayerMapPosition=function() return CreateVector2D(MapX or 0.5,0.5) end,
    GetWorldPosFromMapPos=function(_,position) return 1,CreateVector2D(position.x*10000,position.y*10000) end,
    GetMapArtLayers=function(mapID) if MissingMapArt[mapID] then return nil end; return {{}} end,
    CanSetUserWaypointOnMap=function() return WaypointAllowed ~= false end,
    SetUserWaypoint=function(point) Waypoint=point; return true end,
    GetUserWaypointHyperlink=function() return '|Hworldmap:'..Waypoint.mapID..'|h[Location]|h' end,
}
UiMapPoint = {CreateFromCoordinates=function(mapID,x,y) return {mapID=mapID,x=x,y=y} end}
C_Timer = {NewTimer=function(delay,callback)
    local timer={delay=delay,callback=callback,Cancel=function(self) self.cancelled=true end}
    Timers[#Timers+1]=timer; return timer
end}
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(frame,text) frame.selectedText=text end
function UIDropDownMenu_Initialize(frame, callback) frame.initialize=callback end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) if MenuEntries then MenuEntries[#MenuEntries+1]=info end end
function CloseDropDownMenus() end
if BrokerMode>0 then
    BrokerLibrary={NewDataObject=function(_,name,object) BrokerObject=object; return object end}
    IconLibrary={
        Register=function(_,name,object,db) IconRegistered=true; IconHidden=db.hide end,
        Show=function() IconHidden=false end,
        Hide=function() IconHidden=true end,
    }
    LibStub={GetLibrary=function(_,name)
        if name=='LibDataBroker-1.1' then return BrokerLibrary end
        if name=='LibDBIcon-1.0' and BrokerMode==2 then return IconLibrary end
    end}
end
if Modern then
    SettingsPanel=CreateFrame('Frame'); SettingsPanel:Hide()
    Settings = {
        RegisterCanvasLayoutCategory=function(frame) RegisteredSplash=frame; return {GetID=function() return 7 end} end,
        RegisterCanvasLayoutSubcategory=function(parent,frame,name)
            assert(parent:GetID()==7 and name=='General Options')
            RegisteredSettings=frame; return {GetID=function() return 8 end}
        end,
        RegisterAddOnCategory=function() end,
        OpenToCategory=function(id) OpenedSettings=id; SettingsPanel:Show() end,
    }
else
    InterfaceOptionsFrame=CreateFrame('Frame'); InterfaceOptionsFrame:Hide()
    function InterfaceOptions_AddCategory(frame)
        if frame.parent=='EasyFishing: Forever' then RegisteredSettings=frame else RegisteredSplash=frame end
    end
    function InterfaceOptionsFrame_OpenToCategory(frame) OpenedSettings=frame; InterfaceOptionsFrame:Show() end
end
function GetAddOnMetadata(_,key)
    if key=='Version' then return '0.1.0' end
    if key=='Author' then return 'Meshoot Youtank' end
end
function FindButton(label)
    for _,frame in ipairs(Frames) do
        if frame.kind=='Button' and frame.text==label then return frame end
    end
    error('Button not found: '..label)
end
function ChooseMenu(frame,label)
    MenuEntries={}; frame.initialize()
    for _,info in ipairs(MenuEntries) do
        if info.text==label then assert(info.func); info.func(); MenuEntries=nil; return end
    end
    error('Menu option missing: '..label)
end
function Cast()
    Channel='Fishing'; Emit('UNIT_SPELLCAST_CHANNEL_START','player')
    Clock=Clock+10; Channel=nil; Emit('UNIT_SPELLCAST_CHANNEL_STOP','player')
end
`;

const checks = String.raw`
EasyFishingDB={enableSound=true,doubleClickDelay=0/0,doubleClickButton='Invalid',castClickMode='Invalid'}
EasyFishingCharDB={fishWatcherX='invalid',fishWatcherY='42',windowX=math.huge}
Emit('PLAYER_LOGIN')
assert(EasyFishingDB.doubleClickDelay==0.4 and EasyFishingDB.doubleClickButton=='LeftButton')
assert(EasyFishingDB.castClickMode=='DoubleClick' and EasyFishingCharDB.fishWatcherX==0)
assert(EasyFishingCharDB.fishWatcherY==42 and EasyFishingCharDB.windowX==0)
assert(WorldFrame.mouseMotionEnabled==true, 'click handling enables WorldFrame mouse-motion focus')
assert(SlashCmdList.EASYFISHING and Addon.OpenWindow)
assert(RegisteredSettings and #UISpecialFrames==2)
assert(NamedFrames.EasyFishingWindow.backdrop.bgFile=='Interface\\DialogFrame\\UI-DialogBox-Background')
assert(NamedFrames.EasyFishingWindow.backdrop.edgeFile=='Interface\\DialogFrame\\UI-DialogBox-Border')
assert(NamedFrames.EasyFishingWindow.backdropColor[1]==1 and NamedFrames.EasyFishingWindow.backdropColor[4]==1)
local navigationButtons={}
local gearTab
for _,frame in ipairs(Frames) do
    if frame.kind=='Button' and frame.parent==NamedFrames.EasyFishingWindow
        and frame.point and frame.point[1]=='TOPLEFT' and frame.point[5]==-48 then
        table.insert(navigationButtons,frame)
        if frame.text=='Gear & Rewards' then gearTab=frame end
    end
end
table.sort(navigationButtons,function(first,second) return first.point[4]<second.point[4] end)
assert(#navigationButtons==6 and gearTab and gearTab.width==132
    and gearTab.fontString.width==120, 'the full Gear & Rewards tab label must fit')
for index=1,#navigationButtons-1 do
    assert(navigationButtons[index].point[4]+navigationButtons[index].width
        <=navigationButtons[index+1].point[4], 'main navigation tabs must not overlap')
end
assert(NamedFrames.EasyFishingResetHistoryButton and NamedFrames.EasyFishingResetSettingsButton)
assert(NamedFrames.EasyFishingAtlasScrollFrame.width==620)
assert(NamedFrames.EasyFishingTrainerScrollFrame.width==620)
assert(NamedFrames.EasyFishingQuestRewardsScroll.width==300)
assert(NamedFrames.EasyFishingAtlasScrollFrame.scrollChild.width==600)
assert(NamedFrames.EasyFishingTrainerScrollFrame.scrollChild.width==600)
for _,key in ipairs({'enableDoubleClick','enableAutoLure','preferStrongestLure','enableSound',
    'showFishWatcher','autoExpandFishWatcher','showFishingControls','showMinimapButton','disableClickToMoveWhileFishing'}) do
    local checkbox=NamedFrames['EasyFishingCB_'..key]; local previous=checkbox:GetChecked()
    checkbox:SetChecked(not previous); checkbox.scripts.OnClick(checkbox)
    assert(EasyFishingDB[key]==not previous)
    checkbox:SetChecked(previous); checkbox.scripts.OnClick(checkbox)
end
ChooseMenu(NamedFrames.EasyFishingCastModeDropdown,'Single Click')
assert(EasyFishingDB.castClickMode=='SingleClick' and not NamedFrames.EasyFishingDelaySlider.enabled)
ChooseMenu(NamedFrames.EasyFishingCastModeDropdown,'Double Click')
assert(NamedFrames.EasyFishingDelaySlider.enabled)
ChooseMenu(NamedFrames.EasyFishingButtonDropdown,'Right Mouse'); assert(EasyFishingDB.doubleClickButton=='RightButton')
ChooseMenu(NamedFrames.EasyFishingButtonDropdown,'Left Mouse')
NamedFrames.EasyFishingDelaySlider.scripts.OnValueChanged(NamedFrames.EasyFishingDelaySlider,9)
assert(EasyFishingDB.doubleClickDelay==0.8)
NamedFrames.EasyFishingDelaySlider.scripts.OnValueChanged(NamedFrames.EasyFishingDelaySlider,-1)
assert(EasyFishingDB.doubleClickDelay==0.1)
NamedFrames.EasyFishingDelaySlider.scripts.OnValueChanged(NamedFrames.EasyFishingDelaySlider,0.4)
Skill=75; MaxSkill=75; SlashCmdList.EASYFISHING('guide')
for _,frame in ipairs(Frames) do
    if frame.rank then
        assert(frame.width==290 and frame.detail.width==290 and frame.progressBack.width==282)
        assert(frame.progress.width<=frame.progressBack.width)
    elseif frame.lure or frame.campItem then
        assert(frame.width==290 and frame.name.width==175)
    end
    if frame.rank and frame.rank.name=='Apprentice' then assert(frame.status.text=='AT CAP') end
    if frame.rank and frame.rank.name=='Journeyman' then assert(not frame.status.shown) end
end
MaxSkill=150; Emit('SKILL_LINES_CHANGED')
for _,frame in ipairs(Frames) do
    if frame.rank and frame.rank.name=='Journeyman' then assert(frame.status.text=='CURRENT') end
end
Skill=100; MaxSkill=nil; Emit('SKILL_LINES_CHANGED')
SlashCmdList.EASYFISHING('gear'); MissingSpellTexture=true; Emit('GET_ITEM_INFO_RECEIVED')
local spellRowFound=false
for _,frame in ipairs(Frames) do
    if frame.boost and frame.boost.iconType=='spell' then
        assert(frame.icon.texture=='Interface\\Icons\\INV_Misc_QuestionMark'); spellRowFound=true
    end
    if frame.boost then assert(frame.width==300, 'gear columns use the common 300px column width') end
    if frame.kind=='Button' and type(frame.name)=='table' and frame.name.text=='Find Fish' then
        frame.scripts.OnClick(); assert(SpellBookOpened=='spell')
    end
end
assert(spellRowFound); MissingSpellTexture=false; Emit('GET_ITEM_INFO_RECEIVED')
SlashCmdList.EASYFISHING('npcs')
assert(NamedFrames.EasyFishingTrainerScrollFrame.width==620)
local npcRowCount=0
for _,frame in ipairs(Frames) do
    if frame.waypointButton then
        npcRowCount=npcRowCount+1
        assert(frame.width==600 and frame.waypointButton.point[4]==-8)
        assert(frame.width+frame.waypointButton.point[4]==592,
            'every waypoint button must stay inside the 600px scroll child')
    end
end
assert(npcRowCount==35)
local gubberFound, hemingFound = false, false
for _,frame in ipairs(Frames) do
    if frame.waypointButton and frame.name and frame.name.text=='Gubber Blump' then
        assert(frame.waypointButton.enabled and frame.coordinates.text=='36.1, 44.9')
        gubberFound=true
    elseif frame.waypointButton and frame.name and frame.name.text=='Old Man Heming' then
        assert(frame.waypointButton.enabled and frame.coordinates.text=='27.7, 76.6')
        hemingFound=true
    end
end
assert(gubberFound and hemingFound)
local suppliedPins={
    ['Baelann Swiftcurrent']={16593,63.2,75.6},
    ['Fenn Fairweather']={16593,45,48.4},
    Gikkix={1446,66.6,22.2},
    ['Harn Longcast']={1412,47.4,55.4},
    ['Hunter Moore']={1424,51.0,59.8},
    Kilxx={1413,62.8,38.2},
    Krix={16594,79.2,54.6},
    ['Old Man Heming']={1434,27.7,76.6},
    Wigcik={1434,27.4,76.8},
}
local npcByName={}
for _,npc in ipairs(Addon.Data.FISHING_NPCS) do npcByName[npc.name]=npc end
for name,pin in pairs(suppliedPins) do
    local npc=npcByName[name]
    assert(npc and npc.mapID==pin[1] and npc.x==pin[2] and npc.y==pin[3],
        'NPC map data mismatch: '..name)
end
local tournamentNPCs={}
for _,npc in ipairs(Addon.Data.FISHING_NPCS) do tournamentNPCs[npc.name]=npc end
for _,name in ipairs({'Riggle Bassbait','Fishbot 5000','Jang'}) do
    assert(tournamentNPCs[name] and tournamentNPCs[name].zone=='Stranglethorn Vale')
end
local tournamentReward
for _,reward in ipairs(Addon.Data.FISHING_QUEST_REWARDS) do
    if reward.questID==8193 then tournamentReward=reward end
end
assert(tournamentReward and tournamentReward.reward:find('Pole and Extravagant Extravaganza Coin',1,true)
    and not tournamentReward.reward:find('or Hook',1,true)
    and tournamentReward.sourceLabel=='Weekly; first 50 finishers')
local npcWaypoint=false
for _,frame in ipairs(Frames) do
    if frame.waypointButton and frame.width==600 then
        assert(frame.coordinates.point[4]==414 and frame.location.width==168)
        frame.scripts.OnEnter(frame); assert(GameTooltip.anchor=='ANCHOR_LEFT')
        frame.waypointButton.scripts.OnEnter(frame.waypointButton)
        assert(GameTooltip.anchor=='ANCHOR_LEFT')
        frame.scripts.OnEnter(frame)
        assert(GameTooltip.text~=nil)
    end
    if frame.waypointButton and frame.waypointButton.enabled then
        frame.waypointButton.scripts.OnClick(); npcWaypoint=true; break
    end
end
assert(npcWaypoint and Waypoint.x>=0 and Waypoint.x<=1 and Waypoint.y>=0 and Waypoint.y<=1)
assert(MapOpened==WorldMapFrame and WorldMapFrame.mapID==Waypoint.mapID and WorldMapFrame:IsShown(),
    'NPC waypoint opens the map at the waypoint location')
local openedMapID=WorldMapFrame.mapID
MissingMapArt[16594]=true
assert(Addon.SetFishingWaypoint({mapID=16594,x=0.792,y=0.546},'Krix'))
assert(WorldMapFrame.mapID==openedMapID and MapOpened==WorldMapFrame,
    'maps without art layers must not be passed to WorldMapFrame:SetMapID')
MissingMapArt[16594]=nil
assert(RegisteredSplash==NamedFrames.EasyFishingOptionsPanel)
assert(RegisteredSplash~=RegisteredSettings and RegisteredSplash.name=='EasyFishing: Forever')
Addon.OpenOptions('splash')
assert(OpenedSettings==(Modern and 7 or RegisteredSplash))
FindButton('General Options').scripts.OnClick()
assert(OpenedSettings==(Modern and 8 or RegisteredSettings))
if not Modern then assert(RegisteredSettings.name=='General Options' and RegisteredSettings.parent=='EasyFishing: Forever') end
local logoFound=false
for _,frame in ipairs(Frames) do
    if frame.kind=='Texture' and frame.parent==RegisteredSplash then
        logoFound=frame.texture=='Interface\\AddOns\\EasyFishing\\EasyFishing.tga'
    end
end
assert(logoFound)
SlashCmdList.EASYFISHING('about'); assert(OpenedSettings==(Modern and 7 or RegisteredSplash))
Addon.OpenWindow('home')
assert(not (SettingsPanel or InterfaceOptionsFrame):IsShown())
Addon.OpenOptions('settings'); assert(not NamedFrames.EasyFishingWindow:IsShown())
UIParent:SetSize(800,500); Emit('DISPLAY_SIZE_CHANGED')
assert(NamedFrames.EasyFishingWindow:GetScale()<=500/660)
local fittedScale=NamedFrames.EasyFishingWindow:GetScale()
UIParent:SetSize(0,0); Emit('DISPLAY_SIZE_CHANGED'); assert(NamedFrames.EasyFishingWindow:GetScale()==fittedScale)
UIParent:SetSize(1280,720); Emit('UI_SCALE_CHANGED'); assert(NamedFrames.EasyFishingWindow:GetScale()==1)
Addon.SetFishingPaused(true); assert(not Addon.CanStartFishing())
assert(NamedFrames.EasyFishingKeyboardCastButton.type==nil)
Addon.SetFishingPaused(false); assert(Addon.CanStartFishing())
assert(NamedFrames.EasyFishingKeyboardCastButton.type=='item')
assert(NamedFrames.EasyFishingKeyboardCastButton.stateDriver=='[combat] combat; safe')
for _,command in ipairs({'','stats','locations','journal','guide','npcs','gear','options','settings'}) do
    SlashCmdList.EASYFISHING(command)
end
assert(OpenedSettings)
assert(NamedFrames.EasyFishingControls)
assert(NamedFrames.EasyFishingControls.width==380 and NamedFrames.EasyFishingControls.height==108)
assert(NamedFrames.EasyFishingControls.text=='')
assert(NamedFrames.EasyFishingWatcherTitle.text=='EasyFishing')
local controlTitle,controlState,controlEnchant,controlLure
for _,frame in ipairs(Frames) do
    if frame.kind=='FontString' and frame.text=='EasyFishing'
        and frame.parent==NamedFrames.EasyFishingControls then controlTitle=frame end
    if frame.kind=='FontString' and frame.parent==NamedFrames.EasyFishingControls then
        if frame.width==194 then controlState=frame end
        if frame.width==190 then controlEnchant=frame end
        if frame.width==132 and frame.point and frame.point[2]
            and (frame.point[2]==NamedFrames.EasyFishingControls
                or frame.point[2].parent==NamedFrames.EasyFishingControls) then controlLure=frame end
    end
end
assert(controlTitle and controlState and controlEnchant and controlLure)
assert(controlState.text=='Double-click Left Mouse' and controlEnchant.text=='Pole enchant  None'
    and controlLure.text=='Eligible lures  3')
assert(controlState.point[1]=='TOPRIGHT' and controlState.point[2]==NamedFrames.EasyFishingControls)
assert(controlLure.point[1]=='TOPRIGHT' and controlLure.point[2]==NamedFrames.EasyFishingControls)
local function AssertCenteredDockButtons(parent)
    local buttons={}
    for _,frame in ipairs(Frames) do
        if frame.kind=='Button' and frame.parent==parent and frame.point
            and frame.point[1]=='BOTTOMLEFT' then
            table.insert(buttons,frame)
        end
    end
    table.sort(buttons,function(first,second) return first.point[4]<second.point[4] end)
    assert(#buttons==4)
    assert(math.abs(buttons[1].point[4]-(parent.width-(buttons[1].width+buttons[2].width
        +buttons[3].width+buttons[4].width+18))/2)<0.001)
    assert(math.abs(buttons[4].point[4]+buttons[4].width
        -(parent.width-(buttons[1].point[4])))<0.001)
    for index=1,#buttons-1 do
        assert(buttons[index].point[4]+buttons[index].width+6==buttons[index+1].point[4])
    end
end
AssertCenteredDockButtons(NamedFrames.EasyFishingControls)
AssertCenteredDockButtons(NamedFrames.EasyFishingFishWatcher)
assert(NamedFrames.EasyFishingFishWatcher.point[1]=='BOTTOM'
    and NamedFrames.EasyFishingFishWatcher.point[2]==NamedFrames.EasyFishingControls
    and NamedFrames.EasyFishingFishWatcher.point[3]=='BOTTOM',
    'expanded view shares the dock bottom edge')
NamedFrames.EasyFishingControls.scripts.OnDragStart(NamedFrames.EasyFishingControls)
NamedFrames.EasyFishingControls.scripts.OnDragStop(NamedFrames.EasyFishingControls)
assert(EasyFishingCharDB.controlsX==EasyFishingCharDB.fishWatcherX
    and EasyFishingCharDB.controlsY==EasyFishingCharDB.fishWatcherY)
Addon.OpenWindow('home'); assert(not NamedFrames.EasyFishingControls.shown)
NamedFrames.EasyFishingWindow:Hide(); assert(NamedFrames.EasyFishingControls.shown)
assert(Addon.GetMouseFishingStatus():find('double-click Left Mouse',1,true))
assert(Addon.GetMouseFishingStatus():find('Next action applies lure 6529',1,true))
EasyFishingDB.castClickMode='SingleClick'; Addon.UpdateFishingControls()
assert(controlState.text=='Single-click Left Mouse')
EasyFishingDB.castClickMode='DoubleClick'; Addon.UpdateFishingControls()
Enchanted=true; assert(Addon.GetLureStatus().seconds==90)
PoleEquipped=false; assert(not Addon.GetLureStatus().active)
Addon.UpdateFishingControls(); PoleEquipped=true; Enchanted=false
EasyFishingDB.enableAutoLure=false; Addon.BindCastAction('LeftButton')
assert(NamedFrames.EasyFishingAutoLureButton.type=='spell'
    and NamedFrames.EasyFishingAutoLureButton.spell=='Fishing', 'no lures must fall back to Fishing')
Addon.ClearBinding(); EasyFishingDB.enableAutoLure=true
local oldBauble,oldAttractor=Counts[6529],Counts[6533]
Counts[6529],Counts[6533]=0,0
Addon.BindCastAction('LeftButton')
assert(NamedFrames.EasyFishingAutoLureButton.type=='spell'
    and NamedFrames.EasyFishingAutoLureButton.spell=='Fishing', 'zero eligible lures must cast Fishing')
Addon.ClearBinding(); Counts[6529],Counts[6533]=oldBauble,oldAttractor
if BrokerMode==2 then
    assert(IconRegistered and not NamedFrames.EasyFishingMinimapButton)
else
    assert(NamedFrames.EasyFishingMinimapButton)
    NamedFrames.EasyFishingMinimapButton.scripts.OnClick(nil,'RightButton'); assert(OpenedSettings)
    NamedFrames.EasyFishingMinimapButton.scripts.OnDragStart(NamedFrames.EasyFishingMinimapButton)
    NamedFrames.EasyFishingMinimapButton.scripts.OnUpdate(NamedFrames.EasyFishingMinimapButton)
    NamedFrames.EasyFishingMinimapButton.scripts.OnDragStop(NamedFrames.EasyFishingMinimapButton)
    assert(type(EasyFishingCharDB.minimap.minimapPos)=='number')
end
if BrokerMode>0 then BrokerObject.OnClick(nil,'RightButton'); assert(OpenedSettings) end
EasyFishingDB.showMinimapButton=false; Addon.UpdateMinimapButton()
if BrokerMode==2 then assert(IconHidden) else assert(not NamedFrames.EasyFishingMinimapButton.shown) end
EasyFishingDB.showMinimapButton=true; Addon.UpdateMinimapButton()
FindButton('Pause').scripts.OnClick(); assert(Addon.IsFishingPaused())
EasyFishingDB.showFishingControls=false; Addon.UpdateFishingControls()
assert(not NamedFrames.EasyFishingControls.shown)
NamedFrames.EasyFishingToolsUpdate.scripts.OnUpdate(NamedFrames.EasyFishingToolsUpdate,1)
if BrokerMode>0 then assert(BrokerObject.text=='Fishing paused') end
EasyFishingDB.showFishingControls=true; Addon.UpdateFishingControls()
FindButton('Resume').scripts.OnClick(); assert(not Addon.IsFishingPaused())
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding=='BUTTON1')
GetMouseFocus=function() return GameTooltip end
NamedFrames.EasyFishingAutoLureButton.scripts.PreClick(NamedFrames.EasyFishingAutoLureButton)
assert(Binding==nil and NamedFrames.EasyFishingAutoLureButton.type==nil)
GetMouseFocus=function() return WorldFrame end
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton')
HasTarget=true; NamedFrames.EasyFishingAutoLureButton.scripts.PreClick(NamedFrames.EasyFishingAutoLureButton)
assert(Binding=='BUTTON1', 'a selected target alone must not block fishing')
Addon.ClearBinding(); HasTarget=false
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding=='BUTTON1')
Emit('PLAYER_REGEN_DISABLED')
assert(NamedFrames.EasyFishingKeyboardCastButton.type==nil and NamedFrames.EasyFishingAutoLureButton.type==nil)
assert(Binding==nil, 'combat state clears armed mouse bindings securely')
assert(NamedFrames.EasyFishingAutoLureButton.useOnKeyDown==true)
Emit('PLAYER_REGEN_ENABLED'); assert(NamedFrames.EasyFishingKeyboardCastButton.type=='item')
for _,frame in ipairs(Frames) do
    if frame.initialize then frame.initialize() end
end
assert(Addon.GetAutoLureID()==6529)
EasyFishingDB.preferStrongestLure=true; assert(Addon.GetAutoLureID()==6533)
Skill=50; assert(Addon.GetAutoLureID()==6529); Skill=0; assert(Addon.GetAutoLureID()==nil); Skill=100
Enchanted=true; assert(Addon.GetAutoLureID()==nil); Enchanted=false
local marker={}; _G._=marker; Addon.IsFishingPoleEquipped(); assert(_G._==marker)
EasyFishingDB.disableClickToMoveWhileFishing=true; Addon.UpdateAutoInteractSetting()
assert(CVars.autointeract=='0')
EasyFishingDB.enableDoubleClick=false; Addon.UpdateAutoInteractSetting(); assert(CVars.autointeract=='1')
EasyFishingDB.enableDoubleClick=true; EasyFishingDB.disableClickToMoveWhileFishing=false
GetMouseFocus=nil
GetMouseFoci=function() return {WorldFrame} end
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding=='BUTTON1')
Addon.ClearBinding()
GetMouseFoci=function() return {GameTooltip,WorldFrame} end
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding==nil)
GetMouseFocus=function() return GameTooltip end
GetMouseFoci=function() return {WorldFrame} end
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton')
assert(Binding=='BUTTON1', 'topmost WorldFrame focus takes precedence over stale legacy focus')
Addon.ClearBinding()
GetMouseFocus=function() return WorldFrame end
GetMouseFoci=function() return {GameTooltip,WorldFrame} end
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton')
assert(Binding==nil, 'UI focus above WorldFrame must not cast')
GetMouseFoci=function() return {WorldFrame} end
GetMouseFocus=function() return GameTooltip end
GetMouseFoci=function() return {} end
WorldFrame.motionFocus=true
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton')
assert(Binding=='BUTTON1', 'WorldFrame mouse-motion focus detects world input when the focus stack is empty')
Addon.ClearBinding(); WorldFrame.motionFocus=false
GetMouseFocus=function() return WorldFrame end
GetMouseFoci=function() return {WorldFrame} end
local oldMode=EasyFishingDB.castClickMode
EasyFishingDB.castClickMode='SingleClick'; Addon.ClearBinding(); MouseActions=0
DispatchMouse('LeftButton',true)
assert(MouseActions==0 and Binding=='BUTTON1' and not NamedFrames.EasyFishingAutoLureButton.useOnKeyDown)
DispatchMouse('LeftButton',false)
assert(MouseActions==1 and Binding==nil, 'single click executes on release before cleanup')
assert(Addon.GetClickDiagnostics():find('secure pre/ready/post: %d+/%d+/%d+'))
EasyFishingDB.castClickMode='DoubleClick'; Addon.ClearBinding(); MouseActions=0
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton')
Clock=Clock+0.1; DispatchMouse('LeftButton',true)
assert(MouseActions==1 and Binding==nil, 'double click executes on second press')
assert(Addon.GetClickDiagnostics():find('armed: %d+'))
assert(Addon.GetClickDiagnostics():find('Focus: legacy=',1,true))
EasyFishingDB.castClickMode=oldMode; Addon.ClearBinding()
Addon.SetFishingPaused(true); assert(Addon.GetMouseFishingStatus():find('paused',1,true))
Addon.SetFishingPaused(false)
HasTarget=true
assert(Addon.GetMouseFishingStatus():find('Ready:',1,true)
    and not Addon.GetMouseFishingStatus():find('target',1,true))
HasTarget=false
SlashCmdList.EASYFISHING('status'); assert(Messages[#Messages]:find('Left Mouse',1,true))
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding=='BUTTON1')
Emit('LOOT_OPENED'); assert(Binding==nil)
assert(NamedFrames.EasyFishingKeyboardCastButton.type==nil)
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding==nil)
Emit('LOOT_CLOSED')
Emit('GLOBAL_MOUSE_DOWN','LeftButton'); Emit('GLOBAL_MOUSE_UP','LeftButton'); assert(Binding=='BUTTON1')
Addon.ClearBinding()
local equipped=1
C_EquipmentSet={
    GetEquipmentSetIDs=function() return {1,2} end,
    GetEquipmentSetInfo=function(id) return 'Set '..id,nil,id,id==equipped end,
    UseEquipmentSet=function(id) equipped=id; return true end,
    GetItemIDs=function() return {[16]=6256,[1]=19972,[8]=19969,[10]=1234} end,
}
Addon.GetCharacterDB().fishingOutfitSetID=2
ChooseMenu(NamedFrames.EasyFishingOutfitDropdown,'Set 2')
assert(NamedFrames.EasyFishingOutfitDropdown.selectedText=='Set 2')
FindButton('Equip Gear').scripts.OnClick(); assert(equipped==2)
FindButton('Restore Gear').scripts.OnClick(); assert(equipped==1)
Addon.ToggleFishingOutfit(); assert(equipped==2 and Addon.GetCharacterDB().previousFishingSetID==1)
Addon.ToggleFishingOutfit(); assert(equipped==1 and Addon.GetCharacterDB().previousFishingSetID==nil)
Combat=true; Addon.ToggleFishingOutfit(); assert(equipped==1); Combat=false
Channel='Other spell'; Emit('UNIT_SPELLCAST_CHANNEL_START','player')
assert(Addon.EnsureFishingStats().totalCasts==0)
EquippedItems={[16]=6365,[1]=19972,[8]=19969}
Addon.BindCastAction('LeftButton')
NamedFrames.EasyFishingAutoLureButton.scripts.PostClick(
    NamedFrames.EasyFishingAutoLureButton,'LeftButton',true)
Enchanted=true
local recognizedGearBonus, activeLureBonus, activeLureName=Addon.GetFishingBonusStatus()
local appliedLureID=tonumber((NamedFrames.EasyFishingAutoLureButton.item or ''):match('item:(%d+)'))
local appliedLure
for _,lure in ipairs(Addon.Data.LURES) do if lure.id==appliedLureID then appliedLure=lure end end
assert(recognizedGearBonus==15 and appliedLure
    and activeLureBonus==appliedLure.bonus and activeLureName==appliedLure.name)
Addon.OpenWindow('home')
NamedFrames.EasyFishingWindow:Hide()
Cast()
local sessionZone,seconds=Addon.GetFishingSessionTime()
assert(sessionZone=='Zone A' and math.abs(seconds-10)<0.0001)
assert(CVars.Sound_EnableSFX=='0' and CVars.Sound_EnableSoundWhenGameIsInBG=='0')
assert(CVars.Sound_EnableAllSound=='0')
Emit('LOOT_READY'); Emit('LOOT_OPENED'); Emit('LOOT_OPENED'); Emit('LOOT_CLOSED')
assert(Addon.EnsureFishingStats().totalItems==2)
assert(Addon.EnsureFishingStats().successfulCasts==1)
assert(NamedFrames.EasyFishingWatcherSummary.justifyH=='CENTER'
    and NamedFrames.EasyFishingWatcherSummary.text:find('Session ',1,true)
    and NamedFrames.EasyFishingWatcherSummary.text:find('Zone ',1,true)
    and NamedFrames.EasyFishingWatcherSummary.text:find('/h',1,true)
    and NamedFrames.EasyFishingWatcherSummary.text:find('Gear +15',1,true)
    and NamedFrames.EasyFishingWatcherSummary.text:find('Lure +'..activeLureBonus,1,true),
    'expanded session summary centers counts, rate and fishing bonuses on one line')
assert(not Addon.FishWatcher:IsShown() and NamedFrames.EasyFishingControls:IsShown(),
    string.format('compact dock visibility: watcher=%s controls=%s enabled=%s window=%s options=%s expanded=%s',
        tostring(Addon.FishWatcher:IsShown()), tostring(NamedFrames.EasyFishingControls:IsShown()),
        tostring(EasyFishingDB.showFishingControls), tostring(NamedFrames.EasyFishingWindow:IsShown()),
        tostring((SettingsPanel or InterfaceOptionsFrame):IsShown()), tostring(Addon.IsFishWatcherExpanded())))
FindButton('Details').scripts.OnClick()
assert(Addon.IsFishWatcherExpanded() and Addon.FishWatcher:IsShown()
    and not NamedFrames.EasyFishingControls:IsShown())
assert(Addon.FishWatcher.width==380 and Addon.FishWatcher.height==280)
assert((NamedFrames.EasyFishingWatcherLatestLabel.point[2].point[4] or 0)==0,
    'expanded session details start directly below the shared header')
assert(not Addon.FishWatcher.clampedToScreen,
    'expanded details must not be clamped away from the compact button-row anchor')
assert(NamedFrames.EasyFishingWatcherLatest.itemID==6291,
    'latest row ID='..tostring(NamedFrames.EasyFishingWatcherLatest.itemID)
        ..' saved ID='..tostring(Addon.EnsureFishingStats().lastCatchItemID)
        ..' watcher='..tostring(EasyFishingDB.showFishWatcher))
assert(NamedFrames.EasyFishingWatcherLatestLabel.justifyH=='CENTER')
assert(NamedFrames.EasyFishingWatcherLatest.text.text=='Fish  x2')
assert(NamedFrames.EasyFishingWatcherLatest.count.text=='')
assert(NamedFrames.EasyFishingWatcherCatch1.itemID==6291)
SlashCmdList.EASYFISHING('link fish'); assert(ChatText:find('6291',1,true))
SlashCmdList.EASYFISHING('link gear'); assert(ChatText:find('6256',1,true))
NamedFrames.EasyFishingWatcherLatest.scripts.OnEnter(NamedFrames.EasyFishingWatcherLatest)
NamedFrames.EasyFishingWatcherLatest.scripts.OnClick(NamedFrames.EasyFishingWatcherLatest)
assert(NamedFrames.EasyFishingJournalPage:IsShown())
ModifiedItemClick=true; ChatText=nil
NamedFrames.EasyFishingWatcherLatest.scripts.OnClick(NamedFrames.EasyFishingWatcherLatest)
assert(ChatText:find('6291',1,true)); ModifiedItemClick=false
TallDescriptions=true; SlashCmdList.EASYFISHING('guide'); Emit('BAG_UPDATE_DELAYED')
for _,frame in ipairs(Frames) do
    if frame.rank then assert(frame.height>=frame.detail:GetStringHeight()+28) end
end
TallDescriptions=false; SlashCmdList.EASYFISHING('journal')
FindButton('Compact').scripts.OnClick()
assert(not Addon.FishWatcher.shown and EasyFishingDB.showFishWatcher)
FindButton('Details').scripts.OnClick()
assert(Addon.IsFishWatcherExpanded() and Addon.FishWatcher:IsShown())
local showDetailsCheckbox=NamedFrames.EasyFishingCB_showFishWatcher
showDetailsCheckbox:SetChecked(false); showDetailsCheckbox.scripts.OnClick(showDetailsCheckbox)
assert(not Addon.FishWatcher:IsShown() and not EasyFishingDB.showFishWatcher)
assert(not NamedFrames.EasyFishingCB_showFishWatcher:GetChecked())
SlashCmdList.EASYFISHING('watch'); assert(Addon.FishWatcher.shown and Addon.IsFishWatcherExpanded())
assert(NamedFrames.EasyFishingCB_showFishWatcher:GetChecked())
local journal=Addon.GetFishJournal()
assert(#journal==1 and journal[1].id=='6291' and journal[1].count==2)
assert(journal[1].timeBuckets[2]==2 and journal[1].datesByDay['2026-10-02']==2)
SlashCmdList.EASYFISHING('journal'); Addon.RefreshJournal()
assert(NamedFrames.EasyFishingJournalPage:IsShown())
assert(NamedFrames.EasyFishingJournalLocationScroll.scrollChild.width==342)
for _,frame in ipairs(Frames) do
    if frame.kind=='Button' and frame.parent==NamedFrames.EasyFishingJournalLocationScroll.scrollChild then
        assert(frame.width==338 and frame.fontString.width==322,
            'journal location buttons must stay inside the scroll child gutter')
    end
end
assert(type(Addon.ShowFishAlmanacMap)=='function', 'almanac map action is exported during UI load')
local almanacFishRow
for _,frame in ipairs(Frames) do
    if frame.kind=='Button' and frame.fishID=='16967' then almanacFishRow=frame; break end
end
assert(almanacFishRow and almanacFishRow.caught==false
    and almanacFishRow.nameText.text=='Feralas Ahi', 'uncaught silhouettes retain their fish names')
almanacFishRow.scripts.OnClick(almanacFishRow)
NamedFrames.EasyFishingJournalWhereButton.scripts.OnClick()
assert(WorldMapFrame.mapID==1444 and MapOpened==WorldMapFrame,
    'Where to Catch opens the reported map for an uncaught fish')
NamedFrames.EasyFishingJournalSearch:SetText('6291')
NamedFrames.EasyFishingJournalSearch.scripts.OnTextChanged()
assert(NamedFrames.EasyFishingJournalSearch.scripts.OnEnter==nil,
    'search field must not show a tooltip over the selected fish details')
local journalSummary
for _,frame in ipairs(Frames) do
    if frame.kind=='FontString' and frame.text:find('Character catches: 2',1,true) then
        journalSummary=frame.text; break
    end
end
assert(journalSummary and journalSummary:find('Zone share: Zone A 100.0%',1,true)
    and journalSummary:find('Recent catches: 2026-10-02 (2)',1,true),
    'almanac detail summarizes zone share and recent catch days')
NamedFrames.EasyFishingJournalSearch:SetText('6291')
NamedFrames.EasyFishingJournalSearch.scripts.OnTextChanged()
for _,frame in ipairs(Frames) do
    if frame.kind=='Button' and frame.parent and frame.parent.parent==NamedFrames.EasyFishingJournalLocationScroll then
        frame.scripts.OnClick(); break
    end
end
assert(Addon.GetCharacterDB().lastFishingSpot.mapID==1438)
NamedFrames.EasyFishingJournalSearch:SetText('not a fish')
NamedFrames.EasyFishingJournalSearch.scripts.OnTextChanged()
NamedFrames.EasyFishingJournalSearch:SetText('')
NamedFrames.EasyFishingJournalSearch.scripts.OnTextChanged()
local missing=Addon.EnsureFishingStats().itemsByID['999']
Addon.EnsureFishingStats().itemsByID['999']={name='Old Fish',count=7}
local oldFish
for _,fish in ipairs(Addon.GetFishJournal()) do if fish.id=='999' then oldFish=fish end end
assert(oldFish and oldFish.lifetimeCount==7 and #oldFish.locations==0)
Addon.EnsureFishingStats().itemsByID['999']=missing
FishingLoot=false; Emit('LOOT_OPENED'); Emit('LOOT_CLOSED'); FishingLoot=true
assert(Addon.EnsureFishingStats().totalItems==2)
SlashCmdList.EASYFISHING('locations')
FindButton('Import / Export').scripts.OnEnter(FindButton('Import / Export'))
assert(GameTooltip.text=='Share Fishing Locations')
FindButton('Import / Export').scripts.OnClick()
NamedFrames.EasyFishingWindow:Hide(); assert(not NamedFrames.EasyFishingLocationTransfer.shown)
SlashCmdList.EASYFISHING('locations'); FindButton('Import / Export').scripts.OnClick()
FindButton('Export').scripts.OnClick()
local edit
for _,frame in ipairs(Frames) do if frame.kind=='EditBox' and frame.text:sub(1,4)=='EFS3' then edit=frame end end
assert(edit and edit.text:find('6291',1,true))
FindButton('Import').scripts.OnClick(); FindButton('Import').scripts.OnClick()
assert(Addon.EnsureFishingStats().totalItems==2)
edit:SetText('EFS2\ninvalid'); FindButton('Import').scripts.OnClick()
assert(Addon.EnsureFishingStats().totalItems==2)
MapX=0.503; Cast(); Emit('LOOT_OPENED'); Emit('LOOT_CLOSED')
MapX=0.5031; Cast(); Emit('LOOT_OPENED'); Emit('LOOT_CLOSED')
local zoneStats=Addon.EnsureFishingStats().zones['Zone A']
local function SpotCount()
    local count=0; for _ in pairs(zoneStats.spots) do count=count+1 end; return count
end
assert(SpotCount()==2, 'distant same-cell spots remain separate; nearby catches merge')
local tomTomWaypoints = {}
TomTom = {
    AddWaypoint=function(_,mapID,x,y,options)
        table.insert(tomTomWaypoints, { mapID=mapID,x=x,y=y,options=options })
        return #tomTomWaypoints
    end,
    RemoveWaypoint=function() end,
    SetCrazyArrow=function() end,
}
Addon.OpenFishJournal(6291)
NamedFrames.EasyFishingJournalWhereButton.scripts.OnClick()
assert(WorldMapFrame.mapID==1438 and #tomTomWaypoints==2,
    'Where to Catch opens the fish map and pins all observed hotspots with TomTom')
TomTom=nil
local spot
for _,candidate in pairs(zoneStats.spots) do spot=candidate; break end
local dialog=CreateFrame('Frame'); dialog.data={spot=spot}; dialog.EditBox=CreateFrame('EditBox',nil,dialog)
StaticPopupDialogs.EASYFISHING_RENAME_SPOT.OnShow(dialog)
dialog.EditBox:SetText('  My Fishing Spot  ')
StaticPopupDialogs.EASYFISHING_RENAME_SPOT.OnAccept(dialog); assert(spot.label=='My Fishing Spot')
dialog.editBox=dialog.EditBox; dialog.EditBox=nil
dialog.editBox:SetText('  '); StaticPopupDialogs.EASYFISHING_RENAME_SPOT.OnAccept(dialog); assert(spot.label==nil)
local unicodeLabel=string.rep(string.char(195,169),48)
spot.label=unicodeLabel
FindButton('Export').scripts.OnClick(); local exported=edit.text
zoneStats.spots={}; edit:SetText(exported); FindButton('Import').scripts.OnClick()
assert(SpotCount()==2, 'import preserves distant same-cell spots')
local labelPreserved=false
for _,candidate in pairs(zoneStats.spots) do if candidate.label==unicodeLabel then labelPreserved=true end end
assert(labelPreserved, '48-character Unicode labels survive transfers')
FindButton('Import').scripts.OnClick(); assert(SpotCount()==2, 're-import is idempotent')
assert(Addon.GetFishJournal()[1].datesByDay['2026-10-02']==6, 'catch dates survive export/import')
edit:SetText('EFS2\nZone A\t1438\t0.5\t0.5\tLake\t\t0\t6291:2:0:0:2:0')
FindButton('Import').scripts.OnClick(); assert(SpotCount()==2, 'EFS2 remains supported')
edit:SetText('EFS3\nZone A\t1438\t0.1\t0.1\tLake\t\t0\t6291:2:0:0:2:0:2026-02-30=2')
FindButton('Import').scripts.OnClick(); assert(SpotCount()==2, 'invalid dates reject entire import')
local beforeItems=Addon.EnsureFishingStats().totalItems
local beforeSuccess=Addon.EnsureFishingStats().successfulCasts
Cast(); LootCount=2; MissingSecond=true; Emit('LOOT_READY')
MissingSecond=false; Emit('LOOT_OPENED'); Emit('LOOT_OPENED'); Emit('LOOT_CLOSED'); LootCount=1
assert(Addon.EnsureFishingStats().totalItems==beforeItems+3, 'late item links count without duplicate slots')
assert(Addon.EnsureFishingStats().successfulCasts==beforeSuccess+1, 'multi-event loot is one successful cast')
Cast(); Emit('LOOT_OPENED'); Emit('LOOT_CLOSED'); assert(SpotCount()==2, 'new catches find imported nearby spots')
local oldWorldAPI=C_Map.GetWorldPosFromMapPos
C_Map.GetWorldPosFromMapPos=nil
local key,existing=Addon.FindFishingSpot(zoneStats,1438,0.503,0.5)
assert(existing, 'exact-coordinate matching works without world-distance API')
C_Map.GetWorldPosFromMapPos=oldWorldAPI
    EasyFishingDB.autoExpandFishWatcher=true
Zone='Zone B'; Cast(); Emit('LOOT_OPENED'); Emit('LOOT_CLOSED')
assert(Addon.IsFishWatcherExpanded(), 'auto-expand opens details for a new fishing session')
Emit('PLAYER_STARTED_MOVING')
assert(Addon.FishWatcher:IsShown(), 'movement keeps the watcher visible during the idle grace period')
local movementEndTimer=Timers[#Timers]
assert(movementEndTimer.delay==120)
local _, sessionTimeBeforeIdle=Addon.GetFishingSessionTime()
Clock=Clock+60
local _, sessionTimeDuringIdle=Addon.GetFishingSessionTime()
assert(sessionTimeDuringIdle==sessionTimeBeforeIdle, 'session duration freezes while idle after movement')
Cast()
local _, sessionTimeAfterResume=Addon.GetFishingSessionTime()
assert(math.abs(sessionTimeAfterResume-sessionTimeBeforeIdle-10)<0.0001,
    'resuming within the idle grace period must not re-add the idle interval')
Emit('PLAYER_STARTED_MOVING')
EasyFishingDB.showFishWatcher=false; Addon.UpdateFishWatcher()
EasyFishingDB.showMinimapButton=false; Addon.UpdateMinimapButton()
assert(not Addon.FishWatcher:IsShown())
if BrokerMode==2 then assert(IconHidden) else assert(not NamedFrames.EasyFishingMinimapButton:IsShown()) end
assert(Addon.ResetAccountSettings())
assert(EasyFishingDB.showFishWatcher and EasyFishingDB.showMinimapButton)
assert(Addon.FishWatcher:IsShown(), 'reset preferences restores watcher visibility during an active session')
assert(not Addon.GetCharacterDB().minimap.hide)
if BrokerMode==2 then assert(not IconHidden) else assert(NamedFrames.EasyFishingMinimapButton:IsShown()) end
local resumedIdleTimer=Timers[#Timers]
Clock=Clock+60
local _, sessionTimeAfterResumeIdle=Addon.GetFishingSessionTime()
assert(sessionTimeAfterResumeIdle==sessionTimeAfterResume, 'resumed session time freezes while idle')
Clock=Clock+60; resumedIdleTimer.callback()
assert(not Addon.FishWatcher:IsShown(), 'idle timeout ends the fishing session')
assert(Addon.EnsureFishingStats().zones['Zone B'].casts==2)
Cast()
PoleEquipped=false; Emit('PLAYER_EQUIPMENT_CHANGED')
local endedSessionZone=Addon.GetFishingSessionTime()
assert(endedSessionZone==nil and not Addon.FishWatcher:IsShown(), 'removing the pole ends the watcher session')
PoleEquipped=true
Addon.GetCharacterDB().lastFishingSpot={mapID=1438,x=0.5,y=0.5,label='Lake'}
SlashCmdList.EASYFISHING('link location'); assert(ChatText:find('1438',1,true))
WaypointAllowed=false; ChatText=nil
SlashCmdList.EASYFISHING('link location'); assert(ChatText==nil)
Channel='Fishing'; Emit('UNIT_SPELLCAST_CHANNEL_START','player')
assert(CVars.Sound_EnableSFX=='1' and CVars.Sound_EnableSoundWhenGameIsInBG=='1')
assert(CVars.Sound_EnableAllSound=='1')
EasyFishingDB.enableSound=false; Addon.UpdateFishingSoundSettings()
assert(CVars.Sound_EnableSFX=='0' and CVars.Sound_EnableSoundWhenGameIsInBG=='0')
assert(CVars.Sound_EnableAllSound=='0')
EasyFishingDB.enableSound=true; Addon.UpdateFishingSoundSettings()
assert(CVars.Sound_EnableSFX=='1')
assert(CVars.Sound_EnableAllSound=='1')
Emit('PLAYER_LOGOUT')
Channel=nil
assert(CVars.Sound_EnableSFX=='0' and CVars.Sound_EnableSoundWhenGameIsInBG=='0')
assert(CVars.Sound_EnableAllSound=='0')
EasyFishingDB=false; Addon.InitializeSettings(); assert(EasyFishingDB.doubleClickDelay==0.4)
local resetCharacterDB=Addon.GetCharacterDB()
resetCharacterDB.fishingOutfitSetID=2
resetCharacterDB.lastFishingSpot={mapID=1438,x=0.5,y=0.5,label='Reset me'}
NamedFrames.EasyFishingResetHistoryButton.scripts.OnClick()
assert(LastPopup=='EASYFISHING_RESET_HISTORY')
StaticPopupDialogs.EASYFISHING_RESET_HISTORY.OnAccept()
assert(Addon.EnsureFishingStats().totalItems==0 and next(Addon.EnsureFishingStats().zones)==nil
    and resetCharacterDB.lastFishingSpot==nil and resetCharacterDB.fishingOutfitSetID==2,
    'history reset clears catch data but preserves the selected outfit')
EasyFishingDB.enableSound=false
NamedFrames.EasyFishingResetSettingsButton.scripts.OnClick()
assert(LastPopup=='EASYFISHING_RESET_SETTINGS')
StaticPopupDialogs.EASYFISHING_RESET_SETTINGS.OnAccept()
assert(EasyFishingDB.enableSound==true and EasyFishingDB.castClickMode=='DoubleClick'
    and Addon.EnsureFishingStats().totalItems==0 and resetCharacterDB.fishingOutfitSetID==2,
    'settings reset restores account defaults without clearing character history')
`;

for (const modern of [false, true]) {
    for (const brokerMode of [0, 1, 2]) {
    const state = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(state);
        execute(state, `Modern=${modern}; BrokerMode=${brokerMode}\n${mock}`, 'WoW mocks');
    for (const file of files) {
        const source = fs.readFileSync(path.join(root, file), 'utf8');
        parser.parse(source, { luaVersion: '5.1' });
        if (lauxlib.luaL_loadstring(state, to_luastring(source)) !== lua.LUA_OK) {
            throw new Error(`${file}: ${to_jsstring(lua.lua_tostring(state, -1))}`);
        }
        lua.lua_pushstring(state, to_luastring('EasyFishing'));
        lua.lua_getglobal(state, to_luastring('Addon'));
        if (lua.lua_pcall(state, 2, 0, 0) !== lua.LUA_OK) {
            throw new Error(`${file}: ${to_jsstring(lua.lua_tostring(state, -1))}`);
        }
    }
    execute(state, checks, modern ? 'Modern Settings checks' : 'Legacy Options checks');
        console.log(`PASS (${modern ? 'modern' : 'legacy'}, broker=${brokerMode}): watcher/actions, all pages/settings, rank/text/icon boundaries, display scaling, popup/Unicode transfers, launcher, casting/loot, journal, gear/links/waypoints, master/SFX/background sound`);
    }
}