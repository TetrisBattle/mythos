local PocketDimension   = require("script.PocketDimension")
local util              = require("script.util")
local Connections       = require("script.connections")
local Logistics         = require("script.logistics")
local DimensionDeletion = require("script.dimensionDeletion")
local Electricity       = require("script.electricity")
local DimensionResize   = require("script.dimensionResize")
local Transport         = require("script.transport")
local Icons             = require("script.icons")
local MythosRestore     = require("script.mythosRestore")
local MythosEvents      = require("script.mythosEvents")
local MythosClone       = require("script.mythosClone")
local Registry          = require("script.registry")

local positionKey       = util.positionKey

-- ── Entity → connection-type mapping ──────────────────────────────────────────
-- Used to decide how a slot should be wired when an entity is placed next to
-- (or inside) a mythos.  Belts move items, pipes move fluid, heat-pipes move heat.
local connectionTypes   = {
	["loader"]           = "loader",
	["loader-1x1"]       = "loader",
	["transport-belt"]   = "belt",
	["underground-belt"] = "belt",
	["splitter"]         = "belt",
	["lane-splitter"]    = "belt",
	["pipe"]             = "pipe",
	["pipe-to-ground"]   = "pipe",
	["storage-tank"]     = "pipe",
	["pump"]             = "pipe",
	["offshore-pump"]    = "pipe",
	["generator"]        = "pipe",
	["heat-pipe"]        = "heat-pipe",
	["reactor"]          = "heat-pipe",
	["boiler"]           = "heat-pipe",
}

-- ── Mythos class ───────────────────────────────────────────────────────────────
-- One instance per placed mythos entity.
-- Stores the pocket-dimension surface, slot geometry, and all active connections.
-- Persisted in storage.mythoi[unit_number]; metatables are restored on game load.

local Mythos            = {}
Mythos.__index          = Mythos
Mythos.connectionTypes  = connectionTypes -- exposed for callers that need the map

-- Creates a new Mythos instance for a freshly placed entity.
function Mythos.new(mythosEntity)
	local cx = mythosEntity.position.x
	local cy = mythosEntity.position.y

	local slots, byExternalPos = Connections.buildSlots(cx, cy)

	local dim, inner_acc = PocketDimension.create(mythosEntity.unit_number, mythosEntity.force, mythosEntity.surface)

	-- Hidden accumulator on the placement surface (skipped when nested inside
	-- another mythos; nested mythoi draw from the parent inner accumulator).
	local outer_acc = MythosRestore.createOuterAccumulatorForEntity(mythosEntity)

	local floor_bounds = {
		x_min = PocketDimension.DEFAULT_FLOOR_BOUNDS.x_min,
		x_max = PocketDimension.DEFAULT_FLOOR_BOUNDS.x_max,
		y_min = PocketDimension.DEFAULT_FLOOR_BOUNDS.y_min,
		y_max = PocketDimension.DEFAULT_FLOOR_BOUNDS.y_max,
	}
	local state = setmetatable({
		entity              = mythosEntity,
		slots               = slots,
		byExternalPos       = byExternalPos,
		inside_surface      = dim,
		inside_x            = PocketDimension.VIEW_X,
		inside_y            = PocketDimension.VIEW_Y,
		pendingDeletions    = {},
		outer_acc           = outer_acc,
		inner_acc           = inner_acc,
		floor_bounds        = floor_bounds,
	}, Mythos)
	state:refreshGateRenders()
	return state
end

-- Returns the external-slot key for a world position, or nil.
function Mythos:findSlotAt(pos)
	return self.byExternalPos[positionKey(pos.x, pos.y)]
end

-- Returns true when at least one slot sharing the same inner tile still has an
-- active connection.  Corner slots can share a tile, so this prevents removing
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
-- Pass the mining `buffer` when called from a mine event for legacy item checks.
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

	storage.saved_dimensions = storage.saved_dimensions or {}
	storage.saved_dimensions[saved_id] = {
		surface      = self.inside_surface,
		items        = items,
		custom_icons = self.custom_icons,
		floor_bounds = self.floor_bounds,
	}

	-- Outer power bridge must be destroyed when the mythos is picked up.
	-- The inner accumulator stays with the saved surface and is restored later.
	if self.entity and self.entity.valid then
		MythosRestore.destroyOuterPowerBridge(self.entity.surface, self.entity.position)
	end
	self.outer_acc = nil

	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
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
	if self.entity and self.entity.valid then
		MythosRestore.destroyOuterPowerBridge(self.entity.surface, self.entity.position)
	end
	self.outer_acc = nil
	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	if self.inside_surface and self.inside_surface.valid then
		game.delete_surface(self.inside_surface)
	end
	Registry.remove(self.entity.unit_number)
end

-- ── Sub-system installation ────────────────────────────────────────────────────
-- Each module adds its methods directly onto the Mythos prototype.
Connections.install(Mythos, connectionTypes)
Logistics.install(Mythos)
DimensionDeletion.install(Mythos, connectionTypes)
Electricity.install(Mythos)
DimensionResize.install(Mythos)
Transport.install(Mythos)
Icons.install(Mythos)
MythosEvents.install(Mythos, connectionTypes)
MythosClone.install(Mythos)

return Mythos
