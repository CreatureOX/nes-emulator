# Changelog

All notable changes to this project are documented in this file.

The format follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions use `MAJOR.MINOR.PATCH`: `MAJOR` for incompatible API changes,
`MINOR` for backward-compatible features, and `PATCH` for backward-compatible
fixes. Versions below `1.0.0` are initial development and make no stability
commitment.

## [0.1.0] - 2026-11-25

First distributable release. The core emulation is cycle-accurate and passes
the full CPU/PPU test-ROM gate; this version adds the player-facing features
and release metadata needed to ship it.

### Added

- Region profiles: NTSC, PAL and Dendy timing parameters injected into CPU,
  PPU, APU, DMC and noise through a single `RegionSpec`, selectable from the
  Config menu.
- Save states with version, magic and SHA-256 integrity checks, plus rewind,
  fast-forward, fullscreen and CRT filter in the Emulation menu.
- Complete APU channel set: pulse, triangle, noise and DMC, a post-DAC filter
  chain, band-limited resampling to 44.1 kHz, and MMC5 expansion pulse and PCM.
- NES 2.0 cartridge support and iNES mapper coverage for 20 boards, including
  5, 7, 9, 10, 11, 13, 22, 28, 34, 64, 69, 78, 118 and 180.
- Downloadable Windows and macOS bundles published from tagged releases.
- Golden audio regression harness recording sample-by-sample baselines.
- Menu mnemonics, shortcut hints and F11/F12 bindings for the player controls,
  plus Escape to pause and resume emulation.
- Version metadata in `pyproject.toml`, shown in the About dialog.

### Changed

- Removed per-dot Python object churn on the CPU, PPU, APU and bus hot paths:
  status flags are C fields, pixel and IRQ values are packed integers, APU
  step tables are C arrays, and frames blit directly into the SDL surface.
  Frame work dropped from about 22 ms to 13 ms without changing timing,
  register semantics, save-state format, image or audio quality.

### Fixed

- Cross-region save-state loading now derives the CPU divider phase from the
  current PPU dot instead of carrying a stale phase over.
- APU pulse period and duty stepping, DAC reconstruction, and DMC output mixing.
- MMC5 PCM output and IRQ semantics, scanline IRQ timing, and colour emphasis.
- Shared OAM/DMC DMA cadence and cycle-stealing behaviour.
- Controller input ordering to A, B, Select, Start.
