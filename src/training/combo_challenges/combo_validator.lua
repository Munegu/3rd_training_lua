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
