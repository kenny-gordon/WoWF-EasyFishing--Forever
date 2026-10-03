# EasyFishing: Forever

> *Why tank when you can fish?*

A quality-of-life fishing companion for **WoW Forever**. Cast with a mouse click, apply lures, track catches, and revisit recorded fishing locations. You must still click the bobber yourself when a fish bites; the addon does not automate fishing or work while you are away from the game.

---

## Features

### Fishing Window
`/ef` opens a dedicated EasyFishing window with Locations, Training, NPCs, Gear & Rewards, Statistics, and Journal tabs. It reopens the last tab used during the current login. Drag the title bar to move it; its position is saved per character. Close it with Escape or the close button. The window scales down on smaller screens, and the Fish Watcher remains a separate session overlay.

The window's **Options** button opens Blizzard's addon settings. Those settings contain preferences and outfit selection, not the guide or catch-history tools. **Open EasyFishing** in Options brings you back to the fishing window.

In Blizzard Options, **EasyFishing: Forever** is the splash page with the addon logo, version, and author. Expand it to find **General Options** underneath. The splash has buttons for General Options and the fishing window. `/ef about` opens the splash directly; `/ef options` opens General Options.

### Fishing Controls and Keyboard Casting
The EasyFishing dock combines compact casting controls with session details at one saved position. Its compact view shows status, pole-enchant time, eligible lure count, and latest catch, with Pause / Resume, Toggle Gear, Open, and Details actions. Details replaces the compact view with session metrics and catch rows instead of stacking another panel. **Auto-expand Details** is optional and off by default. Middle-click and drag either view to move the dock. Pause is temporary and resets on UI reload. Hiding the compact dock in Options does not disable the keyboard binding.

In Blizzard's Keybindings, find **EasyFishing: Forever**, then bind **Cast Fishing / Apply Lure**. Each player keypress applies an eligible lure or casts Fishing. Casting is disabled while paused, looting, moving, in combat, casting/channeling another spell, or without a pole. The mouse Click-to-Cast toggle only controls mouse casting; use Pause to disable both inputs. You still click the bobber yourself.

### Launcher
The minimap button opens or closes EasyFishing with left-click, opens Options with right-click, and toggles your outfit with middle-click. Drag the native button around the minimap to reposition it. Hide it in Options. If LibDataBroker is already loaded, EasyFishing also publishes a status feed; if LibDBIcon is present too, it manages the minimap button instead of creating a duplicate. No launcher libraries are required or bundled.

### Fish Journal
`/ef journal` opens the Fish Almanac: searchable fish entries with named, desaturated silhouettes until this character catches them. The 37-entry seed covers common food/alchemy fish, seasonal and high-level catches, Forever's Raw Plated Armorfish, quest fish, and Stranglethorn contest catches; it is not yet an exhaustive item catalogue. Entries show reported waters, catch conditions, source notes, and known cooking uses, including Forever Fishing-skill food bonuses. Caught fish show zone shares, recent catch days, server-time buckets, and saved hotspots. **Where to Catch** opens a reported zone and plots saved catch locations; Blizzard's map shows one native waypoint, while TomTom can show all observed hotspots at once. Habitat hints are reference reports, and recorded coordinates are player observations, not guaranteed pool boundaries. Personal totals exclude imported catches; saved-location observations can include imports. Catch dates are shown in UTC and time buckets use server time. Missing historical dates are not invented, and observed months and times are not guaranteed seasons, availability, or catch probabilities.

Fish IDs are cross-referenced with Wowhead Classic. Habitat summaries are adapted from the [Warcraft Wiki Fishing Items](https://warcraft.wiki.gg/wiki/Fishing_items) and [Fishing Locations](https://warcraft.wiki.gg/wiki/Fishing_locations) pages, licensed CC BY-SA 4.0. Exact pins come from personal catch records, not inferred reference zones.

New location exports use **EFS3** to preserve catch dates. Imports still accept **EFS2** exports, which have no dates. Re-importing a snapshot merges counts conservatively rather than adding the same observations again. Older addon versions do not understand EFS3.

Exports are local text only; EasyFishing does not upload telemetry. An EFS3 location export contains zone/subzone, precise map coordinates, fish IDs/counts, optional labels/favorites, and catch dates, but no character name. Review it before sharing as a community data contribution. It does not include global cast denominators, so it must not be used to claim universal catch rates.

Statistics has a confirmed **Reset History** action that clears the current character's catch totals, zones, saved locations, and last fishing spot while preserving gear choices, window positions, and settings. General Options has a separate **Reset Preferences** action for account-wide options; it preserves character fishing history. Both are disabled while a cast is active or the player is in combat.

### Loot Protection
EasyFishing cancels pending mouse casts when loot becomes ready and blocks its mouse and keyboard casts until loot closes. Catch tracking observes both `LOOT_READY` and `LOOT_OPENED`, counts each item slot once per cast, and can fill in item links that arrive on later events. This improves fast-loot compatibility but cannot recover items another addon removes before EasyFishing observes them.

### 🎣 Double-Click to Cast
With a fishing pole equipped, press the selected mouse button once or twice to cast **Fishing**.

- Choose your trigger button: **Left**, **Right**, **Middle**, **Mouse 4**, or **Mouse 5**
- Choose a **Single Click** or **Double Click** pattern; adjust the double-click delay when using Double Click
- Right-click casting may conflict with Click-to-Move; Left Mouse is the default.
- When finished fishing, use **Toggle Gear** to restore your previous set before interacting with mailboxes or NPCs. This removes the pole so Click-to-Cast no longer intercepts clicks.
- Adjustable double-click delay (0.1s–0.8s)
- Casts only from the game world when standing still, out of combat, and not hovering a unit; clicks on UI controls never cast

Double Click is the default and casts on the second press. Single Click casts when you release the selected mouse button. If clicking does nothing, run `/ef status` with the cursor over the game world to see the active button/pattern and any casting blocker. An eligible lure may be applied instead of casting Fishing on the first action.

### 🪝 Automatic Lures
When enabled, the first click applies an eligible lure if your pole has none. By default it conserves stock by choosing the weakest available lure; enable **Use Strongest Available Lure** to choose the highest-bonus lure instead. Shiny Bauble requires skill 1, Nightcrawlers or Fish Lens require 50, and stronger lures require 100. Click again using the selected pattern to cast Fishing. If a lure is already active or none can be applied, the click casts Fishing directly.

### 🎣 Fish Watcher
The optional Details view uses a native layout with separate status and zone lines, four aligned metrics, session/zone totals, items per hour, recognized equipped fishing gear bonus, active lure bonus, and item icons for the latest catch and top two session catches. The gear total covers recognized equipped poles, hats, and boots. EasyFishing identifies lure bonuses when it applies the lure; manually applied lures whose identity the client does not expose are shown as unknown. Long item names stay contained; hover for the full item tooltip. Click a catch to open that fish in the journal; supported modified-item clicks use WoW's normal item handler. Use **Compact** to collapse Details; `/ef watch` or Options controls whether Details is enabled. Middle-click and drag either view to move the dock.

When expanded, Details stays visible during a fishing session and its two-minute idle grace period after moving or stopping casts. The dock returns to compact controls when the session ends; its timer freezes while idle. Removing the fishing pole ends the session immediately. Statistics refreshes while open and includes current-session time without adding it to saved totals twice. Details shows sessions, casts, time fishing, skill gains, items caught, per-zone activity, top catches, and catch rate. Catch-rate tracking begins with casts observed after installing this update; older lifetime cast totals are preserved but excluded from the rate. Only items observed in Forever Fishing loot are counted.

### 🗺️ Fishing Locations
The Locations tab records fish caught by zone, area, approximate map coordinates, and broad server-time ranges. Search by zone, area, fish name, or item ID; filter by zone or Favorites; expand an area to see its recorded locations. Left-click a location to set a Blizzard map waypoint; when TomTom is installed, EasyFishing also adds a transient TomTom marker and arrow. TomTom is an optional dependency; native waypoints work without it. Right-click a location to rename it, and use **Import / Export** to copy or merge saved locations between characters. Catches within 15 yards are combined into one location. This is a personal catch history, not a prefilled habitat list or a verified map of fishing-pool boundaries.

### 📖 Forever Fishing Guide
The Guide has Training, Fishing NPCs, and Gear & Rewards views. Training highlights your trained rank when the client provides its skill cap, progress, and next threshold; a capped rank stays current until the next rank is trained. Without cap information, it falls back to skill brackets. Completed ranks are marked Done. Long training descriptions grow their rows inside a scrollable view. Fishing NPCs searches 35 trainers, fishers, vendors, quest contacts, and tournament turn-in NPCs by name, role, faction, town, or zone. NPCs with verified map coordinates have a waypoint action; records without verified coordinates remain searchable and show no waypoint action. Listed NPC coordinates are approximate, not verified spawn points. Gear & Rewards lists fishing bonuses, Find Fish, and notable quest rewards in one consistent list; select Find Fish to open the spellbook, then drag it to your action bar. Lure and campsite items use in-game icons and show bag counts; campsite tooltips include recipe materials and effects. The 225-300 leveling route is marked as undocumented in the source guide.

### 🎒 Fishing Outfit
Choose a saved Equipment Manager set for fishing. **Toggle Gear** switches between it and the saved set you wore before. Outfit switching is unavailable in combat, and your current gear must match a saved set before EasyFishing can remember it for restoration. Fishing statistics, locations, watcher position, and equipment-set choices are stored per character; general options remain account-wide. Existing shared history and gear selection migrate to the first character that logs in after updating because the old data did not record character ownership.

### 🖱️ Click-to-Move
The optional Click-to-Move setting turns off auto-interact movement while a fishing pole is equipped and Click-to-Cast is enabled. EasyFishing restores the previous setting when the pole is removed, Click-to-Cast is disabled, the option is turned off, or you log out.

### 🔊 Sound Automation
Tired of alt-tabbing to silence or unmute WoW? EasyFishing automatically:

- Turns **Master Sound**, **Sound Effects**, and **Background Sound** on when you start fishing
- Restores your original settings the moment you stop
- Remembers your preferences across sessions

### ⚙️ In-Game Options Panel
Preferences are configurable from **Interface → AddOns → EasyFishing: Forever → General Options**, or `/ef options`:

| Setting | Description |
|---|---|
| Enable Click-to-Cast | Master toggle for mouse-based fishing casts |
| Click Pattern | Single Click or Double Click |
| Cast Mouse Button | Which mouse button starts a cast |
| Double-Click Delay | Maximum time between clicks; only used with Double Click |
| Apply Lure Automatically | Apply an available lure before casting when none is active |
| Use Strongest Available Lure | Prefer the highest-bonus eligible lure instead of conserving stronger lures |
| Show Session Details | Enable or disable the expanded session view |
| Auto-expand Details | Automatically expand session details when fishing starts |
| Show Fishing Controls | Show or hide the compact controls and lure status |
| Show Minimap Button | Show or hide the launcher; broker feeds remain available |
| Pause Click-to-Move With Pole | Temporarily pause auto-interact movement while the pole is equipped |
| Turn Sound On While Fishing | Turn on game sound while fishing, then restore the previous setting |
| Fishing Outfit | Select a saved Equipment Manager set, equip it, or restore the previous saved set |

### ⌨️ Slash Commands

| Command | Action |
|---|---|
| `/ef` or `/easyfishing` | Open the fishing window on the last-used tab; Locations on first open |
| `/ef options` or `/ef settings` | Open addon preferences in Blizzard Options |
| `/ef about` | Open the EasyFishing splash page in Blizzard Options |
| `/ef status` | Show the click button/pattern and why mouse casting is blocked or ready |
| `/ef stats` | Open Statistics |
| `/ef atlas` or `/ef locations` | Open Fishing Locations |
| `/ef guide` | Open the Forever Fishing Guide |
| `/ef npcs` or `/ef trainers` | Open Fishing NPCs |
| `/ef gear` | Open Gear & Rewards |
| `/ef journal` | Open the fish journal |
| `/ef pause` or `/ef resume` | Pause or resume EasyFishing mouse and keyboard casting |
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
Fishing spell, lure, gear, campsite, reward, and NPC reference data are maintained in [Data.lua](Data.lua). Caught-fish IDs, observed map locations, and equipment-set IDs are recorded or read from the client at runtime. The addon does not store trainer NPC IDs or claim exact waypoint coordinates for NPCs.

Classic NPC roles and locations are cross-referenced with the Warcraft Wiki pages for [Old Man Heming](https://warcraft.wiki.gg/wiki/Old_Man_Heming), [Gubber Blump](https://warcraft.wiki.gg/wiki/Gubber_Blump), [Harn Longcast](https://warcraft.wiki.gg/wiki/Harn_Longcast), [Kilxx](https://warcraft.wiki.gg/wiki/Kilxx), [Gikkix](https://warcraft.wiki.gg/wiki/Gikkix), [Wigcik](https://warcraft.wiki.gg/wiki/Wigcik), [Nat Pagle](https://warcraft.wiki.gg/wiki/Nat_Pagle), [Riggle Bassbait](https://warcraft.wiki.gg/wiki/Riggle_Bassbait), [Fishbot 5000](https://warcraft.wiki.gg/wiki/Fishbot_5000), and [Jang](https://warcraft.wiki.gg/wiki/Jang). Warcraft Wiki content is licensed CC BY-SA 4.0. Coordinates are included only where a Classic-compatible map position was available; other entries are not given guessed waypoints.

---

## Installation

### Manual
1. Download the latest release
2. Extract the `EasyFishing` folder into `<WoW installation>/Interface/AddOns/`
3. Launch WoW and enable **EasyFishing: Forever** in the AddOns list.

## In-game checks

After updating the addon on the Forever client, enable Lua errors (`/console scriptErrors 1`) and reload the UI. With a pole equipped and while standing still:

1. Try both click patterns on the world and confirm that UI clicks, combat, movement, and clicks on units do not cast. Confirm that a lure is applied only when the pole has no lure.
2. Start and stop fishing with sound automation enabled. Verify that Master Sound, Sound Effects, and Background Sound return to their previous values after stopping, moving, and `/reload`.
3. Catch a fish, check the watcher and Statistics, select its location, then try `/ef link location`. Check both with and without TomTom enabled.
4. Export and re-import locations. Confirm the location count and catch totals do not increase on a second import. Toggle fishing gear and confirm the previous saved set is restored.
5. Open `/ef`, switch through every tab, drag the window, and close it with Escape. Reopen it to check the selected tab, then `/reload` to check its position. Verify `/ef options` contains preferences only and **Open EasyFishing** returns to the tools. Check the window at your normal UI scale and a smaller resolution.
6. Bind the fishing key, then test casting and applying a lure. Check both global action-button key-down preferences. Verify Pause, movement, other spells, combat, and an open loot window prevent EasyFishing casts; enter combat with a mouse binding armed and check normal mouse input still works.
7. Test a catch with your usual fast-loot addon enabled. Check Journal search, location waypoints, dates, and an EFS3 export/import round trip. Verify older EFS2 imports still work. Test launcher clicks, dragging, visibility options, and broker integration when available.
8. Check the watcher's empty/latest/top-catch rows, long item names, tooltips, close button, and selected-fish journal action. Verify its checkbox stays synchronized. Leave Statistics or a guide page open while fishing or changing bags; verify values refresh. Resize the client and check the tool window refits. Check transfer messages stay above the buttons and the dialog closes when the main window closes.

## Feature Direction

Prioritize a complete fishing workflow over a long feature checklist: reliable casting and lure controls, clear session tracking, useful recorded catch locations, and safe equipment switching. Keep reference information accessible without crowding configuration. Tournament timers and additional fishing alerts should have verified Forever data and a clear place in that workflow before implementation. Camera-scanning bobber helpers and automatic item disposal are not included.

## UI Conventions

- Use Blizzard's dialog artwork for tool windows and dialogs, and tooltip artwork for compact overlays. Main and transfer windows share the same backdrop styling.
- Use the untinted Blizzard DialogFrame background and border for tool windows so their surface matches native WoW dialogs.
- Use native GameFont styles, buttons, checkboxes, dropdowns, sliders, scrollbars, item icons, and GameTooltip. Gold identifies headings and important values; neutral surfaces keep lists readable.
- Keep page headers aligned to a 640px content rule. Legacy UIPanel scroll frames use a 620px frame and 600px scroll child to reserve the external scrollbar gutter; widen row content only within that child.
- Keep feature tools in the fishing window and preferences in Blizzard Options. Preserve Escape-to-close, predictable tab navigation, and saved window positions.
- Keep dependencies optional and purposeful. Ace libraries are not required for this design. Consider AceDB-3.0 if account/character settings grow into selectable profiles. The launcher integrates with LibDataBroker-1.1 and LibDBIcon-1.0 when already loaded; neither is bundled or required. AceGUI and AceConfig are not needed merely to make native controls look polished.

## Automated Audit

The development-only runner in [tests/audit.js](tests/audit.js) parses the manifest's Lua files as Lua 5.1, compiles and loads them with Fengari, then exercises full login and feature pages against mocked WoW APIs. Six configurations cover modern/legacy Settings with native, broker-only, and broker/icon launchers. Tests cover click event phases and diagnostics, watcher actions/visibility, checkbox synchronization, dropdown choices, slider bounds, trained-rank boundaries, tall description layouts, typed icon fallbacks, display changes, Options/tool navigation, popup APIs and Unicode labels, pause/cast preparation, combat snippets, loot protection and delayed links, lures, launchers, journal workflows, EFS2/EFS3 transfers, equipment/chat links, waypoints, session timing, and master/effects/background audio restoration. Layout checks use mock frame properties and text-height stress cases, not rendered WoW pixels.

From the addon folder in PowerShell, install test tools outside the addon and run:

```powershell
npm install --prefix "$env:TEMP\easyfishing-validation" fengari luaparse --no-audit --no-fund --ignore-scripts
node tests/audit.js
```

Node and these packages are not addon dependencies and are never loaded by WoW. The runner does not simulate protected spell execution or render Blizzard frames. Passing it does not establish that the addon is bug-free; use the in-game checks above, especially click timing, UI interactions, and entering combat while a double-click binding is armed.