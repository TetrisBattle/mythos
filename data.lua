require "lib.lib"

require "prototypes.space-location"
require "prototypes.tile"
require "prototypes.factory"
require "prototypes.component"
require "prototypes.utility"
require "prototypes.recipe"

data:extend {
    {
        type = "item-subgroup",
        name = "mythos-factories",
        group = "logistics",
        order = "e-e"
    },
    {
        type = "custom-input",
        name = "factory-rotate",
        key_sequence = "R",
        controller_key_sequence = "controller-rightstick"
    },
    {
        type = "custom-input",
        name = "factory-open-outside-surface-to-remote-view",
        key_sequence = "SHIFT + mouse-button-2",
        controller_key_sequence = "controller-leftstick"
    },
    {
        type = "custom-event",
        name = "on_script_setup_blueprint"
    },
}
