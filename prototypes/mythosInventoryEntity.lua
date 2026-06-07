local modName = "__mythos__"

local inventoryEntity = {
	name                       = "mythos-inventory",
	icon                       = modName .. "/graphics/mythos_inventory.png",
	icon_size                  = 256,
	type                       = "logistic-container",
	logistic_mode              = "requester",
	max_logistic_slots         = 100,
	render_not_in_network_icon = false,
	icon_draw_specification    = { scale = 0, scale_for_many = 0 },
	flags                      = { "placeable-player", "player-creation" },
	minable                    = { mining_time = 0.5, result = "mythos-inventory" },
	max_health                 = 500,
	collision_box              = { { -1.7, -1.7 }, { 1.7, 1.7 } },
	selection_box              = { { -2, -2 }, { 2, 2 } },
	inventory_size             = 100,
	inventory_type             = "with_custom_stack_size",
	inventory_properties       = { stack_size_min = 9999, stack_size_max = 9999 },
	picture                    = {
		layers = {
			{
				filename = modName .. "/graphics/mythos_inventory.png",
				width    = 256,
				height   = 256,
				scale    = 0.7,
				shift    = { 0, -0.1 },
			},
		},
	},
}

local inventoryItem = {
	name         = "mythos-inventory",
	type         = "item",
	place_result = "mythos-inventory",
	stack_size   = 10,
	icon         = modName .. "/graphics/mythos_inventory.png",
	icon_size    = 256,
}

data:extend({
	inventoryEntity,
	inventoryItem,
})
