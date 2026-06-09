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
-- effective solar output matches the planet the mythos is placed on.

local Registry      = require("script.registry")
local MythosRestore = require("script.mythosRestore")
local util          = require("script.util")

local Electricity = {}

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

local function findBridgePole(surface, name, position)
	local filters = { name = name }
	if position then filters.position = position end
	local poles = surface.find_entities_filtered(filters)
	return poles[1]
end

function Electricity.install(Mythos)

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

	-- Wires the hidden outer bridge pole to nearby player poles so the outer
	-- accumulator can charge from the placement-surface grid.
	function Mythos:syncOuterElectricNetwork()
		if not (self.entity and self.entity.valid) then return end
		if util.parseDimensionUnitNumber(self.entity.surface) then return end

		local bridge = findBridgePole(
			self.entity.surface, "mythos-power-outer-pole", self.entity.position
		)
		if not (bridge and bridge.valid) then return end

		local pos = self.entity.position
		local margin = 64
		for _, pole in ipairs(self.entity.surface.find_entities_filtered{
			type = "electric-pole",
			area = {
				{ pos.x - margin, pos.y - margin },
				{ pos.x + margin, pos.y + margin },
			},
		}) do
			if isPlayerPole(pole) then
				connectPoleCopper(bridge, pole)
			end
		end
	end

	-- Wires the hidden hub pole to every player pole in the pocket dimension.
	-- Player medium poles only reach ~9 tiles, so pole networks at the edges
	-- would otherwise stay isolated from the hub even with a large supply area.
	function Mythos:syncInsideElectricNetwork()
		if not (self.inside_surface and self.inside_surface.valid) then return end

		local hub = findBridgePole(self.inside_surface, "mythos-power-hub-pole")
		if not (hub and hub.valid) then return end

		for _, pole in ipairs(self.inside_surface.find_entities_filtered{ type = "electric-pole" }) do
			if isPlayerPole(pole) then
				connectPoleCopper(hub, pole)
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
			MythosRestore.destroyStrayOuterAccumulators(self.inside_surface)
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
