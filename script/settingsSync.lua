local Config       = require("script.config")
local VirtualChest = require("script.virtual_chest.init")

local SettingsSync = {}

local function setRecipeEnabled(force, name, enabled)
	local recipe = force.recipes[name]
	if recipe and recipe.valid then
		recipe.enabled = enabled
	end
end

local function syncRecipes()
	local no_cost = Config.noCost()
	local hide_inv = Config.hideVirtualInventory()

	for _, force in pairs(game.forces) do
		if force.valid then

			setRecipeEnabled(force, "mythos", not no_cost)
			setRecipeEnabled(force, "mythos-free", no_cost)

			setRecipeEnabled(force, "virtual-chest", not hide_inv and not no_cost)
			setRecipeEnabled(force, "virtual-chest-free", not hide_inv and no_cost)
		end
	end
end

function SettingsSync.apply()
	syncRecipes()
	if Config.hideVirtualInventory() then
		VirtualChest.purgeAll()
	else
		VirtualChest.bootstrapExisting()
	end
end

function SettingsSync.onRuntimeModSettingChanged(event)
	if event.setting ~= "mythos-no-cost"
			and event.setting ~= "mythos-no-virtual-inventory" then
		return
	end
	SettingsSync.apply()
end

return SettingsSync
