# Oro Combo Challenges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a "Combo Challenges" training mode for Oro inside the existing
3rd Strike FBNeo training mod, with step-by-step validation and one-button
retry, gated by the spec in
`docs/superpowers/specs/2026-06-13-oro-combo-challenges-design.md`.

**Architecture:** New training-module folder
`src/training/combo_challenges/`, auto-loaded via `training_mode_names` in
`src/modules.lua`. Three internal files: `combo_challenges.lua`
(lifecycle + menu glue), `combo_validator.lua` (pure FSM), `combo_display.lua`
(in-match overlay). Combo data in `combo_data/oro.lua`.

**Tech Stack:** Lua 5.1 (FBNeo host). No build, no package manager. Host
globals: `emu`, `memory`, `gui`, `joypad`, `input`, `savestate`, `bit`,
`copytable`. Project conventions in `CLAUDE.md` at repo root.

---

## Testing Strategy

This codebase has no unit test suite — code runs inside FBNeo/Fightcade. The
validator FSM is written as pure Lua (no FBNeo globals), so it could be
unit-tested if a `lua` interpreter is installed, but the system one isn't.

**Pragmatic verification** for each task:

1. `print(...)` statements go to the FBNeo Lua console (visible in Fightcade
   if you tail the log, or in FBA-RR window). Use them as in-emulator
   smoke checks.
2. Each task ends with a manual reload of the script in the emulator and a
   specific visual/console check (described per task).
3. The final task is a full manual end-to-end walkthrough.

When a step says "verify manually", it means: reload the script in the
emulator and observe the listed outcome. The user is the integration test
harness.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `src/training/combo_challenges/combo_challenges.lua` | Module public surface (`init/start/stop/update/create_menu/process_gesture`), orchestrates validator + display + lifecycle. |
| `src/training/combo_challenges/combo_validator.lua` | Pure FSM. Inputs: combo definition + a snapshot of player/dummy state per tick. Outputs: state changes and reasons. No FBNeo globals. |
| `src/training/combo_challenges/combo_display.lua` | Reads validator state and draws the overlay. Called from `on_gui` via `update()`. |
| `src/training/combo_challenges/combo_data/oro.lua` | Returns a list of combo definitions (data only). |
| `src/training/combo_challenges/localization.json` | UI strings (FR/EN/JP minimal). |
| `src/training/combo_challenges/settings_default.json` | Per-mode defaults auto-loaded by the module system. |
| `src/modules.lua` | Modify line listing `training_mode_names` to include `"combo_challenges"`. |

---

## Task 1: Module scaffolding (menu entry shows up)

**Files:**
- Create: `src/training/combo_challenges/combo_challenges.lua`
- Create: `src/training/combo_challenges/localization.json`
- Create: `src/training/combo_challenges/settings_default.json`
- Modify: `src/modules.lua` line 2

**Goal of task:** Get a stub menu entry "Combo Challenges" to appear in the
Training tab. No real behavior yet.

- [ ] **Step 1: Create `settings_default.json`**

Path: `src/training/combo_challenges/settings_default.json`

```json
{
  "show_notation_overlay": true,
  "show_step_strip": true,
  "current_difficulty_filter": 1,
  "current_combo_index": 1
}
```

- [ ] **Step 2: Create `localization.json`**

Path: `src/training/combo_challenges/localization.json`

Mirror the structure of `src/training/jumpins/localization.json` (which the
codebase already loads correctly). Use these keys minimum:

```json
{
  "en": {
    "training_combo_challenges": "Combo Challenges",
    "menu_combo": "Combo",
    "menu_difficulty_filter": "Difficulty",
    "menu_show_notation_overlay": "Show notation overlay",
    "menu_show_step_strip": "Show step strip",
    "combo_difficulty_all": "All",
    "combo_difficulty_beginner": "Beginner",
    "combo_difficulty_intermediate": "Intermediate",
    "combo_difficulty_advanced": "Advanced",
    "combo_result_success": "Combo réussi !",
    "combo_result_fail_wrong_input": "Raté — wrong move at step ",
    "combo_result_fail_missed_window": "Raté — missed timing at step ",
    "combo_result_fail_combo_dropped": "Raté — combo dropped at step ",
    "combo_result_fail_wrong_state": "Raté — wrong opponent state at step ",
    "combo_hint_coin_retry": "Coin = Retry"
  },
  "fr": {
    "training_combo_challenges": "Défis de Combos",
    "menu_combo": "Combo",
    "menu_difficulty_filter": "Difficulté",
    "menu_show_notation_overlay": "Afficher la notation",
    "menu_show_step_strip": "Afficher les étapes",
    "combo_difficulty_all": "Tous",
    "combo_difficulty_beginner": "Débutant",
    "combo_difficulty_intermediate": "Intermédiaire",
    "combo_difficulty_advanced": "Avancé",
    "combo_result_success": "Combo réussi !",
    "combo_result_fail_wrong_input": "Raté — mauvais coup à l'étape ",
    "combo_result_fail_missed_window": "Raté — fenêtre ratée à l'étape ",
    "combo_result_fail_combo_dropped": "Raté — combo cassé à l'étape ",
    "combo_result_fail_wrong_state": "Raté — état adverse incorrect à l'étape ",
    "combo_hint_coin_retry": "Pièce = Recommencer"
  },
  "jp": {
    "training_combo_challenges": "コンボチャレンジ",
    "menu_combo": "コンボ",
    "menu_difficulty_filter": "難易度",
    "menu_show_notation_overlay": "表記を表示",
    "menu_show_step_strip": "ステップを表示",
    "combo_difficulty_all": "全て",
    "combo_difficulty_beginner": "初級",
    "combo_difficulty_intermediate": "中級",
    "combo_difficulty_advanced": "上級",
    "combo_result_success": "コンボ成功！",
    "combo_result_fail_wrong_input": "失敗 — 不正な入力 ステップ ",
    "combo_result_fail_missed_window": "失敗 — タイミング ステップ ",
    "combo_result_fail_combo_dropped": "失敗 — コンボ切れ ステップ ",
    "combo_result_fail_wrong_state": "失敗 — 状態不一致 ステップ ",
    "combo_hint_coin_retry": "コイン = リトライ"
  }
}
```

- [ ] **Step 3: Create the module skeleton**

Path: `src/training/combo_challenges/combo_challenges.lua`

```lua
---@diagnostic disable: lowercase-global, undefined-global
local menu_items = require("src.ui.menu_items")
local settings = require("src.settings")

local module_name = "combo_challenges"

local is_enabled = true
local is_mode_active = false
local should_update_while_menu_is_open = false

local combo_challenges

local function init() end

local function start()
   is_mode_active = true
   print("[combo_challenges] start (stub)")
end

local function stop()
   is_mode_active = false
   print("[combo_challenges] stop (stub)")
end

local function update() end

local function process_gesture(gesture) end

local function create_menu()
   local label = menu_items.Header_Menu_Item:new("training_combo_challenges")
   return {
      name = "training_combo_challenges",
      entries = { label },
   }
end

combo_challenges = {
   name = module_name,
   init = init,
   start = start,
   stop = stop,
   update = update,
   create_menu = create_menu,
   process_gesture = process_gesture,
}

setmetatable(combo_challenges, {
   __index = function(_, key)
      if key == "is_enabled" then return is_enabled end
      if key == "is_mode_active" then return is_mode_active end
      if key == "should_update_while_menu_is_open" then
         return should_update_while_menu_is_open
      end
   end,
   __newindex = function(_, key, value)
      if key == "is_mode_active" then is_mode_active = value
      elseif key == "is_enabled" then is_enabled = value
      else rawset(combo_challenges, key, value) end
   end,
})

return combo_challenges
```

- [ ] **Step 4: Register the module**

Modify `src/modules.lua` line 2.

Before:

```lua
local training_mode_names = {"defense", "jumpins", "footsies", "unblockables", "geneijin"}
```

After:

```lua
local training_mode_names = {"defense", "jumpins", "footsies", "unblockables", "geneijin", "combo_challenges"}
```

- [ ] **Step 5: Verify in-emulator**

Load the script in Fightcade / FBNeo against `sfiii3nr1`. Press `Start` to
open the menu, go to the Training tab, scroll the mode dropdown. The new
entry "Combo Challenges" (or "Défis de Combos" / "コンボチャレンジ" based on
language setting) must appear and select cleanly without errors.

Check the FBNeo Lua console for `[combo_challenges] start (stub)` if you
trigger Start. There should be NO Lua errors.

- [ ] **Step 6: Commit**

```bash
git add src/training/combo_challenges/ src/modules.lua
git commit -m "feat(combo-challenges): scaffold module and register in training tab

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Combo data file (Oro stub combos)

**Files:**
- Create: `src/training/combo_challenges/combo_data/oro.lua`

**Goal of task:** Define the data shape used by the validator. Ship two
**stub combos** for development — real combos come from the user later.

- [ ] **Step 1: Create the data file**

Path: `src/training/combo_challenges/combo_data/oro.lua`

```lua
-- Combo definitions for Oro.
-- Schema documented in
-- docs/superpowers/specs/2026-06-13-oro-combo-challenges-design.md §5.

return {
   {
      id = "oro_dev_01",
      difficulty = "beginner",
      name = "c.MK xx Hitobashira LK",
      notation = "c.MK > qcf+LK",
      sa = nil,
      starts_with_meter = 0,
      steps = {
         {
            kind = "normal",
            label = "c.MK",
            move = "crouch_mk",
            button = nil,
            cancel_window = nil,
         },
         {
            kind = "special",
            label = "qcf+LK Hitobashira",
            move = "hitobashira",
            button = "LK",
            cancel_window = { min = 1, max = 20 },
         },
      },
   },
   {
      id = "oro_dev_02",
      difficulty = "intermediate",
      name = "c.LK, c.MK xx Hitobashira MK",
      notation = "c.LK, c.MK > qcf+MK",
      sa = nil,
      starts_with_meter = 0,
      steps = {
         {
            kind = "normal",
            label = "c.LK",
            move = "crouch_lk",
            button = nil,
            cancel_window = nil,
         },
         {
            kind = "normal",
            label = "c.MK",
            move = "crouch_mk",
            button = nil,
            cancel_window = { min = 1, max = 16 },
         },
         {
            kind = "special",
            label = "qcf+MK Hitobashira",
            move = "hitobashira",
            button = "MK",
            cancel_window = { min = 1, max = 20 },
         },
      },
   },
}
```

Note about move names: `crouch_mk`, `crouch_lk`, `hitobashira` are the names
used inside `data/sfiii3nr1/framedata/@oro_framedata.json` (the framedata
JSON uses `name = "hitobashira_LK"` etc.; `framedata.find_frame_data_by_name`
joins `name + "_" + button` internally — confirm during Task 3 step 4).

- [ ] **Step 2: Smoke-load the data from the module**

Edit `src/training/combo_challenges/combo_challenges.lua` — add at the top
after the existing requires:

```lua
local oro_combos = require("src.training.combo_challenges.combo_data.oro")
```

Add inside `init()`:

```lua
local function init()
   print(string.format("[combo_challenges] loaded %d Oro combos", #oro_combos))
end
```

- [ ] **Step 3: Verify in-emulator**

Reload the script. The console should print
`[combo_challenges] loaded 2 Oro combos`. No errors.

- [ ] **Step 4: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): add Oro combo data file with two dev combos

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Validator state machine (pure logic)

**Files:**
- Create: `src/training/combo_challenges/combo_validator.lua`

**Goal of task:** Implement the FSM described in spec §6 as pure Lua (no
FBNeo globals). It takes a combo + a per-frame snapshot of relevant
gamestate fields and returns its state.

- [ ] **Step 1: Create the validator module**

Path: `src/training/combo_challenges/combo_validator.lua`

```lua
-- Pure Lua FSM. No emu / memory / gui calls anywhere in this file.
-- The caller provides a snapshot table each tick; the validator decides
-- whether to advance, fail, or succeed.

local M = {}

M.STATE = {
   IDLE    = "IDLE",
   ARMED   = "ARMED",
   RUNNING = "RUNNING",
   SUCCESS = "SUCCESS",
   FAIL    = "FAIL",
}

M.FAIL_REASON = {
   WRONG_INPUT    = "wrong_input",
   MISSED_WINDOW  = "missed_window",
   COMBO_DROPPED  = "combo_dropped",
   WRONG_STATE    = "wrong_state",
}

local COMBO_DROP_GRACE_FRAMES = 30

-- Create a new validator instance.
-- `resolve_animation` is a callback (move, button) -> animation hash string
-- supplied by the caller, so the FSM stays pure.
function M.new(resolve_animation)
   local self = {
      state = M.STATE.IDLE,
      combo = nil,
      expected = 1,                  -- 1-based index of the next step
      last_hit_frame = 0,
      prev_dummy_combo = 0,
      drop_grace_counter = 0,
      fail_reason = nil,
      fail_step = nil,
      _resolve = resolve_animation,
   }

   -- Resolve and cache the player_anim hash for each step.
   local function arm(combo)
      assert(combo and combo.steps and #combo.steps > 0,
         "validator.arm: combo with at least one step required")
      self.combo = combo
      for _, step in ipairs(combo.steps) do
         step.player_anim = self._resolve(step.move, step.button)
         assert(step.player_anim,
            "validator.arm: could not resolve animation for "
            .. tostring(step.move) .. " / " .. tostring(step.button))
      end
      self.state = M.STATE.ARMED
      self.expected = 1
      self.last_hit_frame = 0
      self.prev_dummy_combo = 0
      self.drop_grace_counter = 0
      self.fail_reason = nil
      self.fail_step = nil
   end

   local function reset()
      self.state = self.combo and M.STATE.ARMED or M.STATE.IDLE
      self.expected = 1
      self.last_hit_frame = 0
      self.prev_dummy_combo = 0
      self.drop_grace_counter = 0
      self.fail_reason = nil
      self.fail_step = nil
   end

   local function fail(reason)
      self.state = M.STATE.FAIL
      self.fail_reason = reason
      self.fail_step = self.expected
   end

   -- `snapshot` shape (caller fills it from gamestate each frame):
   -- {
   --   frame                  = number,
   --   player_has_just_attacked = boolean,
   --   player_animation        = string,         -- 4-hex-digit hash
   --   dummy_combo             = number,
   --   dummy_last_received_anim = string,        -- nil ok
   --   dummy_is_juggled        = boolean,
   --   dummy_is_airborne       = boolean,
   --   dummy_hitstun_remaining = number,         -- nil ok
   -- }
   local function tick(snap)
      if self.state ~= M.STATE.ARMED and self.state ~= M.STATE.RUNNING then
         return self.state
      end

      local step = self.combo.steps[self.expected]

      -- (1) Wrong-input detection: player started a new attack that does
      -- not match the expected step's animation.
      if snap.player_has_just_attacked
         and snap.player_animation ~= step.player_anim
      then
         fail(M.FAIL_REASON.WRONG_INPUT)
         return self.state
      end

      -- (2) A hit just landed this frame.
      if snap.dummy_combo > self.prev_dummy_combo then
         local matches_expected =
            (step.must_hit == false)
            or (snap.dummy_last_received_anim == step.player_anim)

         if matches_expected then
            -- Cancel window check (steps 2..N).
            if self.expected > 1 and step.cancel_window then
               local delta = snap.frame - self.last_hit_frame
               if delta < step.cancel_window.min
                  or delta > step.cancel_window.max
               then
                  fail(M.FAIL_REASON.MISSED_WINDOW)
                  self.prev_dummy_combo = snap.dummy_combo
                  return self.state
               end
            end

            -- Dummy state requirements.
            if step.requires_dummy_juggle and not snap.dummy_is_juggled then
               fail(M.FAIL_REASON.WRONG_STATE)
               self.prev_dummy_combo = snap.dummy_combo
               return self.state
            end
            if step.requires_dummy_in_air and not snap.dummy_is_airborne then
               fail(M.FAIL_REASON.WRONG_STATE)
               self.prev_dummy_combo = snap.dummy_combo
               return self.state
            end
            if step.min_hitstun_remaining
               and (snap.dummy_hitstun_remaining or 0) < step.min_hitstun_remaining
            then
               fail(M.FAIL_REASON.WRONG_STATE)
               self.prev_dummy_combo = snap.dummy_combo
               return self.state
            end

            -- Step succeeded.
            self.state = M.STATE.RUNNING
            self.last_hit_frame = snap.frame
            self.expected = self.expected + 1
            self.drop_grace_counter = 0

            if self.expected > #self.combo.steps then
               self.state = M.STATE.SUCCESS
            end
         else
            -- Hit landed but from an animation we did not expect.
            if not step.ignore_extra_hits then
               fail(M.FAIL_REASON.WRONG_INPUT)
            end
         end
      end

      -- (3) Combo-drop grace period.
      if self.expected > 1
         and snap.dummy_combo == 0
         and self.state ~= M.STATE.SUCCESS
         and self.state ~= M.STATE.FAIL
      then
         self.drop_grace_counter = self.drop_grace_counter + 1
         if self.drop_grace_counter > COMBO_DROP_GRACE_FRAMES then
            fail(M.FAIL_REASON.COMBO_DROPPED)
         end
      end

      self.prev_dummy_combo = snap.dummy_combo
      return self.state
   end

   self.arm = arm
   self.reset = reset
   self.tick = tick
   return self
end

M.COMBO_DROP_GRACE_FRAMES = COMBO_DROP_GRACE_FRAMES
return M
```

- [ ] **Step 2: Add a smoke-test harness inside the module**

Append at the bottom of `combo_challenges.lua`, **before the `return`
statement**:

```lua
-- Throwaway dev-mode smoke test for the validator FSM.
local function smoke_test_validator()
   local validator = require("src.training.combo_challenges.combo_validator")

   local fake_anims = { crouch_mk = "1111", hitobashira_LK = "2222" }
   local resolve = function(move, button)
      if button then return fake_anims[move .. "_" .. button] end
      return fake_anims[move]
   end

   local combo = oro_combos[1]
   local v = validator.new(resolve)
   v.arm(combo)
   assert(v.state == validator.STATE.ARMED, "expected ARMED, got " .. v.state)

   -- Step 1: c.MK comes out and lands on frame 100.
   v.tick({
      frame = 100,
      player_has_just_attacked = true,
      player_animation = "1111",
      dummy_combo = 1,
      dummy_last_received_anim = "1111",
   })
   assert(v.state == validator.STATE.RUNNING, "expected RUNNING after step 1")
   assert(v.expected == 2, "expected step 2 next")

   -- Step 2: Hitobashira LK lands on frame 110 (inside [1, 20] window).
   v.tick({
      frame = 110,
      player_has_just_attacked = true,
      player_animation = "2222",
      dummy_combo = 2,
      dummy_last_received_anim = "2222",
   })
   assert(v.state == validator.STATE.SUCCESS,
          "expected SUCCESS, got " .. v.state)

   print("[combo_challenges] validator smoke test passed")
end
```

And call it from `init()`:

```lua
local function init()
   print(string.format("[combo_challenges] loaded %d Oro combos", #oro_combos))
   smoke_test_validator()
end
```

- [ ] **Step 3: Verify in-emulator**

Reload script. Console must print:

```
[combo_challenges] loaded 2 Oro combos
[combo_challenges] validator smoke test passed
```

If an assertion fires, Lua prints a traceback to the console — fix the FSM
until the smoke test passes.

- [ ] **Step 4: Verify framedata move-name resolution actually works**

Add a one-shot probe in `init()` AFTER the smoke test:

```lua
local framedata = require("src.data.framedata")
print("[combo_challenges] crouch_mk anim:",
      framedata.find_frame_data_by_name("oro", "crouch_mk"))
print("[combo_challenges] hitobashira LK anim:",
      framedata.find_frame_data_by_name("oro", "hitobashira", "LK"))
```

Reload. The console must show two 4-hex-digit animation hashes (or
`nil` if the move name is wrong — in which case adjust the names in
`combo_data/oro.lua` based on what the JSON actually contains under
`data/sfiii3nr1/framedata/@oro_framedata.json`, e.g. it might be
`crouching_mk` or `c.mk`).

Once both lines print real hashes, **delete the probe lines and the
smoke test call from `init()`** (keep `smoke_test_validator` as a
function so it's easy to re-enable; just don't call it on every
init).

- [ ] **Step 5: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): add pure-Lua validator FSM with smoke test

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Wire validator into the update loop

**Files:**
- Modify: `src/training/combo_challenges/combo_challenges.lua`

**Goal of task:** When the mode is active, every frame: build a snapshot
from `gamestate.P1` / `P2`, tick the validator, log state transitions.
No drawing yet — output is on the FBNeo console.

- [ ] **Step 1: Add the gamestate + framedata requires**

At the top of `combo_challenges.lua`:

```lua
local gamestate = require("src.gamestate")
local framedata = require("src.data.framedata")
local validator_module = require("src.training.combo_challenges.combo_validator")
```

- [ ] **Step 2: Locate the dummy juggle / hitstun field names**

Read `src/gamestate.lua` and search for `juggle`, `air_time`, `air_timer`,
`hitstun`, `stun_timer`. Pick the field that represents "remaining
hitstun on the player" (NOT meter stun — those are different) and the
flag/field for "is currently juggled". Note them at the top of the
module file as local variables:

```lua
-- Field names verified against src/gamestate.lua (see Task 4 step 2).
-- These reference fields on a gamestate player object.
local DUMMY_HITSTUN_FIELD  = "remaining_hitstun_time"  -- TODO: confirm actual name
local DUMMY_JUGGLE_FIELD   = "is_juggled"              -- TODO: confirm actual name
local DUMMY_AIRBORNE_FIELD = "is_airborne"             -- TODO: confirm actual name
```

If the names above don't exist, replace with the closest matches. If a
concept doesn't exist at all, set its field name to `nil` and the
snapshot will report `false` / `0` — the optional step fields just
won't fire, which is acceptable for v1 since the dev combos don't use
them yet.

- [ ] **Step 3: Create the active state holder and snapshot builder**

Add module-level state in `combo_challenges.lua`:

```lua
local active_combo = nil
local active_validator = nil
local last_logged_state = nil

local function build_snapshot(player, dummy)
   local hitstun = DUMMY_HITSTUN_FIELD and dummy[DUMMY_HITSTUN_FIELD] or 0
   local is_juggled = DUMMY_JUGGLE_FIELD and dummy[DUMMY_JUGGLE_FIELD] or false
   local is_airborne = DUMMY_AIRBORNE_FIELD and dummy[DUMMY_AIRBORNE_FIELD] or false
   return {
      frame = gamestate.frame_number,
      player_has_just_attacked = player.has_just_attacked or false,
      player_animation = player.animation,
      dummy_combo = dummy.combo or 0,
      dummy_last_received_anim = dummy.last_received_connection_animation,
      dummy_is_juggled = is_juggled,
      dummy_is_airborne = is_airborne,
      dummy_hitstun_remaining = hitstun,
   }
end
```

- [ ] **Step 4: Build a resolver and wire `start`/`update`**

Replace the existing `start`, `stop`, `update` stubs with:

```lua
local function resolve_oro_animation(move, button)
   local anim_hex = framedata.find_frame_data_by_name("oro", move, button)
   return anim_hex
end

local function arm_combo_for_dev()
   active_combo = oro_combos[1]            -- TEMP: hard-armed for dev only
   active_validator = validator_module.new(resolve_oro_animation)
   active_validator.arm(active_combo)
   last_logged_state = active_validator.state
   print("[combo_challenges] armed combo: " .. active_combo.id)
end

local function start()
   is_mode_active = true
   arm_combo_for_dev()
end

local function stop()
   is_mode_active = false
   active_combo = nil
   active_validator = nil
   print("[combo_challenges] stopped")
end

local function update()
   if not is_mode_active or not active_validator then return end
   if not gamestate.is_in_match then return end
   local snap = build_snapshot(gamestate.P1, gamestate.P2)
   active_validator.tick(snap)
   if active_validator.state ~= last_logged_state then
      print(string.format(
         "[combo_challenges] state %s -> %s (step=%d reason=%s)",
         tostring(last_logged_state),
         tostring(active_validator.state),
         active_validator.expected,
         tostring(active_validator.fail_reason)))
      last_logged_state = active_validator.state
   end
end
```

Also add a temporary Start button so you can actually trigger `start()`
from the menu without doing the full lifecycle yet. Replace
`create_menu()` with:

```lua
local function create_menu()
   local label = menu_items.Header_Menu_Item:new("training_combo_challenges")
   local start_btn = menu_items.Button_Menu_Item:new("menu_start", function()
      local modes = require("src.modes")
      local menu = require("src.ui.menu")
      menu.close_menu()
      modes.start(combo_challenges)
   end)
   return {
      name = "training_combo_challenges",
      entries = { label, start_btn },
   }
end
```

- [ ] **Step 5: Verify in-emulator**

Pick Oro for P1 (any character for P2 — Ken recommended). Start the
match. Open the menu, go to Training → Combo Challenges → "Start". The
console should print `armed combo: oro_dev_01`.

Hit the dummy with c.MK. Console should print
`state ARMED -> RUNNING (step=2 reason=nil)`.

Cancel into qcf+LK Hitobashira within ~20 frames. Console should print
`state RUNNING -> SUCCESS (step=3 reason=nil)`.

Try hitting the dummy with a wrong move first instead → expect
`state ARMED -> FAIL (step=1 reason=wrong_input)`.

If any of these don't print the expected transition, debug by adding
more `print` calls in `tick()`. Do NOT proceed until the FSM
transitions cleanly.

- [ ] **Step 6: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): wire validator to gamestate in update loop

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: In-match display module

**Files:**
- Create: `src/training/combo_challenges/combo_display.lua`
- Modify: `src/training/combo_challenges/combo_challenges.lua`

**Goal of task:** Draw the overlay (top banner, step strip, result line,
Coin hint) instead of printing to console.

- [ ] **Step 1: Create the display module**

Path: `src/training/combo_challenges/combo_display.lua`

```lua
---@diagnostic disable: lowercase-global, undefined-global
local draw = require("src.ui.draw")
local colors = require("src.ui.colors")

local M = {}

-- Layout constants (screen is 383 x 223).
local BANNER_X     = 6
local BANNER_Y     = 4
local STRIP_Y      = 18
local STRIP_TILE_W = 60
local STRIP_TILE_H = 12
local RESULT_Y     = 36
local HINT_X       = 6
local HINT_Y       = 215

local function safe_text(key_or_text)
   -- Localization layer wraps text in the menu; here we accept raw strings
   -- already resolved by the caller. Keep this as a passthrough.
   return tostring(key_or_text)
end

function M.draw(view)
   if not view or not view.combo then return end

   if view.show_notation then
      local title = string.format("%s [%s]", view.combo.name, view.combo.difficulty)
      draw.draw_text(BANNER_X, BANNER_Y, title, nil, colors.text.default)
      draw.draw_text(BANNER_X, BANNER_Y + 8, view.combo.notation, nil, colors.text.default)
   end

   if view.show_steps then
      for i, step in ipairs(view.combo.steps) do
         local x = BANNER_X + (i - 1) * STRIP_TILE_W
         local color = colors.text.default
         if i < view.current_step then
            color = colors.text.dim or colors.text.default
         elseif i == view.current_step then
            color = colors.text.selected
         end
         draw.draw_text(x, STRIP_Y, step.label, nil, color)
      end
   end

   if view.result_text then
      draw.draw_text(BANNER_X, RESULT_Y, view.result_text, nil, colors.text.selected)
   end

   draw.draw_text(HINT_X, HINT_Y, view.coin_hint, nil, colors.text.default)
end

return M
```

If `colors.text.dim` doesn't exist (check `src/ui/colors.lua` first), use
`colors.text.default` as the dim fallback. If `colors.text.selected`
doesn't exist either, find the equivalent (look for what
`menu_items.lua` uses for highlighting and reuse the same color).

- [ ] **Step 2: Wire the display from the module**

In `combo_challenges.lua`, add the requires near the top:

```lua
local display = require("src.training.combo_challenges.combo_display")
local image_tables = require("src.ui.image_tables")
```

Add a localization helper. The mod's text rendering pipeline keys text
on `image_tables.text[key]`; if a key is missing, fall back to the key
itself so layout doesn't break:

```lua
local function L(key)
   if not key then return "" end
   local entry = image_tables.text and image_tables.text[key]
   if not entry then return key end
   return entry
end
```

If `image_tables.text` is not the right surface for runtime localized
text (verify by grepping `image_tables.text` in
`src/ui/menu_items.lua` and `src/ui/draw.lua`), fall back to passing
raw keys to `draw.draw_text` — `draw.draw_text` already routes through
the image-based renderer and resolves localization keys by name on its
own when one matches. In that case `L(key)` becomes identity:

```lua
local function L(key) return key or "" end
```

Replace the `update` function with a version that builds a "view"
object and calls `display.draw`:

```lua
local function current_result_text()
   if not active_validator then return nil end
   local s = active_validator.state
   if s == validator_module.STATE.SUCCESS then
      return L("combo_result_success")
   elseif s == validator_module.STATE.FAIL then
      local key_by_reason = {
         [validator_module.FAIL_REASON.WRONG_INPUT]   = "combo_result_fail_wrong_input",
         [validator_module.FAIL_REASON.MISSED_WINDOW] = "combo_result_fail_missed_window",
         [validator_module.FAIL_REASON.COMBO_DROPPED] = "combo_result_fail_combo_dropped",
         [validator_module.FAIL_REASON.WRONG_STATE]   = "combo_result_fail_wrong_state",
      }
      local key = key_by_reason[active_validator.fail_reason]
      if not key then return nil end
      return L(key) .. tostring(active_validator.fail_step)
   end
   return nil
end

local function update()
   if not is_mode_active or not active_validator then return end
   if not gamestate.is_in_match then return end

   local snap = build_snapshot(gamestate.P1, gamestate.P2)
   active_validator.tick(snap)

   display.draw({
      combo = active_combo,
      current_step = active_validator.expected,
      show_notation = settings.training.combo_challenges
         and settings.training.combo_challenges.show_notation_overlay
         or true,
      show_steps = settings.training.combo_challenges
         and settings.training.combo_challenges.show_step_strip
         or true,
      result_text = current_result_text(),
      coin_hint = L("combo_hint_coin_retry"),
   })
end
```

**Important**: per `CLAUDE.md`, drawing must happen during `on_gui`, NOT
`before_frame`. The mode's `update()` is called from inside the
`before_frame` callback (see `3rd_training.lua:322` →
`modules.update()`). Drawing from there is what every other training
module (e.g. `jumpins`) does because `draw.draw_text` queues into
canvases that flush during `on_gui`. So calling `display.draw()` from
`update()` is fine. Confirm by checking `jumpins_display` in
`src/training/jumpins/jumpins.lua` — it follows the same pattern.

- [ ] **Step 3: Verify in-emulator**

Reload. Start the mode from the menu. The console-only logs from Task 4
are now replaced with an on-screen overlay:

- "c.MK xx Hitobashira LK [beginner]" banner top-left.
- "c.MK > qcf+LK" notation below it.
- Step strip below, with `c.MK` highlighted at start.
- "Coin = Retry" / "Pièce = Recommencer" at the bottom-left.

Hit the dummy with c.MK → the highlight moves to `qcf+LK Hitobashira`.
Land Hitobashira within the window → "Combo réussi !" appears.

If anything overlaps with the existing HUD, adjust the layout constants
at the top of `combo_display.lua`. The screen is 383×223; bottom 8 rows
are typically free for hints.

- [ ] **Step 4: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): draw overlay (banner, step strip, result)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: Real menu (difficulty filter + combo list)

**Files:**
- Modify: `src/training/combo_challenges/combo_challenges.lua`

**Goal of task:** Replace the dev "Start" button with the real menu: a
difficulty filter, a list of combos that arms the chosen one on validate,
and settings toggles for the in-match overlay.

- [ ] **Step 1: Add settings defaults at module load**

In `combo_challenges.lua` `init()`:

```lua
local function init()
   settings.training.combo_challenges = settings.training.combo_challenges
      or { show_notation_overlay = true, show_step_strip = true,
           current_difficulty_filter = 1, current_combo_index = 1 }
end
```

- [ ] **Step 2: Build the filter + list**

Define module-level tables and helpers in `combo_challenges.lua`:

```lua
local DIFFICULTY_FILTERS = {
   "combo_difficulty_all",
   "combo_difficulty_beginner",
   "combo_difficulty_intermediate",
   "combo_difficulty_advanced",
}

local DIFFICULTY_KEY = { "all", "beginner", "intermediate", "advanced" }

local filtered_combos = {}
local combo_names = {}

local function refresh_filtered_combos()
   filtered_combos = {}
   combo_names = {}
   local filter = DIFFICULTY_KEY[settings.training.combo_challenges.current_difficulty_filter]
   for _, c in ipairs(oro_combos) do
      if filter == "all" or c.difficulty == filter then
         table.insert(filtered_combos, c)
         table.insert(combo_names, c.name)
      end
   end
   if #filtered_combos == 0 then
      table.insert(combo_names, "—")
   end
end
```

- [ ] **Step 3: Replace `create_menu`**

The popup-with-notation step was dropped from the original spec: the
notation is already shown on the in-match overlay, and the `Label_Menu_Item`
constructor (`name, text_table, object, property, small, inline`) is too
awkward for displaying a free-form combo notation string. Cleaner: the
combo list's `validate_function` arms the combo and starts the mode
directly, no popup. The user always sees the notation once the mode
starts because the overlay drawn in Task 5 includes it.

```lua
local function arm_and_start(combo)
   local modes = require("src.modes")
   local menu = require("src.ui.menu")
   active_combo = combo
   active_validator = validator_module.new(resolve_oro_animation)
   active_validator.arm(active_combo)
   menu.close_menu()
   modes.start(combo_challenges)
end

local function create_menu()
   refresh_filtered_combos()
   local difficulty_item = menu_items.List_Menu_Item:new(
      "menu_difficulty_filter",
      settings.training.combo_challenges,
      "current_difficulty_filter",
      DIFFICULTY_FILTERS,
      1)
   difficulty_item.on_change = function()
      refresh_filtered_combos()
      settings.training.combo_challenges.current_combo_index = 1
   end

   local combo_item = menu_items.List_Menu_Item:new(
      "menu_combo",
      settings.training.combo_challenges,
      "current_combo_index",
      combo_names,
      1)
   combo_item.validate_function = function()
      local i = settings.training.combo_challenges.current_combo_index
      local combo = filtered_combos[i]
      if not combo then return end
      arm_and_start(combo)
   end

   local notation_overlay_item = menu_items.On_Off_Menu_Item:new(
      "menu_show_notation_overlay",
      settings.training.combo_challenges,
      "show_notation_overlay", true)

   local step_strip_item = menu_items.On_Off_Menu_Item:new(
      "menu_show_step_strip",
      settings.training.combo_challenges,
      "show_step_strip", true)

   return {
      name = "training_combo_challenges",
      entries = { difficulty_item, combo_item,
                  notation_overlay_item, step_strip_item },
   }
end
```

- [ ] **Step 4: Remove the dev `arm_combo_for_dev` call**

Replace `start()`:

```lua
local function start()
   is_mode_active = true
   if not active_validator then
      -- Defensive: should have been armed via validate_function; if
      -- not, fall back to the first combo so the mode is still usable.
      active_combo = oro_combos[1]
      active_validator = validator_module.new(resolve_oro_animation)
      active_validator.arm(active_combo)
   end
   print("[combo_challenges] start: " .. active_combo.id)
end
```

- [ ] **Step 5: Verify in-emulator**

Reload. Open menu → Training → Combo Challenges. Difficulty toggle
between All / Beginner / Intermediate / Advanced changes the combo
list. Selecting a combo (LP in the menu) closes the menu and arms
the chosen combo. The overlay shows that specific combo's name and
steps.

- [ ] **Step 6: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): real menu with difficulty filter and combo list

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: Start lifecycle (force Oro vs Ken, savestate for reset)

**Files:**
- Modify: `src/training/combo_challenges/combo_challenges.lua`

**Goal of task:** When the mode starts, force P1 = Oro and P2 = Ken,
set the meter according to the combo, and save a savestate. Reset
loads that savestate.

- [ ] **Step 1: Read existing force-char + savestate patterns**

Read `src/control/character_select.lua` lines 130–200 and the start of
`src/challenge/hadou_matsuri.lua` for an example of
`Register_After_Load_State` + `force_select_character` usage. Note the
SA argument convention (1, 2, 3) and the selection button.

- [ ] **Step 2: Add lifecycle helpers**

In `combo_challenges.lua`:

```lua
local character_select = require("src.control.character_select")
local game_data = require("src.data.game_data")

local combo_reset_savestate = nil

local function set_meter_for_combo(combo)
   if not combo.starts_with_meter then return end
   -- combo.starts_with_meter is 0..max; write to gauge address.
   local addr = gamestate.P1.addresses
   memory.writebyte(addr.gauge, math.min(combo.starts_with_meter,
                                         gamestate.P1.max_meter_gauge or 96))
end

local function force_matchup_for_combo(combo)
   local sa = combo.sa or 1
   character_select.force_select_character(1, "oro", sa, "HK")
   character_select.force_select_character(2, "ken", 1, "HK")
end

local function save_reset_point()
   combo_reset_savestate = savestate.create()
   savestate.save(combo_reset_savestate)
   print("[combo_challenges] reset point saved")
end

local function reload_reset_point()
   if combo_reset_savestate then
      savestate.load(combo_reset_savestate)
      if active_validator then
         active_validator.reset()
      end
   end
end
```

- [ ] **Step 3: Hook into `start`**

Replace `start()`:

```lua
local function start()
   is_mode_active = true
   if not active_validator then
      active_combo = oro_combos[1]
      active_validator = validator_module.new(resolve_oro_animation)
      active_validator.arm(active_combo)
   end
   force_matchup_for_combo(active_combo)
   -- Save the reset point one frame after the round actually starts so
   -- the savestate captures a clean idle state. We register a callback.
   Register_Load_State_Callback(function()
      -- One-shot: after character_select.force_select_character finishes
      -- and the round starts, save the state. Other modes use
      -- Call_After_Load_State / Register_After_Load_State — pick the
      -- one that fires exactly once after the curtain is up.
   end)
   set_meter_for_combo(active_combo)
   save_reset_point()
   print("[combo_challenges] start: " .. active_combo.id)
end
```

The Register_Load_State_Callback / Call_After_Load_State /
Register_After_Load_State surface is in `3rd_training.lua` lines 95–107
and in `src/challenge/hadou_matsuri.lua`. Read both and pick the
matching idiom: we want to save the state AFTER the curtain just began
and the players are in idle. If the API doesn't expose a clean
once-after-round-start hook, fall back to:

```lua
-- In update(), the first frame is_in_match AND has_curtain_just_began,
-- save the reset point if we haven't already.
```

(Add a `pending_save_reset_point` boolean if needed.)

- [ ] **Step 4: Hook into `stop`**

```lua
local function stop()
   is_mode_active = false
   active_combo = nil
   active_validator = nil
   combo_reset_savestate = nil
   print("[combo_challenges] stop")
end
```

- [ ] **Step 5: Verify in-emulator**

Pick any matchup. Open menu → Training → Combo Challenges, pick a combo,
Start. The mod should automatically take you to character select, select
Oro for P1 and Ken for P2, start the round. Hit the dummy with the
combo. Then press Coin once (Task 8 will wire this — for now, manually
test that `reload_reset_point()` works by calling it from a temporary
hotkey or after success). Position should return to the saved one.

- [ ] **Step 6: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): force Oro vs Ken matchup and save reset point

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: Coin = reset wiring

**Files:**
- Modify: `src/training/combo_challenges/combo_challenges.lua`

**Goal of task:** While the mode is active, a single Coin tap reloads the
reset point and re-arms the validator. The recording.process_gesture
path is suppressed automatically because `modes.active_mode` owns
gestures.

- [ ] **Step 1: Implement `process_gesture`**

```lua
local function process_gesture(gesture)
   if not is_mode_active then return end
   if gesture == "single_tap" then
      reload_reset_point()
      print("[combo_challenges] coin reset")
   end
end
```

Confirm `combo_challenges.process_gesture` is exported in the module
table at the bottom. (It was set in Task 1, but check it survived later
edits.)

- [ ] **Step 2: Verify in-emulator**

Start a combo. Drop it intentionally (do nothing after the first hit).
After ~30 frames the overlay shows "Raté — combo cassé à l'étape 1".
Tap Coin once → ~12 frames later (gesture buffer in
`inputs.interpret_gesture`), the position resets, P1 is back at the
starting position, and the overlay shows the first step highlighted
again.

Tap Coin twice fast → triggers `double_tap`, which `process_gesture`
ignores → nothing should happen (no recording starts, because the mode
owns the gesture and recording.process_gesture is not called when a
mode is active; verified at `3rd_training.lua:323`).

- [ ] **Step 3: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "feat(combo-challenges): single-tap Coin resets the active combo

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: Polish — controller scheme + remove dev logs

**Files:**
- Modify: `src/training/combo_challenges/combo_challenges.lua`

**Goal of task:** Remove the `print()` lines used for debugging, ensure
the mode coexists cleanly with the controller-swap helpers other modes
use (see `get_valid_control_schemes` in `jumpins.lua`).

- [ ] **Step 1: Add `get_valid_control_schemes`**

In `combo_challenges.lua`:

```lua
local function get_valid_control_schemes()
   -- The player must control P1 (Oro). P2 is the dummy. Mirror jumpins.
   return { { p1 = "player", p2 = "dummy_control" } }
end
```

Export it in the module table:

```lua
combo_challenges = {
   name = module_name,
   init = init,
   start = start,
   stop = stop,
   update = update,
   create_menu = create_menu,
   process_gesture = process_gesture,
   get_valid_control_schemes = get_valid_control_schemes,
}
```

- [ ] **Step 2: Remove dev prints**

Delete every `print("[combo_challenges] ...")` line from
`combo_challenges.lua` EXCEPT the one inside `smoke_test_validator`
(that one is harmless because the function is no longer called from
`init`).

Keep `print` statements that fire only on `assert` failures inside the
validator — those are intentional.

- [ ] **Step 3: Verify in-emulator**

Reload. Console must be quiet during normal play of the mode. No more
state-transition spam. Functionality unchanged.

- [ ] **Step 4: Commit**

```bash
git add src/training/combo_challenges/
git commit -m "chore(combo-challenges): remove dev prints, add control scheme

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: End-to-end manual validation

**Files:** none modified.

**Goal of task:** Walk through the full feature one time and write up
what works / what's flaky. No code change unless a bug is found.

- [ ] **Step 1: Boot the mod from a fresh Fightcade launch**

Quit Fightcade entirely, relaunch, start training mode, confirm:
- No Lua errors on startup.
- Training tab contains "Combo Challenges" / "Défis de Combos" /
  "コンボチャレンジ" depending on language.

- [ ] **Step 2: Beginner combo path**

Select Combo `oro_dev_01` (c.MK xx Hitobashira LK). Start.
- Matchup forces to Oro vs Ken.
- Overlay shows the banner, notation, step strip, "Coin = Retry".
- Land c.MK → step 2 highlights.
- Land Hitobashira LK within ~20 frames → "Combo réussi !".

- [ ] **Step 3: Failure paths**

For each, observe the overlay shows the right message:
- Throw a Hadouken-equivalent (wrong attack) first → `wrong_input`.
- Land c.MK then wait > 20 frames before Hitobashira → `missed_window`.
- Land c.MK and do nothing → after 30 frames of dummy.combo == 0 →
  `combo_dropped`.

- [ ] **Step 4: Coin reset**

After SUCCESS, tap Coin → position reset, step strip back to step 1.
After FAIL, tap Coin → same.
Tap Coin during a successful step 1 mid-combo → resets cleanly too.

- [ ] **Step 5: Intermediate combo path**

Repeat steps 2–4 for `oro_dev_02` (c.LK, c.MK xx Hitobashira MK). This
validates a 3-step combo with two different cancel windows.

- [ ] **Step 6: Mode lifecycle**

Press Start (Start gamepad button) → menu opens → press Start again →
holds Start for >16 frames → mode stops, controller settings restored.

- [ ] **Step 7: Write findings**

If everything works, commit a one-line note in
`docs/superpowers/plans/2026-06-13-oro-combo-challenges.md` at the very
bottom:

```markdown
## Validation note

End-to-end manual validation passed on YYYY-MM-DD. Mode is ready for
real combo data input from the user.
```

If something is broken, file findings into the same section as a
bulleted list — those become the v1.1 backlog.

- [ ] **Step 8: Commit (only if Step 7 added text)**

```bash
git add docs/superpowers/plans/
git commit -m "docs(combo-challenges): record v1 manual validation outcome

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Out of scope for this plan

Items below are intentionally NOT in any task; they are explicit follow-ups
from the spec §12 or known limitations of this v1:

- Real Oro combos (user supplies them after Task 10 passes — they slot
  directly into `combo_data/oro.lua` with no code changes).
- Other characters (`combo_data/<char>.lua` plus a small character-pick
  branch in `force_matchup_for_combo`).
- Per-combo persisted scoring.
- Frame-precision feedback ("you were N frames off").
- Branching combos.
- Re-enabling the validator smoke test as a real unit test (would need a
  system `lua` interpreter or LÖVE).
