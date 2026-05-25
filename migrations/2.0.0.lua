require "__mythos__.script.electricity"

for _, pole in ipairs(storage.middleman_power_poles or {}) do
    if pole ~= 0 then pole.destroy() end
end
storage.middleman_power_poles = nil

for _, mythos in pairs(storage.factories) do
    for _, inside_power_pole in pairs(mythos.inside_power_poles or {}) do
        if inside_power_pole and inside_power_pole.valid then
            inside_power_pole.destroy()
        end
    end
    mythos.inside_power_poles = nil
    mythos.middleman_id = nil
    mythos.direct_connection = nil

    mythos.update_power_connection(mythos)
end

storage.surface_mythos_counters = nil
storage.middleman_circuit_connectors = nil
storage.spidertrons = nil
