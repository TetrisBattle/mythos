local PocketDimension = require("script.pocket_dimension.init")
local util            = require("script.util")

local DimensionResize = {}

local GATE_CONNECTED_COLOR     = { r = 1,   g = 1,   b = 1,   a = 1   }
local GATE_DISCONNECTED_COLOR  = { r = 0.4, g = 0.4, b = 0.4, a = 0.85 }
local GATE_LABEL_COLOR         = { r = 1,   g = 1,   b = 1,   a = 0.9  }

local function gateTarget(pos)
	return { x = pos[1], y = pos[2] }
end

local function floorBoundsKey(bounds)
	return string.format("%d,%d,%d,%d", bounds.x_min, bounds.x_max, bounds.y_min, bounds.y_max)
end

local function applyGateRender(mythos, slotKey, slot, beltLayout, surface)
	if slot.gateRender and slot.gateRender.valid then
		slot.gateRender.destroy()
	end
	slot.gateRender = nil

	if not beltLayout then return end

	slot.gateRender = rendering.draw_sprite{
		sprite      = "mythos-gate",
		target      = gateTarget(beltLayout.pos),
		surface     = surface,
		render_layer = "lower-object",
		orientation = beltLayout.gateOrientation,
		y_scale     = 0.75,
		tint        = (slot.conn or mythos:hasExternalConnection(slotKey))
			and GATE_CONNECTED_COLOR or GATE_DISCONNECTED_COLOR,
	}
end

local function drawGateSpritesForLayout(mythos, slots, layout, surface)
	for slotKey, slot in pairs(slots) do
		applyGateRender(mythos, slotKey, slot, layout[slotKey], surface)
	end
end

local function clearGateLabelRenders(mythos)
	if mythos.gateLabelRenders then
		for _, render in pairs(mythos.gateLabelRenders) do
			if render and render.valid then render.destroy() end
		end
	end
	mythos.gateLabelRenders = {}
end

local function drawGateLabelsForBounds(mythos, bounds, surface)
	clearGateLabelRenders(mythos)
	local gatePositions = mythos:normalizeDimensionGatePositions()
	for i, label in ipairs(PocketDimension.computeDimensionGateLabels(bounds, gatePositions)) do
		mythos.gateLabelRenders[i] = rendering.draw_text{
			text               = label.text,
			target             = gateTarget(label.pos),
			surface            = surface,
			color              = GATE_LABEL_COLOR,
			scale              = 0.75,
			alignment          = "center",
			vertical_alignment = "bottom",
		}
	end
end

local edgeSlots = {
	left   = util.edgeSlotKeys("left", PocketDimension.GATES_PER_SIDE),
	right  = util.edgeSlotKeys("right", PocketDimension.GATES_PER_SIDE),
	top    = util.edgeSlotKeys("top", PocketDimension.GATES_PER_SIDE),
	bottom = util.edgeSlotKeys("bottom", PocketDimension.GATES_PER_SIDE),
}

local RESIZE_STEP = PocketDimension.RESIZE_STEP

local function axisSize(bounds, edge)
	if edge == "right" or edge == "left" then
		return util.floorWidth(bounds)
	end
	return util.floorHeight(bounds)
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
	if not self.floor_bounds then return end
	self.inside_x, self.inside_y = PocketDimension.floorCentre(self.floor_bounds)
end

local function finalizeFloorBounds(self, refreshGates)
	syncViewPosition(self)
	if self.inside_surface and self.inside_surface.valid and self.floor_bounds then
		PocketDimension.ensureRemoteViewReady(
			self.inside_surface, self.floor_bounds, self.entity.force
		)
	end
	if refreshGates ~= false then
		self:invalidateDimensionGateLayout()
		self:refreshGateRenders()
	end
end

local function applyFloorBounds(self, newBounds, deferFinalize, refreshGates)
	self.floor_bounds = newBounds
	if deferFinalize then return end
	finalizeFloorBounds(self, refreshGates)
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

function DimensionResize.install(Mythos)

	function Mythos:invalidateDimensionGateLayout()
		self.dimensionGateLayout = nil
		self.dimensionGateLayoutBoundsKey = nil
		self.innerPosToSlotInst = nil
	end

	function Mythos:getDimensionGateLayout()
		if not self.floor_bounds then
			self:syncFloorBoundsFromTiles()
		end
		local bounds = self.floor_bounds or PocketDimension.DEFAULT_FLOOR_BOUNDS
		local boundsKey = floorBoundsKey(bounds)
		if not self.dimensionGateLayout or self.dimensionGateLayoutBoundsKey ~= boundsKey then
			self.dimensionGateLayout = PocketDimension.computeDimensionSlotBeltLayout(
				bounds,
				self:normalizeDimensionGatePositions()
			)
			self.dimensionGateLayoutBoundsKey = boundsKey
			self.innerPosToSlotInst = util.buildInnerPosToSlot(self.dimensionGateLayout)
		end
		return self.dimensionGateLayout
	end

	function Mythos:getSlotBeltLayout(slotKey)
		local layout = self:getDimensionGateLayout()
		return layout and layout[slotKey]
	end

	function Mythos:isEdgeConnected(edge)
		for _, slotKey in ipairs(edgeSlots[edge]) do
			if self.slots[slotKey] and self.slots[slotKey].conn then
				return true
			end
		end
		return false
	end

	-- Floor tiles are the source of truth for gate placement.
	function Mythos:syncFloorBoundsFromTiles()
		if self.inside_surface and self.inside_surface.valid then
			self.floor_bounds = PocketDimension.inferFloorBounds(self.inside_surface)
		elseif not self.floor_bounds then
			self.floor_bounds = util.copyBounds(PocketDimension.DEFAULT_FLOOR_BOUNDS)
		end
	end

	function Mythos:refreshGateRenders()
		if not (self.slots and self.inside_surface and self.inside_surface.valid) then return end
		self:syncSlotGeometry()
		local layout = self:getDimensionGateLayout()
		drawGateSpritesForLayout(self, self.slots, layout, self.inside_surface)
		drawGateLabelsForBounds(self, self.floor_bounds or PocketDimension.DEFAULT_FLOOR_BOUNDS, self.inside_surface)
		if self.refreshGateSelectors then
			self:refreshGateSelectors(layout)
		end
	end

	function Mythos:updateGateRender(slotKey)
		if not (self.slots and self.inside_surface and self.inside_surface.valid) then return end
		self:syncSlotGeometry()
		local slot = self.slots[slotKey]
		if not slot then return end
		applyGateRender(self, slotKey, slot, self:getSlotBeltLayout(slotKey), self.inside_surface)
	end

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
		applyFloorBounds(self, newBounds, deferGateRefresh, edge == "right" or edge == "bottom")
		return true
	end

	function Mythos:contractEdge(edge, deferGateRefresh, steps)
		if edge ~= "right" and edge ~= "bottom" then
			return false, "mythos-gui.resize-invalid-edge"
		end

		if self:isEdgeConnected(edge) then
			return false, "mythos-gui.resize-has-connections"
		end

		self:syncFloorBoundsFromTiles()
		steps = steps or resizeStepsForEdge(self.floor_bounds, edge)
		local newBounds, blocked = PocketDimension.contractEdge(
			self.inside_surface, self.floor_bounds, edge, self.entity.force, steps
		)
		if not newBounds then
			if blocked then
				return false, "mythos-gui.resize-has-entities"
			end
			return false, "mythos-gui.resize-min-size"
		end

		applyFloorBounds(self, newBounds, deferGateRefresh, edge == "right" or edge == "bottom")
		return true
	end

	function Mythos:resizeTo(targetWidth, targetHeight)
		targetWidth  = PocketDimension.snapSizeUpEven(targetWidth, PocketDimension.MIN_DIMENSION_WIDTH)
		targetHeight = PocketDimension.snapSizeUpEven(targetHeight, PocketDimension.MIN_DIMENSION_HEIGHT)
		if targetWidth < PocketDimension.MIN_DIMENSION_WIDTH
				or targetHeight < PocketDimension.MIN_DIMENSION_HEIGHT then
			return false, "mythos-gui.resize-invalid-size"
		end

		self:syncFloorBoundsFromTiles()
		local width  = util.floorWidth(self.floor_bounds)
		local height = util.floorHeight(self.floor_bounds)

		local ok, err = resizeAxis(self, "right", width, targetWidth, true)
		if not ok then return false, err end

		ok, err = resizeAxis(self, "bottom", height, targetHeight, true)
		if not ok then return false, err end

		finalizeFloorBounds(self, true)
		return true
	end

end

return DimensionResize
