-- this file rebalances the mythos tech tree for space age

if not mods["space-age"] then return end
if mods["space-is-fake"] then return end

data.raw["storage-tank"]["mythos-1"].surface_conditions = {{
    property = "gravity",
    min = 0.1
}}
data.raw["electric-pole"]["mythos-circuit-connector"].surface_conditions = {{
    property = "gravity",
    min = 0.1
}}
