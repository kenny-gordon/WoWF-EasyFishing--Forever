# EasyFishing: Forever

> *Why tank when you can fish?*

A lightweight, quality-of-life fishing companion for **WoW Forever**. Sit back, alt-tab, and let EasyFishing handle the bobber — your one-stop utility for the ultimate endless fishing grind.

---

## Features

### 🎣 Double-Click to Cast
While a fishing pole is equipped, use the selected cast button in Single Click or Double Click mode to cast **Fishing**.

- Choose your trigger button: **Left**, **Right**, **Middle**, **Mouse 4**, or **Mouse 5**
- Choose **Single Click** or **Double Click**; the double-click window applies only in Double Click mode
- Right-click casting may conflict with Click-to-Move; Left Mouse is the default.
- Adjustable double-click window (0.1s – 0.8s)
- Casts only when standing still, out of combat, no mouseover target, and no unit selected

### 🪝 Automatic Lures
When enabled, the first cast action with an un-lured fishing pole applies the weakest available lure your Fishing skill can use. Forever lure skill floors are respected: Shiny Bauble at 1, Nightcrawlers or Fish Lens at 50, and stronger lures at 100. Repeat the selected click pattern to cast Fishing. If a lure is already active, or none is available, the cast action casts Fishing directly.

### 🎣 Fish Watcher
The optional watcher shows fishing time, casts, skill-ups, **items this session**, **all-time items in the current zone**, the last catch, and the top session catches. The Statistics tab shows lifetime sessions, casts, fishing time, skill-ups, recorded items, plus per-zone activity and item rankings. Loot opened within 60 seconds of a Fishing cast is attributed to fishing, so unrelated loot opened during that window may also be counted.

### 🖱️ Click-to-Move
The optional Click-to-Move override temporarily disables the game setting while a fishing pole is equipped and click-to-cast is enabled. EasyFishing restores the exact previous setting when the pole is unequipped, click-to-cast is disabled, the option is turned off, or the player logs out.

### 🔊 Sound Automation
Tired of alt-tabbing to silence or unmute WoW? EasyFishing automatically:

- Turns **Sound Effects** and **Background Sound** on when you start fishing
- Restores your original settings the moment you stop
- Remembers your preferences across sessions

### ⚙️ In-Game Options Panel
Everything is configurable from **Interface → AddOns → EasyFishing: Forever**:

| Setting | Description |
|---|---|
| Enable Click-to-Cast | Master toggle for mouse-based fishing casts |
| Cast Click Mode | Single Click or Double Click |
| Cast Button | Which mouse button triggers the cast |
| Double-Click Window | How fast you must double-click; only active in Double Click mode |
| Automatically Apply Lure | Apply an available lure before casting when none is active |
| Show Fish Watcher | Show or hide the session and zone tracking panel |
| Disable Click-to-Move While Fishing | Temporarily turn off Click-to-Move and restore its previous setting afterward |
| Enable Sound Automation | Toggle CVar automation around fishing |

---

## Installation

### Manual
1. Download the latest release
2. Extract the `EasyFishing` folder into `<WoW installation>/Interface/AddOns/`
3. Launch WoW and enable **EasyFishing: Forever** in the AddOns list.