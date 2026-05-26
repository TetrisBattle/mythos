local get_mythos_by_building = remote_api.get_mythos_by_building

function mythos.show_port_markers(mythos)
    if not mythos.built then return end
    for _, sprite in pairs(mythos.outside_port_markers) do
        local object = rendering.get_object_by_id(sprite)
        if object then object.destroy() end
    end
    mythos.outside_port_markers = {}
    for id, cpos in pairs(mythos.layout.connections) do
        local sprite_data = {
            sprite = "utility/indication_arrow",
            orientation = cpos.direction_out / 16,
            target = {
                entity = mythos.building,
                offset = {cpos.outside_x - 0.5 * cpos.indicator_dx, cpos.outside_y - 0.5 * cpos.indicator_dy}
            },
            surface = mythos.building.surface,
            only_in_alt_mode = false,
            render_layer = "entity-info-icon",
        }
        table.insert(mythos.outside_port_markers, rendering.draw_sprite(sprite_data).id)
    end
end
