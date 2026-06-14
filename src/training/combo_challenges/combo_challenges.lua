---@diagnostic disable: lowercase-global, undefined-global
local menu_items = require("src.ui.menu_items")
local settings = require("src.settings")
local oro_combos = require("src.training.combo_challenges.combo_data.oro")
local gamestate = require("src.gamestate")
local framedata = require("src.data.framedata")
local validator_module = require("src.training.combo_challenges.combo_validator")

local module_name = "combo_challenges"

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

local function init()
   print(string.format("[combo_challenges] loaded %d Oro combos", #oro_combos))
   -- Smoke test runs once per script load. Remove this call in Task 9
   -- after the user has confirmed the "validator smoke test passed" line
   -- prints during a real emulator session.
   smoke_test_validator()
end

local function resolve_oro_animation(move, button)
   local anim_hex = framedata.find_frame_data_by_name("oro", move, button)
   return anim_hex
end

local function arm_combo_for_dev()
   active_combo = oro_combos[1]            -- TEMP: hard-armed for dev only
   active_validator = validator_module.new(resolve_oro_animation)
   active_validator.arm(active_combo, gamestate.P2.combo)  -- NOTE: pass current dummy combo
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

local function process_gesture(gesture) end

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
