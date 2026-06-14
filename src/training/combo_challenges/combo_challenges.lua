---@diagnostic disable: lowercase-global, undefined-global
local menu_items = require("src.ui.menu_items")
local settings = require("src.settings")
local oro_combos = require("src.training.combo_challenges.combo_data.oro")

local module_name = "combo_challenges"

local is_enabled = true
local is_mode_active = false
local should_update_while_menu_is_open = false

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
