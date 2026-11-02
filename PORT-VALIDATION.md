# Forever beta validation

## Mouseover bindings: status summary (0.4.25)

| Area | Automated | In game |
| --- | --- | --- |
| Editing: Bind window toggles, tile marker, tooltip, export | ForeverHoverBindings | Confirmed |
| Clicks on the player and target frames | ForeverHoverCast | Confirmed (0.4.20) |
| Keys and wheel over the player frame (health-bar motion fix) | ForeverHoverKeys | Confirmed (0.4.22) |
| Test unit frames (`/bc testframes`) | ForeverHoverKeys | Confirmed (0.4.23) |
| Real party/raid frames: pooling, joins in combat, anonymous party frames | ForeverHoverCast/Keys | **Not yet**: needs a group |
| Form and stance cards, shifting in combat | ForeverHoverForms | **Not yet**: needs a form class |
| Bind-window list of clicks Blizzard Click Casting still uses | ForeverHoverBindings | **Not yet** |

Suites run from the client root with `lua5.1`; all 16 pass. Retail
`BindCardsSmoke.lua` in StorageInvestigation fails its Evoker assertion, as it
did before this feature.

## Mouseover bindings on form cards (0.4.24) — not tested in game yet

- `lua5.1 Interface/AddOns/BindCards/tests/ForeverHoverForms.lua` (Druid; reuses the ForeverHoverKeys restricted-environment harness) covers:
  - per-form keys and clicks;
  - a Bear shift in combat while hovering (the hovered frame is re-stamped by the header's `bcform` change);
  - other frames picking up the form on enter;
  - form-only bindings;
  - the "Active in Bear" tooltip;
  - restore.

  Mutation checks: disabling form remaps on enter, the form-change re-run, or installing form-only plans each fails the test. All 16 suites pass.
- In game, on a Druid (or Warrior stances):
  1. Add a friendly Shift-Left heal on the base card and a different one on the Bear card, plus Hostile F on the Bear card only.
  2. Open Menu → Test unit frames. In caster form, Shift-click You: base heal. F over a hostile Target: normal F.
  3. Shift to Bear, including mid-combat, and repeat: Bear heal and Bear F.
  4. Shift while the cursor stays on a test frame: the next click already uses the new form.
  5. `/bc hover` shows "Form state: druid_bear".

## Mouseover keys and mouse wheel (0.4.21)

- `lua5.1 Interface/AddOns/BindCards/tests/ForeverHoverKeys.lua` (from the client root) runs the real OnEnter/OnLeave/unit-lost snippets in an emulated restricted environment and covers:
  - disposition;
  - specific-over-both;
  - the wheel with modifiers;
  - normal keys never claimed;
  - release on leave and on unit loss;
  - no recompile loop from hover keys;
  - combat wraps;
  - cleanup.

  Mutation checks: removing the recompile guard or the both-scope table fails the test. All 15 suites pass.
- In game, fully restart WoW, then:
  1. Give a spell a normal key F, and give a heal **Friendly** F.
  2. Hover a party frame and press F: heals that member. Move off the frames and press F: the normal spell.
  3. Bind **Hostile** Shift-Wheel-Up. It should work over an enemy target frame and leave the camera/other wheel use alone elsewhere.
  4. Repeat in combat. Also hover a party frame while that member leaves the group: F must return to normal.
  5. Druid/Warrior: if F is also used by a form card, check which one wins while hovering; the hover key is expected to.
  6. Check `/console taintLog 1` for blocked actions.

## Mouseover clicks on unit frames (0.4.20)

- `lua5.1 Interface/AddOns/BindCards/tests/ForeverHoverCast.lua` (from the client root) emulates the 70009 `SecureUnitButton_OnClick` path: native check, the Target/menu drop rule, and the help/harm remap. It first shows that an unbound Shift-Left is dropped natively, then covers:
  - friendly, hostile and both scopes;
  - Target/menu fallthrough;
  - macro tiles;
  - combat queueing;
  - the `ClickCastFrames` registry;
  - exact attribute restore;
  - Clique yield.

  Mutation check: disabling the modified-click NOOP makes the test fail. All 14 suites pass.
- In game, `/reload`, in a party. Use Blizzard raid-style party frames, then repeat with the classic party frames.
  1. Bind a heal with **Friendly** on Shift-Left Click and a damage spell with **Hostile** on Shift-Left Click.
  2. Shift-click a party member: heals that member without changing your target. Shift-click the target frame on an enemy: casts the damage spell.
  3. Plain left click still targets; right click still opens the menu.
  4. Bind plain Left Click (Friendly) to a heal: clicking a friend heals, clicking an enemy target frame still targets.
  5. Middle click with both toggles on: works on friend and enemy.
  6. Clear the bindings: all frames behave natively again without `/reload`.
  7. Enter combat, get a new raid member: their frame works after combat ends.
  8. Check for blocked-action or taint messages (`/console taintLog 1`, then Logs/taint.log).
  9. Tooltip says "Active on unit frames." Key labels like S-M2 fit inside the tile.

## Mouseover bindings, editing only (0.4.19)

- `lua5.1 Interface/AddOns/BindCards/tests/ForeverHoverBindings.lua` (from the client root) passes and covers:
  - key format;
  - one binding per scope beside the normal key;
  - mouseover keys never installed as global overrides, with plain BUTTON1/BUTTON2 staying native;
  - export/import and rejection of unknown scopes;
  - native Click Casting overlap;
  - the real capture handlers.

  All 12 suites pass.
- Design checked against the Forever UI source at 1.60.1 (70009):
  - Unit frames load as game type `camelot` on the mainline path.
  - `SecureUnitButton_OnClick` consults `C_ClickBindings` before attributes, so the casting phase must route clicks through `type=click` to a proxy. Direct helpbutton attributes would be swallowed.
  - `SecureHandlerWrapScript`, restricted `SetBindingClick` and `SecureCmdOptionParse` are all available.
- In game, `/reload`, then:
  1. Run `/dump C_ClickBindings ~= nil` and note the result.
  2. Bind a spell with Friendly on, using plain Left Click, and confirm the warning.
  3. Check the green bullseye, the tooltip "Mouseover: M1 · Friendly frames", and that left-clicking a party frame still targets (not active yet).
  4. Repeat with Hostile (red) and with both toggles on (split).
  5. Check that Clear removes only that type and that the tile's normal key still works.
  6. With the Legacy skin, check the capture window layout: the Mouseover row, the Gamepad row below it, and the help text not overlapping.

## Header menu workaround (0.4.16)

- `lua tests/ForeverHeaderMenu.lua .` passes under Lua 5.1 and LuaJIT: actual popup code exercises settings, Display, Profiles, Undo, reuse and dismissal without calling Blizzard MenuUtil.
- The screenshot reports a blocked action without a protected-call stack. The native menu/controller-focus path is a suspected cause, not a confirmed live trace. This workaround removes that path from the header Menu button only.
- In game, `/reload`, open Menu with controller UI enabled, exercise each option, and check outside-click/Escape dismissal and closing/reopening the editor. Verify no blocked-action warning; other card/rule context menus still use Blizzard menus.

## Card reattachment regression (0.4.14)

- `lua tests/ForeverCardReattach.lua .` exercises repeated Primary returns via Druid's tab, a sibling tab, the visible stack page, a backing sheet, and the top Class selector; also covers a floating parent's backing sheet, off-target release, header/control ordering, and refresh deferral during dragging.
- The previous UI fails the first Druid-tab return assertion. Updated code passes under Lua 5.1 and LuaJIT.
- In-game check still required: detach Primary, return it onto the Druid tab, and repeat with Druid itself detached. Verify the title, Menu, Spells, and close button remain visible and clickable after each return and after scrolling. WoW was closed during this fix, so native rendering has not been verified.

Unreleased experimental package based on the current Retail 0.4.6 working copy. Retail source and SavedVariables were not changed. Target: Forever 1.60.1.69893, Interface 16001 confirmed by the user's GetBuildInfo output.

## Automated checks

Passed on Lua 5.4.6 and LuaJIT 2.1:

- ForeverCoreSmoke: sparse classes, Primary/Secondary templates and conditions, secret values, combat cache, bounded repair, stance/forms, and disabled orphans after invalid parent recovery.
- ForeverRankSmoke: distinct numeric rank attributes, no combat attribute writes, export identity and atomic foreign-import rejection.
- ForeverUISmoke: active build selection, editable build conditions and rank-qualified macro generation.
- ForeverIntegrationSmoke: fresh General/Class profiles, child priority, switching active builds, secure application, paused import and reload persistence.
- ForeverFormRuntimeSmoke: actual secure form snippet in a modeled environment, inherited binding restoration, inactive mouse-key blocker, unknown state fallback, and removing the last form binding.
- EUIFacadeSmoke and UILayoutAuditSmoke: existing facade and layout regressions.

All shipped Lua files parse under Lua 5.4. The inherited Retail BindCardsSmoke/ProfileSplitSmoke and FormBindingRuntimeSmoke are not the Forever acceptance suite: they assert Retail spell aliasing, Evoker/spec/role profiles and Skyriding routing intentionally absent here. They remain for reference; dedicated Forever checks cover the changed paths.

## In-game checks still required

1. Try `/reload`, then `/bc`. If newly installed files are not detected, a later full restart may be necessary.
2. Confirm General, Class, Primary and Secondary cards render. Keep Secondary unused until unlocked.
3. Drag a learned spell, bind a spare key, and cast it out of combat. Learn/drag a different rank and verify the selected rank.
4. Test a macro/item, clear the binding, and verify the prior native key returns.
5. Test available forms/stances and a form-only mouse key, both outside and during combat. No protected-attribute errors should occur.
6. Switch Primary/Secondary when available, reload, and confirm the selected build's binding wins.
7. Test rank-qualified spell-to-macro conversion, profile export/import, and queued edits after leaving combat.

Automated checks cannot establish actual WoW rendering, taint safety, event payload accessibility, or spell execution. No live test has been claimed.

User beta check: `/reload` discovered the installed addon and its interface opened. The screenshot exposed UTF-8 text decoded as Windows-1252 during a staging edit. Repaired 47 UI source lines using a reversible encoding conversion, checked the glyph set against the Retail source, reran UI/layout checks and replaced only the installed UI.lua after verifying its previous hash. Rendering after this repair and actual spell execution still need confirmation.

User-reported Lua error at 17:45:43: Blizzard's MultiCastRecallSpellButton calls MultiCastSpellButton_SetTooltip, which passes self.spellId directly to GameTooltip:SetSpellByID without a guard (extracted MultiCastActionBarFrame.lua:863). Its update function can set spellId to nil when no recall spell is known (:1013–1023). Running the extracted tooltip function against a minimal tooltip API model reproduces the missing-ID failure without any BindCards code; a numeric ID succeeds. The provided stack does not show the actual spellId value, so the exact live state is unconfirmed. BindCards does not reference the multicast frames or replace the tooltip methods. No Blizzard source or global tooltip hook was modified for this native beta issue.
# Controller shortcut validation (Unreleased)

- Run `lua tests/ForeverGamepadPages.lua .` from this installed addon directory. The page regression covers spell/macro assignment, same-page conflicts, other-page preservation, legacy conversion, database reload, export/import validation with a stub codec, inactive compilation and real capture handlers using frame stubs.
- Run `lua tests/ForeverGamepadNative.lua .` for the mocked native-storage regression: page mapping, spell/macro placement, card priority, restoration, reload journal, native edits, combat/cursor deferral and rejected writes.
- In beta, open Bind on an ability that already has a keyboard binding. Choose Bar 1, 2 and 3 in separate captures. Press LT then South, RT then South, and both triggers then South. Confirm readable bar labels, retained keyboard binding, and applied status in the ability tooltip. Visually check selector spacing and clicks.
- Verify capture ends on assignment, Escape, closing the editor and combat entry. Verify keyboard and controller input work normally after closing capture.
- Duplicate a gesture on the same bar within a card and verify only the selected ability keeps it; on different bars or conditional cards both records remain.
- Reload and export/import; verify Bar 1/2/3 scope persists. Clearing the binding after reload must restore the original native action. Legacy all-page gestures retain their All bars labels until reassigned.
- On Bar 1 assign Healing Touch to RT + right face (PAD2): native storage position is page-unit slot 23, offset 18 from the first gamepad storage slot. D-pad Right is a different slot (page-unit 19, offset 14).
- Verify the native icon, tooltip, cooldown and actual button cast agree. Switch pages and check the same chord on other pages is unchanged unless assigned separately.
- Test menus, targeting, stance/vehicle overrides and reserved base face controls: native input remains in charge. Enter combat, change conditions, then leave combat: storage changes must wait until combat ends. No immediate combat form/PvP transition is claimed.
- Edit an overridden slot in Blizzard's editor. BindCards must preserve that edit, including across reload; explicitly reassign the shortcut to reclaim it. Use `/bc gamepad off` outside combat to restore tracked original actions before addon disable.
- Source basis: Blizzard's extracted `blizzard_gamepadactionbars/actionbindingutil.lua` (build 69893) documents gamepad storage use with GetActionInfo, PickupAction and PlaceAction. No native input callbacks, binding stack entries or protected frame methods are replaced. Mock checks do not prove the live beta permits these action-storage writes.
