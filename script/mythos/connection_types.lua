-- Entity -> connection-type mapping.
-- Used to decide how a slot should be wired when an entity is placed next to
-- (or inside) a mythos. Belts move items, pipes move fluid, heat-pipes move heat.
return {
	["loader"]           = "loader",
	["loader-1x1"]       = "loader",
	["transport-belt"]   = "belt",
	["underground-belt"] = "belt",
	["splitter"]         = "belt",
	["lane-splitter"]    = "belt",
	["pipe"]             = "pipe",
	["pipe-to-ground"]   = "pipe",
	["storage-tank"]     = "pipe",
	["pump"]             = "pipe",
	["offshore-pump"]    = "pipe",
	["generator"]        = "pipe",
	["heat-pipe"]        = "heat-pipe",
	["reactor"]          = "heat-pipe",
	["boiler"]           = "heat-pipe",
}
