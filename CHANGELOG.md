# 0.4.45

- Fix the camera not moving when a left or right drag starts on a nameplate, and a click on a nameplate not selecting the unit. Nameplates are compact unit frames, so the mouseover key handler was installed on them as on party and raid frames; that turned their mouse on (Blizzard keeps it off and hit-tests plates in the engine) and the plate swallowed the press. Nameplates are no longer registered as mouseover frames. Mouseover keys therefore no longer act on nameplates (they still act on unit frames).

# 0.4.44

- Rule menus (a card's rule chips, the "+" Add condition button and the CARD RULES controls) now use BindCards' own popup, the one the card "•••" menu already uses, instead of Blizzard's context menu. Blizzard's menus run the gamepad focus manager under addon taint, which could leave A/B dead until a reload. Same entries; Escape, a click elsewhere or the same chip again closes them.
- Removed dead code: the BindPad blocker setting (`suspendBindPad`, never reachable from the UI), the always-on experimental toggles (their saved keys are dropped by a schema 4 migration; the previous save is kept in the backup) and the retail role/activity (Skyriding) rule paths. Saved cards that still carry such a rule load as before: the repair drops them, as it already did.
- PvP rule: on clients with `PLAYER_PVP_FLAG_CHANGED` (70338+) `PLAYER_FLAGS_CHANGED` is no longer registered as well (it also fires for AFK/DND and caused a needless recompile). Older clients keep the old event.

# 0.4.43

- Live client (1.60.1.70707) review. Racial detection checked against the launch racials: no active racial was added, removed or renamed since the beta list, so new characters on live get the same two racials per race. The Skyborne leyline racial is also matched under its "Read Leyline" spelling.
- Fix a racial that carries a rank label (e.g. "Rank 1") teaching that label as "racial", which would have added every rank-1 class spell to the character card.
- Mouseover: the list of Blizzard unit frame names is built once instead of on every binding apply.
- README: live install path and client build.

# 0.4.42

- Build 70338: the PvP condition also recompiles on the new `PLAYER_PVP_FLAG_CHANGED` event (Blizzard's player frame now uses it instead of `PLAYER_FLAGS_CHANGED`).

# 0.4.41

- Racial detection now reads the spellbook's own "Racial" label, so Forever-specific racials (e.g. Human Will to Survive) are found. The race ability list and the classic racial table still add what they know; the label also works on translated clients. A list of Forever's active racial names (from Wowhead's Forever racials guide, pre-release) is a fourth source, matched in your spellbook. It covers the new Skyborne racials (Walk on Air, Read Ley Line, Skysight).
- Character card **••• → Add racial abilities** adds any racial missing from the card (racials are otherwise only added once, when the card is created). Racials already on the card or its subcards are not added again.

# 0.4.40

- Blizzard Legacy: unselected active tab marks are darker (50% of the class accent instead of 70%).

# 0.4.39

- Blizzard Legacy tab marks: the selected tab uses your class accent, and unselected active tabs a deeper shade of it (0.4.38 had them the other way round).

# 0.4.38

- Blizzard Legacy: the selected card tab's bar is a deeper shade of your class accent instead of cream. Other skins keep their contrast color.

# 0.4.37

- Fix accent bars on card tabs and page edges showing a darker, orange-red version of the accent while the tab dots showed the right color. Those bars were painted in the accent and then tinted with it again, which squares the color. They now show exactly the accent, like the dots. Affects every skin, most visibly Legacy with class colors.

# 0.4.36

- Fix a card still going under the binder pages while you drag it. The window is top-level, and a click on one of its tabs raised it above any level a dragged stack could hold. The dragged stack (page, sheets and tabs) is now lifted into a higher layer for the drag and put back on drop or cancel.
- Binder mode: the see-through area around and between the pages lets the mouse through to the world. You can rotate the camera or click the world there. The mouse wheel zooms the camera unless the binder is long enough to scroll. Silhouettes pass clicks through except their top strip, which still switches binder. The header still moves the window. Panel mode is unchanged.
- Silhouettes always stick out of the open page (the next binder protrudes on the right) and reach at least its bottom. Before, the character silhouette sat inside the class page and its edges showed through as stray lines.

# 0.4.35

- Blizzard Legacy: the class-colored active marks are softened toward the skin's bronze (45%), so bright class colors like Paladin pink no longer stand out on the brown and gold. The class hue stays recognizable.

# 0.4.34

- Fix a detached card or stack drawing under the docked binder pages while you drag it back. Floating and dragged stacks now always sit above the docked pages, even when the window has been raised to a high level.
- The "Return to main binder" drop area is shown above the docked pages during a drag, still under the stack you are dragging.

# 0.4.33

- Every other docked binder now shows as a silhouette behind the open one, in cascade order: with the character card open you see both General and class behind it.
- Remove the short stray line next to each docked card's right edge (a leftover connector from an older tab layout).

# 0.4.32

- The character card continues the binder cascade: its page sits one step right of the class page (General, class, character), with the class page showing behind it.
- The character card's icon is your character's portrait, as on the player frame, on the tab, the card and its tabs.

# 0.4.31

- Blizzard Legacy skin: the "active" marks (tab dots, the bar on active card tabs, Active labels) use your class color instead of green. Gold stays the selection color; other skins are unchanged.

# 0.4.30

- Fix the character tab showing an empty area instead of its card. The workspace only drew General and class cards.

# 0.4.29 — Editable build cards

- Primary and Secondary can now be renamed, have their rules changed or removed, and be switched ON/OFF, like your own cards. They are still created for you and can't be deleted. The class, General and character cards stay fixed.
- Respec workflow: switch the old build card OFF (it keeps its spells and keys for later). Then add a new card with the rule **Build · Primary** or **Build · Secondary**, and use the same keys.
- Your edits survive the load-time check. Before, it put the original name, rule and ON state back on every load.
- BindCards opens the class tab on the build card that is actually active, e.g. your new Retribution card instead of a switched-off Holy card.

# 0.4.28 — Character card

- New third tab, named after your character, for anything that belongs to this character only: racial abilities, professions, toys. Each character gets its own card on first login.
- Racial abilities are added to it once, the first time; removing one sticks. BindCards reads your race's abilities from the game and matches them in your spellbook. It falls back to a list of the classic racials, and waits for the spellbook to load if needed.
- The character card's keys win over Class and General, so a racial can have a different key per character.
- **••• → Copy from…** on the character card replaces it with a copy of another character's card, tiles and keys included. Undo reverses it.
- The card is kept per character in the shared SavedVariables and survives the load-time data check. It can't be deleted or shared like a binding set.

# 0.4.27

- Fix spell tiles looking dark (unavailable) on a new or lower-level character when the tile is set to **Always use highest learned rank**. A shared class profile can store another character's higher rank (e.g. Seal of Righteousness Rank 2). The tile already cast the rank you know, but the dimming checked the stored rank. It now counts any learned rank for these tiles.
- Exact-rank tiles for a rank this character hasn't learned stay dim, since they really can't cast. When a lower rank is known, the tooltip now says so and points to **Right-click → Always use highest learned rank**.

# 0.4.26

- Fix a Lua error ("attempt to perform boolean test on a secret boolean value") when mouseover bindings were applied with a target selected. BindCards read the target frame's aura area, which the game keeps restricted. The error stopped the rest of the setup, so unit frames later in the list could miss their mouseover keys.
- BindCards now changes only the health and mana bars of unit frames. It no longer touches restricted parts such as the target's auras, or anything inside them.
- An error in the mouseover setup is still reported, but no longer stops the rest of your bindings from applying.

# 0.4.25 — Mouseover polish

- In mouseover mode, the Bind window lists the clicks Blizzard's own Click Casting still runs as spells or macros, e.g. "Blizzard Click Casting still uses: Shift-Left click". On Blizzard frames those clicks run before BindCards, so you can remove them before binding. Its Target and menu clicks aren't listed; they work alongside BindCards.
- The README's "Mouseover bindings" section is now complete user documentation, and the command list includes `/bc hover` and `/bc testframes`.
- The design notes mark the mouseover idea as done. PORT-VALIDATION starts with a status table: what's confirmed in game, and what still needs a group or a form class.

# 0.4.24 — Mouseover bindings on form cards

- Mouseover bindings on form and stance subcards now work: Druid forms, Warrior stances, Shadowform, Rogue Stealth. They switch with your form, also in combat, following the same form tracking as normal form keys. Child cards override the parent card's mouseover bindings, as for normal keys.
- Keys and the mouse wheel use the current form's bindings when the cursor enters a unit frame.
- Clicks: when a form changes what a click does, the frame under the cursor gets that form's click setup as you enter it, and again if you shift while pointing at it.
- Bindings that exist only on a form card are installed even while you're in another form.
- The tooltip names the forms where a form-card binding applies ("Active in Bear"). `/bc hover` shows the current form state.
- Known limit: if a unit frame appears under a cursor that doesn't move, it may use the previous form's click setup until the cursor moves.
- Classes without forms (e.g. Paladin) are unchanged.

# 0.4.23

- **Menu → Test unit frames** (or `/bc testframes`) opens a small movable panel of stand-in unit frames for testing mouseover bindings without a group: You, Target, Target's target, Focus and Pet.
  - They use Blizzard's own unit-button template, so clicks go through the same Forever path as party and raid frames.
  - Their health bars catch mouse movement like Blizzard's do.
  - Bars are tinted green for friendly and red for hostile; target an enemy to get a hostile frame.
  - Open or close it out of combat. It isn't built until you first use it.

# 0.4.22

- Fix mouseover keys not working over the player, target, focus and party frames. On Forever their health and mana bars catch mouse movement (for their hover text), so moving onto a bar counted as leaving the unit frame and released the keys. The key then fired its normal binding, e.g. Judgement's "I don't have a target". Mouse-catching parts of registered unit frames now pass movement through to the frame while keeping their own hover text. Nested unit frames (target of target) keep their own hover.
- `/bc hover`: point at a unit frame and type it to see the frame under the cursor, whether it has its key handler, and what each mouseover key is bound to right now.

# 0.4.21 — Mouseover keys and mouse wheel

- Keyboard keys and the mouse wheel (any modifiers) with a mouseover type now work while the cursor is over a unit frame. When the cursor enters a frame, BindCards checks whether the unit is friendly or hostile and claims only the matching keys. It releases them when the cursor leaves. Everywhere else, and over a frame of the other type, the key keeps its normal binding (including a BindCards key on another tile).
- A friendly- or hostile-only key beats a "both" key on the same unit, as for clicks.
- It works in combat, because the check runs in Blizzard's secure hover handlers. Binding edits and frames that appear mid-fight still wait for combat to end.
- If a unit frame hides under the cursor (the unit leaves), its keys are released through a mouseover check, so nothing stays bound.
- Hover keys no longer look like "missing" BindCards bindings to the conflict check, so hovering doesn't trigger rebinds.
- The tooltip reports "Active while the cursor is over a unit frame" per key.

# 0.4.20 — Mouseover clicks cast on unit frames

- Mouseover bindings on mouse buttons (left, right, middle, buttons 4–5, with any modifiers) now cast on unit frames:
  - Blizzard player, target, target-of-target, focus, pet, party and raid/party (compact) frames.
  - Addon frames that register through `ClickCastFrames`.
- Friendly bindings act on friendly units, hostile on enemies, and both on either. When both a specific and a "both" binding use the same click, the specific one wins.
- On a unit that doesn't match, the frame keeps its own click: plain Left still targets and Right still opens the menu. Modified clicks with no binding for that unit do nothing, as they do natively.
- Forever's frames check Blizzard Click Casting first, and a modified click (e.g. Shift-Left) with no Blizzard binding was silently dropped before any addon could act. BindCards marks those exact clicks so its casts go through.
- Only the attributes BindCards needs are written. Each one is backed up and restored when the binding is removed or its card goes inactive.
  - Frames that appear during combat get their bindings when combat ends.
  - When Clique is loaded, BindCards leaves unit frames to Clique.
- Tooltip status per binding: active, waiting for combat, card inactive, or Clique. Macro tiles need `[@mouseover]` to act on the hovered unit. Active mouseover bindings use the same key color as active normal keys.
- Not yet: keys and the mouse wheel while hovering (next update), and mouseover bindings on form subcards (they follow the card's base, no-form state for now).
- Shortcut labels shrink to fit inside the tile, measured by rendered width rather than character count, so modifier labels like `S-M2` no longer spill over the icon edge.

# 0.4.19 — Mouseover bindings (editing only)

- The binding capture window has a **Mouseover** row with **Friendly** and **Hostile** toggles. Turn on one or both, then press a key, click or wheel direction: the binding is meant to act only while the cursor is over a unit frame of that type. Plain left and right click can be bound here, with a confirmation because they replace Target and the unit menu on those frames.
- A tile keeps its normal key alongside one mouseover binding per type (friendly, hostile, both). Assigning a normal key no longer removes mouseover bindings, and the reverse.
- Tiles with a mouseover binding show a small bullseye in the bottom-left corner (the ability name shifts to stay clear of it): Evoker green for friendly, Death Knight red for hostile, split for both. The tooltip and side panel name the type; the key label is unchanged.
- In mouseover mode, right click is captured instead of clearing. **Clear** (and Backspace/Delete) removes only the selected type's binding. Controller gestures are disabled while a toggle is on.
- Saved as `HOVER:HELP:<key>`, `HOVER:HARM:<key>` or `HOVER:ANY:<key>`. Exports carry them; older BindCards versions reject such exports.
- **Not active yet.** Mouseover bindings are saved, exported and shown, but do not cast. They never install as global keys, so existing bindings behave exactly as before. Casting on unit frames arrives in the next update.
- Warn when Blizzard's own Click Casting already uses the same click. On Forever it runs before any addon on Blizzard unit frames.
- Fix BindCards always reopening on the Primary card after a reload or relog. The last open card was saved correctly, but the database check at load rebuilt each character's record without it. It is now kept, and a card that no longer exists still falls back to the active spec card.

# 0.4.18

- Skip the secure binding teardown and reinstall when a zone, subzone, PvP, spec or combat-end recompile produces exactly the bindings already installed. The fingerprint covers every key's prepared action, form routes and driver, BindPad-blocked keys and the key-down CVar; edits, pending combat work, migrations and `/bc rebind` always install.
- Drag highlights are skinned once instead of rebuilding their backdrop on every frame of a drag. The window resize grip runs per-frame code only while resizing.
- Remove the never-called template repair queue and the retired SavedVariables storage diagnostics (`/bcstorage`, `BindCardsStorageDiagnostics`). The pre-migration `BindCardsDBBackup` safety copy is kept.
- The keyboard-focus guard stays on its 10 Hz ticker while the window is open: it is the safety net that releases a stuck keyboard capture, and this client has no event that covers every case it handles.

# Unreleased

- Each character reopens BindCards on the card it last had open, remembered across logout and reload. It is saved when the window closes and at logout, not on every click. A missing card falls back to the current spec card. Changing spec no longer switches the open card.
- Spells dragged from the spellbook while **Show All Spell Ranks** is off now default to **Always use highest learned rank**, so learning a new rank upgrades the tile. Drags made with all ranks shown, lower-rank drags, and unranked spells stay exact. Existing tiles are unchanged.
- Fix spell options immediately disappearing on workspace right-click: skip the tile refresh that hid the menu's owner. Regression coverage exercises the actual click handler.

- Add spell tile rank options: preserve dragged ranks by default, opt into highest learned rank, or lock back to the current rank. Preserve the choice across reloads, schema-6 exports, macros, form routes, and native controller assignments.
- Keep an open BindCards editor visible when the spellbook opens through P, while retaining normal Escape closing.

- Replace the shared card menu with an addon-owned popup to avoid Forever's native gamepad-focus path when adding GENERAL or DRUID subcards. Preserve form choices, rename, detach/return, and delete actions. Lua 5.1/LuaJIT regression coverage passes; live gamepad verification remains required.
- Replace occupied gamepad slots using the native editor's clear-then-place sequence, validating pickup first and restoring the prior action if placement fails. Covers the Bar 1 D-pad Left Bear Form macro over an existing item; live beta verification remains required.
- Route form bindings through native secure attribute drivers so the same key changes actions in combat without the beta client's missing snippet compiler. Preserve exact spell ranks, macro bodies, target rules, and inactive-key blocking.
- Keep binding confirmations and profile transfer screen dimmers translucent in the Legacy skin instead of covering the screen with leather artwork.
- Use the resolved macro tooltip icon (or manual icon) when creating native gamepad macros. Reuse only macros with both matching text and icon, so old question-mark copies are replaced on the bar after reload. Existing macros are preserved; a replacement requires a free character macro slot.
- Native-storage regression passes under Lua 5.1 and LuaJIT, including icon propagation, old-copy preservation, reload reuse, manual icons and combat deferral. Live rendering still requires an in-game check.

# 0.4.17 — Native gamepad action storage

- Apply active controller assignments to their native page/layer slots outside combat, so native icons, cooldowns and execution share the same action.
- Restore original actions when assignments stop matching, with a per-character journal that survives reloads; honor later native edits.
- Leave reserved controls and unsupported original action types alone; defer changes during combat or while the cursor holds an action.
- Support spell/item actions and native macros; report rejected writes and macro limits instead of claiming inactive saves are active.
- Add `/bc gamepad off` for restoration before addon disable, and `/bc gamepad on` to resume.
- Mock-native regression checks pass; live beta casting, rendering and protected-action checks remain required. In-combat condition transitions are deferred, not secure form substitutions.

## 0.4.16 — Header menu workaround

- Replace the header's Blizzard context menu with an addon-owned popup to avoid the native menu/controller-focus path implicated by the Forever blocked-action warning.
- Preserve Display, ability-name and gather toggles, Profiles, and conditional Undo; close on outside click, Escape, or editor hide.
- Lua 5.1 and LuaJIT menu regression checks pass. Live blocked-action verification remains required.

## 0.4.15 — Gamepad bar selection

- Choose native gameplay Bar 1, 2 or 3 when capturing a controller shortcut; show the selected bar in binding labels and tooltips.
- Preserve bindings on other bars and allow the same combination on different abilities when their bars differ.
- Retain legacy all-page saves; recapturing an ability's controller binding narrows its legacy assignment to the chosen bar.
- Controller execution and native icon overrides remain inactive pending the native integration.

## 0.4.14 — Card reattachment and header layers

- Accept returning cards on the owning stack's tabs, visible page, exposed backing sheets, and top binder selector. The top selector no longer replaces the parent tab as a drop target.
- Keep the editor header and its controls above detached stacks and docked tabs; keep binder selectors above scrolled tabs.
- Defer queued data refreshes until a card drag finishes so the page does not jump back to its saved position mid-drag.
- Cover repeated Primary-to-Druid returns using the actual UI drop handlers and Core mutations. Live header rendering still needs in-game verification.

## 0.4.13 — Attached card clicks

- Keep attached class and build tabs above the Forever editor's DIALOG workspace so they receive clicks after the editor is raised.
- Parent attached tabs to the editor outside the scroll frame, preserving unclipped controls and inherited scale while following focus changes.

## 0.4.12 — Build card persistence

- Preserve Primary and Secondary template identities when detaching a card adds its inherited class condition. Reloading no longer replaces that card with another generated build card.
- Cover repeated database reloads with detached and reattached build cards, keeping unrelated custom cards separate.

## 0.4.11 — Spellbook layering

- Remove the spellbook drag handle and tooltip.
- Raise the editor and embedded cards to DIALOG strata while retaining the Spells button's keep-open behavior.
- Leave spellbook positioning to Blizzard or a dedicated window-management addon.

## 0.4.10 — Spellbook workspace

- Keep BindCards open after its Spells button opens Blizzard's spellbook.
- Add a title-area drag handle for moving the spellbook outside combat, without replacing its buttons or panel management. Blizzard retains placement on later panel layout changes.
- Verify editor restoration and movement with focused Lua smoke tests; in-game controller and taint checks remain manual.

## 0.4.9 — Native spellbook click

- Restore the Spells button using Blizzard's out-of-combat action-button template and native micro-button delegation.
- Retain native-control guidance for combat and unavailable controls. Avoid addon-owned spellbook toggle calls and protected editor ancestry.
- Requires live beta verification; this does not establish the exact cause of the earlier block.

## 0.4.8 — Forever spellbook safety

- Remove the direct spellbook-toggle call that triggers a Blizzard-only-action block in controller mode.
- Spells? now displays the current native spellbook binding or controller/micro-menu instructions. Direct opening from BindCards is unavailable in this build.

## 0.4.7 — Forever storage diagnostics

- Add bounded startup and current profile/card counts through `/bcstorage` to investigate reload resets without changing stored profiles.
- No root-cause persistence fix is claimed by this diagnostic build.

## Earlier Forever beta changes

- Capture LT, RT or both plus face/D-pad buttons on existing ability cards, with readable controller labels and explicit all-gameplay-pages scope.
- Preserve keyboard bindings when adding controller shortcuts and retain gestures through exports and reloads.
- Mark controller shortcuts as saved, not active; exclude them and legacy PAD keys from live overrides and secure form bindings until native navigation ownership and effective bar icons can be guaranteed.
- Repair UTF-8 symbols in the beta UI so buttons, counts and condition labels render correctly.
- Target Interface 16001 with separate Forever exports.
- Add Primary/Secondary build cards, sparse Classic class enumeration, Warrior stances and distinct aquatic form.
- Preserve exact spell ranks in secure bindings and rank-qualified macro conversion.
- Retain the bundled interface and out-of-combat binding ownership rules.

# Changelog

## Unreleased

- Deferred keyboard cleanup during combat until lockdown ends, preventing
  blocked calls when opening the editor or pausing an active interaction.
- Prevented a card drag's mouse-up from toggling an ear chevron after the
  returned stack reflows beneath the cursor; deliberate expand/collapse clicks
  remain unchanged.
- Brightened Xbox 360 selection and primary controls to yellow-green with
  dark labels, retaining its light shell and readable darker status text.
- Slightly darkened and desaturated Xbox surfaces while preserving its green accents.
- Refined PS2 with neutral charcoal plastics, restrained indigo selection,
  and smaller blue/cyan accents instead of navy surfaces and bright blue fills.
- Deepened Genesis to neutral black surfaces, warm dark-red selected controls,
  and silver active accents instead of raspberry and gold.
- Retuned PS1 toward cool medium-grey plastic and graphite selected controls,
  replacing the near-white body and large navy-blue fills.
- Added GameCube, Genesis, PS1, PS2, Xbox, and Xbox 360 appearances immediately
  after Famicom, with contrasting selected tabs and readable icon labels.
- Refined Super NES with neutral grey plastics, lavender controls, and deep
  purple selection; refined Famicom with ivory surfaces and oxblood selection.
  Both use contrasting primary-button text, opaque ears, and light spell labels.
- Refined Chalk, Tungsten, and Editorial with clearer selected tabs, opaque
  unselected ears, higher-contrast secondary text, quieter controls, and light
  outlined spell names over artwork.
- Refined Violet Bloom tab hierarchy: only the selected tab is magenta;
  unselected ears use opaque dark surfaces, light labels, and mint active cues.
- Added Violet Bloom, a bolder Violet Mist variant with solid magenta tabs,
  mint header/panel surfaces, and berry controls. Violet Mist is unchanged.
- Added Violet Mist: black-violet surfaces, soft-magenta selection, mint active
  states, dusty-violet secondary controls, and red-mist text.
- Fixed Appearance menu layering so it stays above cards but below profile and
  confirmation windows; opening a dialog dismisses the menu. The menu is now
  independently hosted, with explicit layers for all of its controls.
- Fixed theme-dependent editor contrast, disappearing close-button surfaces,
  and dropdown arrows disappearing after an Ellesmere repaint.
- Fixed stale binder widths after auto-fit, overlapping narrow-card header
  controls, and non-left clicks starting resize gestures.
- Guarded drag cancellation during workspace refresh and first-time editor
  construction during combat.
- Inactive form-only keys now do nothing instead of triggering an unrelated
  underlying binding. Skyriding-only keys still retain normal ground controls.
- Guarded form resolution when class information is temporarily unavailable.
- Fixed exact-ID abilities such as Oppressing Roar, Aerial Halt, and Second
  Wind by passing their IDs as strings. Numeric secure spell attributes are
  spellbook slots, which made these abilities silently target invalid slots.

## 0.4.5 — 2026-08-28

- Promoted binder relationship strings, the card color pass, and card paper
  sizing to permanent features. They are always enabled and no longer appear
  as experimental options in the Menu.
- Replaced unsupported card drag and resize glyphs with Frame Gambit's compact
  four-dot handle and Blizzard's reliable corner-grip artwork.

## 0.4.4 — 2026-08-28

- Restored Ellesmere's historical layered shell depth by repainting native
  BindCards backdrops before the facade reasserts its translucent panels,
  brown atlas artwork, header/footer bands, and atlas frame.
- Reasserted shell texture visibility during live appearance changes so a
  prior restrip cannot leave the Ellesmere artwork transparent.
- Kept the Display appearance panel above docked and floating card ears so its
  controls and background cannot be covered by the binder workspace.
- Removed the obsolete ear connector strip that the bundled theme had begun
  preserving over the card edge; ears now meet the page with a clean boundary.

## 0.4.3 — 2026-08-28

- Added Ellesmere, Mimezu, and Luminous appearances to the compact Display
  popover. Switching is immediate, saved between sessions, and updates both
  open and lazily created BindCards surfaces without requiring EllesmereUI.
- Kept Ellesmere as the default and preserved its exact bundled window art,
  class-colored accents, panels, controls, typography, and icon treatment.
- Made Global Priority available on every user-created General subcard, including
  manually enabled layouts such as fishing shortcuts, while keeping it
  unavailable on generated cards and all Class subcards.

## 0.4.2 — 2026-08-27

- Bundled the exact EllesmereUI window backdrop and matching panels, controls,
  typography, icon treatment, and class-colored accent directly with BindCards.
  Every player now sees the same skin without installing EllesmereUI.

## 0.4.1 — 2026-08-26

- Restricted release ZIPs to an enforced runtime allowlist containing only the
  TOC, loaded Lua files, and addon icon. Documentation and development files
  remain in the repository but cannot enter the install package.
- Enabled normal semantic-version releases so patch versions such as `0.4.1`
  publish installable GitHub Releases rather than workflow-only artifacts.

## 0.4.0 — 2026-08-26

- Removed talent-loadout card conditions. Existing loadout-conditioned cards
  are retained but disabled during repair so they cannot silently become
  unconditional; conditional macros can cover loadout-specific actions.
- Expanded PvP card activation to War Mode, open-world combat and free-for-all
  PvP zones, and temporary PvP flagging in addition to battlegrounds, arenas,
  Solo Shuffle, and other instanced PvP modes.
- Added an optional Skyriding activity condition for General subcards. A clear
  per-card toggle can promote that card above Class, Spec, and Form bindings
  only while the secure Skyriding state is active.
- Precompiled Skyriding and class-form combinations into one secure state route
  and advanced profile exports to schema 5 while retaining versions 1–4.
- Isolated exact-ID routing to confirmed ambiguous or hidden spellbook actions:
  Oppressing Roar, Aerial Halt, and Skyriding Second Wind. All other native
  spells remain name-bound so live replacements, procs, directional targeting,
  and multi-stage actions continue to mutate.
- Removed an unnecessary protected keyboard-propagation call when closing
  Quick Bind that could be reported as an `ADDON_ACTION_BLOCKED` error.
- Applied the current secure conditional-binding state immediately after every
  route rebuild, preventing an unchanged ground/base state from losing its
  normal binding beneath an inactive Skyriding override card.
- Restricted Skyriding activity cards to actual airborne advanced flight;
  grounded mounts and grounded Soar now retain normal bindings, while airborne
  Skyriding, Evoker Soar, and flight forms activate the card.
- Matched Retail's actual airborne Skyriding state instead of requiring the
  unrelated player override bar, which prevented the card from activating.
- Refreshed visible card state on Retail's glide capability and airborne-state
  events so Skyriding and Evoker Soar show Active immediately on takeoff.
- Added a compact header button that opens Blizzard's spellbook directly on
  the Spells view rather than the Talents view.
- Allowed peeled subcards to return through their binder title, its active
  attached page, or the inactive binder's full ghost page, with matching
  home-target highlights for both General and Class.
- Made inactive-binder returns honor card-drag mouse capture on release, so a
  highlighted selector or exposed backing edge actually reattaches the card.
- Kept inactive-binder drop glows outside embedded sheet anchors and suppressed
  the selector click following a drop, avoiding refresh races during return.
- Moved Panel-mode ability controls into a compact draggable inspector that can
  be closed independently and reopened by clicking any spell or macro tile.

## 0.3.0 — 2026-08-25

- Added optional class-aware Form conditions for user-created subcards: Druid
  Caster/Bear/Cat/Moonkin/Travel, Priest Shadowform, and Rogue Stealth.
- Added direct Form-subcard creation to both supported class cards and their
  specialization cards, so shared form bindings do not need to be duplicated.
- Precompiled every configured form variant into secure state routing so form
  changes work during combat without rebuilding protected bindings.
- Preserved native spell press/release handling for empowered spells while
  retaining secure macro, item, and mouse-button routes.
- Advanced the profile export schema to version 4 while retaining imports from
  versions 1 through 3.
- Added a Display option to hide occupied tile names for a cleaner icon-and-key
  layout while keeping names visible by default.
- Made native secure spell tiles execute their resolved spell name while
  retaining spell IDs for identity and metadata, fixing talented/replacement
  spells such as Judgment and Blessed Hammer being reported as unlearned.
- Resolved equipment-slot macros such as `#showtooltip 14` to the currently
  equipped item's real name, icon, and native hover tooltip.
- Reattached every docked workspace sheet to its current owner before layout,
  preventing returned stacks from leaving only their ear visible until reload.
- Stopped the periodic keyboard-focus safeguard before combat lockdown so it
  cannot touch secure icon ancestry or produce BugSack blocked-action errors.

## 0.2.0 — 2026-08-24

- Added automated install ZIPs containing only the runtime addon files and
  required icon asset; tests, sketches, plans, and repository tooling stay out.
- Released BindCards overrides while Blizzard's house editor is active so its
  dedicated controls, such as Remove Decor, always take precedence.
- Removed retired UI paths, stale implementation-history comments, unused
  helpers, and duplicate condition/profile-sorting logic without changing the
  current workflows.
- Added experimental per-card paper sizing with a separate outer corner grip,
  and isolated that gesture from grid resizing and floating-card movement so
  detached cards remain draggable after resizing.
- Kept the exact cursor-to-card offset when detaching experimentally sized
  papers by saving placement from their displayed width rather than the old
  default floating width.
- Made the caret and mouse selection clearly visible in every macro/profile
  text field, blocked copy/paste shortcuts from reaching gameplay bindings,
  and kept profile transfer dialogs above the profile workflow that opened them.
- Fixed Evoker Oppressing Roar spellbook drops that saved the unlearned action-bar
  override ID instead of the castable base spell ID, and made secure spell tiles
  cast by numeric spell ID.
- Simplified Binder hierarchy stacks so only the selected card and its ancestor
  path render as full sheets. Larger attached ears keep sibling cards available
  without adding full-page clutter, with matching docked and floating geometry.
- Fixed returned binder stacks remaining on their old floating UI layer until
  reload, which could leave only a tab visible after docking.
- Fixed returned loose sheets updating their saved hierarchy without rebuilding
  their floating owner stack, which could hide every card until reload.
- Made inactive General/Class silhouettes reflect their own card height in both
  selection directions instead of inheriting the selected binder's height.
- Standardized nested-ear widths, reserved permanent count and arrow columns,
  and ellipsized only long names so icon counts remain visible.
- Added an optional experimental color pass with persistent amber selection and
  strings for custom nested cards, plus barely tinted amber/class card surfaces
  for clearer empty icon cells.
- Persisted Binder and Panel dimensions together with the final window center,
  restored size before position, and stopped startup from resetting valid
  large layouts.
- Fixed Panel pages to share one top-left origin regardless of General/Class
  ownership or hierarchy depth, without applying Binder layering offsets.
- Stabilized Panel grid and window resizing by avoiding full sibling rebuilds
  during the drag and restoring the complete panel layout when it ends.
- Replaced the profile command menu with a compact profile manager and added a
  focused import/export window with live validation and an explicit review step.
- Added Toy Box and Mount Journal drops. Toys compile to WoW's secure toy
  action, while mounts use their secure summon spell by name.
- Made generated-card repair transactional, rejected duplicate or fake
  generated identities during import, and added an ordered schema-2 migration.
- Added an import summary and explicit selection of imported binding sets.
- Replaced state-driven full workspace rebuilds with throttled updates of only
  visible macro icons, including asynchronous item icon loading.
- Canonicalized keyboard and mouse bindings, surfaced application failures,
  saved one-time legacy binding restoration, and removed stale secure proxy
  attributes.
- Added one-level undo for destructive card, ability, and profile removal.
- Added macro character counts, scrolling, automatic names, manual icon IDs,
  automatic-icon restore, and additional random/localized command parsing.
- Deferred construction of the complete interface until BindCards is opened.
- Added focused UI helper regression tests and a WoW-aware lint baseline.
- Fixed expand/collapse controls on detached nested-card stacks so their clicks
  cannot be captured as stack drags.
- Added cached `#showtooltip` icon resolution for macro tiles and a live
  automatic icon preview in the editor, including conditional casts, items,
  modifiers, mount state, and first-step cast-sequence fallback.
- Raised macro and text prompts onto a dedicated screen-level dialog layer so
  detached binder stacks can never cover the editor or intercept its input.
- Split profiles into independent General and per-class set libraries. Each
  character selects one General set and one set for its current class, with
  generated structure repaired on load and protected from deletion.
- Enlarged icon key labels, gave them a clean black contour, and colored
  winning bindings with the player's class color.
- Opened BindCards directly to the current active specialization page.
- Installed active bindings as non-priority secure overrides so BindPad cannot
  reclaim normal keys after BINDCARDS compiles them, while contextual
  higher-priority bindings can still take precedence on their own frames.
- Resolved secure spell actions to castable spell names and expanded capture
  to middle/extra mouse buttons, wheel, and modifier combinations, including
  modified left/right clicks while reserving their unmodified forms.
- Made the macro editor smaller and anchored it beside the exact ability cell
  that opened it, with screen clamping near the edges.
- Persisted the main app position across reloads and mode changes.
- Allowed any nested card to detach directly from a docked or floating Binder;
  only that card and its descendants move, while parents and siblings remain.
- Reduced opacity on attached background sheets to match the clearer detached
  stack hierarchy while retaining stronger custom-card readability.
- Made Panel a fixed full-page editor: cards cannot detach there, saved
  floating layouts stay hidden, and every selected parent or subcard uses the
  same central workspace footprint.
- Made Panel navigator rows direct ability drop targets, moving or copying the
  icon into the target card's first free cell without losing the source on an
  invalid drop.
- Unified attached and detached stack geometry so both use hierarchy depth for
  horizontal indentation and sheet order for vertical overlap.
- Kept the selected sheet and its own side label above the complete stack while
  every sibling label sits immediately beneath the selected sheet.
- Hid a General or Class selector while its binder is floating and removed the
  full-width strip behind the selectors. With both binders out, the app
  collapses to its header. Every binder return uses the same broad target and
  the same `Return to main binder` label below the header during drag.
- Removed docked placeholder sheets for binders that have been fully detached.
- Let default and custom nested sheets peel temporarily out of an attached or
  floating binder while retaining their exact saved parent. Only that parent
  accepts the return drop.
- Added an option to either gather every loose sheet when its main binder
  returns or leave those temporary editing sheets floating.
- Added a clear green wash over the one valid parent while a peeled sheet is
  dragged; invalid binders remain unhighlighted.
- Allowed dragged abilities to target a card tab or card body, placing them in
  that card's first available visible cell.
- Tightened the paper overlap for mutually exclusive Role and Spec pages and
  made background sheets more translucent, while keeping custom pages clearly
  selectable.
- Folded legacy top-level custom cards into their General or Class root so a
  detached binder stack always carries every page shown beneath it.
- Indented card bodies and ancestor sheets by hierarchy depth so General or
  Class remains leftmost, direct children sit one step right, and deeper
  conditional cards continue the visual nesting.
- Made detached-stack horizontal offsets depend only on hierarchy depth;
  sibling page order now affects vertical peeking without reversing parentage.
- Made every generated General, role, class, and specialization card
  permanently enabled. Their ON/OFF button is replaced by the read-only active
  state.
- Kept nested sheets moving with their containing stack until deliberately
  peeled by their own body or tab, preserving the exact cursor attachment point.
- Kept a detached stack's top-left anchor fixed while switching between its
  differently sized parent and subcards.
- Prevented a detached active stack's ancestor sheets from also appearing
  inside the main binder.
- Increased the contrast between active and inactive nested cards with a
  stronger active surface, bright label, colored edge, and dimmed desaturated
  inactive siblings.
- Added layered paper sheets to detached stacks so their nested cards remain
  visible as a physical stack while floating.
- Locked generated card names and rules. Their conditions remain visible, but
  only player-created cards can rename themselves or edit conditions.
- Shortened nested side tabs and added trailing ellipses for long card names.
- Renamed Panel navigation headings to General Cards and the current class's
  Cards label.
- Dimmed the inactive General or Class binder sheet while preserving its saved
  footprint behind the active binder.
- Stabilized ancestor-sheet geometry. A parent such as Paladin now keeps the
  same position, width, height, and grid-derived footprint when a nested spec
  page is brought forward.
- Joined parent and nested side labels edge-to-edge so class/spec and other
  parent/child stacks read as one physical set of cards.
- Removed macro creation and row/column controls from the card menu. Empty grid
  cells create macros, while the corner handle owns grid sizing.
- Split the embedded binder into stable spatial lanes: General pages stay left
  and Class pages sit slightly to the right. The inactive binder now appears as
  an offset sheet rather than a named page inside the active stack.
- Made the restack target follow the dragged card's binder consistently instead
  of the currently selected binder.
- Anchored the card restack target directly beneath the selected General or
  Class binder tab.
- Removed horizontal workspace scrolling. Binder cards now fit within a
  720-pixel maximum width while vertical scrolling remains available.
- Split the Default profile into two clear editing binders: shared `GENERAL`
  pages and the current character's `CLASS` pages.
- General bindings now resolve first, followed by Class bindings. A more
  precise Class card replaces only duplicate keys and keeps every untouched
  General binding active.
- Added a compact General/Class binder switch, distinct layered cover sheets,
  and progressively smaller labels for roots, role/spec pages, and deeper
  PvP or loadout pages.
- New cards now become pages inside the selected General or Class binder;
  existing top-level custom stacks can be nested from their card menu.
- Detached-only layouts use a compact central restack target and suppress empty
  workspace scrollbars.
- Other classes remain safely stored while only General and the current class
  are shown on a character.
- Coalesced UI refreshes, cached active-card and paper-grid calculations, and
  skipped binding recompiles for unbound or same-card visual grid changes.
- Initial BindCards implementation.
- Conditional nested cards for role, class, specialization, PvE/PvP, and talent loadout.
- Binder and compact Panel views with detachable cards.
- Spell, item, and macro grids with duplicate entries and Quick Bind.
- Inline spell-to-macro conversion and adjustable card capacity.
- Profile creation, copy, rename, delete, import, and export.
- Combat-safe secure binding compiler.
- Added collision-safe stable IDs, bounded profile/card/tile creation, and a
  reusable secure-button pool allocated only for active binding winners.
- Added conservative schema-1 repair and migration with a persistent backup
  before future-schema reset.
- Hardened imports so invalid class, condition, loadout-owner, capacity, and
  binding data fails before SavedVariables are changed.
- Combat-safe Quick Bind, capture, modal, and drag cleanup.
- Responsive card headers, condition menus, graphite paper grids, and clearer
  disabled, unmatched, and overridden states.
- Dedicated profile and transfer menus plus adaptive display controls.
- Added the self-maintaining Default profile with General, role, class, and
  specialization cards plus native role, class, and spec icons.
- Rebuilt Binder as a compact single-page album with a layered side-tab fan.
- Added continuous peel-to-detach and drag-to-restack card movement.
- Added live corner-drag grid sizing with snapped row and column previews.
- Added an optional skin through EllesmereUI's public third-party API.
- Simplified card rules to show only active conditions plus `+ Rule`.
- Made grid cells persistent addresses: abilities can be placed anywhere and
  dragged between cells without packing; occupied-cell drops swap abilities.
- Grid resizing now preserves each ability's row and column. Cropped abilities
  stay saved and small right/down indicators show where hidden cells remain.
- Added a tactile main-window resize corner and automatic two-axis workspace
  scrollbars when a card is larger than the window.
- Root cards now detach and dock as one stack with all nested cards.
- Window resize limits now account for addon scale and the current WoW screen;
  unusable saved dimensions reset to the compact default on reload.
- Replaced card detachment with explicit press-drag-release tracking so root
  cards move continuously from either their page surface or side label.
- Added offset graphite page layers behind the active binder card, with one
  visible layer per other stacked root card.
- Internal spell, item, and macro drags now show the actual icon following the
  cursor, including a Shift-copy badge. Dragging begins after three pixels and
  leaves the source icon visible at 30% opacity until the drop completes.
- Detached card stacks now use isolated frame-level bands and rise as one unit
  when pressed or dragged. Label dragging preserves the exact cursor grab point.
- Binder mode is now a header with a tightly fitted, chrome-free card workspace;
  Panel mode keeps the traditional framed window. Selected subcards show their
  real ancestor cards as the nearest underlying layers.
- Replaced the binding backend with BindPad-style direct secure CLICK bindings,
  including conditional recompilation and restoration of displaced bindings.
- Added a hover-only Binder resize arrow, independent saved Binder dimensions,
  and double-click-to-fit behavior.
- Fixed talent-loadout rules by storing the current character owner with the
  selected trait configuration.
- Quick Bind now clearly prompts the player to leave capture mode before
  testing the newly assigned key.
- Rule menus now provide an explicit Remove condition action; unrestricted
  content no longer leaves a misleading rule chip on the card.
- Inactive root-card tabs now sit behind the active binder sheet and protrude
  farther to the right, keeping their sheet ownership clear and readable.
- Background binder sheets now retain their own grid dimensions. Larger cards
  remain visibly larger behind a smaller active card instead of being resized
  to match the front sheet.
- Panel decoration now lives on a panel-only backdrop layer, preventing its
  dark window fill from leaking into Binder after switching modes.
- Removed the full-window Quick Bind keyboard listener and hardened all modal,
  capture, and tile cleanup so opening BindCards never blocks chat or gameplay
  bindings outside the specific hovered Quick Bind tile.
- Binding dispatch now mirrors BindPad's wildcard secure-button model. Duplicate
  spell and item tiles share their secure action while retaining independent keys.
- Binder background cards now preserve their true height while sharing the
  visible page width. A protected tab rail prevents card switches from adding
  horizontal scrolling or clipping labels at the workspace edge.
- Added a low-rate keyboard ownership guard so stale Quick Bind hover, modal,
  and resize capture cannot block chat or gameplay after the interaction ends.
- Dragging an ability beyond every visible card now removes it; releases inside
  a card but between cells cancel safely, and copy drags never delete the source.
- BindCards now warns when an always-active Clique Global/Hovercast binding masks
  its normal fallback key while preserving unit-frame-only Clique coexistence.
- Displaced Blizzard binding actions are retained for reload-safe restoration,
  even if another addon saves the active binding set during the session.
