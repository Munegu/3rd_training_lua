---@diagnostic disable: lowercase-global, undefined-global
local menu_items = require("src.ui.menu_items")
local settings = require("src.settings")
local oro_combos = require("src.training.combo_challenges.combo_data.oro")
local gamestate = require("src.gamestate")
local framedata = require("src.data.framedata")
local validator_module = require("src.training.combo_challenges.combo_validator")
local display = require("src.training.combo_challenges.combo_display")
local tools = require("src.tools")
local character_select = require("src.control.character_select")
local hud = require("src.ui.hud")

-- Localization: image_tables.text stores pre-rendered image glyphs for
-- known menu keys; our combo keys are not in that table. Pass resolved
-- human-readable strings to draw.render_text so it renders char-by-char.
-- _loc_strings caches the raw JSON; L() resolves the language live on each
-- call from settings.language_tag, so mid-session language switches
-- (en <-> jp) work correctly without cache invalidation.
local _loc_strings = nil
local function _load_loc()
   if _loc_strings then return end
   _loc_strings = tools.read_object_from_json_file(
      "src/training/combo_challenges/localization.json") or {}
end

local function L(key)
   if not key then return "" end
   _load_loc()
   local entry = _loc_strings[key]
   if not entry then return key end
   local lang = settings.language_tag or "en"
   return entry[lang] or entry["en"] or key
end

local module_name = "combo_challenges"

local DIFFICULTY_FILTERS = {
   "combo_difficulty_all",
   "combo_difficulty_beginner",
   "combo_difficulty_intermediate",
   "combo_difficulty_advanced",
}

local DIFFICULTY_KEY = { "all", "beginner", "intermediate", "advanced" }

local filtered_combos = {}
local combo_names = {}

-- Field names verified against src/gamestate.lua (see Task 4 step 2).
-- These reference fields on a gamestate player object.
-- recovery_time: frame countdown for hitstun/blockstun (read_player_vars line ~659,
--   player.recovery_time = memory.readbyte(player.addresses.recovery_time)).
-- juggle_count / juggle_time are NOT stored on the player object (only in player.addresses,
--   read directly from memory by hud.lua). Set to nil; snapshot reports 0 — acceptable for v1.
-- is_airborne: computed boolean on the player object (read_player_vars ~line 685).
local DUMMY_HITSTUN_FIELD  = "recovery_time"
local DUMMY_JUGGLE_FIELD   = nil
local DUMMY_AIRBORNE_FIELD = "is_airborne"

local is_enabled = true
local is_mode_active = false
local should_update_while_menu_is_open = false

local active_combo = nil
local active_validator = nil

-- Savestate for resetting the round (Option B: poll has_curtain_just_began).
local combo_reset_savestate = nil
local pending_save_reset_point = false

local function set_meter_for_combo(combo)
   if not combo or not combo.starts_with_meter then return end
   local addr = gamestate.P1.addresses
   if not addr then return end
   local max_gauge = gamestate.P1.max_meter_gauge
   -- max_meter_gauge may be 0 before the round populates; default to 96.
   if not max_gauge or max_gauge == 0 then max_gauge = 96 end
   memory.writebyte(addr.gauge, math.min(combo.starts_with_meter, max_gauge))
end

local function force_matchup_for_combo(combo)
   local sa = (combo and combo.sa) or 1
   character_select.force_select_character(1, "oro", sa, "HK")
   character_select.force_select_character(2, "ken", 1, "HK")
end

local function save_reset_point()
   combo_reset_savestate = savestate.create()
   savestate.save(combo_reset_savestate)
end

local function reload_reset_point()
   if combo_reset_savestate then
      savestate.load(combo_reset_savestate)
      if active_validator and active_combo then
         active_validator.reset(gamestate.P2.combo)
      end
   end
end

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

local combo_challenges

-- Throwaway dev-mode smoke test for the validator FSM.
local function smoke_test_validator()
   local validator = require("src.training.combo_challenges.combo_validator")

   -- Keys mirror oro_combos[1] step (move, button) pairs:
   --   step 1: move="d_MK", button=nil  -> key "d_MK"
   --   step 2: move="hitobashira", button="LK" -> key "hitobashira_LK"
   local fake_anims = { d_MK = "1111", hitobashira_LK = "2222" }
   local resolve = function(move, button)
      if button then return fake_anims[move .. "_" .. button] end
      return fake_anims[move]
   end

   local combo = oro_combos[1]
   local v = validator.new(resolve)
   v.arm(combo, 0)  -- explicit 0 for clarity
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

local function refresh_filtered_combos()
   for k in ipairs(filtered_combos) do filtered_combos[k] = nil end
   for k in ipairs(combo_names)    do combo_names[k]    = nil end
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

local function init()
   settings.training.combo_challenges = settings.training.combo_challenges
      or { show_notation_overlay = true, show_step_strip = true,
           current_difficulty_filter = 1, current_combo_index = 1 }
   local cc = settings.training.combo_challenges
   if cc.show_notation_overlay == nil then cc.show_notation_overlay = true end
   if cc.show_step_strip       == nil then cc.show_step_strip       = true end
   cc.current_difficulty_filter = cc.current_difficulty_filter or 1
   cc.current_combo_index       = cc.current_combo_index       or 1
end

local function resolve_oro_animation(move, button)
   local anim_hex = framedata.find_frame_data_by_name("oro", move, button)
   return anim_hex
end

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

local function combo_challenges_display()
   if not active_validator then return end
   if not gamestate.is_in_match then return end
   local cc_settings = settings.training and settings.training.combo_challenges
   local show_notation = not (cc_settings and cc_settings.show_notation_overlay == false)
   local show_steps    = not (cc_settings and cc_settings.show_step_strip == false)
   display.draw({
      combo = active_combo,
      current_step = active_validator.expected,
      show_notation = show_notation,
      show_steps    = show_steps,
      result_text   = current_result_text(),
      coin_hint     = L("combo_hint_coin_retry"),
   })
end

local function start()
   is_mode_active = true
   combo_reset_savestate = nil
   pending_save_reset_point = false
   if not active_validator then
      -- Defensive: should have been armed via validate_function; if
      -- not, fall back to the first combo so the mode is still usable.
      active_combo = oro_combos[1]
      active_validator = validator_module.new(resolve_oro_animation)
      active_validator.arm(active_combo, gamestate.P2.combo)
   end
   -- Kick off character select: Oro (P1) vs Ken (P2).
   -- force_select_character queues coroutines that run in
   -- character_select.update_character_select each frame until selection
   -- completes. No dedicated "finished" callback exists, so we poll
   -- has_curtain_just_began in update() to know when the round is live.
   force_matchup_for_combo(active_combo)
   -- Flag update() to save the reset point once the round begins.
   pending_save_reset_point = true
   hud.register_draw(combo_challenges_display)
end

local function stop()
   hud.unregister_draw(combo_challenges_display)
   is_mode_active = false
   active_combo = nil
   active_validator = nil
   combo_reset_savestate = nil
   pending_save_reset_point = false
end

local function update()
   if not is_mode_active then return end

   -- Option B: poll for the curtain that marks the first frame of a new round.
   -- has_curtain_just_began is true for exactly one frame when match_state
   -- transitions to 0x01 (pre-round curtain). We use this moment to:
   --   1) write the starting meter (character data is now valid in memory), and
   --   2) save the reset savestate so the user can replay the round.
   if pending_save_reset_point and gamestate.has_curtain_just_began then
      set_meter_for_combo(active_combo)
      save_reset_point()
      pending_save_reset_point = false
   end

   if not active_validator then return end
   if not gamestate.is_in_match then return end
   local snap = build_snapshot(gamestate.P1, gamestate.P2)
   active_validator.tick(snap)
end

local function process_gesture(gesture)
   if not is_mode_active then return end
   if gesture == "single_tap" then
      reload_reset_point()
   end
end

local function get_valid_control_schemes()
   -- The player must control P1 (Oro). P2 is the dummy. Mirror jumpins.
   return { { p1 = "player", p2 = "dummy_control" } }
end

local function arm_and_start(combo)
   local modes = require("src.modes")
   local menu = require("src.ui.menu")
   active_combo = combo
   active_validator = validator_module.new(resolve_oro_animation)
   active_validator.arm(active_combo, gamestate.P2.combo)
   menu.close_menu()
   modes.start(combo_challenges)
end

local function update_menu()
   -- Called by src/ui/menu.lua whenever the user navigates to this training
   -- mode's page. Re-sync the filtered combo list in case oro_combos changed
   -- (hot-reload) or the difficulty filter was edited elsewhere, and clamp
   -- the current combo index so it can never point past the new list.
   refresh_filtered_combos()
   local cc = settings.training.combo_challenges
   if cc and cc.current_combo_index > math.max(1, #filtered_combos) then
      cc.current_combo_index = 1
   end
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
   combo_item.is_enabled = function() return framedata.is_loaded end
   combo_item.is_unselectable = function() return not framedata.is_loaded end
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

combo_challenges = {
   name = module_name,
   init = init,
   start = start,
   stop = stop,
   update = update,
   create_menu = create_menu,
   update_menu = update_menu,
   process_gesture = process_gesture,
   reload_reset_point = reload_reset_point,
   get_valid_control_schemes = get_valid_control_schemes,
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
