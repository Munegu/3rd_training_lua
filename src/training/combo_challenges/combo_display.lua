---@diagnostic disable: lowercase-global, undefined-global
local draw = require("src.ui.draw")
local colors = require("src.ui.colors")

local M = {}

-- Layout constants (screen is 383 x 223).
local BANNER_X     = 6
local BANNER_Y     = 4
local STRIP_Y      = 18
local STRIP_TILE_W = 60
local RESULT_Y     = 36
local HINT_X       = 6
local HINT_Y       = 215

-- colors.text.dim does not exist; use colors.text.inactive (0x909090FF) for
-- completed steps. colors.text.selected (0x00c2FFFF) exists and is used for
-- the active step and result line.
local COLOR_DONE    -- resolved on first draw (avoids require-time table access)
local COLOR_CURRENT
local COLOR_DEFAULT

local function resolve_colors()
   if COLOR_DEFAULT then return end
   COLOR_DEFAULT = colors.text.default   -- 0xFFFFFFFF
   COLOR_DONE    = colors.text.inactive  -- 0x909090FF (no text.dim; inactive is the grey)
   COLOR_CURRENT = colors.text.selected  -- 0x00c2FFFF
end

function M.draw(view)
   if not view or not view.combo then return end
   resolve_colors()

   if view.show_notation then
      local title = string.format("%s [%s]", view.combo.name, view.combo.difficulty)
      draw.render_text(BANNER_X, BANNER_Y, title, nil, COLOR_DEFAULT)
      if view.combo.notation then
         draw.render_text(BANNER_X, BANNER_Y + 8, view.combo.notation, nil, COLOR_DEFAULT)
      end
   end

   if view.show_steps then
      for i, step in ipairs(view.combo.steps) do
         local x = BANNER_X + (i - 1) * STRIP_TILE_W
         local color = COLOR_DEFAULT
         if i < view.current_step then
            color = COLOR_DONE
         elseif i == view.current_step then
            color = COLOR_CURRENT
         end
         draw.render_text(x, STRIP_Y, step.label, nil, color)
      end
   end

   if view.result_text then
      draw.render_text(BANNER_X, RESULT_Y, view.result_text, nil, COLOR_CURRENT)
   end

   if view.coin_hint then
      draw.render_text(HINT_X, HINT_Y, view.coin_hint, nil, COLOR_DEFAULT)
   end
end

return M
