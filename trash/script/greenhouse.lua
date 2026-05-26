function mythos.build_greenhouse_upgrade(mythos)
    local force = mythos.force
    if not force.valid then return end
    if not mythos.inside_surface.valid or not mythos.outside_surface.valid then return end

    local has_tech = true
    if not has_tech then
        mythos.inside_surface.set_property("solar-power", 0)
        return
    end

    local parent_planet_name = mythos.outside_surface.name:gsub("%-mythos%-floor$", "")
    local parent_planet = game.planets[parent_planet_name]
    if not parent_planet then return end
    local parent_solar_power = parent_planet.surface.get_property("solar-power") or 1
    mythos.inside_surface.set_property("solar-power", parent_solar_power / 2)
end
