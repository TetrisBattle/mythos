local modName = "__mythos__"

-- Half-tile west / south offset so the 2x2 hover footprint matches the sprite.
local OFFSET_X = -0.5
local OFFSET_Y = 0.5

-- Virtual chest: linked storage shared across every chest on a force.
local virtualChestEntity = {
	name                      = "virtual-chest",
	icon                      = modName .. "/graphics/virtual_chest.png",
	icon_size                 = 256,
	type                      = "linked-container",
	link_id                   = 1,
	gui_mode                  = "none",
	flags                     = { "placeable-player", "player-creation", "hide-alt-info" },
	minable                   = { mining_time = 0.5, result = "virtual-chest" },
	max_health                = 500,
	tile_width                = 2,
	tile_height               = 2,
	collision_box             = {
		{ -0.9 + OFFSET_X, -0.9 + OFFSET_Y },
		{  0.9 + OFFSET_X,  0.9 + OFFSET_Y },
	},
	selection_box             = {
		{ -1 + OFFSET_X, -1 + OFFSET_Y },
		{  1 + OFFSET_X,  1 + OFFSET_Y },
	},
	tile_buildability_rules   = {
		{
			area            = { { -1, -1 }, { 1, 1 } },
			colliding_tiles = { layers = { mythos_dimension_floor = true } },
		},
	},
	circuit_wire_max_distance = 0,
	draw_circuit_wires        = false,
	draw_copper_wires         = false,
	inventory_size            = 100,
	inventory_type            = "with_custom_stack_size",
	inventory_properties      = { stack_size_min = 9999, stack_size_max = 9999 },
	picture                   = {
		layers = {
			{
				filename = modName .. "/graphics/virtual_chest.png",
				width    = 256,
				height   = 256,
				scale    = 0.32,
				shift    = { OFFSET_X, OFFSET_Y },
				priority = "extra-high",
			},
		},
	},
}

local virtualChestItem = {
	name         = "virtual-chest",
	type         = "item",
	place_result = "virtual-chest",
	stack_size   = 100,
	icon         = modName .. "/graphics/virtual_chest.png",
	icon_size    = 256,
	subgroup     = "mythos-logistics",
	order        = "c[virtual-chest]",
}

data:extend({
	virtualChestEntity,
	virtualChestItem,
})
