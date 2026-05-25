require("prototypes.entity")
require("prototypes.item")
require("prototypes.recipe")

-- Shift+RMB custom input to enter/exit the pocket dimension
data:extend({
  {
    type         = "custom-input",
    name         = "mythos-enter-pocket",
    key_sequence = "SHIFT + mouse-button-2",
  }
})

-- Port-indicator sprite: first frame of yellow-dir.png (north-facing arrow).
-- Used by surface.lua to draw directional arrows at each connection side.
data:extend({
  {
    type     = "sprite",
    name     = "mythos-port-indicator",
    filename = "__mythos__/graphics/indicator/yellow-dir.png",
    width    = 64,
    height   = 64,
    x        = 0,
    y        = 0,
    scale    = 0.5,
  }
})
