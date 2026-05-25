-- Mythos item prototype
data:extend({
  {
    type = "item-with-tags",
    name = "mythos",
    icons = {
      {icon = "__mythos__/graphics/entities/factory-1.png", icon_size = 64},
      {icon = "__mythos__/graphics/icons/mythos.png",       icon_size = 32, scale = 0.5, shift = {10, 10}},
    },
    stack_size = 1,
    place_result = "mythos-entity",
  }
})
