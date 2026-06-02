-- ── Slot Connection System ────────────────────────────────────────────────────
-- Manages the eight external connection slots on a mythos entity.
-- Each slot can hold one active connection (belt, pipe, or heat-pipe) bridging
-- the outside world to the pocket dimension interior.
--
-- Public surface:
--   Connections.buildSlots(cx, cy)   → slots, byExternalPos
--   Connections.install(Mythos, connectionTypes)  → adds methods to the class

local PocketDimension = require("script.PocketDimension")
local util            = require("script.util")
local positionKey     = util.positionKey

-- ── Slot geometry ──────────────────────────────────────────────────────────────
-- Position offsets relative to the mythos entity centre.
--   externalX/Y : tile where the player-placed connector must sit (outside mythos)
--   innerX/Y    : tile inside the mythos footprint where the hidden proxy goes
--   outwardDir  : direction FROM the mythos centre TOWARD the external connector
local slotLayout = {
	["left-top"]     = { externalX = -1.5, externalY = -0.5, innerX = -0.5, innerY = -0.5, outwardDir = defines.direction.west  },
	["left-bottom"]  = { externalX = -1.5, externalY =  0.5, innerX = -0.5, innerY =  0.5, outwardDir = defines.direction.west  },
	["right-top"]    = { externalX =  1.5, externalY = -0.5, innerX =  0.5, innerY = -0.5, outwardDir = defines.direction.east  },
	["right-bottom"] = { externalX =  1.5, externalY =  0.5, innerX =  0.5, innerY =  0.5, outwardDir = defines.direction.east  },
	["top-left"]     = { externalX = -0.5, externalY = -1.5, innerX = -0.5, innerY = -0.5, outwardDir = defines.direction.north },
	["top-right"]    = { externalX =  0.5, externalY = -1.5, innerX =  0.5, innerY = -0.5, outwardDir = defines.direction.north },
	["bottom-left"]  = { externalX = -0.5, externalY =  1.5, innerX = -0.5, innerY =  0.5, outwardDir = defines.direction.south },
	["bottom-right"] = { externalX =  0.5, externalY =  1.5, innerX =  0.5, innerY =  0.5, outwardDir = defines.direction.south },
}

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
local innerPosToSlot = (function()
	local t = {}
	for slotKey, beltLayout in pairs(PocketDimension.slotBeltLayout) do
		local ip = beltLayout.innerBeltPos
		t[positionKey(ip[1], ip[2])] = slotKey
	end
	return t
end)()

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

-- Adds all connection-management methods to the Mythos class.
-- Must be called once after the Mythos table is created.
function Connections.install(Mythos, connectionTypes)

	-- Returns the slot key if pos matches a gate position inside any pocket dimension.
	function Mythos:findInnerSlotAt(pos)
		return innerPosToSlot[positionKey(pos.x, pos.y)]
	end

	-- Registers a connection between the given entity and the named slot.
	-- Spawns the hidden proxy connector (pipe/heat-pipe) when required.
	-- Returns true on success.
	function Mythos:connect(slotKey, entity)
		local slot = self.slots[slotKey]
		if not slot or slot.conn then return end

		local connType = connectionTypes[entity.type]
		if not connType then return end

		-- Belts and loaders must face toward or away from mythos — not parallel.
		local ioDirection = nil
		if connType == "belt" or connType == "loader" then
			local inwardDir = oppositeDir[slot.outwardDir]
			if entity.direction ~= slot.outwardDir and entity.direction ~= inwardDir then
				return
			end
			ioDirection = entity.direction == inwardDir and "input" or "output"
		end

		slot.conn = { entity = entity, connType = connType, ioDirection = ioDirection }

		-- Belt connections also require a matching inner belt placed by the player
		-- at the gate position inside the pocket dimension.
		if connType == "belt" then
			local beltLayout = PocketDimension.slotBeltLayout[slotKey]
			if not beltLayout then slot.conn = nil; return end

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
			if not innerBelt then slot.conn = nil; return end
			slot.conn.innerBelt = innerBelt
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
				local beltLayout = PocketDimension.slotBeltLayout[slotKey]
				if not beltLayout then slot.conn = nil; return end
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
				if not innerProxy then slot.conn = nil; return end
				local outerProxy = surface.find_entity(hiddenName, slot.inner)
				slot.conn.outerProxy = outerProxy
				slot.conn.innerProxy = innerProxy
			end
		end

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
	end

	-- Called when a belt is placed at a gate position inside the pocket dimension.
	-- Searches for a matching external belt and forms the connection if directions align.
	-- Returns true on success.
	function Mythos:connectFromInner(slotKey, innerEntity)
		local slot = self.slots[slotKey]
		if not slot or slot.conn then return end

		-- Find the external belt sitting at this slot's outside position.
		local externalBelt
		for _, e in pairs(self.entity.surface.find_entities_filtered{
			area = {
				{ slot.external.x - 0.4, slot.external.y - 0.4 },
				{ slot.external.x + 0.4, slot.external.y + 0.4 },
			},
		}) do
			if e.valid and connectionTypes[e.type] == "belt" then
				externalBelt = e
				break
			end
		end
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
		}
		return true
	end

	-- Scans every external slot position for already-placed connectable entities
	-- and connects them.  Called once when a mythos is placed into an existing layout.
	function Mythos:connectExistingNeighbours()
		local surface = self.entity.surface
		for slotKey, slot in pairs(self.slots) do
			for _, candidate in pairs(surface.find_entities_filtered{
				area = {
					{ slot.external.x - 0.4, slot.external.y - 0.4 },
					{ slot.external.x + 0.4, slot.external.y + 0.4 },
				},
			}) do
				if candidate.valid and connectionTypes[candidate.type] then
					self:connect(slotKey, candidate)
					break
				end
			end
		end
	end

	-- Searches all live Mythos instances for one whose external slot matches the
	-- given entity's world position.  Returns (state, slotKey) or nil.
	function Mythos.findStateAndSlot(entity)
		for _, state in pairs(storage.mythoi) do
			if state.entity.valid then
				local slotKey = state:findSlotAt(entity.position)
				if slotKey then return state, slotKey end
			end
		end
	end

end

return Connections
