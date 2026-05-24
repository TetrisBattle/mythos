data:extend({
  {
    type = "container",
    name = "mythos-entity",
    icon = "__mythos__/graphics/icons/mythos.png",
    icon_size = 32,
    flags = {"placeable-neutral", "player-creation", "not-rotatable"},
    minable = {mining_time = 0.5, result = "mythos"},
    max_health = 100,
    collision_box = {{-1.7, -1.7}, {1.7, 1.7}},
    selection_box = {{-2, -2}, {2, 2}},
    picture = {
      filename = "__mythos__/graphics/entities/mythos.png",
      priority = "high",
      width = 64,
      height = 64,
      scale = 2.0,
    },
    inventory_size = 1,
  }
})
