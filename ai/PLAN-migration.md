# sky_ws2 AI docs migration plan

Authoritative plan. Execute one phase per invocation. The §1 git safety
constraints from the earlier session remain in force throughout every phase:

- Stage explicit individual file paths only. No `git add -A`, no `git add .`, no
  `git add <dir>` where the dir contains or is a nested repo.
- Before every commit in main: run `git status --porcelain`, confirm nothing
  under `src/`, `nsrc/`, or `Micro-XRCE-DDS-Gen/` is staged, show that output.
- On any "adding embedded git repository" warning: stop, report, do not work
  around it.
- No `git checkout` / `switch` / `branch` / `reset` / `submodule update` in any
  nested repo.
- No commits in any detached-HEAD repo. Report and skip.

Phases A and B are prerequisites for any root commit. Do not reorder.

---

## Phase A — Quarantine nsrc. Do this first.

`nsrc` is a clone of SkyRats/sky_ws2 inside sky_ws2, carrying 1235 lines of stale
instruction text and 3 clone-in-clone children. It goes.

1. Verify nothing is at risk: for `nsrc` and each of its 3 children, confirm 0
   unpushed commits and list every dirty or untracked file. Report before moving.
2. Do NOT delete. Propose the exact `mv` to a path outside this tree
   (`~/attic/nsrc-YYYYMMDD/`). I run it, not you.
3. After I confirm the move, treat `nsrc` and its children as nonexistent — drop
   all 1235 lines and 4 repos from every subsequent phase and count.

---

## Phase B — Reproducibility: vcstool for all 20, submodules retired.

Decision: single mechanism. Branch-tracking for the 7 ours, exact SHA/tag for the
10 vendored, lock snapshots at milestones. Rejected: all-submodules (multiplies
pointer-bump commits ~6x, and inherits ardupilot's 15 recursive submodules into
main's clone story) and the 3-submodule/17-manifest split (two update commands,
two answers to "how do I pin this").

Produce, but do NOT execute:

1. `sky_ws2.repos` — vcstool YAML, all 20 repos. Ours: `version:` = current
   branch name. Vendored: `version:` = exact current SHA, or an upstream tag if
   the current SHA is on one — say which you used per repo. Include
   `Micro-XRCE-DDS-Gen` at its root path, and note explicitly that vcstool will
   not recurse into its 2 declared submodules, and what I must run instead.
2. The `.gitignore` additions: `/src/*`, `/Micro-XRCE-DDS-Gen/`, `/nsrc/`, plus
   negations for anything under `src/` that main must keep tracking. List what
   those are; if none, say none.
3. The exact command sequence to retire the 3 gitlinks and delete `.gitmodules`,
   as a script I will review and run myself. Include the verification command
   that proves no gitlink remains in the index afterward.
4. A one-line reconstruction command for a fresh machine, and the
   `vcs export --exact` command for milestone locks.
5. Flag `src/outdoor_2025`'s 5 dirty files as blocking — they must be committed
   and pushed before I run any of this.

Write `ai/decisions.md` entry #1 from the above, with the rejected options and
the specific reason each lost. This is the only file you write in Phase B.

Do not run any git command that mutates state in this phase.

---

## Phase C — Consolidate and de-stale. This is the real work.

### C1. Staleness triage

For every one of the 25 remaining instruction files, list every claim that
references a topic, param, frame, or device that you can verify no longer exists
in the current source. Quote the claim verbatim with its file and line. Group as:

- **provably dead** — the referenced symbol is absent from all current source
- **suspect** — self-declared stale, or contradicted by another file
- **current**

Do not delete anything. I approve deletions file by file. For hardware-adjacent
claims — params, wiring, ESC, frame conventions — preserve original wording
verbatim in whatever survives. Do not paraphrase a param value.

Known starting points, not the whole list: `indoor_2026/.claude/rules/bridge_node.md`
(61 lines) and `yaw_frame_research.md` (179 lines) both open by declaring
themselves stale and reference `mocap_pose_estimate`, `/mavros/mocap/pose`, and an
inverted ZED. Verify each against current source rather than trusting either the
file's self-assessment or this note.

### C2. The four duplicate pairs

For each of `bridge_node.md`, `launch_and_config.md`, `yaw_frame_research.md`,
`skymavlink.md`: diff the two copies and report what actually differs, not that
they differ. Classify each difference as:

- (i) **drift** — one copy is simply newer → consolidate into `ai/interfaces.md`,
  newer wins, note which copy lost and where it was
- (ii) **genuine per-repo divergence** → stays per-repo, but state why it
  legitimately differs
- (iii) **contradiction** — both cannot be true → STOP. Quote both verbatim with
  their repo. Do not pick. This includes the frame-convention conflict flagged in
  the earlier session; surface it here with both versions and wait for me.

### C3. Write the shared layer

Only after C1 and C2 are approved. Write `ai/interfaces.md`, `ai/repos.md`,
`ai/stack.md`, `ai/conventions.md`, and the thin main `CLAUDE.md` that imports
`repos`, `interfaces`, `conventions`. Reference `decisions.md` and `stack.md` as
paths in backticks, not as `@` imports. Then delete the per-repo copies you
consolidated.

Report projected at-launch line counts for all four launch points (main root,
`indoor_2026`, `sky_vision2`, `sky_navigation`) before and after. If any launch
point does not go down, the consolidation failed and you say so.

---

## Phase D — Per-repo, ours only.

The 7 ours minus `sky_sim2` (detached; I fix it myself) = 6 repos.

Vendored repos get nothing: no CLAUDE.md, no journal, no settings. Instead add
`permissions.deny` Read rules for their build output and `claudeMdExcludes` for
their subtrees, in main's `.claude/settings.local.json`, gitignored.

Per repo:
- thin `CLAUDE.md` — what it does, run command, test command, pitfalls only.
  Nothing that belongs in `ai/`. If a repo has no test command, write that it has
  none. Do not invent one.
- `docs/JOURNAL.md` — template header, no fabricated entries.
- `.claude/settings.json` — register the shared SessionStart hook. Settings do
  not inherit from parent directories, which is why each repo needs its own.
- Commit in that repo, one repo at a time, pausing for me between each.

---

## Phase E — Verify

Give me the exact expected `/context` "Memory files" list for each of the four
launch points. I run it, not you.

Specifically resolve the ±112 line question: state what you expect for whether
main's `.claude/rules/` loads from inside `src/indoor_2026`, so my `/context`
output either confirms or refutes it.

---

## Ongoing protocol, after Phase E

- Before planning: read the top `docs/JOURNAL.md` entry of the repo in scope,
  plus `ai/decisions.md` if the task touches `ai/interfaces.md`.
- On a cross-repo change: write the plan to a markdown file in the tree before
  editing. Long sessions compact; a saved plan survives where conversation does not.
- Before I quit: write a journal entry. "Tried and failed" is mandatory if
  anything was abandoned.
- A decision with a rationale never goes in a journal. It goes in `ai/decisions.md`.
- If a fact is not written down anywhere in this tree and it matters, say so and
  ask. Do not infer pin assignments, frame conventions, or param values.
