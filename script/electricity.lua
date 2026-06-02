-- ── Electricity System ────────────────────────────────────────────────────────
-- Bridges power between the outer-surface electric grid and the pocket
-- dimension's internal electric network.
--
-- Architecture:
--   outer_acc  – hidden accumulator on the main surface, in the same electric
--                network as any poles nearby the mythos.  Charges naturally
--                from the external grid; our script drains it each tick.
--   inner_acc  – hidden accumulator inside the pocket dimension.  Charged by
--                our script from the outer acc; discharges naturally into the
--                inside grid so assemblers, lights, etc. receive power.
--
-- Solar panels inside the pocket dimension use the surface's
-- solar_power_multiplier, which is synced to the outer surface so the
-- effective solar output matches the planet the mythos is placed on.

local Electricity = {}

-- 10 MJ – matches the buffer_capacity defined in hiddenEntities.lua.
local LINK_CAPACITY = 10 * 1000 * 1000

function Electricity.install(Mythos)

	-- Transfers available energy from the outer-surface accumulator into the
	-- pocket-dimension accumulator.  Called every 60 ticks.
	-- If the external grid has no power the outer_acc stays empty, meaning
	-- the inside grid receives nothing – an intentional "no power" state.
	function Mythos:transferElectricity()
		local outer = self.outer_acc
		local inner = self.inner_acc
		if not (outer and outer.valid and inner and inner.valid) then return end

		local available = outer.energy
		if available <= 0 then return end

		local space = LINK_CAPACITY - inner.energy
		if space <= 0 then return end

		local transfer = math.min(available, space)
		outer.energy = outer.energy - transfer
		inner.energy = inner.energy + transfer
	end

	-- Copies the outer surface's solar_power_multiplier onto the pocket
	-- dimension surface so solar panels inside produce the correct amount for
	-- the planet the mythos is located on.  Called every 300 ticks.
	function Mythos:syncSolar()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end
		local outer_surface = self.entity.surface
		if outer_surface and outer_surface.valid then
			self.inside_surface.solar_power_multiplier = outer_surface.solar_power_multiplier
		end
	end

end

return Electricity
