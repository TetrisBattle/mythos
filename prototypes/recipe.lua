local mythos = {
	name = "mythos",
	type = "recipe",
	category = "crafting",
	subgroup = "mythos-logistics",
	order = "a[mythos]",
	enabled = true,
	ingredients = {
		{ type = "item", name = "iron-plate", amount = 10 },
	},
	results = {
		{ type = "item", name = "mythos", amount = 1 },
	},
	main_product = "mythos",
	energy_required = 1,
}

local mythosFree = {
	name = "mythos-free",
	type = "recipe",
	category = "crafting",
	subgroup = "mythos-logistics",
	order = "a[mythos]",
	enabled = false,
	ingredients = {},
	results = {
		{ type = "item", name = "mythos", amount = 1 },
	},
	main_product = "mythos",
	energy_required = 1,
}

local virtualChest = {
	name = "virtual-chest",
	type = "recipe",
	category = "crafting",
	subgroup = "mythos-logistics",
	order = "c[virtual-chest]",
	enabled = true,
	ingredients = {
		{ type = "item", name = "electronic-circuit", amount = 5 },
	},
	results = {
		{ type = "item", name = "virtual-chest", amount = 1 },
	},
	main_product = "virtual-chest",
	energy_required = 2,
}

local virtualChestFree = {
	name = "virtual-chest-free",
	type = "recipe",
	category = "crafting",
	subgroup = "mythos-logistics",
	order = "c[virtual-chest]",
	enabled = false,
	ingredients = {},
	results = {
		{ type = "item", name = "virtual-chest", amount = 1 },
	},
	main_product = "virtual-chest",
	energy_required = 2,
}

data:extend({
	mythos,
	mythosFree,
	virtualChest,
	virtualChestFree,
})
