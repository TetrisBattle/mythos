local mythos = {
	name = "mythos",
	type = "recipe",
	enabled = true,
	ingredients = {
		{ type = "item", name = "iron-plate", amount = 10 },
	},
	results = {
		{ type = "item", name = "mythos", amount = 1 },
	},
	energy_required = 1,
}

local virtualChest = {
	name = "virtual-chest",
	type = "recipe",
	enabled = true,
	ingredients = {
		{ type = "item", name = "electronic-circuit", amount = 5 },
	},
	results = {
		{ type = "item", name = "virtual-chest", amount = 1 },
	},
	energy_required = 2,
}

data:extend({ mythos, virtualChest })
