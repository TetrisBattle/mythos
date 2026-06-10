# Mythos Architecture

This is a maintainer map for the runtime refactor. It names the main entry points,
module packages, compatibility shims, and persisted names that need migrations if
they change.

## Entry Points

- `data.lua` loads prototypes: hidden entities, collision layers, the dimension
  tile, Mythos entities, virtual chest, recipes, keybinds, and GUI styles.
- `settings.lua` defines runtime-global settings:
  `mythos-no-cost` and `mythos-no-virtual-inventory`.
- `control.lua` wires the runtime: initializes `storage`, applies settings,
  restores metatables on load, delegates configuration changes to migrations,
  and registers all event handlers.

## Runtime Package Map

- `script/bootstrap` initializes persisted storage and handles `on_load`
  metatable refresh flags.
- `script/events` owns Factorio event registration and event grouping for
  chunks, GUI, and ticks.
- `script/mythos` owns active Mythos state, registry, connection slots,
  logistics, icons, resize, deletion, and the public Mythos facade.
- `script/pocket_dimension` owns pocket-dimension constants, layout, floor
  bounds, surface creation, and remote-view preparation.
- `script/clone` owns blueprint snapshotting, paste queueing, and clone apply.
- `script/virtual_chest` owns virtual chest lifecycle, inventory anchors,
  logistics behavior, and legacy migration.
- `script/power` owns hidden power bridge entities and periodic power/solar sync.
- `script/migrations` owns configuration-change and post-load repair steps.
- `script/ui` owns resize, icon, and remote-view GUI code.
- `script/common` does not currently exist; shared helpers remain in
  `script/util.lua`. Other shared top-level runtime modules include
  `script/config.lua`, `script/registerEvents.lua`, `script/settingsSync.lua`,
  `script/transport.lua`, and `script/mythosRestore.lua`.

## Module Paths

Runtime code requires package paths directly. The old top-level compatibility
wrappers were removed, so new code should continue using paths such as
`script.mythos.init`, `script.pocket_dimension.init`, `script.clone.init`, and
`script.ui.remote_view`.

## Persisted Names

Do not rename these without a migration for existing saves:

- Runtime storage keys: `storage.mythoi`, `storage.saved_dimensions`,
  `storage.pending_player_restore`, `storage.viewing`,
  `storage.pending_resize_gui`, `storage.virtualChests`,
  `storage.mythos_next_snapshot_id`, and `storage.mythos_pending_paste`.
- Virtual chest storage and migration keys:
  `storage.virtual_chest_storage_anchors`,
  `storage.virtual_chest_legacy_migrated`, and
  `storage.virtual_chest_legacy_linked_snapshot`.
- Legacy keys consumed by migration: `storage.mythos_storage_anchors`,
  `storage.mythos_inventories`, and `storage.virtual_chests`.
- Surface naming: `mythos-dimension-<unit_number>`, parsed by
  `script/util.lua`.
- Prototype and item names: `mythos`, `mythos-with-contents`, `virtual-chest`,
  `mythos-dimension-floor`, `mythos-hidden-pipe`,
  `mythos-hidden-heat-pipe`, `mythos-hidden-radar`,
  `mythos-power-hub-pole`, `mythos-power-outer-pole`,
  `mythos-power-link-outer`, `mythos-power-link-inner`, and `mythos-gate`.
- Legacy prototype names used by migrations: `mythos-inventory` and
  `lab-dark-2`.
- Runtime setting names and controls: `mythos-no-cost`,
  `mythos-no-virtual-inventory`, `mythos-open-dimension`,
  `mythos-resize-up`, `mythos-resize-down`, `mythos-resize-left`, and
  `mythos-resize-right`.

## Manual Smoke-Test Matrix

Run these in Factorio after static checks, especially before releasing a save
migration:

| Scenario | What to check |
| --- | --- |
| Load | New game loads with no control-stage errors; existing save loads and metatables restore. |
| Place/remove | Placing a Mythos creates its dimension and hidden infrastructure; mining empty vs non-empty Mythos behaves correctly. |
| Connections | Belts, loaders, pipes, and heat pipes connect/disconnect from outer slots and inner gates. |
| Power | Outer and inner bridge entities transfer power; solar sync follows the placement surface. |
| Resize/UI | Remote view opens; resize GUI changes floor bounds; custom icons still render. |
| Clone/blueprint | Blueprint tags preserve saved dimensions; clone/paste restores dimensions and connections where valid. |
| Virtual chest | Virtual chest placement, force-linked inventory storage, logistics, and setting toggles behave correctly. |
| Settings | Runtime setting changes apply immediately and preserve existing storage expectations. |
| Save/load | Save after active dimensions, reload, and confirm dimensions, views, power, and icons still work. |
| Configuration changed/migrations | Updating from an older save runs migrations, prunes invalid state, restores power links/icons, migrates floor tiles, and migrates legacy virtual chest data. |
