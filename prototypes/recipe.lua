local mythos = {
	name = "mythos",
	type = "recipe",
	enabled = true,
	ingredients = {
		{ type = "item", name = "iron-plate", amount = 10 }
	},
	results = {
		{ type = "item", name = "mythos", amount = 1 }
	},
	energy_required = 1,
}

data:extend({ mythos })
