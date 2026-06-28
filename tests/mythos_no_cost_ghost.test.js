const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");

const eventsSource = readFileSync("script/mythos/events.lua", "utf8");
const logisticsSource = readFileSync("script/mythos/logistics.lua", "utf8");

test("no-cost ghosts built inside a Mythos are revived without inventory costs", () => {
  assert.match(
    eventsSource,
    /state and state\.entity\.valid and Config\.noCost\(\) and entity\.type == "entity-ghost"/,
    "dimension build handler must detect no-cost entity ghosts"
  );
  assert.match(
    eventsSource,
    /state:buildGhostFree\(entity\)\s+return/,
    "no-cost entity ghosts should be handled by buildGhostFree before connection logic"
  );
  assert.match(
    logisticsSource,
    /function Mythos:buildGhostFree\(ghost\)[\s\S]*ghost\.type == "entity-ghost"[\s\S]*return materializeGhostFree\(ghost\)/,
    "buildGhostFree must validate entity ghosts and materialize them through the free path"
  );
  assert.doesNotMatch(
    logisticsSource,
    /function Mythos:buildGhostFree\(ghost\)[\s\S]*VirtualChest\.removeItemsFromInventories[\s\S]*end/,
    "buildGhostFree must not consume virtual chest inventory"
  );
});
