local Mythos = require("script.mythos.init")

local LoadBootstrap = {}

local pending_gate_refresh = false

function LoadBootstrap.onLoad()
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
	pending_gate_refresh = true
end

function LoadBootstrap.consumePendingRefresh()
	if not pending_gate_refresh then return false end
	pending_gate_refresh = false
	return true
end

return LoadBootstrap
