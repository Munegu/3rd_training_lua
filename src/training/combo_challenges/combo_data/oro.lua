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
