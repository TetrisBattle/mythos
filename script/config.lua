local Config = {}

function Config.noCost()
	return settings.global["mythos-no-cost"].value
end

function Config.hideVirtualInventory()
	return Config.noCost()
		and settings.global["mythos-no-virtual-inventory"].value
end

return Config
