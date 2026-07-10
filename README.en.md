# wechat-mp-devops

> WeChat MiniProgram (微信小程序) CI/CD & DevOps Playbook — Linux (GitHub Actions) + macOS (local dev)

Hard-won lessons from automating WeChat MiniProgram builds, uploads, and QR-code generation — distilled into a Claude Code skill, **reusable for any WeChat MP project**.

🇨🇳 [中文文档](./README.md) | 🇬🇧 **English**

## What this skill solves

| Problem | How |
|---|---|
| Auto-build + auto-upload WeChat MP on Linux/CI | `miniprogram-ci preview` does it all in one command |
| **One-shot preview on macOS local dev** | **`bin/mp-preview.sh`** (loads `.env.local`, generates QR, `open` Preview.app) — see `macos-setup.md` |
| Confuse `WX_PRIVATE_KEY` (PEM) with `WX_APP_SECRET` (32-char hex) | See `references/secrets.md` |
| `getwxacodeunlimit` returns `41001 access_token missing` | access_token MUST be in URL query, **not body** |
| `getwxacodeunlimit` actually returns JPEG, not PNG | Check first 2 bytes for `ffd8` magic |
| `pnpm install --frozen-lockfile` fails with `ERR_PNPM_OUTDATED_LOCKFILE` | Lockfile specifier out of sync with package.json |
| workflow `paths` filter misses `pnpm-lock.yaml` | Add `pnpm-lock.yaml` to filter list |
| Experience QR says "MiniProgram not yet published" | `getwxacodeunlimit` requires "已发布" (officially published), not just "体验版" (experience) |
| Debug GitHub Actions step log without admin auth | `actions/github-script@v7` + create issue |
| **Want to scan QR without downloading the image** | **HTML deployed to Cloudflare Pages** — see `qr-page.md` |

## Repository structure

```
.
├── README.md                          # Chinese docs
├── README.en.md                       # English docs (this file)
├── LICENSE                            # MIT
├── CONTRIBUTING.md                    # Contribution guide
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
└── .claude/
    └── skills/
        └── wechat-mp-devops/
            ├── SKILL.md               # Skill entry (cheat sheet)
            ├── references/            # Detailed knowledge
            │   ├── secrets.md             # WX_PRIVATE_KEY vs WX_APP_SECRET
            │   ├── miniprogram-ci.md      # miniprogram-ci API reference
            │   ├── wechat-qr-api.md       # getwxacodeunlimit + access_token position
            │   ├── cicd-pitfalls.md       # 8 common workflow gotchas
            │   ├── debug-tips.md          # Debug GitHub Actions without admin auth
            │   ├── qr-page.md             # base64 embed QR to HTML + Cloudflare Pages
            │   └── macos-setup.md         # macOS local dev (brew / zsh / APFS / Apple Silicon)
            └── examples/
                ├── mp-ci.yml              # Complete ready-to-use GitHub Actions workflow
                └── local-mac-dev.sh       # macOS local one-shot script (reads .env.local + opens QR)
```

## Quick start

### Use the skill in your project

```bash
# As a git submodule (recommended — auto-sync with upstream)
cd your-project
mkdir -p .claude/skills
git submodule add https://github.com/toolazytoname/wechat-mp-devops.git .claude/skills/wechat-mp-devops

# Or just copy the files (one-off use)
cp -r /path/to/wechat-mp-devops/.claude/skills/wechat-mp-devops your-project/.claude/skills/
```

Then in Claude Code, say "use wechat-mp-devops skill to do X" — the skill loads automatically.

### Use the example workflow

Copy `.claude/skills/wechat-mp-devops/examples/mp-ci.yml` to your project's `.github/workflows/mp-ci.yml`. See file for required GitHub Secrets.

### macOS local dev

```bash
# 1. Copy the local script
cp .claude/skills/wechat-mp-devops/examples/local-mac-dev.sh bin/mp-preview.sh
chmod +x bin/mp-preview.sh

# 2. Prepare secrets (do not commit)
cat > .env.local <<'EOF'
WX_APPID=wxREPLACE_WITH_YOUR_APPID
WX_APP_SECRET=REPLACE_WITH_YOUR_32_CHAR_HEX_SECRET
WX_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
REPLACE_WITH_YOUR_PEM_BODY
-----END RSA PRIVATE KEY-----"
EOF
echo ".env.local" >> .gitignore

# 3. One-shot preview
./bin/mp-preview.sh   # builds + uploads + generates QR + opens Preview.app
```

## Cheat sheet: 5 things to remember

1. **`WX_PRIVATE_KEY` is a PEM private key** (multi-line, starts with `-----BEGIN`). Used by `miniprogram-ci` for code upload.
2. **`WX_APP_SECRET` is a 32-char hex string** (single line). Used by WeChat HTTP API to fetch `access_token`.
3. **`access_token` position varies by API**:
   - `cgi-bin/token` (fetch token) → body or query both OK
   - **`getwxacodeunlimit` (fetch QR) → MUST be URL query**, body gives `41001 missing`
4. **`getwxacodeunlimit` actually returns JPEG** (FFD8FFE0), not PNG. First 2 bytes `ffd8` = JPEG.
5. **`getwxacodeunlimit` requires the MiniProgram to be "已发布"** (officially published). "体验版" (experience) doesn't count. dev preview QR (from `miniprogram-ci preview`) works without publishing.

## Cheat sheet: errcode

| errcode | Meaning | Fix |
|---|---|---|
| `40001` invalid credential | AppSecret wrong | Reset + ensure it's the **miniProgram** secret, not 公众号 |
| `40125` invalid appsecret | Used 公众号 secret | Use miniProgram secret |
| `41001` access_token missing | access_token in wrong place | Move to URL query (`?access_token=...`) |
| `40013` invalid appid | appid wrong | Verify WX_APPID |
| `40066` invalid path | path not in app.json pages | Fix path |
| `45009` / `45002` | Rate limit exceeded | Wait |
| `errcode=20002` (from miniprogram-ci) | Used AppSecret as PEM | Use real PEM private key |
| `ERR_PNPM_OUTDATED_LOCKFILE` | lockfile specifier out of sync with package.json | Sync lockfile |

## Requirements

- `miniprogram-ci >= 2.1.31` — WeChat official CI tool
- `pnpm >= 9` (recommended) — monorepo-friendly
- `node >= 20`
- GitHub Actions (recommended) — also works with GitLab CI / self-hosted runners
- **macOS local dev** (optional) — macOS 12+ / Apple Silicon natively supported, see `macos-setup.md`

## Origin

From real production usage on the **GridGo** project (a Taro 4 + Supabase cross-platform OKR app). Full story in `references/cicd-pitfalls.md`.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE) © 2026 toolazytoname