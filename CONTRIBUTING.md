# Contributing

## Setup

The addon lives in `Quarry/`. Link it into the client instead of copying (PowerShell; adjust `$wow`):

```powershell
$wow = "C:\Program Files (x86)\World of Warcraft\_forever_"
New-Item -ItemType Junction -Path "$wow\Interface\AddOns\Quarry" -Target "$PWD\Quarry"
```

`/reload` picks up changes, new files included.

## Layout

| Path | |
|---|---|
| `Quarry/Core/` | Namespace, events and the message bus (`Init`), settings and saved variables (`Defaults`, `DB`), the wanted-mob list (`Targets`), the macro text (`Macro`) and Tracking's nameplate scan (`Scanner`) |
| `Quarry/UI/` | Widgets (`Widgets`: the key-capture button, dropdown and menu from Jest, the segmented control from Needy), the Tracking panel and its secure button in full and minimal styles (`TrackerButton`) and the settings window (`Window`) |
| `Quarry/Config/` | Minimap icon and slash commands |
| `Quarry/Bindings.xml` | Key bindings (auto-loaded; labels set in `Core/Init.lua`) |
| `tools/` | The icon generator |
| `tests/` | Offline tests that run the addon against a mocked WoW API |

How it fits together:

- `Targets.Quest` picks one quest: the super-tracked one, else the first unfinished quest in tracker order. `Targets.Collect` lists the mobs it still wants, one entry per name, those spawning in your zone first.
- Where the mobs come from:
  - With QuestieDB loaded, `LibQuestieDB` (its public library, contract 4) gives each quest's creature and kill-credit objectives, and `npcDrops` for item objectives. Its spawn data decides "in your zone".
  - Without it, kill objectives are parsed from the quest log text and loot quests are skipped.
  - Objectives the log shows as finished are left out, matched by name.
- `Macro` builds the text: `/cleartarget`, a `/targetexact` line per mob (most wanted last so it wins), `/cleartarget [dead]`, then `/tm [harm,nodead] !N`. It's cut to fit 255 characters.
  - Clearing first means it never keeps, or marks, a non-quest target you had before.
  - `/tm !N` (Forever's `TARGET_MARKER` handler) skips a unit that already has that marker, so pressing again never clears it.
- The text goes to two places: the `Quarry` macro, and the `macrotext` of `QuarryTrackerButton` (a `SecureActionButtonTemplate` on the Tracking panel, bindable as a `CLICK` binding). Its right-click is the custom type `tracking` (`type2`), which the template runs as the button's `tracking` method, as Jest's `jest` type does. Both are only changed out of combat, and only when the text changes.
  - The macro is per character if there's room, otherwise account-wide. Nothing is written until 2 seconds after the first loading screen, so macros have loaded and no duplicate gets made.
- Addons can't target or set raid markers themselves on Forever (or run a macro on a timer). The player's click or key press does it. RXP's `TargetUnit` proximity trick is off on modern clients too.
- `Scanner` (Tracking) is report-only: once a second, and on `NAME_PLATE_UNIT_ADDED` and `RAID_TARGET_UPDATE`, it reads enemy nameplates, target and mouseover for a live, attackable mob on the list. It raises `SCAN_UPDATE`, which the panel uses for its status and glow. Alerts go to `UIErrorsFrame`, where quest progress shows: "nearby" (with the chosen sound from `ns.SOUNDS`, at most every 30 seconds per name) and "marked" (once per GUID).

The source of truth for Blizzard's side is the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source).

## Tests

```powershell
python -m venv .venv
.venv\Scripts\pip install -r requirements-dev.txt
.venv\Scripts\python tests\check.py   # Lua 5.1 syntax, and backslash escapes Lua would drop
.venv\Scripts\python tests\smoke.py   # loads the addon against a mocked API and exercises it
```

CI runs both on every push and pull request, and builds the release zip without uploading it (see the run's artifacts).

## Generated files

- `Quarry/Media/icon.tga` and `assets/logo.png`: the addon icon, from `tools\gen_icon.py` (source art `assets/bullseye.png`, CC BY 3.0, see README).

## Debugging

- `/quarry debug` for Quarry's own messages.
- `/console scriptErrors 1`, or BugSack, to see Lua errors.
- `/dump LibQuestieDB.Quest.Get(<questID>, "objectives")` to see what QuestieDB has for a quest.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) from `.pkgmeta`. The TOC's `@project-version@` is replaced with the tag.

1. Update `CHANGELOG.md`.
2. Tag and push, e.g. `git tag v0.1.0-beta && git push origin v0.1.0-beta`. Tags containing `alpha` or `beta` are published as that release type.

Uploading needs the repository secrets `CF_API_KEY` (CurseForge) and `WAGO_API_TOKEN` (Wago), plus the project IDs as `## X-Curse-Project-ID` and `## X-Wago-ID` in `Quarry/Quarry.toc`. Without them, the release is only attached to GitHub.
