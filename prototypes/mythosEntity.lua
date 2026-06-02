local modName     = "__mythos__"

local mythosEntity      = {
	name = "mythos",
	icon = modName .. "/graphics/mythos144.png",
	icon_size = 144,
	type = "logistic-container",
	logistic_mode = "requester",
	logistic_slots_count = 48,
	render_not_in_network_icon = false,
	flags = { "placeable-player", "player-creation" },
	minable = { mining_time = 0.5, result = "mythos" },
	max_health = 500,
	collision_box = { { -0.8, -0.8 }, { 0.8, 0.8 } },
	selection_box = { { -1, -1 }, { 1, 1 } },
	inventory_size = 48,
	trash_inventory_size = 20,
	picture = {
		layers = {
			{
				filename = modName .. "/graphics/mythos256.png",
				width = 256,
				height = 256,
				scale = 0.4,
			},
		},
	},
}

local mythosItem = {
	name = "mythos",
	type = "item",
	icon = modName .. "/graphics/mythos144.png",
	icon_size = 144,
	place_result = "mythos",
	stack_size = 10,
}

-- Same entity, but carries saved pocket-dimension contents.
-- The base mythos icon is kept at original colours; a star overlay is added
-- in the bottom-right corner so it is visually distinct from an empty mythos.
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
	place_result = "mythos",
	stack_size   = 1,
}

data:extend({
	mythosEntity,
	mythosItem,
	mythosItemSaved,
})
