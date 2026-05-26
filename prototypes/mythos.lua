local modName = "__mythos__"

local mythos = {
	name = "mythos",
	icon = modName .. "/graphics/mythos_144px.png",
	icon_size = 144,
	type = "container",
	inventory_size = 48,
}

local mythos_item = {
	name = "mythos",
	type = "item",
	icon = modName .. "/graphics/mythos_144px.png",
	icon_size = 144,
	place_result = "mythos",
	stack_size = 10,
}

data:extend({ mythos, mythos_item })
