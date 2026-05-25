local function spawn_radiative_tower(surface, x, y)
    local e = surface.create_entity {
        name = "cerys-fulgoran-radiative-tower-contracted-container",
        position = {x, y},
        force = "neutral",
    }

    if not e or not e.valid then return end

    e.minable_flag = false
    e.destructible = false

    local inv = e.get_inventory(defines.inventory.chest)
    if inv and inv.valid then
        inv.insert {name = "iron-stick", count = 1}
    end
end

local DEFAULT_CERYS_TOWER_POSITIONS = {
    {-10, 10},
    {10,  10},
    {10,  -10},
    {-10, -10},
}

mythos.spawn_cerys_entities = function(mythos)
    if not script.active_mods["Cerys-Moon-of-Fulgora"] then return end

    local surface = mythos.inside_surface
    if surface.name ~= "cerys-mythos-floor" then return end
    local x, y = mythos.inside_x, mythos.inside_y

    for _, tower_position in pairs(mythos.layout.cerys_radiative_towers or DEFAULT_CERYS_TOWER_POSITIONS) do
        spawn_radiative_tower(surface, x + tower_position[1], y + tower_position[2])
    end
end
