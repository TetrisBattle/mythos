if not mods["space-age"] then return end
if mods["space-is-fake"] then return end

local F = "__mythos__"
local pf = "p-q-"

for _, tower in pairs(data.raw["agricultural-tower"]) do
    tower.surface_conditions = tower.surface_conditions or {}
    table.insert(tower.surface_conditions, {
        property = "solar-power",
        min = 1
    })
end

if not mods["warptorio-space-age"] then -- https://github.com/notnotmelon/mythos-2-notnotmelon/issues/255
    for _, plant in pairs {"jellystem", "yumako-tree"} do
        plant = data.raw.plant[plant]
        plant.surface_conditions = plant.surface_conditions or {}
        table.insert(plant.surface_conditions, {
            property = "pressure",
            min = 2000,
            max = 2000
        })
    end
end
