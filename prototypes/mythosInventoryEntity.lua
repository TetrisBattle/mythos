local modName = "__mythos__"

-- Linked storage shared across every mythos-inventory on a force.
local inventoryEntity = {
	name                       = "mythos-inventory",
	icon                       = modName .. "/graphics/mythos_inventory.png",
	icon_size                  = 256,
	type                       = "linked-container",
	link_id                    = 1,
	gui_mode                   = "none",
	flags                      = { "placeable-player", "player-creation", "hide-alt-info" },
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
