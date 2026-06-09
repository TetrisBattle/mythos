-- Recursively replaces all sprite tables (identified by having a 'filename' key)
-- with a 1×1 transparent placeholder, leaving non-visual data (fluid_box, etc.) intact.
local function makeInvisible(prototype)
	if type(prototype) ~= "table" then return prototype end
	if prototype.filename ~= nil then
		return { filename = "__core__/graphics/empty.png", priority = "extra-high", width = 1, height = 1 }
	end
	local result = {}
	for key, value in pairs(prototype) do result[key] = makeInvisible(value) end
	return result
end

local hiddenFlags = {
	"not-blueprintable",
	"not-deconstructable",
	"not-selectable-in-game",
	"not-upgradable",
	"hide-alt-info",
}

-- Hidden pipe: invisible, no collision, fluid connections intact.
-- Placed inside the mythos footprint to bridge external pipes to the fluid network.
local hiddenPipe              = table.deepcopy(data.raw["pipe"]["pipe"])
hiddenPipe.name               = "mythos-hidden-pipe"
hiddenPipe.localised_name     = { "" }
hiddenPipe.collision_mask     = { layers = {} }
hiddenPipe.flags              = hiddenFlags
hiddenPipe.minable            = nil
hiddenPipe.selection_box      = { { 0, 0 }, { 0, 0 } }
hiddenPipe.pictures           = makeInvisible(hiddenPipe.pictures)

-- Hidden heat-pipe: same idea but for heat connections.
local hiddenHeatPipe                 = table.deepcopy(data.raw["heat-pipe"]["heat-pipe"])
hiddenHeatPipe.name                  = "mythos-hidden-heat-pipe"
hiddenHeatPipe.localised_name        = { "" }
hiddenHeatPipe.collision_mask        = { layers = {} }
hiddenHeatPipe.flags                 = hiddenFlags
hiddenHeatPipe.minable               = nil
hiddenHeatPipe.selection_box         = { { 0, 0 }, { 0, 0 } }
hiddenHeatPipe.connection_sprites    = makeInvisible(hiddenHeatPipe.connection_sprites)
if hiddenHeatPipe.heat_glow_sprites then
	hiddenHeatPipe.heat_glow_sprites = makeInvisible(hiddenHeatPipe.heat_glow_sprites)
end

-- Hidden radar: reveals the pocket dimension interior without appearing on the map.
local hiddenRadar = {
	type                              = "radar",
	name                              = "mythos-hidden-radar",
	selectable_in_game                = false,
	flags                             = { "not-on-map", "hide-alt-info" },
	hidden                            = true,
	collision_mask                    = { layers = {} },
	energy_source                     = { type = "void" },
	energy_usage                      = "250W",
	energy_per_nearby_scan            = "250J",
	energy_per_sector                 = "1kW",
	-- Nearby reveal must be <= sector reveal.  Sized so remote-view stays
	-- charted when the pocket dimension is resized well beyond the default.
	max_distance_of_sector_revealed          = 16,
	max_distance_of_nearby_sector_revealed   = 8,
	localised_name                    = "",
	max_health                        = 1,
	connects_to_other_radars          = false,
}

-- Hidden electric pole placed at the centre of the pocket dimension.
-- supply_area_distance = 64 covers resized floors up to 128 tiles across from centre.
-- maximum_wire_distance matches supply so player poles anywhere on the floor
-- auto-wire into the same network as the inner accumulator (wire_distance = 0
-- left player pole networks isolated so accumulators never received power).
---@type table
local hiddenHubPole                      = table.deepcopy(data.raw["electric-pole"]["substation"])
hiddenHubPole.name                       = "mythos-power-hub-pole"
hiddenHubPole.localised_name             = { "" }
hiddenHubPole.hidden                     = true
hiddenHubPole.flags                      = hiddenFlags
hiddenHubPole.collision_mask             = { layers = {} }
hiddenHubPole.minable                    = nil
hiddenHubPole.selection_box              = { { 0, 0 }, { 0, 0 } }
hiddenHubPole.max_health                 = 1
hiddenHubPole.supply_area_distance       = 64
hiddenHubPole.maximum_wire_distance      = 64
hiddenHubPole.draw_copper_wires          = false
hiddenHubPole.pictures                   = {
	filename      = "__core__/graphics/empty.png",
	priority      = "extra-high",
	width         = 1,
	height        = 1,
	direction_count = 4,
}
hiddenHubPole.light                      = nil
hiddenHubPole.active_picture             = nil
hiddenHubPole.connection_sprites         = nil
hiddenHubPole.radius_visualisation_picture = nil

-- Hidden pole on the placement surface at the mythos position.  Bridges the outer
-- accumulator into the surrounding electric grid so it can charge from nearby poles.
local hiddenOuterPole                      = table.deepcopy(hiddenHubPole)
hiddenOuterPole.name                       = "mythos-power-outer-pole"

-- Gate sprite rendered inside the pocket dimension at each active belt connection.
-- Uses rendering.draw_sprite at runtime so it is always visible, with orientation
-- adjusted per wall side.
local mythosGateSprite = {
	type     = "sprite",
	name     = "mythos-gate",
	filename = "__mythos__/graphics/gate171x256.png",
	width    = 171,
	height   = 256,
	scale    = 0.375,
}

-- Hidden accumulator placed on the outer surface at the mythos position.
-- Connects to the external electric grid so the pocket dimension can draw
-- power from it.  Script-drained every tick into the inner accumulator.
-- Must be type "accumulator" (not electric-energy-interface): EEI shares
-- tertiary priority with player accumulators and prevents them from charging
-- on the same network even while other consumers are powered.
---@type table
local hiddenOuterAcc                      = table.deepcopy(data.raw["accumulator"]["accumulator"])
hiddenOuterAcc.name                       = "mythos-power-link-outer"
hiddenOuterAcc.localised_name             = { "" }
hiddenOuterAcc.hidden                     = true
hiddenOuterAcc.flags                      = hiddenFlags
hiddenOuterAcc.collision_mask             = { layers = {} }
hiddenOuterAcc.minable                    = nil
hiddenOuterAcc.selection_box              = { { 0, 0 }, { 0, 0 } }
hiddenOuterAcc.max_health                 = 1
hiddenOuterAcc.charge_cooldown            = 1
hiddenOuterAcc.discharge_cooldown         = 1
hiddenOuterAcc.energy_source              = {
	type                     = "electric",
	buffer_capacity          = "10MJ",
	usage_priority           = "tertiary",
	input_flow_limit         = "10GW",
	output_flow_limit        = "10GW",
	render_no_power_icon     = true,
	render_no_network_icon   = true,
}
hiddenOuterAcc.picture                    = makeInvisible(hiddenOuterAcc.picture)
hiddenOuterAcc.sprites                    = makeInvisible(hiddenOuterAcc.sprites)
hiddenOuterAcc.charge_animation           = makeInvisible(hiddenOuterAcc.charge_animation)
hiddenOuterAcc.discharge_animation        = makeInvisible(hiddenOuterAcc.discharge_animation)
hiddenOuterAcc.chargable_graphics         = nil
hiddenOuterAcc.water_reflection           = nil
hiddenOuterAcc.charge_light               = nil
hiddenOuterAcc.discharge_light            = nil
hiddenOuterAcc.circuit_wire_max_distance  = 0
hiddenOuterAcc.circuit_wire_connection_points = nil
hiddenOuterAcc.circuit_connector_sprites  = nil

-- Inner power injector inside the pocket dimension.  Uses electric-energy-interface
-- as a producer (not accumulator) so it does not compete with player accumulators
-- on tertiary priority.  Script fills the buffer from the outer link and sets
-- power_production (runtime) to discharge into the inside grid.
local hiddenInnerLink = {
	type                      = "electric-energy-interface",
	name                      = "mythos-power-link-inner",
	localised_name            = { "" },
	hidden                    = true,
	selectable_in_game        = false,
	flags                     = hiddenFlags,
	collision_mask            = { layers = {} },
	minable                   = nil,
	selection_box             = { { 0, 0 }, { 0, 0 } },
	max_health                = 1,
	gui_mode                  = "none",
	energy_source             = {
		type                     = "electric",
		buffer_capacity          = "10MJ",
		usage_priority           = "secondary-output",
		input_flow_limit         = "10GW",
		output_flow_limit        = "10GW",
		render_no_power_icon     = true,
		render_no_network_icon   = true,
	},
	energy_production         = "0W",
	energy_usage              = "0W",
	icon_draw_specification   = { scale = 0 },
	alert_when_damaged        = false,
	picture                   = {
		filename = "__core__/graphics/empty.png",
		priority = "extra-high",
		width    = 1,
		height   = 1,
	},
	circuit_wire_max_distance = 0,
}

data:extend({
	hiddenPipe,
	hiddenHeatPipe,
	hiddenRadar,
	mythosGateSprite,
	hiddenOuterAcc,
	hiddenInnerLink,
	hiddenHubPole,
	hiddenOuterPole,
})
