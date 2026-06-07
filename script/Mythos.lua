local PocketDimension   = require("script.PocketDimension")
local util              = require("script.util")
local Connections       = require("script.connections")
local Logistics         = require("script.logistics")
local DimensionDeletion = require("script.dimensionDeletion")
local Electricity       = require("script.electricity")
local IconGui           = require("script.iconGui")

local positionKey       = util.positionKey

local function buildInnerPosToSlot(layout)
	local t = {}
	for slotKey, beltLayout in pairs(layout) do
		local ip = beltLayout.innerBeltPos
		t[positionKey(ip[1], ip[2])] = slotKey
	end
	return t
end

local function layoutForBounds(bounds)
	return PocketDimension.computeSlotBeltLayoutForBounds(
		bounds.x_min, bounds.x_max, bounds.y_min, bounds.y_max
	)
end

local function gateTarget(pos)
	return { x = pos[1], y = pos[2] }
end

local function refreshAllGateRenders(slots, layout, surface)
	for slotKey, slot in pairs(slots) do
		if slot.gateRender and slot.gateRender.valid then
			slot.gateRender.destroy()
		end
		slot.gateRender = nil
		local beltLayout = layout[slotKey]
		if beltLayout then
			slot.gateRender = rendering.draw_sprite{
				sprite      = "mythos-gate",
				target      = gateTarget(beltLayout.pos),
				surface     = surface,
				orientation = beltLayout.gateOrientation,
				y_scale     = 0.75,
			}
		end
	end
end

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

-- Factorio 2.0: trash_not_requested lives on LuaLogisticPoint, not LuaEntity.
local function configureMythosLogistics(entity)
	entity.request_from_buffers = true
	local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
	if point then
		point.trash_not_requested = false
	end
end

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
	-- Prevent auto-trashing of items not currently in the logistic filter.
	-- Without this, manually-inserted items (or over-delivered network items)
	-- get moved to the trash slot the next time filters are narrowed.
	configureMythosLogistics(mythosEntity)

	-- Hidden accumulator on the outer surface: connects to the nearby electric
	-- grid and is script-drained into the pocket dimension each tick.
	local outer_acc = mythosEntity.surface.create_entity{
		name        = "mythos-power-link-outer",
		position    = mythosEntity.position,
		force       = mythosEntity.force,
		raise_built = false,
	}
	if outer_acc then outer_acc.destructible = false end

	local floor_bounds = {
		x_min = PocketDimension.DEFAULT_FLOOR_BOUNDS.x_min,
		x_max = PocketDimension.DEFAULT_FLOOR_BOUNDS.x_max,
		y_min = PocketDimension.DEFAULT_FLOOR_BOUNDS.y_min,
		y_max = PocketDimension.DEFAULT_FLOOR_BOUNDS.y_max,
	}
	local gateLayout = layoutForBounds(floor_bounds)
	refreshAllGateRenders(slots, gateLayout, dim)

	return setmetatable({
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
		slotBeltLayoutInst  = gateLayout,
		innerPosToSlotInst  = buildInnerPosToSlot(gateLayout),
	}, Mythos)
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

-- Returns true when the mythos has items in its chest or non-default entities
-- in the pocket dimension.  Pass the mining `buffer` when called from a mine
-- event, because Factorio drains the chest into the buffer before it fires.
function Mythos:hasContents(buffer)
	if buffer then
		for i = 1, #buffer do
			local s = buffer[i]
			if s.valid_for_read and s.name ~= "mythos" and s.name ~= "mythos-with-contents" then
				return true
			end
		end
	else
		local inv = self.entity.get_inventory(defines.inventory.chest)
		if inv and not inv.is_empty() then return true end
	end
	if self.inside_surface and self.inside_surface.valid then
		for _, e in pairs(self.inside_surface.find_entities()) do
			if e.valid and e.name ~= "mythos-hidden-radar"
					and e.name ~= "mythos-power-link-inner" and e.name ~= "mythos-power-hub-pole" then
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
-- snapshots chest items (stripping them from `buffer` for mine events, or
-- draining the chest for death events to prevent loot spill), disconnects all
-- slots, and removes this instance from the active table WITHOUT deleting the
-- surface.  Returns the saved_id to embed in the pickup item.
function Mythos:save(buffer)
	local saved_id = self.entity.unit_number
	local items    = {}

	if buffer then
		-- Mining path: chest contents already moved to buffer by Factorio.
		for i = 1, #buffer do
			local s = buffer[i]
			if s.valid_for_read and s.name ~= "mythos" and s.name ~= "mythos-with-contents" then
				items[#items + 1] = {
					name    = s.name,
					count   = s.count,
					quality = s.quality and s.quality.name or "normal",
				}
				s.clear()
			end
		end
	else
		-- Death / script-destroy path: chest not yet spilled.
		local inv = self.entity.get_inventory(defines.inventory.chest)
		if inv then
			for i = 1, #inv do
				local slot = inv[i]
				if slot.valid_for_read then
					items[#items + 1] = {
						name    = slot.name,
						count   = slot.count,
						quality = slot.quality and slot.quality.name or "normal",
					}
				end
			end
			inv.clear() -- prevent engine loot spill
		end
	end

	storage.saved_dimensions = storage.saved_dimensions or {}
	storage.saved_dimensions[saved_id] = {
		surface      = self.inside_surface,
		items        = items,
		custom_icons = self.custom_icons,
	}

	-- Outer accumulator must be destroyed when the mythos is picked up.
	-- The inner accumulator stays with the saved surface and is restored later.
	if self.outer_acc and self.outer_acc.valid then
		self.outer_acc.destroy()
	end
	self.outer_acc = nil

	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	storage.mythoi[self.entity.unit_number] = nil
	return saved_id
end

-- Returns the saved_id embedded in the item used to build `entity`, or nil.
-- For player builds reads from the per-player cursor cache set by onCursorChanged.
-- For robot builds attempts a best-effort read of event.stack.tags.
function Mythos.extractSavedId(event)
	-- Reject only when we can positively identify a non-saved item was used.
	-- Allowing nil covers cases where Factorio does not populate event.item.
	if event.item and event.item.name ~= "mythos-with-contents" then return nil end
	if event.player_index then
		storage.pending_player_restore = storage.pending_player_restore or {}
		local saved_id = storage.pending_player_restore[event.player_index]
		if saved_id then
			storage.pending_player_restore[event.player_index] = nil
			return saved_id
		end
	end
	-- Robot build: attempt to read tags from the (possibly empty) cargo slot.
	local stack = event.stack
	if stack and stack.valid then
		local ok, tags = pcall(function() return stack.tags end)
		if ok and tags and tags.saved_id then return tags.saved_id end
	end
	return nil
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
	if self.outer_acc and self.outer_acc.valid then
		self.outer_acc.destroy()
	end
	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	if self.inside_surface and self.inside_surface.valid then
		game.delete_surface(self.inside_surface)
	end
	storage.mythoi[self.entity.unit_number] = nil
end

-- ── Custom icons ───────────────────────────────────────────────────────────────
-- Up to 4 custom icons can be displayed above the mythos entity in the world.
-- `index` is 1-4; `signal` is a SignalID {type, name} from choose-elem-button,
-- or nil to clear that slot.  Icons are never derived from chest contents.

-- Redraws all active icons with layout-aware positions and scales.
-- Layout rules:
--   1 icon  → large, centred above entity
--   2 icons → side by side, medium scale
--   3 icons → 2 on top row, 1 centred on bottom row
--   4 icons → 2×2 grid
function Mythos:refreshIconRenders()
	self.icon_renders = self.icon_renders or {}
	self.custom_icons = self.custom_icons or {}

	-- Destroy all current renders.
	for i, r in pairs(self.icon_renders) do
		if r and r.valid then r.destroy() end
		self.icon_renders[i] = nil
	end

	-- Collect active (non-nil) icon slots in order.
	local active = {}
	for i = 1, 4 do
		if self.custom_icons[i] then
			active[#active + 1] = { idx = i, signal = self.custom_icons[i] }
		end
	end
	local n = #active
	if n == 0 then return end

	-- Determine offsets and scale based on count.
	-- Y = -1.5 places icons just above the 3-tile-tall entity top edge.
	local offsets, scale
	if n == 1 then
		scale   = 0.9
		offsets = { { 0, -0.1 } }
	elseif n == 2 then
		scale   = 0.55
		offsets = {
			{ -0.45, -0.1 },
			{  0.45, -0.1 },
		}
	elseif n == 3 then
		scale   = 0.55
		offsets = {
			{ -0.45, -0.5 },
			{  0.45, -0.5 },
			{  0,     0.3 },
		}
	else  -- n == 4
		scale   = 0.55
		offsets = {
			{ -0.45, -0.5 },
			{  0.45, -0.5 },
			{ -0.45,  0.3 },
			{  0.45,  0.3 },
		}
	end

	for i, entry in ipairs(active) do
		local sprite = IconGui.spritePath(entry.signal)
		if sprite then
			local off = offsets[i] or { 0, -1.6 }
			self.icon_renders[entry.idx] = rendering.draw_sprite {
				sprite       = sprite,
				target       = { entity = self.entity, offset = off },
				surface      = self.entity.surface,
				x_scale      = scale,
				y_scale      = scale,
				render_layer = "entity-info-icon-above",
			}
		end
	end
end

function Mythos:setIcon(index, signal)
	self.icon_renders = self.icon_renders or {}
	self.custom_icons = self.custom_icons or {}

	self.custom_icons[index] = signal or nil
	self:refreshIconRenders()
end

-- ── Dimension resize ──────────────────────────────────────────────────────────

-- Slot keys that belong to each edge (used by resize helpers).
local function edgeSlotKeys(edge)
	local keys = {}
	for i = 1, PocketDimension.GATES_PER_SIDE do
		keys[i] = edge .. "-" .. i
	end
	return keys
end

local edgeSlots = {
	left   = edgeSlotKeys("left"),
	right  = edgeSlotKeys("right"),
	top    = edgeSlotKeys("top"),
	bottom = edgeSlotKeys("bottom"),
}

-- Returns the effective slot-belt layout entry for `slotKey`.
-- Uses the per-instance override when the dimension has been resized; falls
-- back to the shared module-level layout for dimensions at the default size.
function Mythos:getSlotBeltLayout(slotKey)
	if not self.floor_bounds then
		self:syncFloorBoundsFromTiles()
	end
	local layout = self.slotBeltLayoutInst
	if not layout and self.floor_bounds then
		layout = layoutForBounds(self.floor_bounds)
		self.slotBeltLayoutInst = layout
	end
	return layout and layout[slotKey]
end

-- Returns true when at least one slot on `edge` has an active connection.
function Mythos:isEdgeConnected(edge)
	for _, slotKey in ipairs(edgeSlots[edge]) do
		if self.slots[slotKey] and self.slots[slotKey].conn then
			return true
		end
	end
	return false
end

local defaultFloorBounds = PocketDimension.DEFAULT_FLOOR_BOUNDS

-- Floor tiles are the source of truth for gate placement.
function Mythos:syncFloorBoundsFromTiles()
	if self.inside_surface and self.inside_surface.valid then
		self.floor_bounds = PocketDimension.inferFloorBounds(self.inside_surface)
	elseif not self.floor_bounds then
		self.floor_bounds = {
			x_min = defaultFloorBounds.x_min,
			x_max = defaultFloorBounds.x_max,
			y_min = defaultFloorBounds.y_min,
			y_max = defaultFloorBounds.y_max,
		}
	end
end

function Mythos:refreshGateRenders()
	if not (self.slots and self.inside_surface and self.inside_surface.valid) then return end
	self:syncFloorBoundsFromTiles()
	local layout = layoutForBounds(self.floor_bounds)
	self.slotBeltLayoutInst = layout
	self.innerPosToSlotInst = buildInnerPosToSlot(layout)
	refreshAllGateRenders(self.slots, layout, self.inside_surface)
end

local function floorWidth(bounds)
	return bounds.x_max - bounds.x_min + 1
end

local function floorHeight(bounds)
	return bounds.y_max - bounds.y_min + 1
end

local RESIZE_STEP = PocketDimension.RESIZE_STEP

local function axisSize(bounds, edge)
	if edge == "right" or edge == "left" then
		return floorWidth(bounds)
	end
	return floorHeight(bounds)
end

-- Even-sized floors keep gate spacing symmetric; odd sizes step by 1 first.
local function resizeStepsForEdge(bounds, edge)
	local size = axisSize(bounds, edge)
	if size % 2 == 0 then
		return RESIZE_STEP
	end
	return 1
end

local function syncViewPosition(self)
	local b = self.floor_bounds
	if not b then return end
	self.inside_x, self.inside_y = PocketDimension.floorCentre(b)
end

local function finalizeFloorBounds(self, refreshGates)
	syncViewPosition(self)
	if self.inside_surface and self.inside_surface.valid and self.floor_bounds then
		PocketDimension.ensureRemoteViewReady(
			self.inside_surface, self.floor_bounds, self.entity.force
		)
	end
	if refreshGates ~= false then
		self:refreshGateRenders()
	end
end

local function applyFloorBounds(self, newBounds, refreshGates, deferFinalize)
	self.floor_bounds = newBounds
	if deferFinalize then return end
	finalizeFloorBounds(self, refreshGates)
end

-- Expands toward `edge` by RESIZE_STEP tiles (or one when the axis size is odd).
-- Pass deferGateRefresh=true when batching (e.g. resizeTo) to redraw once at the end.
-- Optional `steps` overrides the default step count.
-- Returns true on success, or false + error-message-key on failure.
function Mythos:expandEdge(edge, deferGateRefresh, steps)
	if not edgeSlots[edge] then return false, "mythos-gui.resize-invalid-edge" end

	if self:isEdgeConnected(edge) then
		return false, "mythos-gui.resize-has-connections"
	end

	self:syncFloorBoundsFromTiles()
	steps = steps or resizeStepsForEdge(self.floor_bounds, edge)
	local newBounds = PocketDimension.expandEdge(
		self.inside_surface, self.floor_bounds, edge, self.entity.force, steps
	)
	applyFloorBounds(self, newBounds, not deferGateRefresh, deferGateRefresh)
	return true
end

-- Shrinks from the free edge (right or top) by RESIZE_STEP tiles (or one when odd).
function Mythos:contractEdge(edge, deferGateRefresh, steps)
	local contractEdge = PocketDimension.contractEdge
	if edge ~= "right" and edge ~= "top" then
		return false, "mythos-gui.resize-invalid-edge"
	end

	if self:isEdgeConnected(edge) then
		return false, "mythos-gui.resize-has-connections"
	end

	self:syncFloorBoundsFromTiles()
	steps = steps or resizeStepsForEdge(self.floor_bounds, edge)
	local newBounds, blocked = contractEdge(
		self.inside_surface, self.floor_bounds, edge, self.entity.force, steps
	)
	if not newBounds then
		if blocked then
			return false, "mythos-gui.resize-has-entities"
		end
		return false, "mythos-gui.resize-min-size"
	end

	applyFloorBounds(self, newBounds, not deferGateRefresh, deferGateRefresh)
	return true
end

local function resizeAxis(self, edge, current, target, deferGateRefresh)
	while current < target do
		local steps = math.min(RESIZE_STEP, target - current)
		if current % 2 ~= 0 then
			steps = 1
		end
		local ok, err = self:expandEdge(edge, deferGateRefresh, steps)
		if not ok then return false, err end
		current = current + steps
	end
	while current > target do
		local steps = math.min(RESIZE_STEP, current - target)
		if current % 2 ~= 0 then
			steps = 1
		end
		local ok, err = self:contractEdge(edge, deferGateRefresh, steps)
		if not ok then return false, err end
		current = current - steps
	end
	return true
end

-- Resizes to the target width / height (anchor corner stays fixed).
-- Odd typed values are rounded up to the nearest even size.
function Mythos:resizeTo(targetWidth, targetHeight)
	targetWidth  = PocketDimension.snapSizeUpEven(targetWidth)
	targetHeight = PocketDimension.snapSizeUpEven(targetHeight)
	if targetWidth < PocketDimension.MIN_DIMENSION or targetHeight < PocketDimension.MIN_DIMENSION then
		return false, "mythos-gui.resize-invalid-size"
	end

	self:syncFloorBoundsFromTiles()
	local width  = floorWidth(self.floor_bounds)
	local height = floorHeight(self.floor_bounds)

	local ok, err = resizeAxis(self, "right", width, targetWidth, true)
	if not ok then return false, err end

	ok, err = resizeAxis(self, "top", height, targetHeight, true)
	if not ok then return false, err end

	finalizeFloorBounds(self, true)
	return true
end

-- ── Sub-system installation ────────────────────────────────────────────────────
-- Each module adds its methods directly onto the Mythos prototype.
Connections.install(Mythos, connectionTypes)
Logistics.install(Mythos)
DimensionDeletion.install(Mythos, connectionTypes)
Electricity.install(Mythos)

-- ── Heat transport ───────────────────────────────────────────────────────────
-- Equalises temperature between the outer and inner hidden heat-pipe proxies.
-- Averages the two temperatures and applies the result to both entities so the
-- two networks converge each tick.
local function transferHeat(a, b)
	local avg = (a.temperature + b.temperature) * 0.5
	a.temperature = avg
	b.temperature = avg
end

-- ── Fluid transport ───────────────────────────────────────────────────────────
-- Equalises fluid between the outer hidden pipe (connected to the external
-- network via Factorio's native fluid sim) and the inner pocket-dimension pipe
-- (which the player's internal network connects to).  Called every 6 ticks.
-- Each of the two pipes is a full-capacity vanilla pipe (100 units), so we
-- move half the difference each call to converge quickly without overshooting.
local function transferFluid(a, b)
	local aContents = a.get_fluid_contents()
	local bContents = b.get_fluid_contents()
	-- Merge all fluid names present on either side.
	local fluids = {}
	for name in pairs(aContents) do fluids[name] = true end
	for name in pairs(bContents) do fluids[name] = true end
	for fluidName in pairs(fluids) do
		local aAmt = aContents[fluidName] or 0
		local bAmt = bContents[fluidName] or 0
		local diff = aAmt - bAmt
		if diff > 0.01 then
			local moved = a.remove_fluid({ name = fluidName, amount = diff * 0.5 })
			if moved > 0 then b.insert_fluid({ name = fluidName, amount = moved }) end
		elseif diff < -0.01 then
			local moved = b.remove_fluid({ name = fluidName, amount = -diff * 0.5 })
			if moved > 0 then a.insert_fluid({ name = fluidName, amount = moved }) end
		end
	end
end

-- ── Belt item transport ────────────────────────────────────────────────────────
-- Moves all items from every lane of `from` into the matching lane of `to`.
-- Items that do not fit are left on `from`.
local function transferBeltLines(from, to)
	for lane = 1, 2 do
		local fromLine = from.get_transport_line(lane)
		local toLine   = to.get_transport_line(lane)
		for _, stack in pairs(fromLine.get_contents()) do
			local single = { name = stack.name, quality = stack.quality, count = 1 }
			for _ = 1, stack.count do
				if not toLine.can_insert_at_back() then goto nextLane end
				local taken = fromLine.remove_item(single)
				if taken > 0 then
					if not toLine.insert_at_back(single) then
						fromLine.insert_at_back(single)
						goto nextLane
					end
				end
			end
		end
		::nextLane::
	end
end

-- ── Tick handlers ──────────────────────────────────────────────────────────────

-- Called every 6 ticks: pushes items across active belt connections, then tries
-- to revive pending ghosts inside each pocket dimension.
function Mythos.onNthTick()
	for _, state in pairs(storage.mythoi) do
		if not state.entity.valid then goto continue end

		for _, slot in pairs(state.slots) do
			local conn = slot.conn
			if conn and conn.connType == "belt"
				and conn.entity.valid
				and conn.innerBelt and conn.innerBelt.valid then
				if conn.ioDirection == "input" then
					transferBeltLines(conn.entity, conn.innerBelt)
				else
					transferBeltLines(conn.innerBelt, conn.entity)
				end
			end
			if conn and conn.connType == "pipe"
				and conn.outerProxy and conn.outerProxy.valid
				and conn.innerProxy and conn.innerProxy.valid then
				transferFluid(conn.outerProxy, conn.innerProxy)
			end
			if conn and conn.connType == "heat-pipe"
				and conn.outerProxy and conn.outerProxy.valid
				and conn.innerProxy and conn.innerProxy.valid then
				transferHeat(conn.outerProxy, conn.innerProxy)
			end
		end

		state:buildGhosts()
		::continue::
	end
end

-- Called every 60 ticks: refreshes logistic requests, retries pending
-- deletions, and transfers electricity from the outer grid into the pocket
-- dimension.
function Mythos.onSlowTick()
	for _, state in pairs(storage.mythoi) do
		if state.entity.valid then
			state:updateRequests()
			state:flushPendingDeletions()
			state:transferElectricity()
		end
	end
end

-- ── Entity event handlers ──────────────────────────────────────────────────────

-- Handles any entity being built anywhere in the world.
function Mythos.onEntityBuilt(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	-- Case 1: entity placed inside a pocket dimension.
	local unitNum = tonumber(entity.surface.name:match("^mythos%-dimension%-(%d+)$"))
	if unitNum then
		local state = storage.mythoi[unitNum]
		if state and state.entity.valid and connectionTypes[entity.type] == "belt" then
			local slotKey = state:findInnerSlotAt(entity.position)
			if slotKey and state:connectFromInner(slotKey, entity) then
				entity.surface.play_sound { path = "entity-close/assembling-machine-3", position = entity.position }
			end
		end
		return
	end

	-- Case 2: a new mythos entity was placed.
	if entity.name == "mythos" then
		local saved_id = Mythos.extractSavedId(event)
		local saved    = saved_id and storage.saved_dimensions and storage.saved_dimensions[saved_id]
		if saved then
			-- Restore from a previously saved pocket dimension.
			storage. ---@diagnostic disable-next-line: need-check-nil
			saved_dimensions[saved_id] = nil
			local cx = entity.position.x
			local cy = entity.position.y
			local slots, byExternalPos = Connections.buildSlots(cx, cy)
			-- Recreate the outer accumulator (was destroyed when saved) and recover
			-- the inner accumulator from the saved surface.
			local outer_acc = entity.surface.create_entity{
				name        = "mythos-power-link-outer",
				position    = entity.position,
				force       = entity.force,
				raise_built = false,
			}
			if outer_acc then outer_acc.destructible = false end

			local inner_accs = saved.surface.find_entities_filtered{ name = "mythos-power-link-inner" }
			local inner_acc  = inner_accs[1]
			if not inner_acc then
				-- Fallback: create one if missing (e.g., pre-electricity save).
				inner_acc = saved.surface.create_entity{
					name        = "mythos-power-link-inner",
					position    = { PocketDimension.VIEW_X, PocketDimension.VIEW_Y },
					force       = entity.force,
					raise_built = false,
				}
				if inner_acc then inner_acc.destructible = false end
			end

			-- Sync solar multiplier to the new outer surface.
			local outer_surface = entity.surface
			if outer_surface and outer_surface.valid and saved.surface.valid then
				saved.surface.solar_power_multiplier = outer_surface.solar_power_multiplier
			end

			local state = setmetatable({
				entity           = entity,
				slots            = slots,
				byExternalPos    = byExternalPos,
				inside_surface   = saved.surface,
				inside_x         = PocketDimension.VIEW_X,
				inside_y         = PocketDimension.VIEW_Y,
				pendingDeletions = {},
				outer_acc        = outer_acc,
				inner_acc        = inner_acc,
			}, Mythos)
			state:refreshGateRenders()
			configureMythosLogistics(entity)
			local inv = entity.get_inventory(defines.inventory.chest)
			if inv and saved.items then
				for _, item in pairs(saved.items) do
					inv.insert({ name = item.name, count = item.count, quality = item.quality })
				end
			end
			storage.mythoi[entity.unit_number] = state
			if saved.custom_icons then
				for idx, signal in pairs(saved.custom_icons) do
					state:setIcon(idx, signal)
				end
			end
			state:connectExistingNeighbours()
		else
			local state = Mythos.new(entity)
			storage.mythoi[entity.unit_number] = state
			state:connectExistingNeighbours()
		end
		return
	end

	-- Case 3: a connectable entity was placed next to an existing mythos.
	if not connectionTypes[entity.type] then return end
	local state, slotKey = Mythos.findStateAndSlot(entity)
	if not state then return end
	if state:connect(slotKey, entity) then
		entity.surface.play_sound { path = "entity-close/assembling-machine-3", position = entity.position }
	end
end

-- Handles any entity being removed anywhere in the world.
-- Items mined from inside a pocket dimension are redirected to the mythos chest.
function Mythos.onEntityRemoved(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	-- Case 1: the mythos entity itself was removed.
	if entity.name == "mythos" then
		local state = storage.mythoi[entity.unit_number]
		if state then
			if state:hasContents(event.buffer) then
				local saved_id = state:save(event.buffer)
				if event.buffer then
					-- Mined by player or robot: swap mythos → mythos-with-contents.
					event.buffer.remove({ name = "mythos", count = 1 })
					event.buffer.insert({ name = "mythos-with-contents", count = 1 })
					for i = 1, #event.buffer do
						local s = event.buffer[i]
						if s.valid_for_read and s.name == "mythos-with-contents" then
							s.tags = { saved_id = saved_id }
							break
						end
					end
					-- Prime the restore cache directly so it is available in onEntityBuilt
					-- even if the cursor-stack tag mechanism fails (e.g. on_player_cursor_stack_changed
					-- fires while the cursor is still the mining tool, clearing the cache).
					if event.player_index then
						storage.pending_player_restore = storage.pending_player_restore or {}
						storage.pending_player_restore[event.player_index] = saved_id
					end
				else
					-- Killed or script-destroyed: drop item on the ground.
					local dropped = entity.surface.create_entity {
						name     = "item-on-ground",
						position = entity.position,
						stack    = { name = "mythos-with-contents", count = 1 },
					}
					if dropped and dropped.valid then
						dropped.stack.tags = { saved_id = saved_id }
					end
				end
			else
				state:destroy()
			end
		end
		return
	end

	-- Case 2: an entity was removed from inside a pocket dimension.
	local surfaceIndex = entity.surface_index
	for _, state in pairs(storage.mythoi) do
		if state.inside_surface and state.inside_surface.valid
			and state.inside_surface.index == surfaceIndex
			and state.entity.valid then
			-- Keep connection state consistent if a belt gate was removed.
			if connectionTypes[entity.type] == "belt" then
				local slotKey = state:findInnerSlotAt(entity.position)
				if slotKey then state:disconnect(slotKey) end
			end

			-- Redirect mined items to the chest instead of the player/robot inventory.
			if event.buffer then
				local inv = state.entity.get_inventory(defines.inventory.chest)
				if inv then
					for i = 1, #event.buffer do
						local stack = event.buffer[i]
						if stack.valid_for_read then
							inv.insert(stack)
							stack.clear()
						end
					end
				end
			end
			return
		end
	end

	-- Case 3: a connectable entity next to a mythos was removed.
	if not connectionTypes[entity.type] then return end
	local state, slotKey = Mythos.findStateAndSlot(entity)
	if state then state:disconnect(slotKey) end
end

-- Caches the saved_id from a mythos-with-contents cursor item so it is
-- available in onEntityBuilt (which fires before the cursor is consumed).
function Mythos.onCursorChanged(event)
	storage.pending_player_restore = storage.pending_player_restore or {}
	local player = game.get_player(event.player_index)
	if not player then return end
	local stack = player.cursor_stack
	if stack and stack.valid_for_read and stack.name == "mythos-with-contents" then
		local tags = stack.tags
		storage.pending_player_restore[event.player_index] = tags and tags.saved_id
	else
		storage.pending_player_restore[event.player_index] = nil
	end
end

return Mythos
