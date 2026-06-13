# Oro Combo Challenges — Design

Date: 2026-06-13
Branch: `feature/oro-combo-challenges`
Status: Draft for review

## 1. Goal

Add a "Combo Challenges" training mode to the existing 3rd Strike training
mod, inspired by Street Fighter 6's Combo Trial.

For a first version: ship 5–6 combos for **Oro**, classified by difficulty
(beginner / intermediate / advanced). The player picks a combo, the mod
walks them through it step by step, validates each step in real time, and
gives immediate pass/fail feedback with a one-button reset.

## 2. Non-goals (this version)

- No in-game combo editor — combos live in a Lua data file.
- No characters other than Oro — architecture leaves room for more, but no
  data ships for them.
- No persisted scoring across sessions; "attempted / completed" is held in
  RAM for the session only.
- No frame-precision feedback ("you were 2 frames early"). The validator
  accepts any cancel inside the configured window. Frame-precision feedback
  is a future enhancement.
- No support for combos that branch (one combo = one linear sequence).

## 3. Integration approach

The mod already has a `training_modules` plugin system (Defense, Jump-Ins,
Footsies, Unblockables, Geneijin) wired through `src/modules.lua`. Each
training module is a folder under `src/training/<name>/` with a single
entry file exposing `start / stop / update / create_menu / process_gesture`.
The mode lifecycle (start/stop, save/restore settings, exclusivity with
other modes) is handled by `src/modes.lua`.

This feature ships as **one new training module** in that same slot. No
changes to the menu engine, the input system, or the mode framework — just
a new module name added to `training_mode_names` and a new folder.

## 4. File layout

```
src/training/combo_challenges/
├── combo_challenges.lua            module entry: lifecycle, menu, glue
├── combo_validator.lua             state machine that walks the steps
├── combo_display.lua               in-match overlay drawing
├── combo_data/
│   └── oro.lua                     5–6 Oro combos (the only data file v1)
├── localization.json               UI strings (mirrors other modules)
└── settings_default.json           per-mode defaults (auto-loaded by modules)
```

Boundaries:
- `combo_challenges.lua` owns the public surface (`start`, `stop`,
  `update`, `create_menu`, `process_gesture`, `is_mode_active`,
  `is_enabled`) and orchestrates the other two. It never draws and never
  inspects gamestate directly — those go through `combo_display` and
  `combo_validator`.
- `combo_validator.lua` takes a combo definition + a reference to the
  player/dummy gamestate objects, exposes `arm(combo)`, `tick()`,
  `reset()`, `state`. It does not draw anything and does not know the
  menu exists.
- `combo_display.lua` reads from the validator's exposed state and draws.
  It is called from `on_gui` only.
- `combo_data/oro.lua` returns a list of combo definitions. No logic, just
  data.

## 5. Combo data model

```lua
return {
  {
    id = "oro_01",
    difficulty = "beginner",          -- "beginner" | "intermediate" | "advanced"
    name = "c.MK xx Hitobashira LK",  -- shown in menu and overlay
    notation = "c.MK > qcf+LK",       -- the formal notation string
    sa = nil,                         -- 1|2|3 if a specific SA is required (else nil)
    starts_with_meter = 0,            -- 0..max; gauge to set before arming
    steps = {
      {
        kind = "normal",              -- "normal" | "special" | "super" | "jump_attack" | "throw"
        label = "c.MK",               -- displayed for this step
        animation = "<anim_hex>",     -- player.animation expected when the move comes out
        hit_animation = "<anim_hex>", -- dummy.last_received_connection_animation expected
        cancel_window = nil,          -- first step has no window
      },
      {
        kind = "special",
        label = "qcf+LK Hitobashira",
        animation = "<anim_hex>",
        hit_animation = "<anim_hex>",
        cancel_window = { min = 1, max = 20 },  -- frames between previous step's
                                                -- hit landing and this step's
                                                -- hit landing
      },
    },
  },
  -- ... 4 to 5 more combos ...
}
```

Notes:
- The `animation` / `hit_animation` values are the 4-hex-digit animation
  hashes already used by the framedata system (`bit.tohex(memory.readword(player.base + 0x202), 4)`).
  They will be captured during implementation by running each combo once
  and reading `gamestate.P1.animation` / `dummy.last_received_connection_animation`.
- The "input" the player must perform is NOT explicitly encoded — we infer
  success from the **animation that comes out** and from the **hit landing
  on the dummy**. That is more robust than trying to match motion inputs
  in a buffer, and it matches the rest of the codebase's signal model.
- For steps where the move can come out but the hit does not need to
  connect (e.g. a whiffed kara cancel), `hit_animation = nil` is allowed
  and the validator skips the hit-confirm check for that step.

## 6. Validator state machine

States: `IDLE`, `ARMED`, `RUNNING`, `SUCCESS`, `FAIL`.

```
IDLE  --arm(combo)-->  ARMED
ARMED --player attacks with step[1] move-->  RUNNING(step=1)
RUNNING(step=i) --step hits as expected-->  RUNNING(step=i+1)
RUNNING(step=last) --last step hits-->  SUCCESS
RUNNING(step=i) --wrong attack came out-->  FAIL(reason="wrong_input", at=i)
RUNNING(step=i) --combo dropped before hit-->  FAIL(reason="combo_dropped", at=i)
RUNNING(step=i) --cancel_window exceeded-->  FAIL(reason="missed_window", at=i)
SUCCESS / FAIL  --reset()-->  ARMED
```

Per-frame `tick()` logic (called from `combo_challenges.update()`):

Internal counters tracked across frames:
- `expected` — index of the next step to land (1-based).
- `last_hit_frame` — frame number when the previous step's hit landed
  (0 before any step has landed).
- `prev_dummy_combo` — `dummy.combo` from the previous frame.

Per-frame `tick()` logic (called from `combo_challenges.update()`):

1. Read `player.has_just_attacked` and `player.animation`. If a new
   attack just started AND `player.animation ~= steps[expected].animation`
   → FAIL with `wrong_input` and stop.
2. If `dummy.combo > prev_dummy_combo`:
   - If `dummy.last_received_connection_animation ==
     steps[expected].hit_animation` (or `hit_animation == nil`, the
     "whiff cancel" case):
     - If `expected > 1` and the step's `cancel_window` is set, verify
       `(current_frame - last_hit_frame)` is within `[min, max]`. If
       outside → FAIL with `missed_window`.
     - Else → step succeeds: set `last_hit_frame = current_frame`,
       increment `expected`.
   - Else → the dummy got hit by something the combo didn't ask for →
     FAIL with `wrong_input` (or treated as a stray hit; concrete behavior
     decided during implementation, see Open detail below).
3. If `expected > 1` AND `dummy.combo == 0` (combo just dropped or already
   dropped):
   - Start (or continue) a `drop_grace_counter`. If it exceeds
     `COMBO_DROP_GRACE_FRAMES = 30` → FAIL with `combo_dropped`.
4. If `expected > #steps` → SUCCESS.

Open detail to validate during implementation: the exact mapping of "step
expected to land" vs `dummy.combo` increments for combos with multi-hit
moves (e.g. a super that hits 5 times). Likely modeled as a per-step
`expected_hits` (default 1) compared against the delta of `dummy.combo`.

## 7. Menu integration

The Training tab auto-lists training modules. Adding `"combo_challenges"`
to `training_mode_names` in `src/modules.lua` puts it in the list.

`create_menu()` returns:

```
training_combo_challenges
├── Character: Oro                (label, fixed in v1)
├── Difficulty: [All|Beg|Int|Adv] (filter for the list below)
├── Combo: <list of combos>       (selecting opens the popup below)
├── ─── settings ───
├── Show notation overlay: ON/OFF
└── Show step list overlay:  ON/OFF
```

Coin = reset is hardcoded while this mode is active; no menu toggle.

Selecting a combo opens a popup (same pattern as `jumpins_edit_menu`):

```
[Combo 01 — Beginner — c.MK xx Hitobashira LK]
  c.MK > qcf+LK

  [ Start ]   (calls modes.start(combo_challenges) with this combo armed)
  [ Cancel ]
```

Pressing Start closes the menu, freezes the matchup to **Oro (P1) vs Ken
(P2)** via `character_select.force_select_character`, then arms the
validator.

## 8. In-match display

`combo_display` draws in `on_gui`:

- **Top banner** (safe area above HUD): combo `name` and `notation`.
- **Step strip** under it: one tile per step.
  - Completed step: dimmed + ✓
  - Current step: highlighted (uses `colors.text.selected`)
  - Future steps: normal text
- **Result line**: shown after SUCCESS or FAIL.
  - SUCCESS → "Combo réussi !"
  - FAIL → "Raté — step N (<reason>)" with reason localized
- Localization keys go into `localization.json` like every other module.

Drawing is done via `draw.draw_text_to_canvas` so the existing canvas
ordering is respected. No new draw primitives are introduced.

## 9. Reset / retry flow

- **Coin** (P1) → `combo_validator.reset()` + reload position (same
  savestate the mode created on start). This is wired in
  `process_gesture` so the existing `Coin = recording trigger` behavior
  is **suppressed while this mode is active** (other modes do this
  already; see `recording.process_gesture` vs
  `mode.process_gesture` in `3rd_training.lua`).
- After SUCCESS: the player can press **Coin** to retry the same combo,
  or open the menu and pick another.
- After FAIL: same — Coin resets.

The savestate used for reset is created at `start()` time: lock both
characters at the starting position, set life/meter according to the
combo definition (`starts_with_meter`, SA selection), then
`savestate.create()` so subsequent resets land on it instantly.

## 10. Open dependencies during implementation

- Capturing the `animation` / `hit_animation` hex for each Oro move used
  by the v1 combos. Plan: a tiny developer-mode debug print (gated by
  `debug_settings.developer_mode`) that logs the player's animation each
  time `has_just_attacked` is true. This is throwaway code, removed
  before merge.
- Naming and inputs of the 5–6 combos: the user will supply the list
  once this spec is approved. Spec assumes 5–6 entries with the
  difficulties indicated above.

## 11. Risks

- **Animation-hash brittleness**: animations can vary per button strength
  (LK / MK / HK Hitobashira may share an animation or not). If a step's
  animation collides across strengths, the validator can't distinguish
  them by animation alone. Mitigation: if it happens for an Oro move,
  also check the `pressed` buttons in `player.input_history` on the same
  frame the attack started. Out of scope to implement now; documented
  as a fallback.
- **Force-character interaction with online play / Fightcade**: the
  existing `character_select.force_select_character` is already used by
  other modules (e.g. `hadou_matsuri.lua`), so the path is supported.
  No change needed.
- **Combo-drop grace period (30 frames)**: in theory long enough for any
  legal cancel, but if a combo includes a long-recovery move followed by
  a juggle, 30 frames may not be enough. Constant is exposed at the top
  of `combo_validator.lua` and can be raised per-combo later via an
  optional `drop_grace_frames` field if it proves too tight.

## 12. Out-of-scope future work

- Other characters (Ken, Yun, Chun-Li, etc.).
- Per-combo persistence (best time, completion ratio).
- Frame-precision feedback for links.
- Combos with branching paths (e.g. juggle that can finish two ways).
- A JSON-backed combo format with an external editor.
