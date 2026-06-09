data:extend({
	{
		type                  = "bool-setting",
		name                  = "mythos-no-cost",
		setting_type          = "runtime-global",
		default_value         = false,
		order                 = "a[mythos-no-cost]",
		localised_name        = { "mod-setting-name.mythos-no-cost" },
		localised_description = { "mod-setting-description.mythos-no-cost" },
	},
	{
		type                  = "bool-setting",
		name                  = "mythos-no-virtual-inventory",
		setting_type          = "runtime-global",
		default_value         = false,
		order                 = "b[mythos-no-virtual-inventory]",
		localised_name        = { "mod-setting-name.mythos-no-virtual-inventory" },
		localised_description = { "mod-setting-description.mythos-no-virtual-inventory" },
	},
})
