local Common = {}

Common.MAX_TOTAL_ITEMS         = 5000
Common.VIRTUAL_CHEST_LINK_ID   = 1
Common.VIRTUAL_CHEST_PROTOTYPE = "virtual-chest"
Common.LEGACY_PROTOTYPE        = "mythos-inventory"
Common.LEGACY_ITEM             = "mythos-inventory"
Common.LEGACY_REGISTRY_KEYS    = { "mythos_inventories", "virtual_chests" }

function Common.distanceSq(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return dx * dx + dy * dy
end

function Common.stackQuality(quality)
	if not quality then return nil end
	if type(quality) == "string" then return quality end
	return quality.name
end

function Common.itemLookup(req)
	local quality = Common.stackQuality(req.quality)
	if quality then
		return { name = req.name, quality = quality }
	end
	return req.name
end

function Common.itemRemoveFilter(req, count)
	local quality = Common.stackQuality(req.quality)
	if quality then
		return { name = req.name, count = count, quality = quality }
	end
	return { name = req.name, count = count }
end

function Common.isVirtualChestEntity(entity)
	return entity and entity.valid
		and (entity.name == Common.VIRTUAL_CHEST_PROTOTYPE
			or entity.name == Common.LEGACY_PROTOTYPE)
end

return Common
