# Mythos AI Instructions

Mythos is a Factorio 2.0 Lua mod in first-prototype stage. Before changing
runtime code, read [ARCHITECTURE.md](../ARCHITECTURE.md) for entry points,
module boundaries, persisted names, and the manual smoke-test matrix.

## Prototype Workflow

- There is no automated test suite or test scaffolding in this repo.
- Do not create or request automated tests, test frameworks, migration tests,
  CI, or new test infrastructure unless the user explicitly asks for them.
- Keep verification lightweight and local to the change: `git diff --check`,
  focused searches, and IDE diagnostics.
- Do not require `lua`, `luac`, Lua lint tools, or Factorio load checks for
  normal work; if those tools are unavailable, do not treat that as a
  verification gap. Run manual Factorio smoke checks only when Factorio is
  already available or the user explicitly asks for in-game verification.
- Do not present missing automated tests as a blocker for normal prototype work.

## Save Compatibility

- This project targets clean new saves.
- Do not add migrations or old-save compatibility for normal changes unless the
  user explicitly asks for that work.
- If a change may break existing saves, tell the user they may need to start a
  new save with no placed Mythoses to avoid migration or load errors.
- Keep current storage keys, surface names, prototype names, setting names,
  custom input names, and blueprint tag names stable during normal feature work.
- Virtual chest legacy migration support was intentionally removed. Do not
  reintroduce `mythos-inventory`, old virtual chest storage-key migrations, or
  old floor-tile migrations unless the user explicitly asks for old-save
  support.

## Runtime Conventions

- Keep `control.lua` thin: lifecycle hooks plus event registration.
- Runtime code should require package paths directly, such as
  `script.mythos.init`, `script.pocket_dimension.init`, and
  `script.ui.remote_view`.
- Prefer focused modules and facades over re-growing monolithic files.
- Avoid `goto` patterns; use structured conditionals to stay Lua-load safe.
- Keep Factorio API behavior stable unless the user explicitly asks for
  gameplay changes.
