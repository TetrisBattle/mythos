local GatePositions = {}

local PocketDimension = require("script.pocket_dimension.init")

local function slotExists(state, slotKey)
	return slotKey and state.slots and state.slots[slotKey] ~= nil
end

function GatePositions.install(Mythos)

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

end

return GatePositions
