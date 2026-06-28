local test = require("tests.lua_test")
local util = require("script.util")

test.test("positionKey is stable for integer and fractional positions", function()
	test.assertEquals(util.positionKey(10, -4), "10,-4")
	test.assertEquals(util.positionKey(1.5, -0.5), "1.5,-0.5")
end)

test.test("nearPosition handles missing positions and tolerance", function()
	test.assertFalsy(util.nearPosition(nil, { x = 0, y = 0 }))
	test.assertFalsy(util.nearPosition({ x = 0, y = 0 }, nil))
	test.assertTruthy(util.nearPosition({ x = 1.35, y = 2.3 }, { x = 1, y = 2 }))
	test.assertFalsy(util.nearPosition({ x = 1.41, y = 2 }, { x = 1, y = 2 }))
	test.assertTruthy(util.nearPosition({ x = 1.9, y = 2 }, { x = 1, y = 2 }, 1))
end)

test.test("bounds helpers use inclusive tile ranges", function()
	local bounds = { x_min = 3, x_max = 7, y_min = -2, y_max = 4 }
	test.assertEquals(util.floorWidth(bounds), 5)
	test.assertEquals(util.floorHeight(bounds), 7)
	test.assertDeepEquals(util.copyBounds(bounds), bounds)
end)

test.test("parseDimensionUnitNumber returns ids only for dimension surface names", function()
	test.assertEquals(util.parseDimensionUnitNumber("mythos-dimension-42"), 42)
	test.assertEquals(util.parseDimensionUnitNumber({ name = "mythos-dimension-7" }), 7)
	test.assertEquals(util.parseDimensionUnitNumber("mythos-blueprint-snapshot-7"), nil)
	test.assertEquals(util.parseDimensionUnitNumber(nil), nil)
	test.assertEquals(util.parseDimensionUnitNumber({}), nil)
end)

test.test("buildInnerPosToSlot indexes inner belt positions", function()
	local byPosition = util.buildInnerPosToSlot({
		L1 = { innerBeltPos = { 2.5, 3.5 } },
		R1 = { innerBeltPos = { 4, 5 } },
	})
	test.assertEquals(byPosition["2.5,3.5"], "L1")
	test.assertEquals(byPosition["4,5"], "R1")
	test.assertDeepEquals(util.buildInnerPosToSlot(nil), {})
end)

test.test("edgeSlotKeys expands known edge names to slot prefixes", function()
	test.assertDeepEquals(util.edgeSlotKeys("left", 3), { "L1", "L2", "L3" })
	test.assertDeepEquals(util.edgeSlotKeys("right", 2), { "R1", "R2" })
	test.assertDeepEquals(util.edgeSlotKeys("X", 2), { "X1", "X2" })
end)

test.test("isStoredChestItem ignores content containers and invalid stacks", function()
	test.assertFalsy(util.isStoredChestItem(nil))
	test.assertFalsy(util.isStoredChestItem({ valid_for_read = false, name = "iron-plate" }))
	test.assertFalsy(util.isStoredChestItem({ valid_for_read = true, name = "mythos" }))
	test.assertFalsy(util.isStoredChestItem({ valid_for_read = true, name = "mythos-with-contents" }))
	test.assertFalsy(util.isStoredChestItem({ valid_for_read = true, name = "virtual-chest" }))
	test.assertTruthy(util.isStoredChestItem({ valid_for_read = true, name = "iron-plate" }))
end)
