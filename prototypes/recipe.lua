-- Mythos crafting recipe
data:extend({
  {
    type = "recipe",
    name = "mythos",
    enabled = true,
    ingredients = {
      {type = "item", name = "iron-plate", amount = 5},
    },
    results = {
      {type = "item", name = "mythos", amount = 1}
    },
    energy_required = 1,
  }
})
