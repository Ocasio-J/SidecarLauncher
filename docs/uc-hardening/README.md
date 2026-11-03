# UC hardening — design archive

Working documents for the Universal Control / Sidecar hardening cycle. They are versioned as
**files, not as edits**: a new revision always produces a new `design-vN.md`. Git history is the
second safety net, but the primary record is here, because the first two revisions were lost to
in-place overwrites before these files were tracked.

| file | what it is | state |
|---|---|---|
| `analysis.md` | why Universal Control dropped: log evidence, replies, addendum. Written by an independent analysis agent, annotated by the tool agent | reference |
| `plan.md` | first implementation plan for `tools/` (items A1–A4, B1–B7, C1) | superseded by `design-v3.md` |
| `design-v3.md` | design after two adversarial reviews. v1 and v2 are **lost** (untracked, overwritten); their content survives only in the "Resolution" sections of v3 | awaiting third verdict |

## Cycle state

1. `plan.md` — proposed.
2. **review 1** (adversarial): `RESPINGO`, 7 blocking objections.
3. **design v2**: all 7 accepted, no rebuttals. *(file lost)*
4. **review 2** (adversarial): `RESPINGO`, 3 new blocking objections — `disprule.swift` cannot be
   compiled alongside top-level helper sources; `live_sidecar_line` with a fallback is not "live";
   `A2` falls back to reconnecting when the probe returns `unknown`.
5. **design v3**: 3/3 accepted, plus 9 annotations. *(this archive)*
6. **review 3** — pending.

## Rules for the next revision

- Write `design-v4.md`; never edit `design-v3.md` in place.
- Add a row to the table above and update the cycle state.
- Commit the new file in the same change that produces it.
- The measuring instrument (`~/sidecar-watch`, `local.sidecar.watch`) stays outside this
  directory and is never edited while a design is being evaluated.

## Live state when this archive was created

`2026-11-03`, lid closed, `vdisp` 1321x918 as the main display with the Sidecar mirroring it,
Sidecar session up since `09:05:18` (no `up`/`down` in between), Universal Control forwarding
input from the other Mac. This is the longest clean sample recorded so far and it is the state any
implementation must not regress.
