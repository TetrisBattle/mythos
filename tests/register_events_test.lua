local test = require("tests.lua_test")

local function withEventGlobals(events, callback)
	local oldDefines = _G.defines
	local oldScript = _G.script
	local calls = {}

	_G.defines = { events = events }
	_G.script = {
		on_event = function(event, handler)
			calls[#calls + 1] = { event = event, handler = handler }
		end,
	}

	package.loaded["script.registerEvents"] = nil
	local registerEvents = require("script.registerEvents")
	local ok, err = pcall(callback, registerEvents, calls)

	_G.defines = oldDefines
	_G.script = oldScript
	package.loaded["script.registerEvents"] = nil

	if not ok then
		error(err, 0)
	end
end

test.test("registerEvents wires core built and removed entity events", function()
	local onBuilt = function() end
	local onRemoved = function() end

	withEventGlobals({
		on_built_entity = 1,
		on_robot_built_entity = 2,
		script_raised_built = 3,
		script_raised_revive = 4,
		on_player_mined_entity = 5,
		on_robot_mined_entity = 6,
		on_entity_died = 7,
		script_raised_destroy = 8,
	}, function(registerEvents, calls)
		registerEvents(onBuilt, onRemoved)

		test.assertEquals(#calls, 8)
		test.assertDeepEquals(calls[1], { event = 1, handler = onBuilt })
		test.assertDeepEquals(calls[4], { event = 4, handler = onBuilt })
		test.assertDeepEquals(calls[5], { event = 5, handler = onRemoved })
		test.assertDeepEquals(calls[8], { event = 8, handler = onRemoved })
	end)
end)

test.test("registerEvents includes optional space platform events when available", function()
	local onBuilt = function() end
	local onRemoved = function() end

	withEventGlobals({
		on_built_entity = 1,
		on_robot_built_entity = 2,
		script_raised_built = 3,
		script_raised_revive = 4,
		on_space_platform_built_entity = 9,
		on_player_mined_entity = 5,
		on_robot_mined_entity = 6,
		on_entity_died = 7,
		script_raised_destroy = 8,
		on_space_platform_mined_entity = 10,
	}, function(registerEvents, calls)
		registerEvents(onBuilt, onRemoved)

		test.assertEquals(#calls, 10)
		test.assertDeepEquals(calls[5], { event = 9, handler = onBuilt })
		test.assertDeepEquals(calls[10], { event = 10, handler = onRemoved })
	end)
end)
