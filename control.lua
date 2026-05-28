local registerEvents = require("script.registerEvents")
local Mythos = require("script.Mythos")

script.on_init(function()
	storage.mythoi = {}
end)

script.on_load(function()
	-- Metatables are not saved; restore them so methods work after a load.
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
end)

registerEvents(Mythos.onEntityBuilt, Mythos.onEntityRemoved)
