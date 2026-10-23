# ADR-0004: Ship delta resource packages beside full packages

## Status

Accepted

## Date

2026-10-23

## Context

Players download every resource update from a cloud drive as a full package
from `Dey410/extract-pvzge-gpnext`: about 520 MiB compressed and 1 GiB
unpacked in 8,500 files. Most files survive an update unchanged. Comparing the
real pipeline outputs:

- 0.14.0 to 0.15.0: 274 files are new, 21.6 MiB compressed. The other 8,247
  files exist in 0.14.0 with the same SHA-256.
- Two 0.15.0 builds from different producer commits: one file differs. The
  ASTC encoder and the other tools reproduce their output byte for byte.

Each indexed package already carries `file-index.json` (path, size and SHA-256
of every file) and its identity, `packageId`: `sha256:` plus the SHA-256 of
`resource-manifest.json`, whose `fileIndexSha256` pins the index.

CI artifacts expire after seven days, so they cannot record which package
players hold.

## Decision

The exporter publishes two packages per release; the loader imports both
through the one ZIP import entry.

- **Full package.** Unchanged. Its marker is its `packageId`.
- **Delta package.** The files whose SHA-256 is absent from the base package's
  index, the full package's own `resource-manifest.json` and `file-index.json`
  byte for byte, and `docs/__gardendless/package/delta.json`:
  `{"schemaVersion":1,"basePackageId":"sha256:…"}`. One delta has exactly one
  base.
- **Base.** The newest GitHub Release of the exporter, by creation time. The
  workflow input `publish` (default off) creates a Release named
  `<gameVersion>+<first 8 hex of packageId>` with
  `GardendlessResources-<tag>.zip` and
  `GardendlessResources-<tag>-from-<base tag>.zip`. Publishing a `packageId`
  that already has a Release fails; old Releases are never deleted
  automatically. Runs without `publish` keep both packages as seven-day
  artifacts. `release_tag` is required and names the run
  (`0.15.0 · 测试` / `0.15.0 · 发布`).
- **CI proof.** Before upload, CI verifies the base and the new full package,
  checks that the delta's metadata equals the full package's, that every
  delta file matches the index, that every omitted file's SHA-256 is in the
  base index, and that nothing unindexed rides along.
- **Native extractors.** A directory holding
  `__gardendless/package/resource-manifest.json` is a docs root even without
  `index.html` and the runtime layout, because a delta carries only changed
  files.
- **ImportService.** After native extraction and before validation, a
  candidate with `delta.json` must name the active `packageId` as its base;
  otherwise the import fails with `delta_base_mismatch`. Every indexed file
  missing from the candidate is copied from the active slot file with the same
  SHA-256, `delta.json` is deleted, and the unchanged validator hashes every
  file. A completed delta is byte-identical to the full package, so the next
  delta applies whichever way a player got there.
- **Identification.** Technical details shows `packageId`, or 「这不是加载器优化包」
  for packages without an index. Its first 8 hex digits match the `from`
  part of a delta's file name.

## Alternatives considered

- **Reuse by path and digest.** Content addressing reuses files that moved,
  at no extra cost.
- **Deltas without a marker**, filling any missing indexed file. Implicit
  completion would hide a wrong base until a file turned out missing; the
  marker states the base and gives a precise error.
- **A marker inside `resource-manifest.json`.** The delta's manifest would
  differ from the full package's and change its `packageId`, breaking the
  next delta.
- **Anchor files in every delta** so the old native docs-root rule still
  matches. It ships unchanged files only to satisfy a detection rule.
- **Base from a run ID or a committed index.** Artifacts expire in seven days
  and a committed index needs a manual step after each upload.
- **Hard links instead of copies.** Copies need no native code; disk use
  equals a full import, which already keeps two slots.

## Consequences

- An update to the next published package downloads about 4% of a full
  package. Players further behind, or on packages from other sources, import
  the full package.
- Copying and hashing the reused files still costs about as much local I/O as
  a full import.
- GardendlessLoader 0.9.x rejects delta packages with a misleading error
  (`zip_docs_missing` or an extra reserved file). Release notes say a newer
  loader is needed.
- Releases of the exporter are public and persistent; this supersedes "no
  automatic publishing" in `resource-release-pipeline-design.md`.
