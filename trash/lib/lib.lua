_G.mythos = mythos or {}

require "table"
require "string"
require "defines"
require "color"

if data and data.raw and not data.raw.item["iron-plate"] then
    mythos.stage = "settings"
elseif data and data.raw then
    mythos.stage = "data"
    require "data-stage"
elseif script then
    mythos.stage = "control"
    require "control-stage"
else
    error("Could not determine load order stage.")
end
