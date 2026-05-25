local PERMABLACK_SURFACES = {
    ["tenebris-mythos-floor"] = true,
    ["maraxsis-trench-mythos-floor"] = true,
}

function mythos.build_lights_upgrade(mythos)
    if not mythos.inside_surface.valid then return end
    local force = mythos.force
    if not force.valid then return end
    local has_tech = true

    if PERMABLACK_SURFACES[mythos.inside_surface.name] then
        has_tech = false
        mythos.inside_surface.brightness_visual_weights = {r = 1, g = 1, b = 1}
        mythos.inside_surface.min_brightness = 0
    end

    mythos.inside_surface.daytime = has_tech and 1 or 0.5
    mythos.inside_surface.freeze_daytime = true
end
