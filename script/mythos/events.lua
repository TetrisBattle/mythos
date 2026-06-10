local MythosClone     = require("script.clone.init")
local Registry        = require("script.mythos.registry")
local VirtualChest    = require("script.virtual_chest.init")
local Config          = require("script.config")
local util            = require("script.util")

local MythosEvents = {}

local function playConnectSound(surface, position)
	surface.play_sound { path = "entity-close/assembling-machine-3", position = position }
end

local function giveSavedItemToBuffer(buffer, saved_id)
	buffer.remove({ name = "mythos", count = 1 })
	buffer.insert({ name = "mythos-with-contents", count = 1 })
	for i = 1, #buffer do
		local stack = buffer[i]
		if stack.valid_for_read and stack.name == "mythos-with-contents" then
			stack.tags = { saved_id = saved_id }
			break
		end
	end
end

local function dropSavedItem(entity, saved_id)
	local dropped = entity.surface.create_entity {
		name     = "item-on-ground",
		position = entity.position,
		stack    = { name = "mythos-with-contents", count = 1 },
	}
	if dropped and dropped.valid then
		dropped.stack.tags = { saved_id = saved_id }
	end
end

local function primePlayerRestoreCache(event, saved_id)
	if not event.player_index then return end
	storage.pending_player_restore = storage.pending_player_restore or {}
	storage.pending_player_restore[event.player_index] = saved_id
end

local function moveRemovalBufferToInventory(state, buffer)
	if Config.hideVirtualInventory() then
		for i = 1, #buffer do
			buffer[i].clear()
		end
		return
	end

	local force = state.entity.force
	local pos   = state.entity.position
	for i = 1, #buffer do
		local stack = buffer[i]
		if stack.valid_for_read then
			local leftover = VirtualChest.insertStack(force, pos, stack)
			if leftover <= 0 then
				stack.clear()
			else
				stack.count = leftover
			end
		end
	end
end

function MythosEvents.install(Mythos, connectionTypes)

	function Mythos.extractSavedId(event)
		if event.item and event.item.name ~= "mythos-with-contents" then return nil end
		if event.player_index then
			storage.pending_player_restore = storage.pending_player_restore or {}
			local saved_id = storage.pending_player_restore[event.player_index]
			if saved_id then
				storage.pending_player_restore[event.player_index] = nil
				return saved_id
			end
		end

		local stack = event.stack
		if stack and stack.valid then
			local ok, tags = pcall(function() return stack.tags end)
			if ok and tags and tags.saved_id then return tags.saved_id end
		end
	end

	local function initPlacedMythos(entity, event)
		MythosClone.schedulePlacement(Mythos, entity, event)
	end

	local function rejectVirtualChestInDimension(entity, event)
		local surface = entity.surface
		local pos     = entity.position
		local force   = entity.force
		entity.destroy{ raise_destroy = false }
		surface.spill_item_stack{
			position = pos,
			stack    = { name = VirtualChest.PROTOTYPE, count = 1 },
			force    = force,
		}

		if event.player_index then
			local player = game.get_player(event.player_index)
			if player then
				player.print({ "mythos-gui.virtual-chest-dimension-forbidden" })
			end
		end
	end

	local function rejectNestedMythos(entity, event)
		local state = Registry.get(entity.unit_number)
		if state then
			state:destroy()
		end

		local surface = entity.surface
		local pos     = entity.position
		local force   = entity.force
		entity.destroy{ raise_destroy = false }
		surface.spill_item_stack{
			position = pos,
			stack    = { name = "mythos", count = 1 },
			force    = force,
		}

		if event.player_index then
			local player = game.get_player(event.player_index)
			if player then
				player.print({ "mythos.nested-mythos-forbidden" })
			end
		end
	end

	function Mythos.onEntityBuilt(event)
		if MythosClone.isBulkCloning() then return end

		local entity = event.entity
		if not (entity and entity.valid) then return end

		if entity.name == VirtualChest.PROTOTYPE then
			if Config.hideVirtualInventory() then
				entity.destroy{ raise_destroy = false }
				return
			end
			if util.parseDimensionUnitNumber(entity.surface) then
				rejectVirtualChestInDimension(entity, event)
				return
			end
			VirtualChest.onBuilt(entity)
			return
		end

		local unitNum = util.parseDimensionUnitNumber(entity.surface)
		if unitNum then
			if entity.name == "mythos" then
				rejectNestedMythos(entity, event)
				return
			end

			local state = Registry.get(unitNum)
			if state and state.entity.valid and connectionTypes[entity.type] == "belt" then
				local slotKey = state:findInnerSlotAt(entity.position)
				if slotKey then
					if state:connectFromInner(slotKey, entity) then
						playConnectSound(entity.surface, entity.position)
					else
						state:refreshGateRenders()
					end
				end
			end
			return
		end

		if entity.name == "mythos" then
			initPlacedMythos(entity, event)
			return
		end

		if not connectionTypes[entity.type] then return end
		local state, slotKey = Mythos.findStateAndSlot(entity)
		if state then
			if slotKey then
				if state:connect(slotKey, entity) then
					playConnectSound(entity.surface, entity.position)
				end
			end
			state:refreshGateRenders()
			return
		end
	end

	function Mythos.onPrePlayerMinedItem(event)
		local entity = event.entity
		if not (entity and entity.valid and entity.name == VirtualChest.PROTOTYPE) then return end
		VirtualChest.onRemoved(entity)
	end

	function Mythos.onEntityRemoved(event)
		local entity = event.entity
		if not entity then return end

		local unit_number = entity.unit_number
		if unit_number and storage.virtualChests and storage.virtualChests[unit_number] then
			VirtualChest.onRemoved(entity)
			return
		end

		if entity.name == VirtualChest.PROTOTYPE then
			VirtualChest.onRemoved(entity)
			return
		end

		if not entity.valid then return end

		if entity.name == "mythos" then
			local state = Registry.get(entity.unit_number)
			if state then
				if state:hasContents(event.buffer) then
					local saved_id = state:save(event.buffer)
					if event.buffer then
						giveSavedItemToBuffer(event.buffer, saved_id)
						primePlayerRestoreCache(event, saved_id)
					else
						dropSavedItem(entity, saved_id)
					end
				else
					state:destroy()
				end
			end
			return
		end

		local state = Registry.findByInsideSurfaceIndex(entity.surface_index)
		if state then
			if connectionTypes[entity.type] == "belt" then
				local slotKey = state:findInnerSlotAt(entity.position)
				if slotKey then
					state:disconnect(slotKey)
				end
				state:refreshGateRenders()
			end

			if event.buffer then
				moveRemovalBufferToInventory(state, event.buffer)
			end
			return
		end

		if not connectionTypes[entity.type] then return end
		local outsideState, slotKey = Mythos.findStateAndSlot(entity)
		if outsideState then
			if slotKey then
				outsideState:disconnect(slotKey)
			else
				outsideState:disconnectExternalEntity(entity)
			end
			outsideState:refreshGateRenders()
			return
		end
	end

	function Mythos.onCursorChanged(event)
		storage.pending_player_restore = storage.pending_player_restore or {}
		local player = game.get_player(event.player_index)
		if not player then return end
		local stack = player.cursor_stack
		if stack and stack.valid_for_read and stack.name == "mythos-with-contents" then
			local tags = stack.tags
			storage.pending_player_restore[event.player_index] = tags and tags.saved_id
		else
			storage.pending_player_restore[event.player_index] = nil
		end

	end

end

return MythosEvents
