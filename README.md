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
- When finished fishing, use **Toggle Gear** to restore your previous set before interacting with mailboxes or NPCs. This removes the pole so Click-to-Cast no longer intercepts clicks.
- Adjustable double-click delay (0.1s–0.8s)
- Casts only from the game world when standing still, out of combat, with no mouseover target and no unit selected; clicks on UI controls never cast

### 🪝 Automatic Lures
When enabled, the first click applies an eligible lure if your pole has none. By default it conserves stock by choosing the weakest available lure; enable **Use Strongest Available Lure** to choose the highest-bonus lure instead. Shiny Bauble requires skill 1, Nightcrawlers or Fish Lens require 50, and stronger lures require 100. Click again using the selected pattern to cast Fishing. If a lure is already active or none can be applied, the click casts Fishing directly.

### 🎣 Fish Watcher
The optional watcher shows Fishing skill, time fishing, casts, skill gains, items per hour, items caught this session, items caught in the current zone, the latest catch, and this session's top catches. It stays visible while a fishing session is active, then hides when you move away or after two minutes without another cast. Statistics shows total fishing sessions, casts, time fishing, skill gains, items caught, per-zone activity, top catches, and catch rate. Catch-rate tracking begins with casts observed after installing this update; older lifetime cast totals are preserved but excluded from the rate. Only items shown in the Forever Fishing loot window are counted.

### 🗺️ Fishing Locations
The Locations tab records fish caught by zone, area, approximate map coordinates, and broad server-time ranges. Search by zone, area, fish name, or item ID; filter by zone or Favorites; expand an area to see its recorded locations. Left-click a location to set a Blizzard map waypoint; when TomTom is installed, EasyFishing also adds a transient TomTom marker and arrow. TomTom is an optional dependency; native waypoints work without it. Right-click a location to rename it, and use **Import / Export** to copy or merge saved locations between characters. Catches within 15 yards are combined into one location. This is a personal catch history, not a prefilled habitat list or a verified map of fishing-pool boundaries.

### 📖 Forever Fishing Guide
The Guide has Training, Fishing NPCs, and Gear & Rewards views. Training highlights your current rank, progress, and next threshold; completed ranks are marked Done. Fishing NPCs searches 25 entries by name, role, faction, town, or zone. NPCs with a known map and coordinates have a waypoint action; entries without both are marked unavailable. Listed NPC coordinates are approximate, not verified spawn points. Gear & Rewards lists fishing bonuses, Find Fish, and notable quest rewards in one consistent list; select Find Fish to open the spellbook, then drag it to your action bar. Lure and campsite items use in-game icons and show bag counts; campsite tooltips include recipe materials and effects. The 225-300 leveling route is marked as undocumented in the source guide.

### 🎒 Fishing Outfit
Choose a saved Equipment Manager set for fishing. **Toggle Gear** switches between it and the saved set you wore before. Outfit switching is unavailable in combat, and your current gear must match a saved set before EasyFishing can remember it for restoration. Fishing statistics, locations, watcher position, and equipment-set choices are stored per character; general options remain account-wide. Existing shared history and gear selection migrate to the first character that logs in after updating because the old data did not record character ownership.

### 🖱️ Click-to-Move
The optional Click-to-Move setting turns off auto-interact movement while a fishing pole is equipped and Click-to-Cast is enabled. EasyFishing restores the previous setting when the pole is removed, Click-to-Cast is disabled, the option is turned off, or you log out.

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
| Use Strongest Available Lure | Prefer the highest-bonus eligible lure instead of conserving stronger lures |
| Show Fish Watcher | Show or hide the session and zone tracking panel |
| Pause Click-to-Move With Pole | Temporarily pause auto-interact movement while the pole is equipped |
| Turn Sound On While Fishing | Turn on game sound while fishing, then restore the previous setting |
| Fishing Outfit | Select a saved Equipment Manager set, equip it, or restore the previous saved set |

### ⌨️ Slash Commands

| Command | Action |
|---|---|
| `/ef` or `/easyfishing` | Open the Forever Fishing Guide |
| `/ef stats` | Open Statistics |
| `/ef atlas` or `/ef locations` | Open Fishing Locations |
| `/ef guide` | Open the Forever Fishing Guide |
| `/ef watch` | Toggle the Fish Watcher |
| `/ef equip` | Equip the selected fishing outfit |
| `/ef restore` | Restore the previous saved outfit |
| `/ef toggle` | Switch between the selected fishing set and your previous set |
| `/ef link fish` | Prefill chat with the last caught fish hyperlink |
| `/ef link location` | Prefill chat with the selected fishing-location waypoint link |
| `/ef link gear` | Prefill chat with links to the selected outfit's fishing gear |

Link commands open the chat edit box with the links inserted; they do not send the message.

To put the gear toggle on your action bar, create a macro and drag it onto a bar:

```text
#showtooltip Fishing Pole
/ef toggle
```

### ID Data
Fishing spell, lure, gear, campsite, reward, and NPC reference data are maintained in [Data.lua](EasyFishing/Data.lua). Caught-fish IDs, observed map locations, and equipment-set IDs are recorded or read from the client at runtime. The addon does not store trainer NPC IDs or claim exact waypoint coordinates for NPCs.

---

## Installation

### Manual
1. Download the latest release
2. Extract the `EasyFishing` folder into `<WoW installation>/Interface/AddOns/`
3. Launch WoW and enable **EasyFishing: Forever** in the AddOns list.