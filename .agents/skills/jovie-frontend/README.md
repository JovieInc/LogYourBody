# Jovie frontend skill installation

Canonical package: `.agents/skills/jovie-frontend/`.
Codex discovers `SKILL.md` there. `.claude/skills/jovie-frontend` is a relative
symlink to the same directory, following Jovie's one-source resolver convention.

In Pen 1.2.16, add this package's `SKILL.md` using the custom-skills interface.
The installed `SkillsManager.addSkill` records its absolute path in
`customSkills` and invalidates the skill cache. Use the skill from Pen's skill
selector when working on LYB. Do not copy it into `~/.pencil/skills`, which the
vendor updater replaces. If the checkout moves, update the registered path.

The source is Jovie's repository frontend contract, defined in
[PR #15923](https://github.com/JovieInc/Jovie/pull/15923), pinned in
[SOURCE.json](SOURCE.json). This package adds a short destination/platform
adapter. Upstream document prose is preserved; Markdown links to unbundled
repository resources are rewritten to the pinned GitHub revision, and the
repository formatter normalizes presentation. Code-path
references remain Jovie paths, as explained in `SKILL.md`. No executable
installer, credentials, or runtime dependencies are included.

Validate frontmatter, every bundled Markdown link, the Claude symlink, source
blob IDs, installed SHA-256 hashes, and Pen's registered-path discovery after
installation. A loader check is not visual acceptance or model-use proof.
