data:extend({
  {
    type = "container",
    name = "mythos-entity",
    icons = {
      {icon = "__mythos__/graphics/entities/factory-1.png", icon_size = 64},
      {icon = "__mythos__/graphics/icons/mythos.png",       icon_size = 32, scale = 0.5, shift = {10, 10}},
    },
    flags = {"placeable-neutral", "player-creation", "not-rotatable"},
    minable = {mining_time = 0.5, result = "mythos"},
    max_health = 100,
    collision_box = {{-1.7, -1.7}, {1.7, 1.7}},
    selection_box = {{-2, -2}, {2, 2}},
    picture = {
      layers = {
        {
          filename = "__mythos__/graphics/entities/factory-1-shadow.png",
          width    = 832,
          height   = 640,
          scale    = 0.25,
          shift    = {0.75, 0},
          draw_as_shadow = true,
        },
        {
          filename = "__mythos__/graphics/entities/factory-1.png",
          width    = 832,
          height   = 640,
          scale    = 0.25,
          shift    = {0.75, 0},
        },
      },
    },
    inventory_size = 1,
  }
})
