# EasyFishing: Forever

> *Why tank when you can fish?*

A lightweight, quality-of-life fishing companion for **WoW Forever**. Sit back, alt-tab, and let EasyFishing handle the bobber — your one-stop utility for the ultimate endless fishing grind.

---

## Features

### 🎣 Double-Click to Cast
With a fishing pole equipped, press the selected mouse button once or twice to cast **Fishing**.

- Choose your trigger button: **Left**, **Right**, **Middle**, **Mouse 4**, or **Mouse 5**
- Choose a **Single Click** or **Double Click** pattern; adjust the double-click delay when using Double Click
- Right-click casting may conflict with Click-to-Move; Left Mouse is the default.
- Adjustable double-click delay (0.1s–0.8s)
- Casts only when standing still, out of combat, no mouseover target, and no unit selected

### 🪝 Automatic Lures
When enabled, the first click applies the weakest lure allowed by your Fishing skill if your pole has none. Shiny Bauble requires skill 1, Nightcrawlers or Fish Lens require 50, and stronger lures require 100. Click again using the selected pattern to cast Fishing. If a lure is already active or none can be applied, the click casts Fishing directly.

### 🎣 Fish Watcher
The optional watcher shows Fishing skill, time fishing, casts, skill gains, items per hour, items caught this session, items caught in the current zone, the latest catch, and this session's top catches. Statistics shows total fishing sessions, casts, time fishing, skill gains, items caught, and per-zone activity and top catches. Only items shown in the Forever Fishing loot window are counted.

### 🗺️ Fishing Locations
The Locations tab records fish caught by zone, area, approximate map coordinates, and broad server-time ranges. Filter by zone; expand an area to see its recorded locations, then select one to set a map waypoint. Catches within 15 yards are combined into one location. This is a personal catch history, not a prefilled habitat list or a verified map of fishing-pool boundaries.

### 📖 Forever Fishing Guide
The Guide tab highlights your current Fishing rank, shows rank-by-rank training advice, and includes a faction-filtered trainer directory with approximate zone coordinates. It also lists lure requirements and campsite fishing crafts. The 225-300 leveling route is marked as undocumented in the source guide.

### 🎒 Fishing Outfit
Choose a saved Equipment Manager set for fishing, equip it, then restore the previous saved set. Outfit switching is manual and unavailable in combat. The current gear must match a saved set so EasyFishing can restore it safely.

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
| Click Pattern | Single Click or Double Click |
| Cast Mouse Button | Which mouse button starts a cast |
| Double-Click Delay | Maximum time between clicks; only used with Double Click |
| Apply Lure Automatically | Apply an available lure before casting when none is active |
| Show Fish Watcher | Show or hide the session and zone tracking panel |
| Pause Click-to-Move While Fishing | Temporarily pause Click-to-Move and restore its previous setting afterward |
| Turn Sound On While Fishing | Turn on game sound while fishing, then restore the previous setting |
| Fishing Outfit | Select a saved Equipment Manager set, equip it, or restore the previous saved set |

### ⌨️ Slash Commands

| Command | Action |
|---|---|
| `/ef` or `/easyfishing` | Open Settings |
| `/ef stats` | Open Statistics |
| `/ef atlas` or `/ef locations` | Open Fishing Locations |
| `/ef guide` | Open the Forever Fishing Guide |
| `/ef watch` | Toggle the Fish Watcher |
| `/ef equip` | Equip the selected fishing outfit |
| `/ef restore` | Restore the previous saved outfit |
| `/ef link fish` | Prefill chat with the last caught fish hyperlink |
| `/ef link location` | Prefill chat with the selected fishing-location waypoint link |
| `/ef link gear` | Prefill chat with links to the selected outfit's fishing gear |

Link commands open the chat edit box with the links inserted; they do not send the message.

### ID Data
Static fishing spell, lure, pole, and equipment-slot IDs are maintained in [Data.lua](EasyFishing/Data.lua). Fish item IDs, map IDs, and equipment-set IDs are captured from the client at runtime; the addon currently uses no trainer NPC IDs.
| `/ef link fish` | Prefill chat with the last caught fish hyperlink |
| `/ef link location` | Prefill chat with the selected atlas waypoint link |
| `/ef link gear` | Prefill chat with links to the selected outfit's fishing gear |

Link commands open the chat edit box with the links inserted; they do not send the message.

---

## Installation

### Manual
1. Download the latest release
2. Extract the `EasyFishing` folder into `<WoW installation>/Interface/AddOns/`
3. Launch WoW and enable **EasyFishing: Forever** in the AddOns list.