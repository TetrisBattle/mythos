local modName = "__mythos__"

local mythosEntity = {
	name              = "mythos",
	icon              = modName .. "/graphics/mythos144.png",
	icon_size         = 144,
	type              = "simple-entity-with-owner",
	flags             = { "placeable-player", "player-creation", "hide-alt-info" },
	minable           = { mining_time = 0.5, result = "mythos" },
	max_health        = 500,
	destructible      = false,
	collision_box     = { { -1.7, -1.7 }, { 1.7, 1.7 } },
	selection_box     = { { -2, -2 }, { 2, 2 } },
	picture           = {
		layers = {
			{
				filename = modName .. "/graphics/mythos256.png",
				width    = 256,
				height   = 256,
				scale    = 0.72,
				shift    = { 0, 0.2 },
			},
		},
	},
}

local mythosItem = {
	name         = "mythos",
	type         = "item",
	icon         = modName .. "/graphics/mythos144.png",
	icon_size    = 144,
	subgroup     = "mythos-logistics",
	order        = "a[mythos]",
	place_result = "mythos",
	stack_size   = 100,
}

local savedIconLayers = {
	{ icon = modName .. "/graphics/mythos144.png", icon_size = 144 },
}
savedIconLayers[2] = {
	icon      = "__base__/graphics/icons/signal/signal-star.png",
	icon_size = 64,
	scale     = 0.4,
	shift     = { 8, 8 },
}

local mythosItemSaved = {
	name         = "mythos-with-contents",
	type         = "item-with-tags",
	icons        = savedIconLayers,
	hidden       = true,
	subgroup     = "mythos-logistics",
	order        = "b[mythos-with-contents]",
	place_result = "mythos",
	stack_size   = 100,
}

data:extend({
	mythosEntity,
	mythosItem,
	mythosItemSaved,
})
