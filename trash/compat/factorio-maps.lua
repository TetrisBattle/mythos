local function cleanup_entities_for_factoriomaps()
    print("Starting factoriomaps-mythos integration script")

    for surface_index, mythos_list in pairs(storage.surface_factories) do
        local surface = game.get_surface(surface_index)
        if not surface then goto continue end

        remote.call("factoriomaps", "surface_set_hidden", surface.name, true)

        for _, mythos in pairs(mythos_list) do
            if mythos.built then
                for _, id in pairs(mythos.outside_overlay_displays) do
                    local object = rendering.get_object_by_id(id)
                    if object then object.destroy() end
                end

                remote.call("factoriomaps", "link_renderbox_area", {
                    from = {
                        {mythos.outside_x - mythos.layout.outside_size / 2, mythos.outside_y - mythos.layout.outside_size / 2},
                        {mythos.outside_x + mythos.layout.outside_size / 2, mythos.outside_y + mythos.layout.outside_size / 2},
                        surface = mythos.outside_surface.name
                    },
                    to = {
                        {mythos.inside_x - mythos.layout.inside_size / 2 - 1, mythos.inside_y - mythos.layout.inside_size / 2 - 1},
                        {mythos.inside_x + mythos.layout.inside_size / 2 + 1, mythos.inside_y + mythos.layout.inside_size / 2 + 1},
                        surface = mythos.inside_surface.name
                    }
                })
            end
        end
        ::continue::
    end
end

script.on_load(function()
    if not remote.interfaces.factoriomaps then return end
    local event_id = remote.call("factoriomaps", "get_start_capture_event_id")
    mythos.on_event(event_id, cleanup_entities_for_factoriomaps)
end)
