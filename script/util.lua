-- Stable string key for a {x, y} position.
-- Works correctly for both integer and .5-fractional tile coordinates.
local function positionKey(x, y)
	return string.format("%g,%g", x, y)
end

return { positionKey = positionKey }
