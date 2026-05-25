data:extend {
    -- Mythos buildings
    {
        type = "recipe",
        name = "mythos-1",
        enabled = false,
        energy_required = 30,
        ingredients = {
            {type = "item", name = "stone",        amount = 500},
            {type = "item", name = "iron-plate",   amount = 500},
            {type = "item", name = "copper-plate", amount = 200}
        },
        results = {{type = "item", name = "mythos-1", amount = 1}},
        main_product = "mythos-1",
        localised_name = {"entity-name.mythos-1"},
        category = data.raw["recipe-category"]["metallurgy-or-assembling"] and "metallurgy-or-assembling" or nil
    },
    -- Utilities
    {
        type = "recipe",
        name = "mythos-circuit-connector",
        enabled = false,
        energy_required = 1,
        ingredients = {
            {type = "item", name = "electronic-circuit", amount = 2},
            {type = "item", name = "copper-cable",       amount = 5}
        },
        results = {{type = "item", name = "mythos-circuit-connector", amount = 1}},
    }
}

-- small vanilla change to allow factories to be crafted at the start of the game
if data.raw["recipe-category"]["metallurgy-or-assembling"] then
    table.insert(data.raw["assembling-machine"]["assembling-machine-1"].crafting_categories or {}, "metallurgy-or-assembling")
end
