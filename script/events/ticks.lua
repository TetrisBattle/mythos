local Mythos        = require("script.mythos.init")
local Registry      = require("script.mythos.registry")
local Maintenance   = require("script.migrations.init")
local RemoteView    = require("script.ui.remote_view")
local SettingsSync  = require("script.settingsSync")
local LoadBootstrap = require("script.bootstrap.load")

local Ticks = {}

function Ticks.onFastTick()
	Mythos.onNthTick()
end

function Ticks.onSlowTick()
	Mythos.onSlowTick()
end

function Ticks.onSolarSync()
	Registry.forEach(function(state)
		if state.entity.valid then
			state:syncSolar()
		end
	end)
end

function Ticks.onTick()
	if LoadBootstrap.consumePendingRefresh() then
		Maintenance.refreshAfterLoad()
		SettingsSync.apply()
	end
	Mythos.processDeferredClones()
	RemoteView.openPendingResizeGuis()
end

return Ticks
