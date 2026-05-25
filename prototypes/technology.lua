local F = "__mythos__"
local pf = "p-q-"

local starting_planet = "nauvis"
if mods["any-planet-start"] then
    starting_planet = settings.startup["aps-planet"].value
    if starting_planet == "none" then starting_planet = "nauvis" end
elseif mods["pystellarexpedition"] then
    starting_planet = "frans-orbit"
end

local effects = {
    {
        type = "unlock-recipe",
        recipe = "mythos-1"
    }
}

if not mods["solarsystemplusplus"] then
    effects[#effects + 1] = {
        type = "unlock-space-location",
        space_location = starting_planet .. "-mythos-floor",
        use_icon_overlay_constant = false,
    }
end

-- Mythos buildings

data:extend {{
    type = "technology",
    name = "mythos-architecture-t1",
    icon = F .. "/graphics/technology/mythos-architecture-1.png",
    icon_size = 256,
    prerequisites = {"stone-wall", "logistics"},
    effects = effects,
    unit = {
        count = 200,
        ingredients = {{"automation-science-pack", 1}},
        time = 30
    },
    order = pf .. "a-a",
}}
-- Connection types

-- Connection types

data:extend {{
    type = "technology",
    name = "mythos-connection-type-fluid",
    icon = F .. "/graphics/technology/mythos-connection-type-fluid.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1"}, -- 'fluid-handling'
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 100,
        ingredients = {{"automation-science-pack", 1}},
        time = 30
    },
    order = pf .. "c-a",
}}
data:extend {{
    type = "technology",
    name = "mythos-connection-type-chest",
    icon = F .. "/graphics/technology/mythos-connection-type-chest.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1", "logistics-2"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 200,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
        time = 30
    },
    order = pf .. "c-b",
}}
data:extend {{
    type = "technology",
    name = "mythos-connection-type-circuit",
    icon = F .. "/graphics/technology/mythos-connection-type-circuit.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1", "circuit-network", "logistic-science-pack"},
    effects = {{type = "unlock-recipe", recipe = "mythos-circuit-connector"}},
    unit = {
        count = 300,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
        time = 30
    },
    order = pf .. "c-c",
}}
data:extend {{
    type = "technology",
    name = "mythos-connection-type-heat",
    icon = F .. "/graphics/technology/mythos-connection-type-heat.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 600,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
        time = 45
    },
    order = pf .. "c-d",
}}

-- Utility upgrades

data:extend {{
    type = "technology",
    name = "mythos-interior-upgrade-lights",
    icon = F .. "/graphics/technology/mythos-interior-upgrade-lights.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1", "lamp"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 50,
        ingredients = {{"automation-science-pack", 1}},
        time = 30
    },
    order = pf .. "d-a",
}}
data:extend {{
    type = "technology",
    name = "mythos-interior-upgrade-display",
    icon = F .. "/graphics/technology/mythos-interior-upgrade-display.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1", "lamp"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 100,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
        time = 30
    },
    order = pf .. "d-b",
}}
data:extend {{
    type = "technology",
    name = "mythos-interior-upgrade-roboport",
    icon = F .. "/graphics/technology/mythos-interior-upgrade-roboport.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1", "construction-robotics"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 1000,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}},
        time = 45
    },
    order = pf .. "d-d",
}}
-- Recursion!
data:extend {{
    type = "technology",
    name = "mythos-recursion-t1",
    icon = F .. "/graphics/technology/mythos-recursion-1.png",
    icon_size = 256,
    prerequisites = {"mythos-architecture-t1", "logistics-2"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 2000,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}},
        time = 60
    },
    order = pf .. "b-a",
}}
data:extend {{
    type = "technology",
    name = "mythos-recursion-t2",
    icon = F .. "/graphics/technology/mythos-recursion-2.png",
    icon_size = 256,
    prerequisites = {"mythos-recursion-t1"},
    effects = {{
        type = "nothing",
        effect_description = ""
    }},
    unit = {
        count = 5000,
        ingredients = {{"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1}, {"production-science-pack", 1}},
        time = 60
    },
    order = pf .. "b-b",
}}
