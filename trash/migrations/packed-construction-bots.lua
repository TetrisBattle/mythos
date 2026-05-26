for _, mythos in pairs(storage.factories or {}) do
    if mythos.roboport_upgrade then
        mythos.roboport_upgrade.num_robots_requested = mythos.roboport_upgrade.num_robots_requested or 0
    end
end
