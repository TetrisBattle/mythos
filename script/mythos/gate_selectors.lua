local Registry = require("script.mythos.registry")
local util     = require("script.util")

local GateSelectors = {}

GateSelectors.PROTOTYPE = "mythos-gate-selector"

local function destroySelector(entity)
	if entity and entity.valid then
		entity.destroy{ raise_destroy = false }
	end
end

function GateSelectors.findStateAndGatePosition(entity)
	if not (entity and entity.valid and entity.name == GateSelectors.PROTOTYPE) then return nil end
	for _, state in pairs(Registry.all()) do
		if state.inside_surface and state.inside_surface.valid
				and state.inside_surface.index == entity.surface.index then
			for physicalGateKey, selector in pairs(state.gateSelectorEntities or {}) do
				if selector == entity then
					return state, physicalGateKey
				end
			end
			local layout = state.getDimensionPhysicalGateLayout and state:getDimensionPhysicalGateLayout()
			for physicalGateKey, gateLayout in pairs(layout or {}) do
				local pos = gateLayout.pos
				if util.nearPosition(entity.position, { x = pos[1], y = pos[2] }, 0.1) then
					return state, physicalGateKey
				end
			end
		end
	end
end

GateSelectors.findStateAndSlot = GateSelectors.findStateAndGatePosition

function GateSelectors.install(Mythos)

	function Mythos:destroyGateSelectors()
		if self.gateSelectorEntities then
			for _, selector in pairs(self.gateSelectorEntities) do
				destroySelector(selector)
			end
		end
		self.gateSelectorEntities = nil
	end

	function Mythos:refreshGateSelectors(physicalLayout)
		if not (self.inside_surface and self.inside_surface.valid and self.entity and self.entity.valid) then
			return
		end

		self:destroyGateSelectors()
		for _, selector in pairs(self.inside_surface.find_entities_filtered{ name = GateSelectors.PROTOTYPE }) do
			destroySelector(selector)
		end
		self.gateSelectorEntities = {}
		physicalLayout = physicalLayout or self:getDimensionPhysicalGateLayout()

		for physicalGateKey, gateLayout in pairs(physicalLayout or {}) do
			local pos = gateLayout.pos
			local selector = self.inside_surface.create_entity{
				name        = GateSelectors.PROTOTYPE,
				position    = { x = pos[1], y = pos[2] },
				force       = self.entity.force,
				raise_built = false,
			}
			if selector and selector.valid then
				self.gateSelectorEntities[physicalGateKey] = selector
			end
		end
	end

	function Mythos:findGateSelectorPosition(entity)
		if not (entity and entity.valid) then return nil end
		for physicalGateKey, selector in pairs(self.gateSelectorEntities or {}) do
			if selector == entity then return physicalGateKey end
			if selector and selector.valid and util.nearPosition(entity.position, selector.position, 0.1) then
				return physicalGateKey
			end
		end
	end

	Mythos.findGateSelectorSlot = Mythos.findGateSelectorPosition

end

return GateSelectors
