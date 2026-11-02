# BindCards condition ideas

Design brainstorm — September 20, 2026. Proposals only; no implementation is implied.

## Current baseline

The Forever condition engine inspected for this brainstorm supports class,
Primary/Secondary build, PvE/PvP, and supported forms, stances and stealth.
Older UI code mentions roles and activities, but those are not supported
conditions in the current Forever engine.

The main design distinction is between conditions that select a whole card
and conditions that change one key's action. A friendly target can justify
changing one spell without rearranging the entire combat setup.

## Most useful missing conditions

| Condition | Player situation | Suggested behavior |
| --- | --- | --- |
| Solo / party / raid | A Druid quests alone, then joins a dungeon to heal. | Layer a group-support card over the solo setup. Preserve common movement and emergency keys. |
| Open world / dungeon / raid / battleground | PvE currently includes both questing and organized encounters. | Separate travel, dungeon utility, raid assignments and battleground tools. |
| Friendly / hostile / no target | A hybrid needs healing and damage without twice as many keys. | Per-key rules: heal a friendly target, attack a hostile target, and provide an explicit fallback. |
| Valid mouseover target | Heal or crowd-control without losing the current target. | **Done for unit frames (0.4.19–0.4.24):** per-key Friendly/Hostile mouseover bindings in the Bind window; see README "Mouseover bindings". 3D world units are deliberately out of scope. |
| Pet present / absent / dead | Hunters need Call, Mend, Revive, Dismiss and pet commands. | A pet-care card or configurable pet-care key. Retain a manual override for ambiguous dead/despawned pets. |
| Mounted / unmounted | Travel and combat abilities compete for convenient keys. | A small travel card while mounted, with predictable restoration on dismount. |
| Swimming / indoors / outdoors | Druids choose between aquatic, travel and other movement options. | A movement key with visible branches, or an exploration card. Useful with a controller. |
| Fishing pole / shield / weapon type equipped | Fishing, tanking and weapon setups require different tools. | Match equipment categories rather than specific item names. |
| Spell learned / item owned or equipped | Leveling cards contain abilities not yet learned. | Unlock upgraded cards when their required spells or items become available. |
| In combat / out of combat | Buffs, food and travel compete with combat tools. | Initially favor utility-card visibility. Binding changes need explicit, predictable rules. |

## Further ideas suited to cards

1. **Manual job selector.** Healing, tanking, farming or utility, independent
   of talent build. A leveling Druid can heal a dungeon without changing builds;
   explicit selection is more reliable than guessing intention.
2. **Preparation mode.** A temporary card for food, buffs, weapon enhancements,
   pet preparation and consumables. Enable manually or suggest on entering a
   dungeon out of combat. Combat can dismiss its display without destabilizing
   critical bindings.
3. **Named teammate or assignment.** Configure “my tank,” “my leveling partner,”
   or “my crowd-control target” once and reuse it across actions. Begin with
   manual assignments rather than assuming reliable automatic role information.
4. **Temporary held card.** Hold a key or controller button for pet commands,
   raid markers or travel; release to return. Must coexist with existing
   controller pages and triggers.
5. **City / inn / resting area.** An optional convenience card for professions,
   social actions, wardrobe and utility. Avoid moving common keys at boundaries.
6. **Specific zone or instance.** An explicit location card for relevant items,
   targeting macros and utility. Encounter detection is a later possibility,
   dependent on reliable Forever information.
7. **Leveling milestone.** Beginner and advanced cards at chosen levels.
   Combine with spell learned so activation reflects actual capability, not an
   assumption that the player visited a trainer.
8. **Pet family or summon type.** Keep a consistent pet-special key while
   choosing the relevant action for the companion. Consider after basic pet
   states and verification of available client information.

## Condition-system improvements

- **ALL / ANY / NOT:** Party AND not battleground; Bear OR Defensive stance.
- **Readable explanations:** Show why a card is active or inactive.
- **Conflict preview:** List the bindings a card would replace before enabling it.
- **Temporary pinning:** Keep a chosen card active until the player releases it.
- **Stable transitions:** Avoid repeated switches at zone boundaries or during
  brief target loss.

## Conditions to treat cautiously

Low health, low mana, cooldown ready, enemy casting and distance to target are
promising for highlighting or displaying cards. Rapidly changing a key's action
based on these states would undermine muscle memory.

Detecting a state does not establish that the client permits binding or action
changes during combat. Each proposal needs separate Forever API and secure-action
verification. Player reports from other WoW versions are evidence of needs, not
proof of Forever compatibility.

## Suggested priority

First batch:

1. Solo / party / raid.
2. Specific content type.
3. Mounted state.
4. Equipment category.
5. Pet state.
6. Manual job selector.

Friendly/hostile mouseover rules at the individual-key level shipped in 0.4.19–0.4.24 (unit frames only). A friendly/hostile rule for the current target, without hovering, remains open.

Design goal: cards adapt to the activity while important keys stay predictable.

## Player situations consulted

These discussions informed the brainstorm; the proposed design is our synthesis.

- [Classic keybind tricks](https://www.reddit.com/r/classicwow/comments/1ifm2op):
  players discuss reducing keybind pressure with friendly/hostile combinations.
- [Mouseover / target macro discussion](https://eu.forums.blizzard.com/en/wow/t/mouseover-target-macro/4091):
  players want mouseover actions with a current-target fallback.
- [Mend / Revive pet edge cases](https://us.forums.blizzard.com/en/wow/t/mendrevive-pet-macro-to-fix-the-bug/1717400):
  a dead pet whose corpse disappears complicates Call versus Revive behavior.
- [One-button fishing macro discussion](https://www.reddit.com/r/classicwow/comments/d0cemw/one_button_fishing_macro/):
  changing poles and weapons creates maintenance work for item-specific macros.
- [Healer targeting by role](https://us.forums.blizzard.com/en/wow/t/healer-macros-to-target-by-roles/1168533/):
  players seek reusable teammate assignments instead of repeatedly editing names.
