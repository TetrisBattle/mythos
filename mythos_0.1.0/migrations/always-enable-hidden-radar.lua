for _, mythos in pairs(storage.factories or {}) do
    if mythos.radar.valid then
        mythos.radar.active = true
    end
end
storage.hidden_radars = nil
