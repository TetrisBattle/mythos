-- ── Slot Connection System ────────────────────────────────────────────────────
-- Manages the external connection slots on a mythos entity (4 per side).
-- Each slot can hold one active connection (belt, pipe, or heat-pipe) bridging
-- the outside world to the pocket dimension interior.
--
-- Public surface:
--   Connections.buildSlots(cx, cy)   → slots, byExternalPos
--   Connections.install(Mythos, connectionTypes)  → adds methods to the class

local PocketDimension = require("script.pocket_dimension.init")
local util            = require("script.util")
local Registry        = require("script.mythos.registry")
local positionKey     = util.positionKey

-- ── Slot geometry ──────────────────────────────────────────────────────────────
-- Position offsets relative to the mythos entity centre.
--   externalX/Y : tile where the player-placed connector must sit (outside mythos)
--   innerX/Y    : tile inside the mythos footprint where the hidden proxy goes
--   outwardDir  : direction FROM the mythos centre TOWARD the external connector
-- Pocket wall order (north → south): T1..T4, L1..L4, R1..R4, B1..B4.

local slotLayout = PocketDimension.buildMythosSlotLayout()

local oppositeDir = {
	[defines.direction.north] = defines.direction.south,
	[defines.direction.south] = defines.direction.north,
	[defines.direction.east]  = defines.direction.west,
	[defines.direction.west]  = defines.direction.east,
}

-- Prototype names for the invisible proxy entities placed inside the mythos footprint.
-- Pipe and heat-pipe connections need a physical entity to carry fluid or heat.
local hiddenEntityName = {
	["pipe"]      = "mythos-hidden-pipe",
	["heat-pipe"] = "mythos-hidden-heat-pipe",
}

-- Constant lookup: pocket-dimension inner belt position → slot key.
-- Derived from PocketDimension layout; identical for every mythos instance.
local innerPosToSlot = util.buildInnerPosToSlot(PocketDimension.slotBeltLayout)

-- ── Public API ─────────────────────────────────────────────────────────────────
local Connections = {}

-- Builds the slots and byExternalPos lookup tables for a newly placed mythos.
-- cx, cy: world position of the mythos entity centre.
-- Returns (slots, byExternalPos) ready to be stored in the Mythos state.
function Connections.buildSlots(cx, cy)
	local slots         = {}  -- slotKey → { external, inner, outwardDir, conn }
	local byExternalPos = {}  -- positionKey(x,y) → slotKey

	for slotKey, layout in pairs(slotLayout) do
		local externalPos = { x = cx + layout.externalX, y = cy + layout.externalY }
		local innerPos    = { x = cx + layout.innerX,    y = cy + layout.innerY    }

		slots[slotKey] = {
			external   = externalPos,
			inner      = innerPos,
			outwardDir = layout.outwardDir,
			conn       = nil,
		}
		byExternalPos[positionKey(externalPos.x, externalPos.y)] = slotKey
	end

	return slots, byExternalPos
end

-- Re-applies current slotLayout to a live state (preserves conn / gateRender).
-- Needed after layout changes so saved mythoi pick up moved top/bottom ports.
local function syncSlotGeometry(state)
	if not (state.entity and state.entity.valid) then return end

	local cx, cy = state.entity.position.x, state.entity.position.y
	local oldSlots = state.slots or {}
	local slots = {}
	local byExternalPos = {}

	for slotKey, layout in pairs(slotLayout) do
		local old = oldSlots[slotKey] or {}
		local externalPos = { x = cx + layout.externalX, y = cy + layout.externalY }
		local innerPos    = { x = cx + layout.innerX,    y = cy + layout.innerY    }
		slots[slotKey] = {
			external   = externalPos,
			inner      = innerPos,
			outwardDir = layout.outwardDir,
			conn       = old.conn,
			gateRender = old.gateRender,
		}
		byExternalPos[positionKey(externalPos.x, externalPos.y)] = slotKey
	end

	state.slots         = slots
	state.byExternalPos = byExternalPos
	state.dimensionGateLayout = nil
	state.dimensionGateLayoutBoundsKey = nil
	state.innerPosToSlotInst = nil
end

local function slotArea(slot)
	return {
		{ slot.external.x - util.SLOT_POS_TOLERANCE, slot.external.y - util.SLOT_POS_TOLERANCE },
		{ slot.external.x + util.SLOT_POS_TOLERANCE, slot.external.y + util.SLOT_POS_TOLERANCE },
	}
end

local function slotKeysInOrder(slots)
	local keys = {}
	for _, slotKey in ipairs(PocketDimension.SLOT_KEYS) do
		if slots and slots[slotKey] then keys[#keys + 1] = slotKey end
	end
	return keys
end

local function appendSlotKeyOnce(slotKeys, seen, slotKey)
	if slotKey and not seen[slotKey] then
		seen[slotKey] = true
		slotKeys[#slotKeys + 1] = slotKey
	end
end

local function entityOverlapsArea(entity, area)
	if not (entity and entity.valid) then return false end
	local box = entity.bounding_box
	if not box then
		return util.nearPosition(entity.position, {
			x = (area[1][1] + area[2][1]) * 0.5,
			y = (area[1][2] + area[2][2]) * 0.5,
		})
	end

	local leftTop = box.left_top or box[1]
	local rightBottom = box.right_bottom or box[2]
	if not (leftTop and rightBottom) then return false end

	return leftTop.x <= area[2][1]
		and rightBottom.x >= area[1][1]
		and leftTop.y <= area[2][2]
		and rightBottom.y >= area[1][2]
end

local function entityOverlapsSlot(entity, slot)
	return entityOverlapsArea(entity, slotArea(slot))
end

local function connectionPositionMatches(pos, target)
	return pos and target and util.nearPosition(pos, target, 0.1)
end

local function entityFluidConnectionFacesSlot(slot, entity)
	local fluidbox = entity.fluidbox
	if not fluidbox then return nil end

	for index = 1, #fluidbox do
		local ok, connections = pcall(function()
			return fluidbox.get_pipe_connections(index)
		end)
		if ok and connections then
			for _, connection in pairs(connections) do
				if connection.connection_type ~= "underground"
						and connectionPositionMatches(connection.target_position, slot.inner) then
					return true
				end
			end
		elseif not ok then
			return nil
		end
	end

	return false
end

local function pipeEntityConnectsToSlot(slot, entity)
	local fluidSideMatch = entityFluidConnectionFacesSlot(slot, entity)
	if fluidSideMatch ~= nil then return fluidSideMatch end

	if entity.type == "pipe" then return true end
	if entity.type == "pipe-to-ground" then
		return entity.direction == slot.outwardDir
	end
	return true
end

local function externalEntityConnType(slot, entity, connectionTypes)
	if not (entity and entity.valid) then return nil end
	local connType = connectionTypes[entity.type]
	if not connType then return nil end
	if connType == "belt" or connType == "loader" then
		local inwardDir = oppositeDir[slot.outwardDir]
		if entity.direction ~= slot.outwardDir and entity.direction ~= inwardDir then
			return nil
		end
	elseif connType == "pipe" then
		if not pipeEntityConnectsToSlot(slot, entity) then
			return nil
		end
	end
	return connType
end

local function findExternalConnectionEntity(state, slot, connectionTypes, requiredConnType)
	if not (state.entity and state.entity.valid) then return nil end

	for _, entity in pairs(state.entity.surface.find_entities_filtered{ area = slotArea(slot) }) do
		local connType = externalEntityConnType(slot, entity, connectionTypes)
		if connType and (not requiredConnType or connType == requiredConnType) then
			return entity, connType
		end
	end
end

local function maxTransportLineIndex(entity)
	local okMax, maxIndex = pcall(function()
		return entity.get_max_transport_line_index()
	end)
	if okMax and maxIndex then return maxIndex end
	return nil
end

local function transportLinePair(leftName, rightName)
	local transportLines = defines.transport_line or {}
	return { transportLines[leftName], transportLines[rightName] }
end

local function validLinePair(pair, maxIndex)
	return pair
		and pair[1]
		and pair[2]
		and pair[1] >= 1
		and pair[2] >= 1
		and pair[1] <= maxIndex
		and pair[2] <= maxIndex
end

local function splitterLinePairs(maxIndex)
	local candidatePairs = {
		transportLinePair("left_line", "right_line"),
		transportLinePair("secondary_left_line", "secondary_right_line"),
		transportLinePair("left_split_line", "right_split_line"),
		transportLinePair("secondary_left_split_line", "secondary_right_split_line"),
	}
	local validPairs = {}
	for _, pair in ipairs(candidatePairs) do
		if validLinePair(pair, maxIndex) then
			validPairs[#validPairs + 1] = pair
		end
	end
	return validPairs
end

local function distanceSquared(a, b)
	if not (a and b) then return math.huge end
	local dx = (a.x or a[1]) - (b.x or b[1])
	local dy = (a.y or a[2]) - (b.y or b[2])
	return dx * dx + dy * dy
end

local function lineEndpointDistanceSquared(entity, lineIndex, position)
	local okLine, line = pcall(function()
		return entity.get_transport_line(lineIndex)
	end)
	if not okLine or not line then return math.huge end

	local best = math.huge
	for _, linePosition in ipairs({ 0, line.line_length or 0 }) do
		local okPos, mapPosition = pcall(function()
			return entity.get_line_item_position(lineIndex, linePosition)
		end)
		if okPos and mapPosition then
			best = math.min(best, distanceSquared(mapPosition, position))
		end
	end
	return best
end

local function linePairDistanceSquared(entity, pair, position)
	return math.min(
		lineEndpointDistanceSquared(entity, pair[1], position),
		lineEndpointDistanceSquared(entity, pair[2], position)
	)
end

local function nearestUnusedLinePair(entity, candidatePairs, used, position)
	local bestIndex = nil
	local bestDistance = math.huge
	for index, pair in ipairs(candidatePairs) do
		if not used[index] then
			local distance = linePairDistanceSquared(entity, pair, position)
			if not bestIndex or distance < bestDistance then
				bestIndex = index
				bestDistance = distance
			end
		end
	end
	if not bestIndex then return nil end
	used[bestIndex] = true
	return candidatePairs[bestIndex]
end

local function adjacentLinePairForIndex(pairIndex, maxIndex)
	local first = (pairIndex - 1) * 2 + 1
	if first >= 3 then first = first + 2 end
	local second = first + 1
	if first < 1 or second > maxIndex then return { 1, 2 } end
	return { first, second }
end

local function linePairForIndex(entity, pairIndex, maxIndex)
	if entity.type == "splitter" or entity.type == "lane-splitter" then
		local candidatePairs = splitterLinePairs(maxIndex)
		return candidatePairs[pairIndex] or candidatePairs[1] or { 1, 2 }
	end
	return adjacentLinePairForIndex(pairIndex, maxIndex)
end

local function splitterLineIndexesForSlot(state, slotKey, entity, connectionTypes, maxIndex)
	local candidatePairs = splitterLinePairs(maxIndex)
	if #candidatePairs == 0 then return { 1, 2 } end

	local used = {}
	for _, candidateSlotKey in ipairs(slotKeysInOrder(state.slots)) do
		local candidateSlot = state.slots[candidateSlotKey]
		if entityOverlapsSlot(entity, candidateSlot)
				and externalEntityConnType(candidateSlot, entity, connectionTypes) then
			local selectedPair = nearestUnusedLinePair(
				entity, candidatePairs, used, candidateSlot.external
			) or candidatePairs[1]
			if candidateSlotKey == slotKey then return selectedPair end
		end
	end

	return candidatePairs[1]
end

local function beltLineIndexesForPosition(entity, position)
	if not (entity and entity.valid and position) then return { 1, 2 } end

	local maxIndex = maxTransportLineIndex(entity)
	if not maxIndex or maxIndex <= 2 then return { 1, 2 } end

	local okLine, lineIndex = pcall(function()
		local index = entity.get_item_insert_specification(position)
		return index
	end)
	if not okLine or not lineIndex then return { 1, 2 } end

	local first = lineIndex
	if first % 2 == 0 then first = first - 1 end
	local second = first + 1
	if first < 1 or second > maxIndex then return { 1, 2 } end

	return { first, second }
end

local function beltLineIndexesForSlot(state, slotKey, entity, connectionTypes)
	local maxIndex = maxTransportLineIndex(entity)
	if not maxIndex or maxIndex <= 2 then return { 1, 2 } end
	if entity.type == "splitter" or entity.type == "lane-splitter" then
		return splitterLineIndexesForSlot(state, slotKey, entity, connectionTypes, maxIndex)
	end

	local pairCount = math.floor(maxIndex / 2)
	local pairIndex = 0
	for _, candidateSlotKey in ipairs(slotKeysInOrder(state.slots)) do
		local candidateSlot = state.slots[candidateSlotKey]
		if entityOverlapsSlot(entity, candidateSlot)
				and externalEntityConnType(candidateSlot, entity, connectionTypes) then
			pairIndex = pairIndex + 1
			if candidateSlotKey == slotKey then
				return linePairForIndex(entity, math.min(pairIndex, pairCount), maxIndex)
			end
		end
	end

	local slot = state.slots and state.slots[slotKey]
	return beltLineIndexesForPosition(entity, slot and slot.external)
end

local function refreshBeltConnectionLineIndexes(state, slotKey, connectionTypes)
	local slot = state.slots and state.slots[slotKey]
	local conn = slot and slot.conn
	if not (conn and conn.connType == "belt" and conn.entity and conn.entity.valid) then return end

	conn.entityLineIndexes = beltLineIndexesForSlot(state, slotKey, conn.entity, connectionTypes)
	if conn.innerBelt and conn.innerBelt.valid then
		local beltLayout = state:getSlotBeltLayout(slotKey)
		local innerBeltPos = beltLayout and beltLayout.innerBeltPos
		local position = innerBeltPos and { x = innerBeltPos[1], y = innerBeltPos[2] }
			or conn.innerBelt.position
		conn.innerBeltLineIndexes = beltLineIndexesForPosition(conn.innerBelt, position)
	end
end

local function collectExternalSlotKeysForEntity(state, entity, connectionTypes)
	local slotKeys = {}
	local seen = {}
	if not (state and state.entity and state.entity.valid) then return slotKeys end

	local exactSlotKey = state:findSlotAt(entity.position)
	if exactSlotKey then
		local slot = state.slots and state.slots[exactSlotKey]
		if slot and (externalEntityConnType(slot, entity, connectionTypes)
				or (slot.conn and slot.conn.entity == entity)) then
			appendSlotKeyOnce(slotKeys, seen, exactSlotKey)
		end
	end

	for _, candidateSlotKey in ipairs(slotKeysInOrder(state.slots)) do
		local slot = state.slots[candidateSlotKey]
		if entityOverlapsSlot(entity, slot)
				and externalEntityConnType(slot, entity, connectionTypes) then
			appendSlotKeyOnce(slotKeys, seen, candidateSlotKey)
		end
	end

	for _, candidateSlotKey in ipairs(slotKeysInOrder(state.slots)) do
		local slot = state.slots[candidateSlotKey]
		if slot.conn and slot.conn.entity == entity then
			appendSlotKeyOnce(slotKeys, seen, candidateSlotKey)
		end
	end

	return slotKeys
end

-- Adds all connection-management methods to the Mythos class.
-- Must be called once after the Mythos table is created.
function Connections.install(Mythos, connectionTypes)

	function Mythos:syncSlotGeometry()
		syncSlotGeometry(self)
	end

	-- Returns the slot key if pos matches a gate position inside any pocket dimension.
	-- Checks the per-instance lookup first (set after a resize) then the shared default.
	function Mythos:findInnerSlotAt(pos)
		local key = positionKey(pos.x, pos.y)
		if self.getDimensionGateLayout then
			self:getDimensionGateLayout()
			if self.innerPosToSlotInst and self.innerPosToSlotInst[key] then
				return self.innerPosToSlotInst[key]
			end
		end
		if innerPosToSlot[key] then return innerPosToSlot[key] end

		local layout = self.dimensionGateLayout or PocketDimension.slotBeltLayout
		for slotKey, beltLayout in pairs(layout) do
			local ip = beltLayout.innerBeltPos
			local innerPos = { x = ip[1], y = ip[2] }
			if util.nearPosition(pos, innerPos) then
				return slotKey
			end
		end
	end

	-- True when a validly oriented connectable entity sits at this slot's outside position.
	function Mythos:hasExternalConnection(slotKey)
		local slot = self.slots[slotKey]
		if not slot or not (self.entity and self.entity.valid) then return false end

		return findExternalConnectionEntity(self, slot, connectionTypes) ~= nil
	end

	-- Registers a connection between the given entity and the named slot.
	-- Spawns the hidden proxy connector (pipe/heat-pipe) when required.
	-- Returns true on success.
	function Mythos:connect(slotKey, entity)
		local slot = self.slots[slotKey]
		if not slot then return end
		if slot.conn then
			if slot.conn.entity == entity then
				refreshBeltConnectionLineIndexes(self, slotKey, connectionTypes)
			end
			self:refreshGateRenders()
			return
		end

		local connType = externalEntityConnType(slot, entity, connectionTypes)
		if not connType then
			self:refreshGateRenders()
			return
		end

		if self.assignDimensionGateSlotToNextAvailable then
			local ok = self:assignDimensionGateSlotToNextAvailable(slotKey)
			if not ok then
				self:refreshGateRenders()
				return
			end
		end

		-- Belts and loaders must face toward or away from mythos — not parallel.
		local ioDirection = nil
		if connType == "belt" or connType == "loader" then
			local inwardDir = oppositeDir[slot.outwardDir]
			ioDirection = entity.direction == inwardDir and "input" or "output"
		end

		slot.conn = { entity = entity, connType = connType, ioDirection = ioDirection }

		-- Belt connections also require a matching inner belt placed by the player
		-- at the gate position inside the pocket dimension.
		if connType == "belt" then
			local beltLayout = self:getSlotBeltLayout(slotKey)
			if not beltLayout then slot.conn = nil; self:refreshGateRenders(); return end

			local ip = beltLayout.innerBeltPos
			local innerBelt
			for _, e in pairs(self.inside_surface.find_entities_filtered{
				area = { {ip[1] - 0.4, ip[2] - 0.4}, {ip[1] + 0.4, ip[2] + 0.4} },
			}) do
				if e.valid and connectionTypes[e.type] == "belt" and e.direction == entity.direction then
					innerBelt = e
					break
				end
			end
			if not innerBelt then slot.conn = nil; self:refreshGateRenders(); return end
			slot.conn.innerBelt = innerBelt
			slot.conn.entityLineIndexes = beltLineIndexesForSlot(self, slotKey, entity, connectionTypes)
			slot.conn.innerBeltLineIndexes = beltLineIndexesForPosition(innerBelt, { x = ip[1], y = ip[2] })
		end

		-- Spawn the hidden proxy for fluid / heat connections.
		local hiddenName = hiddenEntityName[connType]
		if hiddenName then
			local surface = self.entity.surface
			if not surface.find_entity(hiddenName, slot.inner) then
				surface.create_entity{
					name        = hiddenName,
					position    = slot.inner,
					force       = entity.force,
					raise_built = false,
				}
			end
			-- For pipe and heat-pipe connections, also place a matching hidden proxy
			-- inside the pocket dimension at the gate position so the player's
			-- internal network connects to it.  Store both proxy references for the
			-- fluid/heat transfer tick.
			if connType == "pipe" or connType == "heat-pipe" then
			local beltLayout = self:getSlotBeltLayout(slotKey)
				if not beltLayout then slot.conn = nil; self:refreshGateRenders(); return end
				local gp = beltLayout.pos
				local innerProxy = self.inside_surface.find_entity(hiddenName, { x = gp[1], y = gp[2] })
				if not (innerProxy and innerProxy.valid) then
					innerProxy = self.inside_surface.create_entity{
						name        = hiddenName,
						position    = { x = gp[1], y = gp[2] },
						force       = entity.force,
						raise_built = false,
					}
				end
				if not innerProxy then slot.conn = nil; self:refreshGateRenders(); return end
				local outerProxy = surface.find_entity(hiddenName, slot.inner)
				slot.conn.outerProxy = outerProxy
				slot.conn.innerProxy = innerProxy
			end
		end

		self:refreshGateRenders()
		return true
	end

	-- Clears a slot's connection and removes the hidden proxy connector, but only
	-- when no other slot sharing the same inner position is still connected.
	-- (Two corner slots can share one inner tile, so the proxy must outlive both.)
	function Mythos:disconnect(slotKey)
		local slot = self.slots[slotKey]
		if not slot or not slot.conn then return end

		local connType   = slot.conn.connType
		local innerPos   = slot.inner
		local innerProxy = slot.conn.innerProxy  -- pipe-only; may be nil
		slot.conn = nil  -- The inner belt is player-placed; it stays in the world.

		-- Destroy the outer hidden proxy when no corner-sharing slot still needs it.
		local hiddenName = hiddenEntityName[connType]
		if hiddenName and not self:innerPositionStillNeeded(innerPos) then
			local proxy = self.entity.surface.find_entity(hiddenName, innerPos)
			if proxy and proxy.valid then
				proxy.destroy{ raise_destroy = false }
			end
			-- Also destroy the paired pocket-dimension proxy for pipe connections.
			if innerProxy and innerProxy.valid then
				innerProxy.destroy{ raise_destroy = false }
			end
		end
		self:refreshGateRenders()
	end

	-- Called when a belt is placed at a gate position inside the pocket dimension.
	-- Searches for a matching external belt and forms the connection if directions align.
	-- Returns true on success.
	function Mythos:connectFromInner(slotKey, innerEntity)
		local slot = self.slots[slotKey]
		if not slot then return end
		if slot.conn then
			if slot.conn.innerBelt == innerEntity then
				refreshBeltConnectionLineIndexes(self, slotKey, connectionTypes)
			end
			return
		end

		-- Find the external belt-like entity overlapping this slot.
		local externalBelt = findExternalConnectionEntity(self, slot, connectionTypes, "belt")
		if not externalBelt then return end

		-- Both belts must face the same direction (toward or away from mythos).
		local inwardDir = oppositeDir[slot.outwardDir]
		if externalBelt.direction ~= slot.outwardDir and externalBelt.direction ~= inwardDir then return end
		if innerEntity.direction ~= externalBelt.direction then return end

		local ioDirection = externalBelt.direction == inwardDir and "input" or "output"
		slot.conn = {
			entity      = externalBelt,
			connType    = "belt",
			ioDirection = ioDirection,
			innerBelt   = innerEntity,
			entityLineIndexes = beltLineIndexesForSlot(self, slotKey, externalBelt, connectionTypes),
			innerBeltLineIndexes = beltLineIndexesForPosition(innerEntity, innerEntity.position),
		}
		self:refreshGateRenders()
		return true
	end

	function Mythos:connectExistingSlot(slotKey)
		local slot = self.slots and self.slots[slotKey]
		if not (slot and self.entity and self.entity.valid) then return false end
		if slot.conn then return true end

		local candidate = findExternalConnectionEntity(self, slot, connectionTypes)
		if candidate then
			return self:connect(slotKey, candidate) == true
		end

		self:updateGateRender(slotKey)
		return false
	end

	-- Scans every external slot position for already-placed connectable entities
	-- and connects them.  Called once when a mythos is placed into an existing layout.
	function Mythos:connectExistingNeighbours()
		for slotKey in pairs(self.slots) do
			self:connectExistingSlot(slotKey)
		end
		self:refreshGateRenders()
	end

	function Mythos:recheckExternalEntity(entity)
		if not (entity and entity.valid and self.entity and self.entity.valid) then return false end
		local changed = false

		for _, slotKey in ipairs(slotKeysInOrder(self.slots)) do
			local slot = self.slots[slotKey]
			local connectedToEntity = slot.conn and slot.conn.entity == entity
			local validForSlot = entityOverlapsSlot(entity, slot)
				and externalEntityConnType(slot, entity, connectionTypes) ~= nil

			if connectedToEntity and not validForSlot then
				self:disconnect(slotKey)
				if self.clearDimensionGateSlotForSlot then
					self:clearDimensionGateSlotForSlot(slotKey)
				end
				changed = true
			elseif connectedToEntity then
				refreshBeltConnectionLineIndexes(self, slotKey, connectionTypes)
				changed = true
			elseif validForSlot and not slot.conn then
				self:connect(slotKey, entity)
				changed = true
			end
		end

		if changed then self:refreshGateRenders() end
		return changed
	end

	-- Searches all live Mythos instances for one whose external slot matches the
	-- given entity's world position.  Returns (state, slotKey) or nil.
	function Mythos.findStateAndSlot(entity)
		local state, slotKeys = Mythos.findStateAndSlots(entity)
		return state, slotKeys and slotKeys[1]
	end

	function Mythos.findStateAndSlots(entity)
		if not (entity and entity.valid) then return end
		for _, state in pairs(Registry.all()) do
			if state.entity.valid then
				local slotKeys = collectExternalSlotKeysForEntity(state, entity, connectionTypes)
				if #slotKeys > 0 then return state, slotKeys end
			end
		end
	end

	-- Disconnects an outside connector and refreshes gate tints.
	function Mythos:disconnectExternalEntity(entity)
		if not (entity and entity.valid) then return end
		local slotKey = self:findSlotAt(entity.position)
		if slotKey then
			self:disconnect(slotKey)
			if self.clearDimensionGateSlotForSlot then
				self:clearDimensionGateSlotForSlot(slotKey)
			end
			return
		end
		for key, slot in pairs(self.slots or {}) do
			if slot.conn and slot.conn.entity == entity then
				self:disconnect(key)
				if self.clearDimensionGateSlotForSlot then
					self:clearDimensionGateSlotForSlot(key)
				end
				return
			end
		end
		self:refreshGateRenders()
	end

end

return Connections
