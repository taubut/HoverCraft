# Changelog

## 1.3.0 (2026-09-19)

- Renamed from HoverCast to **HoverCraft** (CurseForge already has an addon called HoverCasts).
  `/hover` and the `HC ...` macro names are unchanged, so existing macros keep working;
  `/hovercraft` replaces `/hovercast`.
- New targeting options: **tank** (mouseover > target > target's target > you: target the boss
  and it heals whoever the boss is hitting), **enemy** (for damage spells) and **resurrect**
  (dead friendly mouseover; the other options skip the dead).
- Picking a damage spell switches a friendly option to enemy, and a heal switches back.
- Right-click the targeting button to step backwards.
- A `?` button (and hovering the targeting button) explains the current option and lists them all.
- "Also start auto-attack" checkbox adds `/startattack [harm,nodead]` above the cast.
- Your hover macros list shows each macro's targeting; click a row to load it back into the editor.
- Spell names that collide at the 16-character macro name limit fall back to initials
  ("HC GBoK"), then numbered initials ("HC BoS2"). A macro for anything else is never overwritten.
- Remove looks the macro up by name right before deleting it, so it can't delete the wrong one.
- Entry in the addon menu by the minimap.

## 1.2.0 (2026-09-19)

- Spell ranks. Spells with more than one rank ask which one you want: **Max rank** (always your
  highest) or a specific rank, written as `Holy Light(Rank 1)`. Each rank gets its own macro.

## 1.1.1 (2026-09-19)

- Now a plain macro maker: no key binding step. **Create macro** puts the macro on your cursor to
  drop onto an action bar, with the spell's own icon. **Pick up** grabs an existing one again.
- The hover macro list scrolls, and both lists show a scroll bar when there is more to see.

## 1.0.0 (2026-09-18)

First version: pick a spell and a targeting option, get a mouseover macro.
