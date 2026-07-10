# wechat-mp-devops

> 微信小程序（WeChat MiniProgram）CI/CD 与 DevOps 实战手册

把"Linux/macOS 上自动化构建/上传/扫码测试微信小程序"的全套踩坑经验沉淀成 Claude Code skill，**可复用**到任何微信小程序项目。

## 仓库结构

```
.
├── README.md                          # 本文件
└── .claude/
    └── skills/
        └── wechat-mp-devops/
            ├── SKILL.md               # skill 入口（核心要点速查）
            ├── references/            # 详细知识沉淀
            │   ├── secrets.md             # WX_PRIVATE_KEY vs WX_APP_SECRET
            │   ├── miniprogram-ci.md      # miniprogram-ci API 完整说明
            │   ├── wechat-qr-api.md       # getwxacodeunlimit + access_token 位置
            │   ├── cicd-pitfalls.md       # 常见 workflow 坑（paths filter / lockfile / 等）
            │   ├── debug-tips.md          # 在 sandbox 限制下 debug GitHub Actions
            │   ├── qr-page.md             # base64 embed QR 到 HTML + Cloudflare Pages
            │   └── macos-setup.md         # macOS 本地开发适配（brew / zsh / APFS / Apple Silicon）
            └── examples/
                ├── mp-ci.yml              # 完整可用的 GitHub Actions workflow
                └── local-mac-dev.sh       # macOS 本地一键 preview 脚本（读 .env.local + open QR）
```

## 这个 skill 解决什么问题

| 场景 | 解决 |
|---|---|
| 在 Linux/GitHub Actions 上自动 build + 上传微信小程序 | `miniprogram-ci preview` 一条命令搞定 |
| **在 macOS 本地一键 preview + 扫码测试** | **`bin/mp-preview.sh`**（读 `.env.local`、生成 QR、`open` Preview）→ 见 `macos-setup.md` |
| 区分 `WX_PRIVATE_KEY`（PEM）和 `WX_APP_SECRET`（32位 hex）| 别再混淆 → `secrets.md` |
| `getwxacodeunlimit` 报 `41001 access_token missing` | access_token 必须在 URL query，**不在 body** |
| `getwxacodeunlimit` 实际返 JPEG，not PNG | 头 2 字节 `ffd8` = JPEG |
| `pnpm install --frozen-lockfile` 报 `ERR_PNPM_OUTDATED_LOCKFILE` | lockfile specifier 跟 package.json 不同步 |
| workflow paths filter 漏了 lockfile，lockfile 改了 CI 不跑 | paths filter 加 `pnpm-lock.yaml` |
| 体验版 QR 扫码提示"小程序尚未发布" | getwxacodeunlimit 要求"已发布"，不是"体验版" |
| 在无 admin auth 情况下 debug GitHub Actions step log | `actions/github-script@v7` 创建 issue |
| **不想下载图片，扫码就进 dev preview** | **HTML 部署到 Cloudflare Pages** → 见 `qr-page.md` |

## 起源

来自 GridGo 项目（一个 Taro 4 + Supabase 跨端 OKR App）的真实踩坑。完整故事见 `references/cicd-pitfalls.md`。

## 快速开始

在你的项目里：

```bash
# 把 skill 文件复制到你项目的 .claude/skills/wechat-mp-devops/ 即可
# 或作为 git submodule：
git submodule add https://github.com/toolazytoname/wechat-mp-devops.git .claude/skills/wechat-mp-devops
```

然后在 Claude Code 里说"用 wechat-mp-devops skill 帮我做 XX"，Claude 会自动加载。

### macOS 本地快速开始

```bash
# 1. 复制本地脚本到项目
cp .claude/skills/wechat-mp-devops/examples/local-mac-dev.sh bin/mp-preview.sh
chmod +x bin/mp-preview.sh

# 2. 准备 secrets（不要 commit）
cat > .env.local <<'EOF'
WX_APPID=wxREPLACE_WITH_YOUR_APPID
WX_APP_SECRET=REPLACE_WITH_YOUR_32_CHAR_HEX_SECRET
WX_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
REPLACE_WITH_YOUR_PEM_BODY
-----END RSA PRIVATE KEY-----"
EOF
echo ".env.local" >> .gitignore

# 3. 一键 preview
./bin/mp-preview.sh   # 自动 build + 上传 + 生成 QR + 打开 Preview.app
```

## 关键依赖

- `miniprogram-ci >= 2.1.31` — 微信官方 CI 工具
- `pnpm >= 9`（推荐）— monorepo 友好
- `node >= 20`
- GitHub Actions（推荐）— 也兼容 GitLab CI / 自建 runner
- **macOS 本地开发**（可选）— macOS 12+ / Apple Silicon 原生支持，详见 `macos-setup.md`

## License

MIT
# wechat-mp-devops