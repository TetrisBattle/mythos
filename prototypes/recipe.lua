data:extend {
    {
        type = "recipe",
        name = "factory-1",
        enabled = true,
        energy_required = 30,
        ingredients = {
            {type = "item", name = "stone",        amount = 500},
            {type = "item", name = "iron-plate",   amount = 500},
            {type = "item", name = "copper-plate", amount = 200}
        },
        results = {{type = "item", name = "factory-1", amount = 1}},
        main_product = "factory-1",
        localised_name = {"entity-name.factory-1"},
    },
    {
        type = "recipe",
        name = "factory-circuit-connector",
        enabled = true,
        energy_required = 1,
        ingredients = {
            {type = "item", name = "electronic-circuit", amount = 2},
            {type = "item", name = "copper-cable",       amount = 5}
        },
        results = {{type = "item", name = "factory-circuit-connector", amount = 1}},
    }
}
