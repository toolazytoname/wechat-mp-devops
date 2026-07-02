# Contributing to wechat-mp-devops

Thank you for your interest in contributing! 🎉

This repo is a knowledge base of WeChat MiniProgram (微信小程序) CI/CD lessons, distilled into a Claude Code skill.

## How to contribute

### 1. Report an issue

Use one of the issue templates:
- **🐛 Bug Report** — something in the docs/examples is wrong
- **💡 Feature Request** — propose new content (a new gotcha, a new reference, etc.)

### 2. Submit a Pull Request

1. **Fork** this repo
2. Create a **feature branch** (`git checkout -b fix/your-fix` or `feat/your-feature`)
3. Make your changes
4. **Verify** the skill structure is preserved (see below)
5. **Test** if you added any code/workflow
6. **Commit** with a clear message
7. **Push** and open a PR

## Skill structure

All knowledge lives under `.claude/skills/wechat-mp-devops/`:

```
SKILL.md                 # Required. Entry point + cheat sheet.
references/              # Detailed knowledge files (markdown)
  <topic>.md             # One topic per file
examples/                # Ready-to-use artifacts
  <example>.<ext>        # e.g. mp-ci.yml
```

### Adding a new reference

1. Create `references/<topic>.md`
2. Link to it from `SKILL.md` (in the "完整内容索引" table)
3. Add a one-line description to the cheat sheet in `SKILL.md` if it's a top-5 lesson
4. Update both `README.md` (Chinese) and `README.en.md` (English) tables

### Editing SKILL.md

`SKILL.md` is the entry point. It should:
- Stay concise (< 200 lines)
- Frontmatter must have `name` + `description`
- Include a "完整内容索引" table linking to references
- Be language-agnostic (use English in the body; Chinese readers have README.md)

### Adding an example

Place under `examples/` with a descriptive name. Include comments explaining non-obvious parts.

## Style guide

- **Markdown** — use ATX headers (`#`, `##`), fenced code blocks with language hints
- **Code blocks** — always specify language: ` ```bash `, ` ```yaml `, ` ```python `
- **Links** — relative within repo (`./CONTRIBUTING.md`), absolute for external
- **Tone** — practical, no fluff; this is a playbook, not a textbook
- **Tables** — prefer over lists when comparing options (errcode cheatsheet, etc.)

## What NOT to commit

- Real secrets, appids, or private keys (even for testing)
- Generated files (PDFs, screenshots, etc.)
- Vendor-specific content that doesn't generalize

## License

By contributing, you agree that your contributions will be licensed under [MIT](./LICENSE).
