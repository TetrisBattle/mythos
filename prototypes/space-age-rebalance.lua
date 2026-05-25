-- this file rebalances the mythos tech tree for space age

if not mods["space-age"] then return end
if mods["space-is-fake"] then return end
if settings.startup["mythos-cheap-research"].value then return end

data.raw.technology["mythos-recursion-t2"].unit = {
    count = 5000,
    ingredients = {
        {"automation-science-pack",  1},
        {"logistic-science-pack",    1},
        {"chemical-science-pack",    1},
        {"space-science-pack",       1},
        {"production-science-pack",  1},
        {"utility-science-pack",     1},
        {"metallurgic-science-pack", 1},
    },
    time = 60
}
data.raw.technology["mythos-recursion-t2"].prerequisites = {
    "production-science-pack",
    "mythos-recursion-t1",
}

data.raw.technology["mythos-connection-type-heat"].unit = {
    count = 5000,
    ingredients = {
        {"automation-science-pack",      1},
        {"logistic-science-pack",        1},
        {"chemical-science-pack",        1},
        {"space-science-pack",           1},
        {"production-science-pack",      1},
        {"utility-science-pack",         1},
        {"metallurgic-science-pack",     1},
        {"agricultural-science-pack",    1},
        {"electromagnetic-science-pack", 1},
        {"cryogenic-science-pack",       1},
    },
    time = 60
}
data.raw.technology["mythos-connection-type-heat"].prerequisites = {
    "mythos-architecture-t1",
    "cryogenic-science-pack",
}

data.raw.technology["mythos-connection-type-chest"].unit = {
    count = 1000,
    ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
        {"chemical-science-pack",   1},
    },
    time = 45
}
data.raw.technology["mythos-connection-type-chest"].prerequisites = {
    "mythos-architecture-t1",
    "logistic-system"
}

data.raw.technology["mythos-connection-type-circuit"].unit = {
    count = 200,
    ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
    },
    time = 30
}
data.raw.technology["mythos-connection-type-circuit"].prerequisites = {
    "mythos-architecture-t1",
    "circuit-network"
}

data.raw.technology["mythos-recursion-t1"].unit = {
    count = 2000,
    ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
        {"chemical-science-pack",   1},
        {"space-science-pack",      1},
    },
    time = 45
}
data.raw.technology["mythos-recursion-t1"].prerequisites = {
    "mythos-architecture-t1",
}

data.raw.technology["mythos-interior-upgrade-display"].unit = {
    count = 200,
    ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
    },
    time = 30
}
data.raw.technology["mythos-interior-upgrade-display"].prerequisites = {
    "mythos-interior-upgrade-lights",
    "logistic-science-pack"
}

data.raw.technology["mythos-interior-upgrade-roboport"].unit = {
    count = 1000,
    ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack",   1},
        {"chemical-science-pack",   1},
    },
    time = 45
}

data.raw.technology["mythos-upgrade-greenhouse"].prerequisites = {
    "mythos-architecture-t1",
    "electromagnetic-science-pack",
    "overgrowth-soil",
    "mythos-interior-upgrade-lights",
}
data.raw.technology["mythos-upgrade-greenhouse"].unit = {
    count = 2000,
    ingredients = {
        {"automation-science-pack",      1},
        {"logistic-science-pack",        1},
        {"chemical-science-pack",        1},
        {"space-science-pack",           1},
        {"production-science-pack",      1},
        {"utility-science-pack",         1},
        {"agricultural-science-pack",    1},
        {"electromagnetic-science-pack", 1},
    },
    time = 60
}

data.raw["storage-tank"]["mythos-1"].surface_conditions = {{
    property = "gravity",
    min = 0.1
}}
data.raw["electric-pole"]["mythos-circuit-connector"].surface_conditions = {{
    property = "gravity",
    min = 0.1
}}