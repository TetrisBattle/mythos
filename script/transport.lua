local Registry     = require("script.mythos.registry")
local VirtualChest = require("script.virtual_chest.init")

local Transport = {}

local function transferHeat(a, b)
	local avg = (a.temperature + b.temperature) * 0.5
	a.temperature = avg
	b.temperature = avg
end

local function transferFluid(a, b)
	local aContents = a.get_fluid_contents()
	local bContents = b.get_fluid_contents()
	local fluids = {}
	for name in pairs(aContents) do fluids[name] = true end
	for name in pairs(bContents) do fluids[name] = true end

	for fluidName in pairs(fluids) do
		local aAmt = aContents[fluidName] or 0
		local bAmt = bContents[fluidName] or 0
		local diff = aAmt - bAmt
		if diff > 0.01 then
			local moved = a.remove_fluid({ name = fluidName, amount = diff * 0.5 })
			if moved > 0 then b.insert_fluid({ name = fluidName, amount = moved }) end
		elseif diff < -0.01 then
			local moved = b.remove_fluid({ name = fluidName, amount = -diff * 0.5 })
			if moved > 0 then a.insert_fluid({ name = fluidName, amount = moved }) end
		end
	end
end

local function transferBeltLines(from, to, fromLineIndexes, toLineIndexes)
	fromLineIndexes = fromLineIndexes or { 1, 2 }
	toLineIndexes = toLineIndexes or { 1, 2 }
	for lane = 1, 2 do
		local fromLine = from.get_transport_line(fromLineIndexes[lane] or lane)
		local toLine   = to.get_transport_line(toLineIndexes[lane] or lane)
		local laneOpen = true
		for _, stack in pairs(fromLine.get_contents()) do
			if not laneOpen then break end
			local single = { name = stack.name, quality = stack.quality, count = 1 }
			for _ = 1, stack.count do
				if not toLine.can_insert_at_back() then
					laneOpen = false
					break
				end
				local taken = fromLine.remove_item(single)
				if taken > 0 then
					if not toLine.insert_at_back(single) then
						fromLine.insert_at_back(single)
						laneOpen = false
						break
					end
				end
			end
		end
	end
end

local function transferConnection(conn)
	if conn.connType == "belt"
			and conn.entity.valid
			and conn.innerBelt
			and conn.innerBelt.valid then
		if conn.ioDirection == "input" then
			transferBeltLines(conn.entity, conn.innerBelt,
				conn.entityLineIndexes, conn.innerBeltLineIndexes)
		else
			transferBeltLines(conn.innerBelt, conn.entity,
				conn.innerBeltLineIndexes, conn.entityLineIndexes)
		end
	elseif conn.connType == "pipe"
			and conn.outerProxy
			and conn.outerProxy.valid
			and conn.innerProxy
			and conn.innerProxy.valid then
		transferFluid(conn.outerProxy, conn.innerProxy)
	elseif conn.connType == "heat-pipe"
			and conn.outerProxy
			and conn.outerProxy.valid
			and conn.innerProxy
			and conn.innerProxy.valid then
		transferHeat(conn.outerProxy, conn.innerProxy)
	end
end

function Transport.install(Mythos)

	function Mythos.onNthTick()
		Registry.forEach(function(state)
			if not state.entity.valid then return end

			for _, slot in pairs(state.slots) do
				if slot.conn then
					transferConnection(slot.conn)
				end
			end

			state:buildGhosts()
		end)
	end

	function Mythos.onSlowTick()
		Registry.forEach(function(state)
			if state.entity.valid then
				state:flushPendingDeletions()
				state:syncElectricity()
			end
		end)

		VirtualChest.tickSlow()
	end

end

return Transport
