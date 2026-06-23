local PocketDimension  = require("script.pocket_dimension.init")
local util             = require("script.util")
local Connections      = require("script.mythos.connections")
local Bridge           = require("script.power.bridge")
local connectionTypes  = require("script.mythos.connection_types")
local Registry         = require("script.mythos.registry")
local Config           = require("script.config")

local positionKey      = util.positionKey

local function destroyGateLabelRenders(state)
	if state.gateLabelRenders then
		for _, r in pairs(state.gateLabelRenders) do
			if r and r.valid then r.destroy() end
		end
	end
	state.gateLabelRenders = nil
end

local function destroyPhysicalGateRenders(state)
	if state.physicalGateRenders then
		for _, render in pairs(state.physicalGateRenders) do
			if render and render.valid then render.destroy() end
		end
	end
	state.physicalGateRenders = nil
end

local function destroyGateSelectors(state)
	if state.destroyGateSelectors then
		state:destroyGateSelectors()
	elseif state.gateSelectorEntities then
		for _, selector in pairs(state.gateSelectorEntities) do
			if selector and selector.valid then selector.destroy{ raise_destroy = false } end
		end
		state.gateSelectorEntities = nil
	end
end

local function destroyNestedMythoi(state)
	if not (state.inside_surface and state.inside_surface.valid) then return end
	for _, entity in pairs(state.inside_surface.find_entities_filtered{ name = "mythos" }) do
		if entity.valid then
			local child = entity.unit_number and Registry.get(entity.unit_number)
			if child and child ~= state then
				child:destroy()
			end
			if entity.valid then
				entity.destroy{ raise_destroy = false }
			end
		end
	end
end

-- One instance per placed mythos entity.
-- Stores the pocket-dimension surface, slot geometry, and all active connections.
-- Persisted in storage.mythoi[unit_number]; metatables are restored on game load.
local Mythos           = {}
Mythos.__index         = Mythos
Mythos.connectionTypes = connectionTypes -- exposed for callers that need the map

-- Creates a new Mythos instance for a freshly placed entity.
function Mythos.new(mythosEntity)
	local cx = mythosEntity.position.x
	local cy = mythosEntity.position.y

	local slots, byExternalPos = Connections.buildSlots(cx, cy)

	local floor_bounds = Config.defaultDimensionBounds()
	local dim, inner_acc = PocketDimension.create(
		mythosEntity.unit_number,
		mythosEntity.force,
		mythosEntity.surface,
		{ floor_bounds = floor_bounds }
	)

	-- Hidden accumulator on the placement surface (skipped when nested inside
	-- another mythos; nested mythoi draw from the parent inner accumulator).
	local outer_acc = Bridge.createOuterAccumulatorForEntity(mythosEntity)
	local inside_x, inside_y = PocketDimension.floorCentre(floor_bounds)

	local state = setmetatable({
		entity              = mythosEntity,
		slots               = slots,
		byExternalPos       = byExternalPos,
		inside_surface      = dim,
		inside_x            = inside_x,
		inside_y            = inside_y,
		pendingDeletions    = {},
		outer_acc           = outer_acc,
		inner_acc           = inner_acc,
		floor_bounds        = floor_bounds,
		dimension_gate_positions = PocketDimension.defaultDimensionGatePositions(),
	}, Mythos)
	state:refreshGateRenders()
	return state
end

function Mythos:normalizeDimensionGatePositions()
	self.dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
		self.dimension_gate_positions,
		self.floor_bounds
	)
	return self.dimension_gate_positions
end

-- Returns the external-slot key for a world position, or nil.
function Mythos:findSlotAt(pos)
	local slotKey = self.byExternalPos and self.byExternalPos[positionKey(pos.x, pos.y)]
	if slotKey then return slotKey end

	for key, slot in pairs(self.slots or {}) do
		if slot.external and util.nearPosition(pos, slot.external) then
			return key
		end
	end
end

-- Returns true when at least one slot sharing the same inner tile still has an
-- active connection. Corner slots can share a tile, so this prevents removing
-- a shared hidden proxy connector before both slots are disconnected.
function Mythos:innerPositionStillNeeded(innerPos)
	local key = positionKey(innerPos.x, innerPos.y)
	for _, slot in pairs(self.slots) do
		if slot.conn and positionKey(slot.inner.x, slot.inner.y) == key then
			return true
		end
	end
	return false
end

-- Returns true when the pocket dimension has non-default content.
-- Pass the mining `buffer` when called from a mine event to inspect saved items.
function Mythos:hasContents(buffer)
	if buffer then
		for i = 1, #buffer do
			local s = buffer[i]
			if util.isStoredChestItem(s) then
				return true
			end
		end
	end
	if self.inside_surface and self.inside_surface.valid then
		for _, e in pairs(self.inside_surface.find_entities()) do
			if e.valid and not util.isInfrastructureEntityName(e.name) then
				return true
			end
		end
		-- find_entities() does not return ghost entities; check explicitly.
		if #self.inside_surface.find_entities_filtered { type = "entity-ghost" } > 0 then
			return true
		end
		if #self.inside_surface.find_entities_filtered { type = "tile-ghost" } > 0 then
			return true
		end
	end
	return false
end

-- Preserves this mythos for future restoration: keeps the pocket-dimension alive,
-- snapshots any saved item list from `buffer`, disconnects all slots, and removes
-- this instance from the active table WITHOUT deleting the surface.
function Mythos:save(buffer)
	local saved_id = self.entity.unit_number
	local items    = {}

	if buffer then
		for i = 1, #buffer do
			local s = buffer[i]
			if util.isStoredChestItem(s) then
				items[#items + 1] = {
					name    = s.name,
					count   = s.count,
					quality = s.quality and s.quality.name or "normal",
				}
				s.clear()
			end
		end
	end

	destroyGateLabelRenders(self)
	destroyPhysicalGateRenders(self)
	destroyGateSelectors(self)

	storage.saved_dimensions = storage.saved_dimensions or {}
	self:normalizeDimensionGatePositions()
	storage.saved_dimensions[saved_id] = {
		surface                  = self.inside_surface,
		items                    = items,
		custom_icons             = self.custom_icons,
		floor_bounds             = self.floor_bounds,
		dimension_gate_positions = self.dimension_gate_positions,
	}

	-- Outer power bridge must be destroyed when the mythos is picked up.
	-- The inner accumulator stays with the saved surface and is restored later.
	if self.entity and self.entity.valid then
		Bridge.destroyOuterPowerBridge(self.entity.surface, self.entity.position)
	end
	self.outer_acc = nil

	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	destroyGateLabelRenders(self)
	destroyPhysicalGateRenders(self)
	destroyGateSelectors(self)
	Registry.remove(self.entity.unit_number)
	return saved_id
end

-- Disconnects all slots, deletes the pocket-dimension surface, and removes this
-- instance from global storage.
function Mythos:destroy()
	if self.icon_renders then
		for _, r in pairs(self.icon_renders) do
			if r and r.valid then r.destroy() end
		end
	end
	self.icon_renders = nil
	destroyGateLabelRenders(self)
	destroyPhysicalGateRenders(self)
	destroyGateSelectors(self)
	if self.entity and self.entity.valid then
		Bridge.destroyOuterPowerBridge(self.entity.surface, self.entity.position)
	end
	self.outer_acc = nil
	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	destroyGateLabelRenders(self)
	destroyPhysicalGateRenders(self)
	destroyNestedMythoi(self)
	if self.inside_surface and self.inside_surface.valid then
		game.delete_surface(self.inside_surface)
	end
	Registry.remove(self.entity.unit_number)
end

return Mythos
