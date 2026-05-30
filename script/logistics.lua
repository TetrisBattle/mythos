-- ── Logistics System ──────────────────────────────────────────────────────────
-- Manages auto-building of ghost entities and logistic requests for a
-- pocket dimension.
--
--   buildGhosts()    – consumes items from the mythos chest to revive ghosts  (6-tick)
--   updateRequests() – syncs the chest's logistic section to match ghost needs (60-tick)

local Logistics = {}

function Logistics.install(Mythos)

	-- Tries to revive every ghost in the pocket dimension by consuming items
	-- from the mythos chest inventory.  Ghosts that cannot be revived (e.g.,
	-- blocked by a collision) return their items and are skipped.
	function Mythos:buildGhosts()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

		local ghosts = self.inside_surface.find_entities_filtered{ type = "entity-ghost" }
		if #ghosts == 0 then return end

		local inv = self.entity.get_inventory(defines.inventory.chest)
		if not inv then return end

		for _, ghost in pairs(ghosts) do
			if not ghost.valid then goto continue end

			local proto  = ghost.ghost_prototype
			local stacks = proto and proto.items_to_place_this
			local stack  = stacks and stacks[1]

			if stack then
				-- Only revive if we have the required item in stock.
				if inv.get_item_count(stack.name) < stack.count then goto continue end
				inv.remove({ name = stack.name, count = stack.count })
				if ghost.revive{ raise_revive = true } == nil then
					-- Revive failed (collision, etc.); return the consumed items.
					inv.insert({ name = stack.name, count = stack.count })
				end
			else
				-- Entities with no place-item (e.g., decoratives) are free to revive.
				ghost.revive{ raise_revive = true }
			end

			::continue::
		end
	end

	-- Scans all ghost entities in the pocket dimension and updates the mythos
	-- chest's logistic section so the network delivers exactly the items needed.
	-- Items already in the chest that are no longer needed are marked as trash
	-- (max = 0), returning them to the logistic network automatically.
	function Mythos:updateRequests()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

		-- Count how many of each item the pending ghosts require.
		local needed = {}
		for _, ghost in pairs(self.inside_surface.find_entities_filtered{ type = "entity-ghost" }) do
			if ghost.valid then
				local proto  = ghost.ghost_prototype
				local stacks = proto and proto.items_to_place_this
				local stack  = stacks and stacks[1]
				if stack then
					needed[stack.name] = (needed[stack.name] or 0) + stack.count
				end
			end
		end

		-- Retrieve (or create) the first logistic section on the chest.
		local sections = self.entity.get_logistic_sections()
		if not sections then return end
		local section = sections.get_section(1) or sections.add_section()
		if not section then return end

		local filters = {}

		-- Request exactly the needed amount.
		-- Setting min = max causes any excess to be returned to the network.
		for itemName, count in pairs(needed) do
			filters[#filters + 1] = {
				value = { type = "item", name = itemName, quality = "normal" },
				min   = count,
				max   = count,
			}
		end

		-- Trash items in the chest that are no longer required by any ghost.
		local inv = self.entity.get_inventory(defines.inventory.chest)
		if inv then
			local trashed = {}
			for i = 1, #inv do
				local slot = inv[i]
				if slot.valid_for_read and not needed[slot.name] and not trashed[slot.name] then
					trashed[slot.name] = true
					filters[#filters + 1] = {
						value = { type = "item", name = slot.name, quality = "normal" },
						min   = 0,
						max   = 0,
					}
				end
			end
		end

		section.filters = filters
	end

end

return Logistics
