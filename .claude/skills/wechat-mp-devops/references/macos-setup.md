# macOS 本地开发适配

> 这份文档专门讲 **macOS 本地开发**（不是 GitHub Actions runner）。如果你的开发机是 Mac，
> 想在本地跑 `miniprogram-ci` 生成 QR 扫码测试，可以从这里开始。

## 速查：5 条 Mac 特有的坑

1. **默认 shell 是 zsh**（不是 bash）——脚本头建议 `#!/usr/bin/env bash` 或 `#!/bin/zsh`，别假设 `.bashrc`
2. **BSD coreutils 不带 GNU 扩展** ——`date -d '+30 minutes'` 会报错；要么装 `brew install coreutils` 用 `gdate`，要么用 `node`/`python3` 算时间
3. **APFS 默认 case-insensitive** —— `app.json` 和 `App.json` 会冲突；CI 在 Linux ext4 上行为不同
4. **HTTP_PROXY 常被设上** ——公司 VPN / Charles / Surge / ClashX 经常设 `HTTP_PROXY=http://127.0.0.1:7890`；`miniprogram-ci` 会警告但能用，本地访问 WeChat API 通常没问题
5. **PEM 私钥**别用 `chmod 600` 之外的方式——APFS 权限正常，`chmod 600 .keys/wx.pem` 直接生效

## 环境准备

### 1. 必备工具

```bash
# Homebrew（没装的话）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Node（推荐 nvm，方便多版本切换；也可以直接 brew install node@20）
brew install nvm
mkdir -p ~/.nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
nvm install 20
nvm use 20

# pnpm（任何 node 包管理器都行；pnpm 适合 monorepo）
npm install -g pnpm@9

# python3（macOS 自带；没用的话装一下，生成 HTML 页面要用）
brew install python3

# GNU coreutils（可选；让 date -d 可用；不装也行，避开 GNU 特定语法）
brew install coreutils
# 装完后 PATH 加 /opt/homebrew/opt/coreutils/libexec/gnubin（Apple Silicon）
# 或 /usr/local/opt/coreutils/libexec/gnubin（Intel）
```

### 2. 验证环境

```bash
node --version     # v20.x 或更高
pnpm --version     # 9.x 或更高
python3 --version  # 3.9+ 即可
gdate --version    # （可选）GNU date 9.x
```

## 本地 secrets 管理

**不要**把 WX_PRIVATE_KEY / WX_APP_SECRET 写到 `~/.zshrc` 里全局 export。
推荐用 **项目级 `.env.local`**（`.gitignore` 已加），加载方式：

```bash
# 项目根目录 .env.local（GitHub Secrets 同名，方便对照）
WX_APPID=wxREPLACE_WITH_YOUR_APPID
WX_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
REPLACE_WITH_YOUR_PEM_BODY
... 多行 ...
-----END RSA PRIVATE KEY-----"
WX_APP_SECRET=REPLACE_WITH_YOUR_32_CHAR_HEX_SECRET
```

加载到当前 shell（zsh 用 `source`，bash 用 `source`，都行）：

```bash
set -a              # 自动 export 所有变量
source .env.local
set +a
```

或者用 `direnv`（推荐，自动加载 `.envrc`）：

```bash
brew install direnv
# ~/.zshrc 加一行
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

# 项目根目录 .envrc
cat > .envrc <<'EOF'
export WX_APPID="wx..."
export WX_PRIVATE_KEY="$(cat ~/.secrets/wx.pem)"  # 或直接写多行
export WX_APP_SECRET="9c561..."
EOF
direnv allow .
```

## 一键本地 preview 脚本

把 `examples/local-mac-dev.sh` 复制到项目根目录 `bin/mp-preview.sh`：

```bash
chmod +x bin/mp-preview.sh
./bin/mp-preview.sh    # 自动 build + 上传 + 生成 QR + 打开 Preview
```

## Mac 特有：查看 QR

不像 CI 要上传 artifact，本地直接 `open`：

```bash
# 方式 1: 打开图片（Preview.app）
open apps/mp/qrcode.png

# 方式 2: 打开 HTML（浏览器 + 30 分钟倒计时）
open apps/mp/qrcode.html

# 方式 3: 把 PNG 复制到剪贴板（Cmd+V 贴到微信/Notion）
osascript -e 'set the clipboard to (read (POSIX file "apps/mp/qrcode.png") as «class PNGf»)'

# 方式 4: 用终端 ASCII QR（Mac iTerm2 渲染 Unicode block 比 GitHub log 准）
npx -y qrcode-terminal apps/mp/qrcode.png
```

> ⚠️ **GitHub Actions log 输出 ASCII QR 扫不出**（monospace 1:2 比例），
> 但 **本地 iTerm2 / Terminal.app 终端直接打** 可以用（用 `qrcode-terminal` 包生成 Unicode block），
> 因为本地终端字体你可以调成等宽 + 高 cell。

## HTTP_PROXY 问题

`miniprogram-ci` 启动会检测 `HTTP_PROXY` 环境变量，如果设了就 warn。

```bash
# 看是否设了
echo "$HTTP_PROXY"
# http://127.0.0.1:7890

# 本地 dev 时通常可以忽略：miniprogram-ci 走的是 https://servicewechat.com，
# VPN / Surge / Charles 的代理也支持，warn 不影响功能
# 真要干净跑：
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
./bin/mp-preview.sh
```

## APFS case-insensitive 陷阱

macOS APFS 默认 **case-insensitive but case-preserving**。
意味着 `app.json` 和 `App.json` 是同一文件——开发时容易复制粘贴出 bug。

CI runner 是 Linux ext4，**严格区分大小写**。本地能跑的代码 CI 可能挂。

```bash
# 看当前卷是不是 case-insensitive
diskutil info / | grep -i "case-sensitive"
# 通常: Case-sensitive: No

# 真要做大小写敏感开发，建一个 case-sensitive APFS 卷：
hdiutil create -size 20g -fs "Case-sensitive APFS" -volname devcase ~/devcase.sparseimage
open ~/devcase.sparseimage
# /Volumes/devcase/ 在这里开发
```

日常项目一般不用这么折腾，知道有这差异就行。

## Apple Silicon (M1/M2/M3) 注意事项

- `miniprogram-ci` 是纯 Node.js + 原生模块（`node-canvas` 等），**预编译包通常有 arm64-darwin 版本**，`npm install` 一次过
- 如果报 `node-gyp` 错：装 Xcode Command Line Tools `xcode-select --install`
- **Rosetta 2** 不用装——`miniprogram-ci` 早就是 universal / arm64

```bash
# 验证 miniprogram-ci 在 arm64 上跑
npm install --save-dev miniprogram-ci
node -e "console.log(process.arch, process.platform)"  # arm64 darwin
./node_modules/.bin/miniprogram-ci --version
```

## zsh vs bash 兼容要点

CI workflow 用 `run:` 跑的是 bash，没问题。
**本地脚本**如果用 zsh 跑，注意：

```bash
# ✅ 两边都行
echo "$VAR"
$(command)
[ -f file ] && echo yes

# ⚠️ zsh 特有，bash 也能用但写法略不同
[[ -f file ]]             # 双方括号 zsh 默认行为不同，建议坚持用 [ ]
${VAR:-default}           # OK 两边
$(command 2>&1)           # OK 两边

# ❌ zsh 跟 bash 不一样的地方
# 1. word splitting: zsh 默认不分词（VAR="a b"; echo $VAR 输出 "a b"）
#    bash 会分词成两参数。**始终加双引号**："$VAR"
# 2. 数组: zsh 数组下标从 1 开始，bash 从 0
# 3. 通配: zsh 默认不展开 dotfiles，bash 默认展开

# 推荐：脚本头写 #!/usr/bin/env bash，明确用 bash
# 或显式 emulate sh / emulate ksh
```

## 完整本地工作流（无 CI）

```bash
# 1. 准备
cd ~/code/your-mp-project
cp .env.local.example .env.local   # 填好三个 secret

# 2. 安装
pnpm install
(cd apps/mp && npm install)        # miniprogram-ci

# 3. 一键 preview
./bin/mp-preview.sh
# → build + 上传 + qrcode.png + 自动 open Preview.app
# → 微信扫码进 dev preview

# 4. 改代码 → 再跑 ./bin/mp-preview.sh
```

## 什么时候切回 CI（GitHub Actions）

| 场景 | 用什么 |
|---|---|
| 本地快速迭代 | `./bin/mp-preview.sh`（本地，秒级） |
| 团队成员扫码测试 | 推 develop → CI 跑 → Cloudflare Pages 出链接 |
| 体验版（30 分钟后还要用）| 推 main → CI 跑 → Cloudflare Pages 长期链接 |
| 发正式版 | mp 后台手动 + CI artifact 留档 |

## 进一步

- CI workflow 模板：`examples/mp-ci.yml`（GitHub Actions + Cloudflare Pages，跟 Mac 无关）
- QR HTML 页面生成：`references/qr-page.md`
- 完整 secrets 说明：`references/secrets.md`