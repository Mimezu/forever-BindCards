# BindCards for WoW Forever

Visual keybinding cards for spells, items and macros. Open with `/bc`.

Choose **Menu → Blizzard Legacy** for the Forever Legacy appearance. It uses
the client's leather background, metal frame pieces, gold-edged controls, and
native red close button. Binder covers have heavier framing; cards and stacked
sheets use lighter insets. Card dimensions, floating positions, stack offsets,
drag targets, and bindings stay unchanged. All previous appearances remain
available in the same menu. After updating the addon, use `/reload` once to load
the skin module.

The **Spells** header button forwards your click to Blizzard's spellbook micro button through Blizzard's out-of-combat action-button template. It keeps the native click handler rather than calling a spellbook toggle from addon Lua. In combat, or if the native control is unavailable, use the displayed native key or controller-menu guidance.

BindCards stays open when you use **Spells**, with the editor and its cards above the spellbook so you can drag abilities onto your cards. Spellbook positioning is left to Blizzard or your preferred window-management addon.

Use `/bcstorage` to report startup and current database counts when investigating a reload reset. It does not print profile names, spell names or binding contents, and does not reset or repair the database.

## Getting started

1. Open the Class binder. Put shared class bindings on its root card.
2. Use Primary and Secondary cards for your two talent builds. Secondary activates only when that build is active. You can rename them (e.g. "Prot", "Holy"), change their rules, or switch them OFF. **After a respec**, switch the old build card OFF to keep it for later. Then add a new card (e.g. "Retribution") with the rule **Build · Secondary**, and bind its spells to the same keys.
3. Drag a spell from the spellbook onto a card, click it, and assign a key.
4. For forms and Warrior stances, right-click a class or build card and choose New form subcard.

Spell tiles dragged while the spellbook hides low ranks (**Show All Spell Ranks** off) automatically use the highest learned rank. With all ranks shown, or when you drag a lower rank, the tile casts the exact rank you dragged. Right-click a spell tile and choose **Always use highest learned rank** to follow newly learned ranks automatically. Choose **Use current rank only** to lock it to the highest rank currently learned. The tooltip identifies universal spells as **Highest learned rank**. Right-click **Make macro** preserves this choice: universal spells omit the rank, and fixed spells include it. Existing tiles remain fixed unless you enable the option. Opening the spellbook with P keeps an already-open BindCards editor visible.

The General binder applies alongside your Class binder. Child cards override duplicate parent keys while keeping other parent bindings. Binding changes made during combat wait until combat ends.

## Character card

The third tab, named after your character, holds whatever belongs to this
character only: racial abilities, professions, a favourite toy. It is created
the first time a character logs in, and its racial abilities are added once;
remove any you don't want and they stay removed. Add anything else as usual.

Its keys win over the Class and General binders, so a racial can use a
different key on your Paladin and on your Mage. To start an alt from another
character, open the card's **•••** menu and choose **Copy from…**. This
replaces the card with a copy (tiles and keys); Undo reverses it.

Profiles and exports are specific to Forever. Retail exports cannot be imported into this version.

## Mouseover bindings (click-casting)

Clique-style click-casting, set up on your cards. Put a spell on a tile, open its
Bind window, turn on **Friendly**, **Hostile** or both, then press a key, click or
wheel direction. The binding acts only while the cursor is over a unit frame of
that type: friendly bindings on friends, hostile bindings on enemies, both on
either. Everywhere else, and over a frame of the other type, the key keeps its
normal binding. Characters in the 3D world are not included.

- **Where:** Blizzard player, target, target-of-target, focus, pet, party and
  raid frames, plus addon unit frames that register through `ClickCastFrames`.
- **What:** mouse clicks (left, right, middle, buttons 4–5), keyboard keys and
  the mouse wheel, with any modifiers. Plain left and right click can be bound
  here; clicking a unit of the other type still targets or opens the menu.
- **On a tile:** a tile keeps its normal key plus one mouseover binding per
  type, e.g. Flash Heal on friendly Shift-click and Smite on hostile Shift-click
  on another tile. A small bullseye in the tile's bottom-left corner marks it:
  green for friendly, red for hostile, split for both. **Clear** in the Bind
  window removes only the selected type; the tooltip shows each binding's status.
- **Cards and forms:** child cards override their parent, as for normal keys.
  Bindings on form and stance cards (Druid forms, Warrior stances, Shadowform,
  Stealth) switch with your form, also in combat.
- **Macros:** use `[@mouseover]` in the macro to act on the hovered unit.
- **Combat:** everything works in combat; edits and frames that appear
  mid-fight apply when combat ends.

**Blizzard Click Casting.** On Forever, Blizzard's own Click Casting runs before
any addon on Blizzard frames. Remove its spell and macro bindings for clicks you
bind in BindCards; the Bind window lists the clicks it still uses. Keep its
**Target Unit** on Left Click and **Open Unit Menu** on Right Click. When Clique
is loaded, BindCards leaves unit frames to Clique.

**Testing solo.** **Menu → Test unit frames** (or `/bc testframes`) opens
stand-in unit frames for you, your target, target's target, focus and pet. They
use Blizzard's unit-button template, so they behave like party frames; target an
enemy for a hostile one. If a mouseover key misbehaves, point at the frame and
type `/bc hover` to see what each key is bound to right now.

## Controller shortcuts

Blizzard's visual gamepad editor remains the base. To save a conditional shortcut,
select an ability in BindCards and click Bind. Choose **Bar 1, Bar 2, or Bar 3**
in the capture window. These are Blizzard's three gameplay pages, each with its
own base, LT, RT and both-trigger combinations. Press LT, RT, or both after opening
the capture window, then press a face or D-pad button. Without a trigger, the
button is saved as a base gesture. Existing keyboard bindings are preserved.
The same gesture on another card represents a conditional override; within a
single card it moves to the newly selected ability only when the bar also matches.
RT + South on Bar 1 and RT + South on Bar 2 can therefore belong to different
spells or macros. An ability can keep one captured controller combination per
bar alongside its keyboard binding. Rebinding that ability on one bar preserves
its assignments on the other two bars.

**Controller assignments now write to native gamepad action storage outside combat.**
Blizzard displays and executes that stored action, including its icon, tooltip
and cooldown, on the selected bar. Clearing a binding, disabling its binding set,
or leaving its condition restores the original native action. Other pages retain
their own actions. Native menus, stance/possess overrides and navigation remain
Blizzard-controlled. The base layer's four face buttons remain reserved.

Condition changes during combat wait until combat ends; this includes form changes.
The last applied native action remains in place until then. This bridge does not
implement immediate secure form/PvP substitutions. A busy cursor also defers updates.
The tooltip reports applied, queued, overridden or failed status; active labels
require a verified native slot write. Automated coverage uses mocked native APIs;
actual beta-client casting, rendering and protected-action behavior need live validation.

Gestures describe physical held triggers, not toggle states or ordered trigger
presses. Older all-page assignments remain readable
and are labelled "All bars"; capturing a new controller binding on that ability
replaces its legacy all-page assignment with the selected bar.
Hover the ability to inspect every saved binding and its status. Right-click in
the capture window clears all bindings on that ability.

Original actions are journaled per character in `BindCardsGamepadStorage`, in the
same SavedVariables file as the profiles. If you edit a slot directly in Blizzard's
editor, that edit wins; reassign the shortcut in BindCards to take ownership again.
Unsupported original action types are left unchanged when restoration cannot be
guaranteed. Legacy raw PAD bindings remain inactive; recapture them with a bar choice.

Controller macros use an existing native macro with the same text or create a
character macro named BCPad<number>. They must fit the native 255-character limit
and require a free macro slot if no exact match exists. Generated macros are retained;
BindCards never edits or deletes your native macros.

Use `/bc gamepad off` to restore native defaults before disabling the addon;
`/bc gamepad on` re-enables the bridge. A reload preserves the restoration journal.
Keyboard and mouse bindings continue to work normally.

## Installation

Place the BindCards folder under `World of Warcraft/_forever_/Interface/AddOns/`.
The TOC must be at `Interface/AddOns/BindCards/BindCards.toc`.

Commands: `/bc`, `/bindcards`, `/bc rebind`, `/bc hover` (mouseover diagnostics), `/bc testframes` (stand-in unit frames), `/bc help`.

## Client build

Targets WoW Forever 1.60.1 (live client 70707), Interface 16001. Live casting, dual-build changes and combat taint still need in-game verification after each client update. See PORT-VALIDATION.md for checks.
