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
	max_distance_of_sector_revealed   = 0,
	max_distance_of_nearby_sector_revealed = 1,
	localised_name                    = "",
	max_health                        = 1,
	connects_to_other_radars          = false,
}

data:extend({
	hiddenPipe,
	hiddenHeatPipe,
	hiddenRadar,
})
