package.path = table.concat({
	"./?.lua",
	"./?/init.lua",
	"tests/?.lua",
}, ";") .. ";" .. package.path

_G.defines = _G.defines or {
	direction = {
		north = 0,
		east = 4,
		south = 8,
		west = 12,
	},
}

local test = require("tests.lua_test")

require("tests.util_test")
require("tests.pocket_dimension_layout_test")
require("tests.pocket_dimension_floor_test")
require("tests.register_events_test")

if not test.run() then
	os.exit(1)
end
