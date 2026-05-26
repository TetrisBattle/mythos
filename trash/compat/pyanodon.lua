if not mods["pyalienlife"] then return end
if not mods["pyhightech"] then return end

data.raw.recipe["mythos-1"].ingredients = {
    {type = "item", name = "concrete",     amount = 500},
    {type = "item", name = "steel-plate",  amount = 100},
    {type = "item", name = "tinned-cable", amount = 100},
    {type = "item", name = "treated-wood", amount = 100}
}
