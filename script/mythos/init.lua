local Mythos            = require("script.mythos.state")
local connectionTypes   = require("script.mythos.connection_types")
local Connections       = require("script.mythos.connections")
local Logistics         = require("script.mythos.logistics")
local DimensionDeletion = require("script.mythos.deletion")
local Electricity       = require("script.power.sync")
local DimensionResize   = require("script.mythos.resize")
local Transport         = require("script.transport")
local Icons             = require("script.mythos.icons")
local MythosEvents      = require("script.mythos.events")
local MythosClone       = require("script.clone.init")

-- Each module adds its methods directly onto the Mythos prototype.
Connections.install(Mythos, connectionTypes)
Logistics.install(Mythos)
DimensionDeletion.install(Mythos, connectionTypes)
Electricity.install(Mythos)
DimensionResize.install(Mythos)
Transport.install(Mythos)
Icons.install(Mythos)
MythosEvents.install(Mythos, connectionTypes)
MythosClone.install(Mythos)

return Mythos
