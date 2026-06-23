local GatePositions = {}

local PocketDimension = require("script.pocket_dimension.init")

local function slotExists(state, slotKey)
	return slotKey and state.slots and state.slots[slotKey] ~= nil
end

local function positionUsed(positions, physicalGateKey)
	for _, candidatePhysicalGateKey in pairs(positions) do
		if candidatePhysicalGateKey == physicalGateKey then return true end
	end
	return false
end

local function orderedConnectionSlots()
	local slots = {}
	for _, prefix in ipairs{ "L", "T", "R", "B" } do
		for index = 1, PocketDimension.GATES_PER_SIDE do
			slots[#slots + 1] = prefix .. index
		end
	end
	return slots
end

function GatePositions.install(Mythos)

	function Mythos:assignDimensionGateSlotToNextAvailable(slotKey)
		if not slotExists(self, slotKey) then
			return false, "mythos-gui.gate-position-invalid"
		end

		local positions = self:normalizeDimensionGatePositions()
		if positions[slotKey] then return true end

		local physicalLayout = self.getDimensionPhysicalGateLayout
			and self:getDimensionPhysicalGateLayout()
			or PocketDimension.computeDimensionPhysicalGateLayout(self.floor_bounds)
		for index = 1, 999 do
			local physicalGateKey = "PL" .. index
			if not physicalLayout[physicalGateKey] then break end
			if not positionUsed(positions, physicalGateKey) then
				positions[slotKey] = physicalGateKey
				self.dimension_gate_positions = positions
				self:invalidateDimensionGateLayout()
				return true
			end
		end
		return false, "mythos-gui.gate-position-failed"
	end

	function Mythos:clearDimensionGateSlotForSlot(slotKey)
		if not slotExists(self, slotKey) then
			return false, "mythos-gui.gate-position-invalid"
		end
		local positions = self:normalizeDimensionGatePositions()
		if not positions[slotKey] then return true end

		positions[slotKey] = nil
		self.dimension_gate_positions = positions
		self:invalidateDimensionGateLayout()
		self:refreshGateRenders()
		return true
	end

	function Mythos:clearDimensionGateSlot(physicalGateKey)
		local physicalLayout = self.getDimensionPhysicalGateLayout
			and self:getDimensionPhysicalGateLayout()
			or PocketDimension.computeDimensionPhysicalGateLayout(self.floor_bounds)
		if not (physicalLayout and physicalLayout[physicalGateKey]) then
			return false, "mythos-gui.gate-position-invalid"
		end

		local positions = self:normalizeDimensionGatePositions()
		local previousSlotKey = nil
		for candidateSlotKey, candidatePhysicalGateKey in pairs(positions) do
			if candidatePhysicalGateKey == physicalGateKey then
				previousSlotKey = candidateSlotKey
				break
			end
		end
		if not previousSlotKey then return true end

		self:disconnect(previousSlotKey)
		positions[previousSlotKey] = nil
		self.dimension_gate_positions = positions
		self:invalidateDimensionGateLayout()
		self:refreshGateRenders()
		return true
	end

	function Mythos:assignDimensionGateSlot(physicalGateKey, slotKey)
		if not slotExists(self, slotKey) then
			return false, "mythos-gui.gate-position-invalid"
		end

		local physicalLayout = self.getDimensionPhysicalGateLayout
			and self:getDimensionPhysicalGateLayout()
			or PocketDimension.computeDimensionPhysicalGateLayout(self.floor_bounds)
		if not (physicalLayout and physicalLayout[physicalGateKey]) then
			return false, "mythos-gui.gate-position-invalid"
		end

		local positions = self:normalizeDimensionGatePositions()
		local previousSlotKey = nil
		for candidateSlotKey, candidatePhysicalGateKey in pairs(positions) do
			if candidatePhysicalGateKey == physicalGateKey then
				previousSlotKey = candidateSlotKey
				break
			end
		end

		if previousSlotKey == slotKey then return true end

		local previousPhysicalGateKey = positions[slotKey]
		self:disconnect(slotKey)
		if previousSlotKey then
			self:disconnect(previousSlotKey)
		end

		positions[slotKey] = physicalGateKey
		if previousSlotKey then
			positions[previousSlotKey] = previousPhysicalGateKey
		end
		self.dimension_gate_positions = positions
		self:invalidateDimensionGateLayout()
		self:refreshGateRenders()

		self:connectExistingSlot(slotKey)
		if previousSlotKey then
			self:connectExistingSlot(previousSlotKey)
		end
		self:refreshGateRenders()
		return true
	end

	function Mythos:swapDimensionGateSlots(sourceSlotKey, targetSlotKey)
		if not slotExists(self, sourceSlotKey) or not slotExists(self, targetSlotKey) then
			return false, "mythos-gui.gate-position-invalid"
		end
		if sourceSlotKey == targetSlotKey then return true end

		local positions = self:normalizeDimensionGatePositions()
		local sourcePosition = positions[sourceSlotKey]
		positions[sourceSlotKey] = positions[targetSlotKey]
		positions[targetSlotKey] = sourcePosition

		self:disconnect(sourceSlotKey)
		self:disconnect(targetSlotKey)
		self.dimension_gate_positions = positions
		self:invalidateDimensionGateLayout()
		self:refreshGateRenders()

		self:connectExistingSlot(sourceSlotKey)
		self:connectExistingSlot(targetSlotKey)
		self:refreshGateRenders()
		return true
	end

	function Mythos:resetDimensionGatePositions()
		local physicalLayout = self.getDimensionPhysicalGateLayout
			and self:getDimensionPhysicalGateLayout()
			or PocketDimension.computeDimensionPhysicalGateLayout(self.floor_bounds)
		if not physicalLayout then
			return false, "mythos-gui.gate-position-invalid"
		end

		local connectedSlotKeys = {}
		for _, slotKey in ipairs(orderedConnectionSlots()) do
			local slot = self.slots and self.slots[slotKey]
			if slot and (slot.conn or (self.hasExternalConnection and self:hasExternalConnection(slotKey))) then
				connectedSlotKeys[#connectedSlotKeys + 1] = slotKey
			end
		end

		local positions = {}
		for index, slotKey in ipairs(connectedSlotKeys) do
			local physicalGateKey = "PL" .. index
			if not physicalLayout[physicalGateKey] then
				return false, "mythos-gui.gate-position-failed"
			end
			self:disconnect(slotKey)
			positions[slotKey] = physicalGateKey
		end

		self.dimension_gate_positions = positions
		self:invalidateDimensionGateLayout()
		self:refreshGateRenders()

		for _, slotKey in ipairs(connectedSlotKeys) do
			self:connectExistingSlot(slotKey)
		end
		self:refreshGateRenders()
		return true
	end

end

return GatePositions
