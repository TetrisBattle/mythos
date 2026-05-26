for _, mythos in pairs(storage.factories or {}) do
    if mythos.roboport_upgrade and mythos.roboport_upgrade.item_request_proxies then
        for k, proxy in pairs(mythos.roboport_upgrade.item_request_proxies) do
            if type(proxy) == "userdata" then
                proxy.destroy()
                mythos.roboport_upgrade.item_request_proxies[k] = nil
            end
        end
    end
end
