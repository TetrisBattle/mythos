local DIMENSION_SIZE = 32   -- floor side length in tiles
local VIEW_X = DIMENSION_SIZE / 2  -- remote-view camera centre
local VIEW_Y = DIMENSION_SIZE / 2
local mid    = DIMENSION_SIZE / 2  -- centre of each wall side (gap straddles mid-1 and mid)

-- Maps each mythos slot key to the wall-gap position and the gate sprite orientation.
--   pos             : rendering.draw_sprite position (centre of the wall-gap tile).
--   gateOrientation : RealOrientation (0–1) passed to rendering.draw_sprite.
--     The image has its connection at the bottom, so:
--       top wall    → 0    (no rotation,  connection faces south into room)
--       right wall  → 0.25 (90° CW,       connection faces west  into room)
--       bottom wall → 0.5  (180°,         connection faces north into room)
--       left wall   → 0.75 (270° CW,      connection faces east  into room)
-- innerBeltPos: the tile one step inside the floor where the player places their belt.
local slotBeltLayout = {
	["left-top"]     = { pos = { -0.5,                  mid - 0.5 }, innerBeltPos = { 0.5,                  mid - 0.5 }, gateOrientation = 0.75 },
	["left-bottom"]  = { pos = { -0.5,                  mid + 0.5 }, innerBeltPos = { 0.5,                  mid + 0.5 }, gateOrientation = 0.75 },
	["right-top"]    = { pos = { DIMENSION_SIZE + 0.5,  mid - 0.5 }, innerBeltPos = { DIMENSION_SIZE - 0.5, mid - 0.5 }, gateOrientation = 0.25 },
	["right-bottom"] = { pos = { DIMENSION_SIZE + 0.5,  mid + 0.5 }, innerBeltPos = { DIMENSION_SIZE - 0.5, mid + 0.5 }, gateOrientation = 0.25 },
	["top-left"]     = { pos = { mid - 0.5, -0.5                  }, innerBeltPos = { mid - 0.5, 0.5                  }, gateOrientation = 0    },
	["top-right"]    = { pos = { mid + 0.5, -0.5                  }, innerBeltPos = { mid + 0.5, 0.5                  }, gateOrientation = 0    },
	["bottom-left"]  = { pos = { mid - 0.5, DIMENSION_SIZE + 0.5  }, innerBeltPos = { mid - 0.5, DIMENSION_SIZE - 0.5  }, gateOrientation = 0.5  },
	["bottom-right"] = { pos = { mid + 0.5, DIMENSION_SIZE + 0.5  }, innerBeltPos = { mid + 0.5, DIMENSION_SIZE - 0.5  }, gateOrientation = 0.5  },
}

-- Creates the 32×32 pocket-dimension surface for one mythos entity.
-- Floor tiles: (0,0)→(31,31).  Stone walls at the one-tile perimeter outside.
-- outer_surface: the LuaSurface the mythos is placed on; used to copy the
-- solar multiplier so solar panels inside match the planet the mythos is on.
-- Returns: surface, inner_acc
local function create(unit_number, force, outer_surface)
	---@diagnostic disable-next-line: missing-fields
	local mapGenSettings = { default_enable_all_autoplace_controls = false, width = 2, height = 2 }
	local surface = game.create_surface(
		"mythos-dimension-" .. unit_number,
		mapGenSettings
	)

	-- Hide this surface from the map surface selector.
	-- set_surface_hidden is per-force, so call it for every force.
	for _, f in pairs(game.forces) do
		f.set_surface_hidden(surface, true)
	end

	-- Keep the pocket dimension permanently at full daylight brightness.
	surface.daytime       = 0.5
	surface.freeze_daytime = true

	-- Mark chunks as fully generated so the renderer shows them.
	-- Without this, void chunks stay black on the map even after tiles are placed.
	for cx = -2, 2 do
		for cy = -2, 2 do
			surface.set_chunk_generated_status(
				{ cx, cy },
				defines.chunk_generated_status.entities
			)
		end
	end

	-- Floor
	local tiles = {}
	for x = 0, DIMENSION_SIZE - 1 do
		for y = 0, DIMENSION_SIZE - 1 do
			tiles[#tiles + 1] = { name = "lab-dark-2", position = { x, y } }
		end
	end
	surface.set_tiles(tiles)

	-- Fill the void outside the floor with a hidden tile so the engine doesn't
	-- render raw black space when the player remote-views the surface.
	local hiddenPos = {0, 0}
	for x = -64, 64 + DIMENSION_SIZE - 1 do
		for y = -64, 64 + DIMENSION_SIZE - 1 do
			if x < 0 or x >= DIMENSION_SIZE or y < 0 or y >= DIMENSION_SIZE then
				hiddenPos[1] = x
				hiddenPos[2] = y
				surface.set_hidden_tile(hiddenPos, "water")
			end
		end
	end

	-- Perimeter walls (one tile outside the floor)
	local n = DIMENSION_SIZE
	local function wall(tx, ty)
		surface.create_entity{
			name        = "stone-wall",
			position    = { tx + 0.5, ty + 0.5 },
			force       = force,
			raise_built = false,
		}
	end
	for i = -1, n do
		if i ~= mid - 1 and i ~= mid then
			wall(i, -1)  -- top row
			wall(i,  n)  -- bottom row
		end
	end
	for i = 0, n - 1 do
		if i ~= mid - 1 and i ~= mid then
			wall(-1, i)  -- left column
			wall( n, i)  -- right column
		end
	end

	-- Hidden radar so the interior is revealed when remote-viewing.
	local radar = surface.create_entity{
		name        = "mythos-hidden-radar",
		position    = { DIMENSION_SIZE / 2, DIMENSION_SIZE / 2 },
		force       = force,
		raise_built = false,
	}
	if radar then radar.destructible = false end

	-- Sync solar output to the planet the mythos is placed on.
	-- Solar panels inside will produce power proportional to the outer
	-- surface's solar_power_multiplier (e.g., Aquilo gets ~30% of Nauvis).
	-- The dimension is kept at noon (daytime = 0.5) so solar panels always
	-- run at their full fraction without a day/night cycle.
	if outer_surface and outer_surface.valid then
		surface.solar_power_multiplier = outer_surface.solar_power_multiplier
	end

	-- Hidden electric pole: creates the electric network that covers the full
	-- 32×32 floor (supply_area_distance = 16 from the centre tile).  Without
	-- this, the inner accumulator has no network to distribute into.
	local hub_pole = surface.create_entity{
		name        = "mythos-power-hub-pole",
		position    = { DIMENSION_SIZE / 2, DIMENSION_SIZE / 2 },
		force       = force,
		raise_built = false,
	}
	if hub_pole then hub_pole.destructible = false end

	-- Inner power accumulator: joins the hub pole's network and acts as the
	-- battery that the script fills from the outer-surface accumulator.
	local inner_acc = surface.create_entity{
		name        = "mythos-power-link-inner",
		position    = { DIMENSION_SIZE / 2, DIMENSION_SIZE / 2 },
		force       = force,
		raise_built = false,
	}
	if inner_acc then inner_acc.destructible = false end

	return surface, inner_acc
end

return {
	create         = create,
	VIEW_X         = VIEW_X,
	VIEW_Y         = VIEW_Y,
	slotBeltLayout = slotBeltLayout,
}
