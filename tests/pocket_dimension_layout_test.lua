local test = require("tests.lua_test")
local layout = require("script.pocket_dimension.layout")

local bounds = {
	x_min = 3,
	x_max = 5,
	y_min = 10,
	y_max = 11,
}

local function countEntries(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

test.test("physical gate layout follows inclusive floor bounds", function()
	local physical = layout.computeDimensionPhysicalGateLayout(bounds)

	test.assertEquals(countEntries(physical), 10)
	test.assertDeepEquals(physical.PT1.pos, { 3.5, 9.5 })
	test.assertDeepEquals(physical.PT3.innerBeltPos, { 5.5, 10.5 })
	test.assertDeepEquals(physical.PR2.pos, { 6.5, 11.5 })
	test.assertDeepEquals(physical.PB3.innerBeltPos, { 5.5, 11.5 })
	test.assertDeepEquals(physical.PL1.pos, { 2.5, 10.5 })
	test.assertEquals(physical.PL1.edge, "left")
	test.assertEquals(physical.PR1.gateOrientation, defines.direction.east / 16)
end)

test.test("normalization keeps valid unique physical gates in slot order", function()
	local normalized = layout.normalizeDimensionGatePositions({
		T1 = "PL1",
		T2 = "PL1",
		L1 = "PL99",
		R4 = "PR2",
		B1 = "not-a-gate",
		Z1 = "PT1",
	}, bounds)

	test.assertDeepEquals(normalized, {
		T1 = "PL1",
		R4 = "PR2",
	})
end)

test.test("slot belt layout maps logical slots through normalized gate positions", function()
	local slotLayout = layout.computeDimensionSlotBeltLayout(bounds, {
		T1 = "PT2",
		L1 = "PL1",
		R1 = "PR1",
		B1 = "PB3",
	})

	test.assertDeepEquals(slotLayout.T1.pos, { 4.5, 9.5 })
	test.assertDeepEquals(slotLayout.T1.innerBeltPos, { 4.5, 10.5 })
	test.assertEquals(slotLayout.T1.physicalGateKey, "PT2")
	test.assertEquals(slotLayout.L1.edge, "left")
	test.assertEquals(slotLayout.R1.edge, "right")
	test.assertEquals(slotLayout.B1.edge, "bottom")
	test.assertEquals(slotLayout.T2, nil)
end)

test.test("mythos slot layout has one external and inner position per side slot", function()
	local mythosLayout = layout.buildMythosSlotLayout()

	test.assertEquals(countEntries(mythosLayout), 16)
	test.assertDeepEquals(mythosLayout.L1, {
		externalX = -2.5,
		externalY = -1.5,
		innerX = -1.5,
		innerY = -1.5,
		outwardDir = defines.direction.west,
	})
	test.assertEquals(mythosLayout.T4.outwardDir, defines.direction.north)
	test.assertEquals(mythosLayout.B4.outwardDir, defines.direction.south)
end)
