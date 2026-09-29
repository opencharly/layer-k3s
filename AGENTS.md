# AGENTS.md — layer-k3s

Standalone candy repo for the `k3s` layer — the verified-checksum k3s binary
installer plus its CNI runtime dependencies. The candy lives in `charly.yml` at
the repo root: the `package:`/`distro:` sections, the `run:` install step, the
`check:` assertions, and the embedded `skill:` entity projected into the
marketplace corpus as `/charly-infrastructure:k3s`.

Canonical files:

- `charly.yml` — the `k3s:` candy entity and the `k3s-skill:` skill entity.
- `.github/workflows/tag-on-merge.yml` — CalVer tag + `CHANGELOG/` on merge.
- `README.md` — user overview only; never agent guidance.

## Load these skills first (R0)

- `/charly-infrastructure:k3s` — the owning skill. The checksum-verified binary
  fetch, the `kubectl`/`crictl`/`ctr` symlinks, and verification. Load before
  editing or troubleshooting the layer.
- `/charly-image:layer` — the candy authoring reference (`charly.yml` schema,
  `plan:` step verbs incl. `check:`/`run:`, per-distro `distro:` arms, package
  sections). Load before editing any entity field or plan step.

## Build / validate / test

- The merge gate is the **org-wide** `charly/pr-validator` (required check
  `validate / validate`, defined in `opencharly/.github`); this repo has **no
  per-repo candy gate** and ships only `.github/workflows/tag-on-merge.yml`.
- The candy's `plan:` `check:` steps are the functional evidence; they must stay
  valid on every distro arm they run on. Scope a distro-specific check in the
  command itself — the check runner does not honour runner-level
  `exclude-distro` fields.

## Modify this repo

- Edit the `k3s:` candy entity AND the `k3s-skill:` skill entity in `charly.yml`
  together. The skill is the projected usage source, so a behaviour change not
  mirrored in the skill leaves the corpus stale.
- The pinned version lives in the `K3S_VERSION`/`K3S_VERSION_URL` vars consumed
  by the `run:` step; bump the vars and the `check:` version assertion together.
  The checksum verification is part of the install contract — keep it.
- New behaviour claims belong in the `plan:` as an observable `check:` step, and
  in the skill body.

## Landing

- PR-only. Every change lands through a pull request; the org-required
  `charly/pr-validator` validates the diff and body and arms native auto-merge
  on PASS. Direct pushes to `main` are blocked.
- History lives in `CHANGELOG/` (written by `tag-on-merge` at merge time); the
  PR body IS the changelog.
- The authoritative rulebook is the umbrella `AGENTS.md` in
  `opencharly/opencharly` and `charly/AGENTS.md` in the charly repo. Do not
  restate its rules here.
