-- Personal roboport travel surface: a tiny void used as a waypoint when teleporting players between surfaces.
data:extend {{
    type = "planet",
    name = "factory-travel-surface",
    localised_name = "",
    hidden = true,
    icon = "__base__/graphics/icons/space-science-pack.png",
    icon_size = 64,
    gravity_pull = 0,
    distance = 0,
    orientation = 0,
    map_gen_settings = {
        height = 1,
        width = 1,
        property_expression_names = {},
        autoplace_settings = {
            ["decorative"] = {treat_missing_as_default = false, settings = {}},
            ["entity"] = {treat_missing_as_default = false, settings = {}},
            ["tile"] = {treat_missing_as_default = false, settings = {}},
        }
    },
}}
