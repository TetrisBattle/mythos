local M = {
	tests = {},
}

local function fail(message, level)
	error(message or "assertion failed", (level or 1) + 1)
end

local function formatValue(value, seen)
	seen = seen or {}
	if type(value) ~= "table" then
		return tostring(value)
	end
	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true

	local parts = {}
	for key, child in pairs(value) do
		parts[#parts + 1] = tostring(key) .. "=" .. formatValue(child, seen)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(actual, expected, seen)
	if actual == expected then
		return true
	end
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return false
	end

	seen = seen or {}
	seen[actual] = seen[actual] or {}
	if seen[actual][expected] then
		return true
	end
	seen[actual][expected] = true

	for key, expectedValue in pairs(expected) do
		if not deepEqual(actual[key], expectedValue, seen) then
			return false
		end
	end
	for key in pairs(actual) do
		if expected[key] == nil then
			return false
		end
	end
	return true
end

function M.test(name, fn)
	M.tests[#M.tests + 1] = { name = name, fn = fn }
end

function M.assertEquals(actual, expected, message)
	if actual ~= expected then
		fail(
			(message or "values differ")
				.. "\nexpected: "
				.. formatValue(expected)
				.. "\nactual:   "
				.. formatValue(actual),
			2
		)
	end
end

function M.assertDeepEquals(actual, expected, message)
	if not deepEqual(actual, expected) then
		fail(
			(message or "tables differ")
				.. "\nexpected: "
				.. formatValue(expected)
				.. "\nactual:   "
				.. formatValue(actual),
			2
		)
	end
end

function M.assertTruthy(value, message)
	if not value then
		fail(message or "expected truthy value", 2)
	end
end

function M.assertFalsy(value, message)
	if value then
		fail(message or "expected falsy value", 2)
	end
end

function M.run()
	local failed = 0
	for _, entry in ipairs(M.tests) do
		local ok, err = pcall(entry.fn)
		if ok then
			print("ok - " .. entry.name)
		else
			failed = failed + 1
			io.stderr:write("not ok - " .. entry.name .. "\n" .. tostring(err) .. "\n") ---@diagnostic disable-line: undefined-global
		end
	end

	local passed = #M.tests - failed
	print(string.format("%d passed, %d failed", passed, failed))
	return failed == 0
end

return M
