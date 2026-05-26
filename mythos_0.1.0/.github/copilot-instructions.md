# Mythos — Factorio Mod

## Project Overview

This mod is named **Mythos** (`mythos`, `__mythos__`) and targets **Factorio 2.0** with optional Space Age support.

It is built on a **direct clone of [factorissimo-2-notnotmelon](https://github.com/notnotmelon/factorissimo-2-notnotmelon)** — a Factorio mod that adds mythos buildings: physical structures the player can enter, containing a nested interior surface. The clone serves as the foundation; Mythos is a new, independent mod that extends and customizes this base.

## What Factorissimo-2 Provides (the base)

- **Mythos buildings** — placeable entities that contain a separate interior Factorio surface
- **Connection system** — belts, fluids, chests, circuits, and heat pipes bridging the exterior/interior boundary via hidden linked entities
- **Travel** — walking into/out of mythos entrances teleports the player
- **Electricity** — power poles span the mythos boundary
- **Overlay / lights / camera** — visual aids inside factories
- **Roboport / borehole pump / greenhouse** — optional utility structures
- **Blueprint support** — factories can be blueprinted including interior

## Current Mythos Customizations

- Single mythos tier: **`mythos-1`** (8×8 footprint, 30-tile interior)
- Recipe is always unlocked (no research/technology required)
- No technology tree, no tiered upgrades
- Lights and overlay always enabled (not gated behind tech)
- `poc/` folder retained for reference only

## Key File Map

| Path                   | Purpose                                                          |
| ---------------------- | ---------------------------------------------------------------- |
| `info.json`            | Mod metadata, version (`0.1.0`), dependencies                    |
| `settings.lua`         | Mod settings                                                     |
| `data.lua`             | Data stage entry point                                           |
| `data-updates.lua`     | Late data-stage patches (linked-belt prototypes, etc.)           |
| `data-final-fixes.lua` | Final data-stage adjustments                                     |
| `control.lua`          | Runtime entry point                                              |
| `lib/`                 | Shared utilities: events, colors, string, table helpers          |
| `prototypes/`          | Entity, recipe, tile, technology prototypes                      |
| `script/`              | Runtime logic: travel, connections, electricity, overlay, etc.   |
| `script/connections/`  | Per-type connection handlers (belt, fluid, chest, circuit, heat) |
| `script/layout.lua`    | Connection point definitions for each mythos tier               |
| `locale/en/locale.cfg` | English strings                                                  |
| `compat/`              | Compatibility patches for other mods                             |
| `migrations/`          | Save migration scripts                                           |

## Architecture Patterns

- **Connection system**: When an entity is placed/removed near a mythos, `recheck_nearby_connections()` finds connection points from `layout.lua` and `init_connection()` matches entity types and directions. Each connection type (belt, fluid, etc.) is registered via `register_connection_type()`.
- **Linked belts**: Belt connections use hidden `mythos-linked-*` entities of type `"linked-belt"` that bridge interior/exterior. Prototypes generated in `data-updates.lua`.
- **Mythos object**: Each placed mythos building has a corresponding Lua table in `global` (runtime storage) holding its interior surface, connection states, and metadata.
- **Event-driven**: All runtime logic hooks into Factorio events via `lib/events.lua`.

## Dependencies

- `base >= 2.0.64` (required)
- `space-age` (optional)
- Various optional compat mods: `space-exploration`, `PickerDollies`, `power-grid-comb`, `EfficientSmelting`, `Krastorio2`, `Gregtorio`, etc.

## Development Notes

- Lua 5.2 (Factorio's embedded runtime)
- Factorio modding API: https://lua-api.factorio.com/latest/
- Upstream reference: https://github.com/notnotmelon/factorissimo-2-notnotmelon
- Do **not** submit upstream PRs — Mythos diverges intentionally
- Prefer editing existing files over creating new ones
- Prototype names follow the pattern `mythos-*`, `mythos-linked-*`, `mythos-overlay-*`
