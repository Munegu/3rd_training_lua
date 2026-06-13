# CLAUDE.md

Notes for Claude Code when working in this repository.

## What this project is

A Lua mod for **FBNeo / Fightcade** that adds a training mode to
**Street Fighter III: 3rd Strike** (`sfiii3nr1`). It is loaded by FBNeo's Lua
scripting host (FBA-RR API). It is not a regular Lua application, not a Love2D
game, and not a script you run from the command line — it is injected into
the emulator and runs synchronously with the emulation loop.

Original project: https://github.com/effie3rd/3rd_training_lua

## Running it

You don't "run" this from a shell. The script is loaded by Fightcade/FBNeo:

1. From Fightcade, click the **Training** button (the host loads
   `fbneo-training-mode.lua` automatically) — or in FBNeo Lua console, load
   `fbneo-training-mode.lua` while the `sfiii3nr1` ROM is running.
2. In game, press `Start` to open the training menu.
3. `Alt+1` returns to the character select.

No build step, no test suite, no linter on CI. The host re-loads the script
when the ROM starts. The only formatter config in the repo is
`lua_format.config`.

## Entry point and bootstrap

- `fbneo-training-mode.lua` — 8-line shim. If ROM is `sfiii3nr1`, it requires
  `3rd_training.lua`. Otherwise it falls back to
  `fbneo-training-mode-original.lua` (the upstream, unmodded file — leave it
  alone).
- `3rd_training.lua` — registers the four FBNeo host callbacks:
  - `emu.registerstart(on_start)` — one-shot init at ROM start
  - `emu.registerbefore(before_frame)` — runs every emulated frame BEFORE the
    frame executes (this is where most game logic / input mutation happens)
  - `gui.register(on_gui)` — runs every frame for drawing
  - `savestate.registerload(on_load_state)` — fires after a savestate loads

## Code layout (`src/`)

- `gamestate.lua` — reads memory each frame into `gamestate.P1`, `gamestate.P2`,
  `gamestate.frame_number`, `is_in_match`, etc. **Read-only view of the game.**
- `control/`
  - `memory_addresses.lua` — every RAM address used by the mod
  - `inputs.lua` — reads pad/keyboard, builds `player.input` (with
    `.down/.pressed/.released/.state_time` per button) and `player.input_history`
    (last 20 distinct input states, side-normalized). Also handles input
    injection (`queue_input_sequence`, `process_pending_input_sequence`).
  - `write_memory.lua`, `dummy_control.lua`, `advanced_control.lua`,
    `recording.lua`, `managers.lua`, `character_select.lua`
- `data/`
  - `framedata.lua` + `framedata_meta.lua` — full framedata model
  - `move_data.lua` + `data/move_list.json` — symbolic move inputs per character
    (already contains Oro's full move list)
  - `prediction.lua` — dummy AI blocking/parrying prediction
- `training/<mode>/<mode>.lua` — exclusive training modes (defense, jumpins,
  footsies, unblockables, geneijin). **Loaded automatically by name** from the
  list in `src/modules.lua` (`training_mode_names`). Each module exports
  `init`, `start`, `stop`, `update`, `create_menu`, etc.
- `modules/<name>/<name>.lua` — non-exclusive feature modules (distances,
  extra_settings, key_bindings), same loading pattern from `extra_module_names`.
- `ui/`
  - `menu.lua` — multitab menu (Dummy / Recording / Display / Rules / Training
    / Modules). Pressing Start toggles it. Training modes auto-populate the
    Training tab.
  - `menu_items.lua` — menu widget classes (`Button_Menu_Item`,
    `List_Menu_Item`, `On_Off_Menu_Item`, `Slider_Menu_Item`,
    `Integer_Menu_Item`, `Header_Menu_Item`, `Label_Menu_Item`, popups, etc.)
  - `draw.lua` — `draw_text`, `draw_text_to_canvas`, image helpers, screen-space
    conversion
  - `hud.lua` — in-game overlays (combo info, frame advantage, etc.)
  - `input_history.lua` — on-screen input history widget
- `modes.lua` — owns `active_mode`. Only one training mode runs at a time;
  `start(mode)` stops the others. Save/restore controller + training settings.
- `modules.lua` — loads every training and extra module by name; calls each
  module's `update()` every frame.
- `challenge/hadou_matsuri.lua` — **abandoned / unfinished** experiment.
  Don't use it as a structural reference; use `src/training/jumpins/` instead.

## How to add a new training mode

This is the path used by Defense, Jump-Ins, Footsies, etc. It auto-wires into
the menu, mode lifecycle, controller swap handling, and save/load.

1. Create `src/training/<my_mode>/<my_mode>.lua`.
2. The module must return a table that exposes at least:
   `name`, `init`, `start`, `stop`, `update`, `create_menu`, `process_gesture`,
   `is_mode_active`, `is_enabled`. `create_menu()` returns
   `{ name = "training_<my_mode>", entries = { ... menu items ... } }`.
3. Add `"<my_mode>"` to `training_mode_names` in `src/modules.lua`. That is
   the only registration needed.
4. Optionally drop `localization.json` and `settings_default.json` in the
   module's folder (mirrors the other training modes).

## Conventions worth knowing

- The codebase uses `---@diagnostic disable: lowercase-global, undefined-global`
  in a few files because FBNeo's Lua host injects globals (`emu`, `memory`,
  `gui`, `joypad`, `input`, `savestate`, `copytable`, `bit`). Don't try to
  "fix" these — they're the host API.
- Memory reads use `memory.readbyte` / `readword`; writes use
  `memory.writebyte` / `writeword`. Addresses live in
  `src/control/memory_addresses.lua`. **Do not hardcode addresses elsewhere.**
- Input directions in `input_history` are **side-normalized** — back/forward
  always reflect "toward/away from opponent" regardless of P1/P2 side. Use
  `direction_raw` when you need the literal stick direction.
- All per-frame work that mutates state happens in `before_frame` callbacks.
  Drawing happens in `on_gui`. Don't draw in `before_frame` and don't mutate
  state in `on_gui`.
- `tools.Pools` is a small object-pool to avoid GC pressure inside the frame
  loop — match the existing pattern when allocating tables that live for one
  frame.

## Don't

- Don't edit `fbneo-training-mode-original.lua` — it is the upstream original
  kept as a fallback for non-3s ROMs.
- Don't add code paths that call `emu.registerstart` / `gui.register` /
  `emu.registerbefore` outside `3rd_training.lua`. Wire new behavior through
  a module's `update()` instead.
- Don't add new top-level dependencies (no LuaRocks here — only the bundled
  libs in `src/libs/`).
