-- Pocket-dimension floor tile.  Carries a dedicated collision layer so selected
-- entities can opt out of being built inside mythoi via tile_buildability_rules.
local floor = table.deepcopy(data.raw.tile["lab-dark-2"])
floor.name = "mythos-dimension-floor"
floor.localised_name = { "" }
floor.autoplace = nil
floor.map_color = floor.map_color or { r = 50, g = 50, b = 60, a = 255 }

local mask = floor.collision_mask
if mask.layers then
	mask.layers.mythos_dimension_floor = true
else
	floor.collision_mask = { layers = { ground_tile = true, mythos_dimension_floor = true } }
end

data:extend({ floor })
