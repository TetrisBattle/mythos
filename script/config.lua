local Config = {}

local PocketDimension = require("script.pocket_dimension.init")

local function settingValue(name, fallback)
	local setting = settings.global[name]
	if not setting then return fallback end
	return setting.value
end

local function defaultDimensionSize(settingName, fallback, minSize)
	return PocketDimension.normalizeSize(settingValue(settingName, fallback), minSize)
end

function Config.noCost()
	return settings.global["mythos-no-cost"].value
end

function Config.hideVirtualInventory()
	return Config.noCost()
		and settings.global["mythos-no-virtual-inventory"].value
end

function Config.defaultDimensionWidth()
	return defaultDimensionSize(
		"mythos-default-width",
		PocketDimension.DEFAULT_WIDTH,
		PocketDimension.MIN_DIMENSION_WIDTH
	)
end

function Config.defaultDimensionHeight()
	return defaultDimensionSize(
		"mythos-default-height",
		PocketDimension.DEFAULT_HEIGHT,
		PocketDimension.MIN_DIMENSION_HEIGHT
	)
end

function Config.defaultDimensionBounds()
	local bounds = {
		x_min = PocketDimension.DEFAULT_FLOOR_BOUNDS.x_min,
		y_min = PocketDimension.DEFAULT_FLOOR_BOUNDS.y_min,
	}
	bounds.x_max = bounds.x_min + Config.defaultDimensionWidth() - 1
	bounds.y_max = bounds.y_min + Config.defaultDimensionHeight() - 1
	return bounds
end

return Config
