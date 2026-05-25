data:extend {{
    type = "sprite",
    name = "mythos-floor-space",
    filename = "__mythos__/graphics/icon/mythos-floor-space.png",
    width = 64,
    height = 64,
    scale = 1,
    flags = {"gui-icon"},
}}

local function generate_mythos_floor_planet_icons(planet)
    if not planet.icons and not planet.icon then
        error("Planet " .. planet.name .. " has no icon or icons")
    end

    local icons = table.deepcopy(planet.icons or {})
    if planet.icon then
        table.insert(icons, {icon = planet.icon, icon_size = planet.icon_size or 64})
    end

    -- shift all planet icons to the top left corner
    for _, icon in pairs(icons) do
        local old_shift = icon.shift or {0, 0}
        local x = old_shift.x or old_shift[1] or 0
        local y = old_shift.y or old_shift[2] or 0

        icon.icon_size = icon.icon_size or planet.icon_size or 64
        icon.scale = 64 / (icon.icon_size or 64) or 1
        icon.scale = (icon.scale or 1) * 0.75
        icon.shift = {x - 4, y - 4}
    end

    -- add a mythos icon to the bottom right corner
    table.insert(icons, {
        icon = "__mythos__/graphics/icon/mythos-subicon.png",
        icon_size = 64,
        scale = 1
    })

    return icons
end

local function fog_color(planet)
    if planet == "nauvis" then return {0.3, 0.3, 0.3}, {0.3, 0.3, 0.3} end
    if planet == "gleba" then return {1, 1, 0.3}, {1, 0, 1} end
    if planet == "vulcanus" then return {1.0, 0.8706, 0.302}, {1.0, 0.8706, 0.2902} end
    if planet == "fulgora" then return {0, 0, 0.6}, {0.6, 0.1, 0.6} end
    if planet == "aquilo" then return {0.9, 0.9, 0.9}, {0.6, 0.6, 1} end

    return {0.3, 0.3, 0.3}, {0.3, 0.3, 0.3}
end

local function update_surface_render_parameters(planet, mythos_floor)
    if not feature_flags.expansion_shaders then return end

    local color1, color2 = fog_color(planet.name)

    local fog = {
        shape_noise_texture = {
            filename = "__core__/graphics/clouds-noise.png",
            size = 2048
        },
        detail_noise_texture = {
            filename = "__core__/graphics/clouds-detail-noise.png",
            size = 2048
        },
        color1 = color1,
        color2 = color2,
        fog_type = "vulcanus",
    }

    mythos_floor.surface_render_parameters = mythos_floor.surface_render_parameters or {}
    local srp = mythos_floor.surface_render_parameters
    srp.fog = fog
    srp.draw_sprite_clouds = false
    srp.clouds = nil

    if planet.name == "gleba" then -- No rain indoors
        mythos_floor.player_effects = nil
    end
end

local function add_music(planet, mythos_floor)
    for _, music in pairs(data.raw["ambient-sound"]) do
        if music.planet == planet.name or (music.track_type == "hero-track" and music.name:find(planet.name)) then
            local new_music = table.deepcopy(music)
            new_music.name = music.name .. "-" .. mythos_floor.name
            new_music.planet = mythos_floor.name
            if new_music.track_type == "hero-track" then
                new_music.track_type = "main-track"
                new_music.weight = 10
            end
            data:extend {new_music}
        end
    end
end

-- we need to copy all existing planets in order to create mythos floors for them
local mythos_floors = {}
for _, planet in pairs(data.raw.planet) do
    if planet.hidden and planet.name ~= "neo-nauvis" then goto continue end
    if planet.ignored_for_factorissimo then goto continue end

    local mythos_floor = table.deepcopy(planet)
    local original_localised_name = planet.localised_name or {"space-location-name." .. planet.name}
    mythos_floor.name = planet.name .. "-mythos-floor"
    mythos_floor.localised_name = {"space-location-description.mythos-floor-in-list", original_localised_name}
    mythos_floor.localised_description = {"space-location-description.mythos-floor", original_localised_name, planet.name}
    mythos_floor.lightning_properties = nil
    mythos_floor.distance = mythos_floor.distance - (1.25 * (mythos_floor.magnitude or 1))
    mythos_floor.draw_orbit = false
    mythos_floor.solar_power_in_space = 0
    mythos_floor.fly_condition = true
    mythos_floor.auto_save_on_first_trip = false
    mythos_floor.asteroid_spawn_definitions = nil
    mythos_floor.order = "z-[mythos-floor]" .. (planet.order or planet.name)
    mythos_floor.map_gen_settings = nil
    mythos_floor.surface_properties = mythos_floor.surface_properties or {}
    mythos_floor.surface_properties["solar-power"] = 0
    mythos_floor.surface_properties["day-night-cycle"] = 0
    mythos_floor.surface_properties["ceiling"] = 0
    mythos_floor.magnitude = (mythos_floor.magnitude or 1) / 2
    mythos_floor.starmap_icons = nil
    mythos_floor.starmap_icon = nil
    mythos_floor.icon = nil
    mythos_floor.icon_size = 64
    mythos_floor.icons = generate_mythos_floor_planet_icons(planet)
    mythos_floor.starmap_icon_size = 115
    mythos_floor.factoriopedia_alternative = planet.name
    mythos_floor.hidden = true
    mythos_floor.hidden_in_factoriopedia = true
    update_surface_render_parameters(planet, mythos_floor)
    add_music(planet, mythos_floor)
    table.insert(mythos_floors, mythos_floor)

    ::continue::
end
data:extend(mythos_floors)

-- ensure that the mythos planets are unlocked when the original planets are unlocked
for _, technology in pairs(data.raw.technology) do
    if technology.effects and type(technology.effects) == "table" then
        local new_effects = {}
        for _, effect in pairs(technology.effects) do
            table.insert(new_effects, effect)
            local planet, mythos_floor

            if type(effect) ~= "table" then goto continue end
            if effect.type ~= "unlock-space-location" then goto continue end
            if not effect.space_location then goto continue end
            local planet = data.raw.planet[effect.space_location]
            if not planet or not planet.name then goto continue end
            local mythos_floor = data.raw.planet[planet.name .. "-mythos-floor"]
            if not mythos_floor then goto continue end

            table.insert(new_effects, {
                type = "unlock-space-location",
                space_location = mythos_floor.name,
                use_icon_overlay_constant = false,
            })

            ::continue::
        end
        technology.effects = new_effects
    end
end
