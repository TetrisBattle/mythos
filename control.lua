local StorageBootstrap = require("script.bootstrap.storage")
local LoadBootstrap    = require("script.bootstrap.load")
local RuntimeEvents    = require("script.events.init")
local SettingsSync     = require("script.settingsSync")

script.on_init(function()
	StorageBootstrap.init()
	SettingsSync.apply()
end)

script.on_load(LoadBootstrap.onLoad)

script.on_configuration_changed(RuntimeEvents.onConfigurationChanged)

RuntimeEvents.register()
