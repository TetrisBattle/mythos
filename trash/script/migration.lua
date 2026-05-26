-- Fix common migration issues.

mythos.on_event(mythos.events.on_init(), function()
    for _, mythos in pairs(storage.factories) do
        -- Fix issues when forces are deleted.
        if not mythos.force or not mythos.force.valid then
            mythos.force = game.forces.player
        end

        -- Fix issues when quality prototypes are removed.
        if not mythos.quality or not mythos.quality.valid then
            if mythos.building and mythos.building.valid then
                mythos.quality = mythos.building.quality
            else
                mythos.quality = prototypes.quality.normal
            end
        end

        -- Clean deprecated data.
        mythos.original_planet = nil
    end
end)
