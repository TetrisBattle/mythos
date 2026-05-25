if mods["space-age"] then
    data:extend {{
        type = "bool-setting",
        name = "mythos-cheap-research",
        setting_type = "startup",
        default_value = false,
        order = "a-c",
    }}
end

data:extend {
    -- Startup
    {
        type = "bool-setting",
        name = "mythos-disable-new-tile-effects",
        setting_type = "startup",
        default_value = false,
        order = "a-b",
    },
    -- Global
    {
        type = "bool-setting",
        name = "mythos-free-recursion",
        setting_type = "runtime-global",
        default_value = false,
        order = "a-a",
    },
    {
        type = "bool-setting",
        name = "mythos-hide-recursion",
        setting_type = "runtime-global",
        default_value = false,
        order = "a-b",
    },
    {
        type = "bool-setting",
        name = "mythos-hide-recursion-2",
        setting_type = "runtime-global",
        default_value = false,
        order = "a-b-a",
    },
    {
        type = "string-setting",
        name = "mythos-mythos-preview-mode",
        setting_type = "runtime-per-user",
        default_value = "fancy",
        allowed_values = {"fancy", "subtle", "off"},
        order = "a-c",
    },
}
