mythos.on_event(mythos.events.on_init(), function()
    if not remote.interfaces["PickerDollies"] then return end

    remote.call("PickerDollies", "add_blacklist_name", "mythos-1", true)
end)
