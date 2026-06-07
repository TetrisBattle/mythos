local Registry = {}

function Registry.all()
	storage.mythoi = storage.mythoi or {}
	return storage.mythoi
end

function Registry.get(unitNumber)
	return Registry.all()[unitNumber]
end

function Registry.set(unitNumber, state)
	Registry.all()[unitNumber] = state
end

function Registry.remove(unitNumber)
	Registry.all()[unitNumber] = nil
end

function Registry.forEach(callback)
	for unitNumber, state in pairs(Registry.all()) do
		callback(state, unitNumber)
	end
end

function Registry.findByInsideSurfaceIndex(surfaceIndex)
	for _, state in pairs(Registry.all()) do
		if state.inside_surface
				and state.inside_surface.valid
				and state.inside_surface.index == surfaceIndex
				and state.entity
				and state.entity.valid then
			return state
		end
	end
end

return Registry
