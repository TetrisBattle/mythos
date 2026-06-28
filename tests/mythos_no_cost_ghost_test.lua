local test = require("tests.lua_test")

local function readFile(path)
	local f = assert(io.open(path, "r")) ---@diagnostic disable-line: undefined-global
	local src = f:read("*a")
	f:close()
	return src
end

local eventsSource = readFile("script/mythos/events.lua")
local logisticsSource = readFile("script/mythos/logistics.lua")

test.test("no-cost ghosts built inside a Mythos are revived without inventory costs", function()
	test.assertTruthy(
		eventsSource:find(
			"state and state%.entity%.valid and Config%.noCost%(%) and entity%.type == \"entity%-ghost\"",
			1, false
		),
		"dimension build handler must detect no-cost entity ghosts"
	)

	test.assertTruthy(
		eventsSource:find("state:buildGhostFree%(entity%)", 1, false),
		"no-cost entity ghosts should be handled by buildGhostFree"
	)

	test.assertTruthy(
		logisticsSource:find("function Mythos:buildGhostFree%(ghost%)", 1, false),
		"buildGhostFree must exist on Mythos"
	)

	test.assertTruthy(
		logisticsSource:find("return materializeGhostFree%(ghost%)", 1, false),
		"buildGhostFree must materialize through the free path"
	)

	test.assertFalsy(
		logisticsSource:find("function Mythos:buildGhostFree.-VirtualChest%.removeItemsFromInventories", 1, false),
		"buildGhostFree must not consume virtual chest inventory"
	)
end)
