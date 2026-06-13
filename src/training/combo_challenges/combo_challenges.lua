---@diagnostic disable: lowercase-global, undefined-global
local menu_items = require("src.ui.menu_items")
local settings = require("src.settings")
local oro_combos = require("src.training.combo_challenges.combo_data.oro")

local module_name = "combo_challenges"

local is_enabled = true
local is_mode_active = false
local should_update_while_menu_is_open = false

local combo_challenges

local function init()
   print(string.format("[combo_challenges] loaded %d Oro combos", #oro_combos))
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
