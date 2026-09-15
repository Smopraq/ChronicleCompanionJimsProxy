# Chronicle Companion for Jim'sProxy 1.14.2

This tree targets WoW Classic Era 1.14.2 on Kronos 1.12.1 through Jim'sProxy. The current local tree is authoritative.

## Production scope

- Loaded providers: Reset, Zone, Header, PlayerList, Loot, RaidGroup, and Meta.
- PlayerList emits identity, gear, self talents, guild, pet, and honor data. Peer talents, glyphs, arena teams, and vehicle data are unsupported.
- The advanced combat log supplies ordinary combat and location data. Do not duplicate those events through Relay.
- Relay transport, framing, chunk size, provider ordering, and landing confirmation are runtime verified. Preserve them unless new runtime evidence proves a defect.
- Keep the shared combat-log controller as the only source of logging state for Settings, Relay Monitor, and the minimap control.

## Compatibility rules

- Prefer documented Classic Era APIs. Current raid code uses `IsInRaid()`, `GetNumGroupMembers()`, `GROUP_ROSTER_UPDATE`, and `GetRaidRosterInfo()` with intentional legacy fallbacks where present.
- Peer inspection completes through `INSPECT_READY`; self talents use the Classic Era single-spec talent APIs.
- Do not add peer-talent, glyph, arena-team, vehicle, officer-chat, or EPGP-specific capture.
- Preserve Chronicle wire formats and parser-facing identifiers.

## Identity and files

- The display name is `Chronicle Companion for Jim'sProxy 1.14.2`.
- Preserve the internal `Chronicle` namespace, `ChronicleCompanionJimsProxy` addon identifier, `ChronicleCompanionJimsProxyDB` and `ChronicleCompanionJimsProxyCharDB` SavedVariables, provider IDs, and existing module paths.
- The TOC targets Interface 11402. Keep TOC paths with backslashes and store the TOC as ASCII with CRLF line endings.
- Keep Lua source ASCII-compatible.

## Development

- Temporary probes, validation harnesses, synthetic tests, diagnostic wrappers, and their slash commands are not part of the release build.
- Add production modules to the TOC in dependency order. Do not load diagnostic-only files.
- Keep changes small and source-driven. Do not modify game logs, WTF data, or reference addons.
