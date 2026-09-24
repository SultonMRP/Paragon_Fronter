# Paragon_Fronter — agent notes (3.3.5a)

Read with `D:\Warcrafts\Aethro\Interface\AddOns\agent-global.md`.

Maintained companion for launcher-owned **AethroParagon**. Do not edit `AethroParagon`. The launcher can restore it.

**Live version:** 1.2.2  
**Status:** Confirmed working in-game with Bartender, including a full client restart. Window raise, XP-bar rescue, config panel, fill redraw `0.2`–`1.5`, and **Show XP Bar** persist/sync (Fronter checkbox + their Paragon checkbox) all work. Panel layout may still be tweaked.

## Why this exists

Their main window `UIParagon` (`AethroParagon\Paragon\UIParagon.xml`) has no `frameStrata` (default `MEDIUM`) and no `toplevel`. `UIParagon_OnShow` only hides Blizzard micro-button panels. `AethroParagon.lua` uses a plain `:Show()`. Other addons on `HIGH` / `DIALOG` draw over it. The author blamed other addons; the missing raise is in their frame. Work around it here.

Their extra `ParagonExpBar` (`ParagonExpBar.xml` / `ParagonExpBar.lua`) is parented to `MainMenuBar`. Bartender hides `MainMenuBar`, so their checkbox (`paragonShowMainMenuXP`) can `:Show()` the bar and it still never appears. Position and size are also hardcoded. Work around that here too.

## Files

- `Paragon_Fronter.toc` — folder name must match TOC (`Paragon_Fronter`)
- `Paragon_Fronter.lua` — watcher, OnShow wrap, XP bar rescue, config panel, slash
- This file

## Load order

`## OptionalDeps: AethroParagon` so we load after them when both are enabled. We still start a watcher if they load later. If `UIParagon` is missing at `PLAYER_LOGIN`, chat prints to enable AethroParagon and `/reload`.

## How it works

1. **Watcher** — `OnUpdate` polls `_G.UIParagon:IsShown()` every 0.05s. Hidden → shown starts a front hold. This catches any open path (slash, micro button, other callers). Also re-rescues `ParagonExpBar` if the CVar is on and the bar is not visible or not parented to `UIParent`.
2. **OnShow wrap** — `GetScript("OnShow")` then `SetScript` so their `UIParagon_OnShow` still runs, then we raise. Used because 3.3.5 widget `:Show()` is not a reliable `hooksecurefunc` target.
3. **Front hold** — `SetToplevel(true)`, `SetFrameStrata` (default `DIALOG`), `Raise()`. Repeats for **0.25s** (`HOLD_SECONDS`) so other addon OnShow handlers do not steal the top slot. During the hold, the watcher ticks every frame.
4. **Their slash** — `hooksecurefunc(SlashCmdList, "AETHROPARAGON", ...)` after login as a backup if `/paragon` is used.
5. **XP bar rescue** — `hooksecurefunc` on `ParagonExpBar_UpdatePosition` and `ParagonExpBar_Update`. If `expBar.show` is true, reparent to `UIParent` and `:Show()`. If it is false, `:Hide()`. Do not rescue from `UIParagon_UpdateMainMenuXPVisibility` — that ran before we saved the new click and put the bar back.
5b. **XP bar show persist** — source of truth is `ParagonFronterDB.expBar.show`, toggled by our config **Show XP Bar** (`/pfront config`). Their Paragon checkbox is hooked and kept in sync, and we still `SetCVar("paragonShowMainMenuXP")` so their UI matches. That CVar does not survive a restart. `/pfront reset` does not clear show.
6. **XP bar layout** — after their position math (`BOTTOM` → `ReputationWatchBar` or `MainMenuBar` `TOP`, original `x = 0`, `y = -2`), apply saved `ParagonFronterDB.expBar`. Always from that original point and size (`1024 x 11`, four 256px chrome textures, status height `8`), never from the live frame. Re-applied on load, hooks, slash, and the config panel. Horizontal scale is width only. Vertical scale is height only. There is no 3.3.5 `SetScaleX` / `SetScaleY`. After a width change, poke the StatusBar texture and `SetValue` again — 3.3.5 does not redraw the fill on `SetWidth` alone.
7. **Config panel** — Lua-only `ParagonFronterConfig`. Stock WotLK dialog backdrop, `InputBoxTemplate` boxes, **Show XP Bar** (`UICheckButtonTemplate`), `UIPanelButtonTemplate` Reset, `UIPanelCloseButton`. Strata `HIGH` so it does not fight the Paragon `DIALOG` raise. Default dock `TOPLEFT` of `UIParent` (`16, -160`). Movable, `SetClampedToScreen`, position saved per character. Escape closes via `UISpecialFrames`. Independent of `UIParagon`. Open with `/pfront config`. Apply a box on Enter or focus lost.

Do not hide other addons. Only change Paragon’s strata / toplevel / frame level, and `ParagonExpBar` parent / points / size / show.

## Saved variables

`ParagonFronterDB` is per-character (`## SavedVariablesPerCharacter`). Different characters can have different bar addons and offsets. Do not init it at file scope; wait for `ADDON_LOADED`. An old account-wide `SavedVariables` file is unused.

- `strata` — `HIGH`, `DIALOG` (default), or `FULLSCREEN_DIALOG`
- `expBar.x` — horizontal offset from original `0`, default `0`
- `expBar.y` — vertical offset from original `-2`, default `0` (this is `/pfront xpvoffset`)
- `expBar.width` — horizontal scale, default `1` (`1024 * width`). Clamped `0.2`–`3`
- `expBar.height` — vertical scale, default `1` (`11 * height`). Clamped `0.2`–`3`
- `expBar.show` — their main-interface XP checkbox. 3.3.5 does not persist `paragonShowMainMenuXP`
- `xpvoffset` — kept in sync with `expBar.y` for older 1.1.0 values
- `panel.point` / `panel.relPoint` / `panel.x` / `panel.y` — config window position

Positive Y moves the XP bar up, negative Y moves it down.

## Slash

- `/pfront` / `/paragonfronter` — raise Paragon now
- `/pfront config` — open/close the XP bar options
- `/pfront reset` — stock XP bar **and** stock config dock, then show the config window
- `/pfront status` — window strata plus exp bar shown/visible/parent/cvar/x/y/w/h
- `/pfront high` | `dialog` | `fullscreen_dialog`
- `/pfront xpvoffset` — print current vertical offset (`offset set to <number>`)
- `/pfront xpvoffset 40` — +40 from original
- `/pfront help`

Panel **Reset** button resets the XP bar only (offsets `0`, scales `1`). It does not move the options window.

`/pfront reset` is the panic button if the config window is lost. If the saved panel point is off-screen, opening `/pfront config` also snaps it back to the default dock.

If some addon still covers Paragon after a confirmed open, try `/pfront fullscreen_dialog`. Do not raise the default unless needed.

Their checkbox in the Paragon window still toggles the extra XP bar.

## Non-goals

- Do not patch `AethroParagon`, `UIParagon.xml`, `ParagonExpBar.lua`, `ParagonExpBar.xml`, or `Paragon_Interface.lua`.
- Do not register `UIParagon` as a Blizzard UI panel.
- Do not fight other addons by hiding them.
- Their Paragon checkbox is optional; Fronter’s **Show XP Bar** is the one that persists.
- Do not parent the config panel to `UIParagon`.
- A leftover `AethroParagonFront` folder was removed; this addon is the only companion.
