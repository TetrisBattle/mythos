require "prototypes.mythos"
require "prototypes.component"
require "prototypes.utility"
require "prototypes.recipe"
require "prototypes.tile"
require "prototypes.borehole-pump"
require "prototypes.roboport"
require "prototypes.greenhouse"
require "prototypes.space-age-rebalance"
require "compat.power-grid-comb"

data:extend {
    {
        type = "item-subgroup",
        name = "mythos",
        group = "logistics",
        order = "e-e"
    },
    {
        type = "custom-input",
        name = "mythos-rotate",
        key_sequence = "R",
        controller_key_sequence = "controller-rightstick"
    },
    {
        type = "custom-input",
        name = "mythos-increase",
        key_sequence = "SHIFT + R",
        controller_key_sequence = "controller-dpright"
    },
    {
        type = "custom-input",
        name = "mythos-decrease",
        key_sequence = "CONTROL + R",
        controller_key_sequence = "controller-dpleft"
    },
    {
        type = "custom-input",
        name = "mythos-open-outside-surface-to-remote-view",
        key_sequence = "SHIFT + mouse-button-2",
        controller_key_sequence = "controller-leftstick"
    },
    {
        type = "custom-event",
        name = "on_script_setup_blueprint"
    },
}
