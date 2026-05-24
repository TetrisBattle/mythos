# Mythos – Implementation Plan

## Current State (done)
- `item-with-tags` with per-item UID, craftable from 5 iron plates
- 4×4 placeable container entity (`mythos-entity`)
- Right-click entity → teleport player inside as god-mode (invisible, sandbox feel)
- 32×32 concrete floor pocket surface, always full brightness
- Exit via HUD button or Escape
- UID preserved through mine → place cycles

---

## Feature 1 – Belt I/O ports

**What:** 8 `loader-1x1` entities attached to the outer faces of the placed entity (2 centered ports per side on the 4×4 shell).
They are invisible/hidden companions that act as the connection points between the outer world and the pocket surface.

**How:**
- On `on_built_entity` for `mythos-entity`: create 8 loader-1x1 entities in the 4 cardinal directions, 2 centered ports per side, stored in `storage.mythos_ports[unit_number]`
- On `on_player_mined_entity` / `on_entity_died`: destroy all companion loaders
- Loaders on the LEFT and TOP faces face INWARD (input); RIGHT and BOTTOM face OUTWARD (output) — or make all ports bidirectional via detection
- Store port positions in `storage.mythos_ports[uid]` indexed by slot number

**Files:** `prototypes/entity.lua` (loader prototype), `control/surface.lua` (build/mine handlers)

---

## Feature 2 – Cross-surface belt transfer

**What:** Items on inner connector belts (inside the pocket surface, near the edges) are moved to the corresponding outer loader output, and items from outer loader inputs are moved to inner connector belts — every 6 ticks.

**How:**
- Place 8 `transport-belt` entities inside the pocket surface near the 4 walls (at matching positions to the outer ports) on surface creation
- `on_nth_tick(6)`: for each active Mythos entity, iterate its 8 ports:
  - Outer input loader → find items → insert onto the matching inner belt
  - Inner output belt → find items → insert onto the outer output belt / ground
- Use `LuaTransportLine` to read/write items from belt lines

**Files:** `control/surface.lua` (tick handler), `control/ports.lua` (new file for port logic)

---

## Feature 3 – Internal steel chest

**What:** A steel chest is pre-placed inside the pocket surface at a fixed position (e.g. `{-14, -14}`, top-left corner) when the surface is first created.

**How:**
- In `get_or_create_surface`, after `set_tiles`: create a `steel-chest` entity at `{-14, -14}` on the pocket surface
- Store its reference in `storage.mythos[uid].chest_pos = {-14, -14}` (position, not entity ref, for save/load safety)

**Files:** `control/surface.lua`

---

## Feature 4 – Item deletion routing

**What:** When a player mines (deletes) an entity or picks up items inside the pocket dimension, the items go to:
1. The internal steel chest (if it exists and has space)
2. Otherwise the player's character inventory (on the outer surface)

**How:**
- Hook `on_player_mined_entity` and `on_picked_up_item` filtered to the pocket surface
- Check if the player is inside a pocket (`storage.player_in_mythos[player.index]`)
- Find the chest via `surface.find_entity("steel-chest", {-14, -14})`
- Insert items into chest first; overflow goes to character inventory (`data.character.get_main_inventory()`)

**Files:** `control/gui.lua` or new `control/routing.lua`

---

## Feature 5 – Open chest from outside

**What:** Left-clicking (or some interaction with) the placed `mythos-entity` from outside opens the internal steel chest's inventory directly, without entering the pocket.

**How:**
- Add a custom input (`defines.events.on_custom_input`) OR detect `on_gui_opened` with alt/ctrl modifier check
- Simpler: add a second interaction — if player is holding nothing and **shift+right-clicks** the entity, open the chest GUI instead of entering
- Use `player.opened = chest_entity` to show the chest inventory natively

**Files:** `control/gui.lua`, `prototypes/custom-inputs.lua` (if custom keybind needed)

---

## Skipped (out of scope)
- Fluid I/O (pipe connections across surfaces)
- Heat connections
