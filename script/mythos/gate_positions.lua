local GatePositions = {}

local function slotExists(state, slotKey)
	return slotKey and state.slots and state.slots[slotKey] ~= nil
end

function GatePositions.install(Mythos)

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
