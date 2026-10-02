local _, EasyFishing = ...
EasyFishing = EasyFishing or _G.EasyFishing or {}
_G.EasyFishing = EasyFishing

EasyFishing.Data = {
    MAIN_HAND_SLOT = 16,
    FISHING_ITEM_CLASS_ID = 2,
    FISHING_POLE_SUBCLASS_IDS = {
        [20] = true,
        [25] = true,
    },
    FISHING_SPELL_IDS = { 7620, 131474 },
    LURES = {
        { id = 6529, minimumSkill = 1 },
        { id = 6530, minimumSkill = 50 },
        { id = 6811, minimumSkill = 50 },
        { id = 6532, minimumSkill = 100 },
        { id = 7307, minimumSkill = 100 },
        { id = 6533, minimumSkill = 100 },
    },
    CHAT_GEAR_SLOT_IDS = { 16, 1, 10, 8, 17 },
}