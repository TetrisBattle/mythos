-- ── Electricity System ────────────────────────────────────────────────────────
-- Bridges power between the outer-surface electric grid and the pocket
-- dimension's internal electric network.
--
-- Architecture:
--   outer_acc  – hidden accumulator on the main surface, in the same electric
--                network as any poles nearby the mythos.  Charges naturally
--                from the external grid; our script drains it each tick.
--   inner_acc  – hidden electric-energy-interface inside the pocket dimension.
--                Script fills its buffer from the outer link and sets
--                power_production so it injects power as a secondary-output
--                producer (avoiding tertiary competition with player accumulators).
--
-- Solar panels inside the pocket dimension use the surface's
-- solar_power_multiplier, which is synced to the outer surface so the
-- effective solar output matches the planet the mythos is placed on. Surface
-- properties such as gravity are synced for the same reason.

local Registry = require("script.mythos.registry")
local Bridge   = require("script.power.bridge")
local PocketDimension = require("script.pocket_dimension.init")
local util     = require("script.util")

local Sync = {}

-- 10 MJ – matches the buffer_capacity defined in hiddenEntities.lua.
local LINK_CAPACITY = 10 * 1000 * 1000

local BRIDGE_POLE_NAMES = {
	["mythos-power-hub-pole"]   = true,
	["mythos-power-outer-pole"] = true,
}

local function isPlayerPole(entity)
	return entity.valid
		and entity.type == "electric-pole"
		and not BRIDGE_POLE_NAMES[entity.name]
end

local function connectPoleCopper(pole_a, pole_b)
	if not (pole_a.valid and pole_b.valid) then return end

	local connector_a = pole_a.get_wire_connector(defines.wire_connector_id.pole_copper, true)
	local connector_b = pole_b.get_wire_connector(defines.wire_connector_id.pole_copper, true)
	if not (connector_a and connector_b and connector_a.valid and connector_b.valid) then return end
	if connector_a.is_connected_to(connector_b) then return end

	connector_a.connect_to(connector_b, false, defines.wire_origin.script)
end

function Sync.install(Mythos)

	-- World mythoi draw from their hidden outer accumulator on the placement
	-- surface.  Nested mythoi (entity sitting inside another pocket dimension)
	-- draw from the parent mythos inner accumulator instead, since the parent
	-- inner grid is the only powered network available there.
	function Mythos:getPowerSource()
		if not (self.entity and self.entity.valid) then return nil end

		local parentUnit = util.parseDimensionUnitNumber(self.entity.surface)
		if parentUnit then
			local parent = Registry.get(parentUnit)
			if parent and parent.inner_acc and parent.inner_acc.valid then
				return parent.inner_acc
			end
		end

		if self.outer_acc and self.outer_acc.valid then
			return self.outer_acc
		end
		return nil
	end

	-- Outer accumulators join the placement grid through normal electric
	-- coverage.  Hidden outer poles from older versions must not remain, because
	-- they extend the grid and can supply nearby machines.
	function Mythos:syncOuterElectricNetwork()
		if not (self.entity and self.entity.valid) then return end
		if util.parseDimensionUnitNumber(self.entity.surface) then return end

		Bridge.destroyOuterPoles(self.entity.surface, self.entity.position)
	end

	-- Wires every hub pole to its neighboring hubs and copper-wires each
	-- player pole to the nearest hub. Hub poles are arranged in a grid; without
	-- chaining them, each hub forms an isolated electric network and only one
	-- ends up sharing the inner accumulator. Player medium poles also can't
	-- reach distant hubs by themselves, so they must be connected explicitly.
	function Mythos:syncInsideElectricNetwork()
		if not (self.inside_surface and self.inside_surface.valid) then return end

		local hubs = self.inside_surface.find_entities_filtered{ name = "mythos-power-hub-pole" }
		if #hubs == 0 then return end

		local hub_wire = 64

		for i = 1, #hubs do
			for j = i + 1, #hubs do
				local dx = hubs[i].position.x - hubs[j].position.x
				local dy = hubs[i].position.y - hubs[j].position.y
				if dx * dx + dy * dy <= hub_wire * hub_wire then
					connectPoleCopper(hubs[i], hubs[j])
				end
			end
		end

		for _, pole in ipairs(self.inside_surface.find_entities_filtered{ type = "electric-pole" }) do
			if isPlayerPole(pole) then
				local best, best_d2
				for _, hub in ipairs(hubs) do
					local dx = hub.position.x - pole.position.x
					local dy = hub.position.y - pole.position.y
					local d2 = dx * dx + dy * dy
					if not best_d2 or d2 < best_d2 then
						best, best_d2 = hub, d2
					end
				end
				if best then connectPoleCopper(best, pole) end
			end
		end
	end

	-- Drives power_production on the inner producer from its current buffer.
	function Mythos:syncInnerPowerOutput()
		local inner = self.inner_acc
		if not (inner and inner.valid and inner.type == "electric-energy-interface") then return end

		local buffer = inner.energy
		if buffer <= 0 then
			inner.power_production = 0
			return
		end

		local flow_limit = inner.get_electric_output_flow_limit and inner.get_electric_output_flow_limit()
			or (10 * 1000 * 1000 * 1000)
		inner.power_production = math.min(buffer, flow_limit)
	end

	-- Wires networks, transfers energy, and updates inner output.  Called on
	-- placement and dimension open so hidden power links never flash status
	-- icons before the first slow tick.
	function Mythos:syncElectricity()
		if self.inside_surface and self.inside_surface.valid then
			Bridge.destroyStrayOuterAccumulators(self.inside_surface)
		end
		self:syncOuterElectricNetwork()
		self:syncInsideElectricNetwork()
		self:transferElectricity()
	end

	-- Transfers available energy from the outer-surface accumulator into the
	-- pocket-dimension producer.  Called every 60 ticks.
	-- If the external grid has no power the outer_acc stays empty, meaning
	-- the inside grid receives nothing – an intentional "no power" state.
	function Mythos:transferElectricity()
		local source = self:getPowerSource()
		local inner  = self.inner_acc
		if not (source and source.valid and inner and inner.valid) then return end

		local available = source.energy
		if available > 0 then
			local space = LINK_CAPACITY - inner.energy
			if space > 0 then
				local transfer = math.min(available, space)
				source.energy = source.energy - transfer
				inner.energy  = inner.energy + transfer
			end
		end

		self:syncInnerPowerOutput()
	end

	-- Copies outer-surface properties onto the pocket dimension so build
	-- conditions and solar output match where the mythos is located. Called
	-- every 300 ticks.
	function Mythos:syncSolar()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end
		PocketDimension.syncSurfaceProperties(self.inside_surface, self.entity.surface)
	end

end

return Sync
