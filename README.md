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
The optional watcher shows Fishing skill, session time, casts, skill-ups, session items/hour, **items this session**, **all-time items in the current zone**, the last catch, and the top session catches. The Statistics tab shows lifetime sessions, casts, fishing time, skill-ups, recorded items, plus per-zone activity and item rankings. Loot is counted only when the Forever client identifies the loot window as fishing loot.

### 🗺️ Fish Atlas
The Locations tab learns fish species by zone, approximate subzone, map coordinates, and broad server-time buckets from this character's confirmed catches. Filter the list by zone and click a recorded spot to set a world-map waypoint. Nearby catches within 15 yards merge into one observed spot. This is a personal catch history, not a prefilled habitat list or a verified map of fishing-pool boundaries.

### 📖 Forever Fishing Guide
The Guide tab shows your current Fishing skill alongside documented Forever training ranks, leveling areas, lure requirements, and campsite fishing crafts. The 225-300 leveling route is marked as undocumented in the source guide.

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
| Cast Click Mode | Single Click or Double Click |
| Cast Button | Which mouse button triggers the cast |
| Double-Click Window | How fast you must double-click; only active in Double Click mode |
| Automatically Apply Lure | Apply an available lure before casting when none is active |
| Show Fish Watcher | Show or hide the session and zone tracking panel |
| Disable Click-to-Move While Fishing | Temporarily turn off Click-to-Move and restore its previous setting afterward |
| Enable Sound Automation | Toggle CVar automation around fishing |
| Fishing Outfit | Select a saved Equipment Manager set, equip it, or restore the previous saved set |

### ⌨️ Slash Commands

| Command | Action |
|---|---|
| `/ef` or `/easyfishing` | Open Settings |
| `/ef stats` | Open Statistics |
| `/ef atlas` or `/ef locations` | Open the Fish Atlas |
| `/ef guide` | Open the Forever Fishing Guide |
| `/ef watch` | Toggle the Fish Watcher |
| `/ef equip` | Equip the selected fishing outfit |
| `/ef restore` | Restore the previous saved outfit |
| `/ef link fish` | Prefill chat with the last caught fish hyperlink |
| `/ef link location` | Prefill chat with the selected atlas waypoint link |
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