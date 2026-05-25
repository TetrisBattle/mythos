if not mods["pyalienlife"] then return end
if not mods["pyhightech"] then return end

data.raw.technology["mythos-connection-type-circuit"].prerequisites = {
    "mythos-architecture-t1",
    "advanced-combinators",
}
data.raw.technology["mythos-connection-type-circuit"].unit.ingredients = {
    {"py-science-pack-1", 1},
}

data.raw.technology["mythos-architecture-t2"].unit.ingredients = {
    {"py-science-pack-1", 1},
}

data.raw.technology["mythos-interior-upgrade-display"].prerequisites = {
    "mythos-architecture-t1"
}
data.raw.technology["mythos-interior-upgrade-display"].unit.ingredients = {
    {"automation-science-pack", 1},
}

table.insert(
    data.raw.technology["mythos-connection-type-heat"].prerequisites,
    "uranium-processing"
)
data.raw.technology["mythos-connection-type-heat"].unit.ingredients = {
    {"chemical-science-pack", 1},
}

data.raw.technology["mythos-connection-type-chest"].unit.ingredients = {
    {"py-science-pack-2", 1},
}

data.raw.recipe["mythos-1"].ingredients = {
    {type = "item", name = "concrete",     amount = 500},
    {type = "item", name = "steel-plate",  amount = 100},
    {type = "item", name = "tinned-cable", amount = 100},
    {type = "item", name = "treated-wood", amount = 100}
}
