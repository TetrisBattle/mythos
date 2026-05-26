local tile_graphics = require("__base__/prototypes/tile/tile-graphics")
local tile_spritesheet_layout = tile_graphics.tile_spritesheet_layout

local tile_trigger_effects = require("__base__.prototypes.tile.tile-trigger-effects")
local sounds = require("__base__.prototypes.entity.sounds")

local concrete_vehicle_speed_modifier = data.raw["tile"]["concrete"].vehicle_friction_modifier
local concrete_driving_sound = table.deepcopy(data.raw["tile"]["concrete"].driving_sound)
local concrete_tile_build_sounds = table.deepcopy(data.raw["tile"]["concrete"].build_sound)

local F = "__mythos__"

data:extend {{
    type = "item-subgroup",
    name = "mythos-tiles",
    order = "q",
    group = "tiles"
}}

local function tile_transitions(tile_variants)
    tile_variants.transition = {
        transition_group = out_of_map_transition_group_id,

        background_layer_offset = 1,
        background_layer_group = "zero",
        offset_background_layer_by_tile_layer = true,

        spritesheet = "__mythos__/graphics/tile/out-of-map-transition.png",
        layout = tile_spritesheet_layout.transition_4_4_8_1_1,
        overlay_enabled = false
    }
    return tile_variants
end

local function make_tile(tinfo)
    local freezable = not not (feature_flags.freezing and data.raw.tile["frozen-concrete"])

    if freezable then
        local frozen_concrete = table.deepcopy(data.raw.tile["frozen-concrete"])
        frozen_concrete.name = tinfo.name .. "-frozen"
        frozen_concrete.map_color = tinfo.map_color or {r = 1}
        frozen_concrete.thawed_variant = tinfo.name
        frozen_concrete.collision_mask = tinfo.collision_mask
        frozen_concrete.walking_speed_modifier = 1.4
        frozen_concrete.vehicle_friction_modifier = concrete_vehicle_speed_modifier
        frozen_concrete.driving_sound = concrete_driving_sound
        frozen_concrete.mined_sound = sounds.deconstruct_bricks(0.8)
        frozen_concrete.layer_group = "ground-artificial"
        frozen_concrete.layer = (tinfo.layer or 50) - 1
        frozen_concrete.localised_name = {"tile-name." .. tinfo.name}
        frozen_concrete.variants = tile_transitions(frozen_concrete.variants)
        frozen_concrete.tint = tinfo.frozen_tint
        data:extend {frozen_concrete}
    end

    data:extend {{
        type = "tile",
        subgroup = "mythos-tiles",
        name = tinfo.name,
        localised_name = tinfo.localised_name,
        needs_correction = false,
        collision_mask = tinfo.collision_mask,
        variants = tinfo.variants or tile_transitions {
            main = tinfo.pictures
        },
        layer = tinfo.layer or 50,
        walking_speed_modifier = 1.4,
        layer_group = "ground-artificial",
        mined_sound = sounds.deconstruct_bricks(0.8),
        driving_sound = concrete_driving_sound,
        build_sound = concrete_tile_build_sounds,
        scorch_mark_color = {r = 0.373, g = 0.307, b = 0.243, a = 1.000},
        vehicle_friction_modifier = concrete_vehicle_speed_modifier,
        trigger_effect = tile_trigger_effects.concrete_trigger_effect(),
        map_color = tinfo.map_color or {r = 1},
        frozen_variant = freezable and (tinfo.name .. "-frozen") or nil,
    }}

    if tinfo.growable then
        for _, overgrowth_tile in pairs {"overgrowth-yumako-soil", "overgrowth-jellynut-soil"} do
            local tile_item = data.raw.item[overgrowth_tile]
            if not tile_item then goto continue end
            if not tile_item.place_as_tile or not tile_item.place_as_tile.tile_condition then goto continue end
            table.insert(tile_item.place_as_tile.tile_condition, tinfo.name)
            ::continue::
        end
    end
end

local function wall_mask()
    return {
        layers = {
            ground_tile = true,
            water_tile = true,
            resource = true,
            floor = true,
            item = true,
            object = true,
            player = true,
            doodad = true,
        }
    }
end

local function edge_mask()
    return {
        layers = {
            ground_tile = true,
            water_tile = true,
            resource = true,
            floor = true,
            item = true,
            object = true,
            doodad = true,
        }
    }
end

local function floor_mask()
    return {
        layers = {
            ground_tile = true,
        }
    }
end

local function pictures_mythos_floor_tile()
    return {
        {
            picture = F .. "/graphics/tile/mythos-floor-1.png",
            count = 16,
            size = 1
        },
        {
            picture = F .. "/graphics/tile/mythos-floor-2.png",
            count = 4,
            size = 2,
            probability = 0.39
        },
        {
            picture = F .. "/graphics/tile/mythos-floor-4.png",
            count = 4,
            size = 4,
            probability = 1
        },
    }
end

local function pictures_mythos_wall_tile(i, space)
    local space = space and "space-" or ""
    return {
        {
            picture = F .. "/graphics/tile/" .. space .. "mythos-wall-" .. i .. ".png",
            count = 16,
            size = 1
        },
    }
end

local function floor_color() return {r = 130, g = 110, b = 100} end
local function mythos_1_wall_color() return {r = 190, g = 125, b = 80} end
local function mythos_2_wall_color() return {r = 80, g = 140, b = 200} end
local function mythos_3_wall_color() return {r = 190, g = 190, b = 80} end

make_tile {
    name = "mythos-entrance",
    collision_mask = edge_mask(),
    layer = 30,
    pictures = pictures_mythos_floor_tile(),
    map_color = floor_color(),
}

make_tile {
    name = "mythos-floor",
    collision_mask = floor_mask(),
    layer = 30,
    pictures = pictures_mythos_floor_tile(),
    map_color = floor_color(),
    growable = true,
}

-- Mythos 1

make_tile {
    name = "mythos-wall-1",
    collision_mask = edge_mask(),
    layer = 70,
    pictures = pictures_mythos_wall_tile(1),
    map_color = mythos_1_wall_color(),
    frozen_tint = {1, 0.85, 0.85},
    localised_name = {"tile-name.mythos-wall"},
}

make_tile {
    name = "mythos-pattern-1",
    collision_mask = floor_mask(),
    layer = 70,
    pictures = pictures_mythos_wall_tile(1),
    map_color = mythos_1_wall_color(),
    frozen_tint = {1, 0.85, 0.85},
    growable = true,
    localised_name = {"tile-name.mythos-floor"},
}

-- Mythos 2

make_tile {
    name = "mythos-wall-2",
    collision_mask = edge_mask(),
    layer = 70,
    pictures = pictures_mythos_wall_tile(2),
    map_color = mythos_2_wall_color(),
    frozen_tint = {0.85, 0.85, 1},
    localised_name = {"tile-name.mythos-wall"},
}

make_tile {
    name = "mythos-pattern-2",
    collision_mask = floor_mask(),
    layer = 70,
    pictures = pictures_mythos_wall_tile(2),
    map_color = mythos_2_wall_color(),
    frozen_tint = {0.85, 0.85, 1},
    growable = true,
    localised_name = {"tile-name.mythos-floor"},
}

-- Mythos 3

make_tile {
    name = "mythos-wall-3",
    collision_mask = edge_mask(),
    layer = 70,
    pictures = pictures_mythos_wall_tile(3),
    map_color = mythos_3_wall_color(),
    frozen_tint = {1, 1, 0.7},
    localised_name = {"tile-name.mythos-wall"},
}

make_tile {
    name = "mythos-pattern-3",
    collision_mask = floor_mask(),
    layer = 70,
    pictures = pictures_mythos_wall_tile(3),
    map_color = mythos_3_wall_color(),
    frozen_tint = {1, 1, 0.7},
    growable = true,
    localised_name = {"tile-name.mythos-floor"},
}

if feature_flags.expansion_shaders then
    data:extend {{
        type = "tile-effect",
        name = "mythos-out-of-map",
        shader = "space",
        space = {
            star_scale = 0,
            nebula_saturation = 1,
        }
    }}

    data.raw.tile["out-of-map"].effect = "mythos-out-of-map"
    data.raw.tile["out-of-map"].effect_color = {0.5, 0.507, 0}
    data.raw.tile["out-of-map"].effect_color_secondary = {0, 68, 25}
end
