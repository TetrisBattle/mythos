# Testing

Mythos has a small dependency-free test setup for logic that can run outside
Factorio.

## Lua Unit Tests

```powershell
lua tests/run.lua
```

These tests stub the small `defines` table needed by pure modules and cover
helpers under `script/util.lua` and `script/pocket_dimension`.
