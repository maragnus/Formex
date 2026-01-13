# Formex Transactions

This document describes how build transactions work in `src/shared/FormexTransaction.luau`, including normalization, validation, merge behavior, and result semantics. It is written from the current implementation, not a theoretical design.

## Overview
Transactions are a shared, deterministic pipeline for applying or validating changes to walls, floors, and objects. The same logic is used on the server for authoritative validation and on the client for prediction/feedback.

Core entry points:
- `Formex.Transaction.Apply(plotData, changes, options)` applies changes and optionally commits them.
- `Formex.Transaction.Validate(plotData, changes)` runs the same pipeline without committing; used by `Formex.IsTransactionValid`.

Key behaviors:
- Changes are normalized into a canonical form before validation.
- Structural changes (walls/floors) can trigger wall merge/splitting.
- Objects are revalidated and may be removed if invalid (unless the transaction is object-only, in which case invalid objects fail the transaction).
- Object collisions are resolved or rejected depending on the transaction type.
- Transaction results report ID entries, and the working levels are returned for lookup.

## Inputs
A transaction is a list of `BuildChange` entries:
- `PartType`: `Wall`, `Floor`, or `Object`
- `Action`: `Add`, `Edit`, or `Delete`
- `Data`: the data payload, either a single item or a list, where Data is the intended new state of that item

Notes:
- Walls and floors accept a single item or a list. Objects are single-item only.
- `collectLevelsTouched` determines which levels are impacted and whether the transaction is object-only.

## Outputs
`TransactionResult` includes:
- `IsValid`: success/failure for the full transaction.
- `Error`: failure reason for invalid transactions.
- `DidChange`: whether any changes occurred.
- `Results`: per-change results (preserve list vs single input).
- `LevelsTouched`: sorted levels impacted.
- `MergeSegments`: segments where overlapping walls were detected (used for UI preview).
- `RemovedObjects`: `{Level, ObjectId}` entries for objects removed due to delete/validation/collision.
- `UpdatedWalls`, `AddedWalls`, `RemovedWalls` (and same for floors/objects) are `{Level, Id}` entries.
- `Levels`, `NextId`: working levels and next id for prediction/preview.

## Pipeline (Order of Operations)
`applyTransaction` runs these phases in order:
1. **Basic checks**
   - `plotData` must exist.
   - `changes` must be non-empty.
2. **Collect scope**
   - `collectLevelsTouched` determines `levelsTouched`, whether there is a structural change, and whether the transaction is object-only.
   - A `TransactionContext` is created with a working `LevelArray`.
   - For touched levels, a shallow `LevelData` shell is created (copy-on-write for Walls/Floors/Objects maps).
   - `plotData.Levels` is temporarily swapped to the working levels so lookups see inflight state.
   - `nextId` starts from `plotData.NextId`.
3. **Apply changes (mutation phase)**
   - For each `BuildChange`:
     - Normalize data and convert it into canonical forms.
     - Mutate `workingLevels` by `Add`, `Edit`, or `Delete`, cloning the relevant map on first write.
     - Track `Added*`, `Updated*`, `Removed*`, and per-change `Results`.
4. **Merge walls (structural changes only)**
   - If there were any wall/floor changes:
     - Each touched level is passed through `mergeWallsForLevel`.
     - Overlaps are merged, IDs are reused when possible, and `MergeSegments` is recorded.
     - Objects are reattached to merged walls using `reattachObjectsToMergedWalls`.
5. **Validation phase**
   - Walls are validated for geometry and intersections.
   - Floors are validated via `Formex.Floors.IsValid`.
   - Objects are normalized (again) and validated:
     - Invalid objects: removed if the transaction is structural; fail the transaction if object-only.
6. **Collision resolution**
   - `collectObjectCollisions` uses bounds intersection tests:
     - In object-only transactions, any collision invalidates the transaction.
     - In structural transactions, colliding objects are removed and recorded.
7. **Commit or return**
   - If `Commit` is true, `plotData.Levels` and `plotData.NextId` are updated.
   - If `Commit` is false, `plotData.Levels` is restored to the original reference.
   - A `TransactionResult` is returned with all recorded deltas and metadata.

## Normalization
Normalization converts partial inputs into canonical data structures before validation.

### Walls
Normalization is applied per wall in `Add` or `Edit`:
- Heights:
  - `resolveWallHeight` chooses input height, falls back to existing, then to `Formex.LevelHeight`.
  - Clamped to `[Formex.LayoutGridSize, Formex.LevelHeight]` and snapped to `Formex.LayoutGridSize`.
  - `0` or negative values are treated as unset.
- Split heights:
  - `resolveSplitHeight` clamps to `[Formex.LayoutGridSize, height - Formex.LayoutGridSize]`.
  - Returns `0` if split is invalid or wall height too short.
- Materials and colors:
  - `resolveSideMaterials` and `resolveSideColors` reconcile legacy fields, top/bottom values, and defaults.
  - Missing colors fall back to white.
- Deletion shortcut:
  - Edit with zero-length (`Start == End`) removes the wall.

### Floors
Floor changes normalize:
- `RaiseHeight` via `resolveRaiseHeight` (clamped to `0..LevelHeight-InterfloorHeight`, snapped to `Formex.GridSize`).
- Colors default to white and inherit when missing.
- Materials are carried forward when omitted in edits.
- Points are validated later by `Formex.Floors.IsValid`.

### Objects
Object normalization uses `normalizeObject`:
- `resolvePrefab` uses `PrefabName` (or `Prefab.PrefabName`) to fetch a prefab.
- Side is normalized via `Formex.Objects.ResolveObjectSide`.
- Mount-specific rules:
  - `Door`: `Y` forced to `0`, rotation forced to `0`.
  - `Window`/`Wall`: `Z` forced to `0`, rotation forced to `0`.
  - `Floor`/`Ceiling`: position `Y` is computed from floor/ceiling surfaces.
  - Other mounts clear `WallId`.
- Design data is ensured with `EnsureDesignDefaults`.
- `IsPortal` is set based on `Door`.

## Validation
### Wall validation
`validateWallGeometry` checks:
- Start/end exist and length > `EPSILON`.
- Line is within unlocked plot segments.

`validateWallIntersections` checks:
- Uses `isWallIntersectionDisallowed`:
  - Colinear overlaps are disallowed.
  - True intersections are disallowed.
  - Shared endpoints are allowed.

### Floor validation
`Formex.Floors.IsValid` checks:
- Cleaned polygon has 3..`MaxFloorPoints` points.
  - Positive area.
  - Simple polygon.
  - Each edge within unlocked plot segments.

### Object validation
`isObjectValid` checks:
- Wall mounts:
  - Wall exists.
  - Position.X inside wall length.
  - Object height fits within wall height above the floor.
  - Doors force elevation `0`.
- Floor/Ceiling mounts:
  - Must sit over an existing floor at that position.
- Others:
  - Position must be within unlocked plot segments.

Invalid objects:
- Structural transactions: invalid objects are removed (recorded in `RemovedObjects`).
- Object-only transactions: any invalid object invalidates the transaction.

## Wall Merging (Overlap Resolution)
`mergeWallsForLevel` is called when structural changes occur:
1. **Collect segments**
   - Each wall contributes a segment.
2. **Split segments**
   - `Formex.Poly.SplitSegments` splits at intersections.
3. **Detect overlaps**
   - For each split segment, all contributing walls are collected.
   - Any segment with multiple contributors is added to `MergeSegments` for preview.
4. **Assign wall IDs**
   - Reuse the lowest unused contributor `WallId` when possible.
   - Otherwise, allocate from `nextId`.
5. **Resolve wall geometry**
   - Orientation follows the primary wall's direction.
   - Height is the maximum contributor height.
   - Front/back materials, colors, and split heights are inherited from a "best" contributor:
     - Preference: walls with connected rooms, then taller walls, then lower IDs.
6. **Rebuild wall table**
   - `levelData.Walls` becomes the new wall map.
   - Updated/added/removed lists are returned.

### Object reattachment after merge
`reattachObjectsToMergedWalls`:
- Projects each object's old wall position into world space.
- Finds a new wall segment containing that anchor.
- Updates `WallId` and `Position.X`.
- Flips `Side` when wall direction reverses.
- Clears `WallId` when no matching wall exists.

## Object Collisions
`collectObjectCollisions`:
- Builds AABB bounds per object.
- For wall mounts, bounds are placed using wall basis and side.
- Collisions are resolved:
  - Portals (doors) are preferred over non-portals.
  - Otherwise, lowest numeric `ObjectId` survives.

Collision handling:
- **Object-only transaction**: any collision invalidates the transaction.
- **Structural transaction**: colliding objects are removed and recorded.

## Options
`TransactionOptions`:
- `Commit` (default true): write changes into `plotData`.

## Task List (Implementation Issues)
If these are still present in the code, they should be fixed:
- `resolveSideForSource` in `mergeWallsForLevel` always finds the wall in `frontCandidates` first, even when resolving the back side. This likely picks the wrong side for the back face. Consider passing the candidate record (or choosing from the correct list based on side) instead of searching both lists in a fixed order.
