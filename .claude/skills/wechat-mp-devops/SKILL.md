---
name: wechat-mp-devops
description: |
  微信小程序（WeChat MiniProgram）的 Linux 端 CI/CD 与 DevOps 实战手册。
  覆盖：miniprogram-ci 用法、private key / AppSecret 区分、access_token 位置、QR API、workflow 坑、debug 技巧。
  当用户提到微信小程序自动发布、miniprogram-ci、mp-ci、WeChat QR code、getwxacodeunlimit、access_token missing 等场景时触发。
metadata:
  type: reference
  scope: wechat-mp-cicd
---

# wechat-mp-devops

## 什么时候用这个 skill

用户在以下场景**应该**触发本 skill：

- 在 Linux/CI 上**自动 build / upload** 微信小程序
- 配置 GitHub Actions `.github/workflows/mp-ci.yml` 或类似 CI
- 区分 `WX_PRIVATE_KEY`（PEM）和 `WX_APP_SECRET`（32位 hex）这两种 key
- 调 `getwxacodeunlimit` / `cgi-bin/token` 等 WeChat API
- 排查 `41001 access_token missing` / `40001 invalid credential` / `小程序尚未发布` 等错误
- 在没有 admin auth 情况下 debug GitHub Actions step log

## 速查：5 句话

1. **`WX_PRIVATE_KEY` 是 PEM 私钥**（多行，`-----BEGIN` 开头）→ 给 miniprogram-ci 上传代码
2. **`WX_APP_SECRET` 是 32 位 hex**（一行）→ 给 WeChat API 取 access_token
3. **access_token 在不同 API 位置不同**：
   - `cgi-bin/token`（取 token）→ body 或 query 都行
   - **`getwxacodeunlimit`（取 QR）→ 必须在 URL query**，body 里会被报 `41001 missing`
4. **`getwxacodeunlimit` 实际返 JPEG**（FFD8FFE0），**不是 PNG**。判定头 2 字节 `ffd8` = JPEG
5. **`getwxacodeunlimit` 要求小程序"已发布"**，"体验版"不算。dev preview QR（`miniprogram-ci preview`）不需要发布

## 推荐 workflow 路径

```yaml
# 最稳的 6 step 路径（不需要 AppSecret）
- uses: actions/checkout@v4
- uses: actions/setup-node@v4       # node 20
- run: npm install -g pnpm@9
- run: pnpm install --frozen-lockfile
- working-directory: apps/mp
  run: npm install --no-audit --no-fund
- working-directory: apps/mp
  env: { WX_APPID, WX_PRIVATE_KEY }
  run: |
    mkdir -p .keys
    printf '%s' "$WX_PRIVATE_KEY" > .keys/wx.pem
    chmod 600 .keys/wx.pem
    ./node_modules/.bin/miniprogram-ci preview \
      --appid "$WX_APPID" --pkp ./.keys/wx.pem --pp ./ \
      --uv 1 --rv 1 \
      --enable-qrcode --qrcode-format image --qrcode-output-dest ./qrcode.png
- uses: actions/upload-artifact@v4
  with: { name: mp-qrcode, path: apps/mp/qrcode.png }
```

`miniprogram-ci preview` 一条命令完成 build + upload + 生成 dev preview QR。

## 完整内容索引

| 文件 | 内容 |
|---|---|
| `references/secrets.md` | WX_PRIVATE_KEY / WX_APP_SECRET 详细区别、获取、混淆排查 |
| `references/miniprogram-ci.md` | miniprogram-ci API 完整说明（preview/upload/build）、参数、退出码 |
| `references/wechat-qr-api.md` | getwxacodeunlimit vs unlimit、access_token 位置、errcode 速查 |
| `references/cicd-pitfalls.md` | 8 个常见 workflow 坑（lockfile drift / paths filter / YAML alias / 等）|
| `references/debug-tips.md` | 在无 admin auth 限制下 debug GitHub Actions step log 的 5+ 种方法 |
| `examples/mp-ci.yml` | 完整可用的 workflow（含体验版 QR，可直接用） |

## 速查：errcode

| errcode | 含义 | 修法 |
|---|---|---|
| `40001` invalid credential | AppSecret 错 | 重置 + 确认是小程序 secret（非公众号）|
| `40125` invalid appsecret | 填了公众号 secret | 用小程序 secret |
| `41001` access_token missing | access_token 不在正确位置 | 移到 URL query（`?access_token=...`）|
| `40013` invalid appid | appid 错 | 重新核对 WX_APPID |
| `40066` invalid path | path 不在 app.json pages | 修 path |
| `45009` / `45002` | 调用频率超限 | 等几小时 |
| `errcode=20002` | miniprogram-ci 报：把 AppSecret 当 PEM 用了 | 换成真 PEM 私钥 |
| `ERR_PNPM_OUTDATED_LOCKFILE` | lockfile specifier 跟 package.json 不同步 | 改 lockfile specifier 后 commit |

## 速查：WeChat 平台状态

| 状态 | 触发 | 哪些 QR 能用 |
|---|---|---|
| 开发版 | miniprogram-ci upload 默认 | dev preview |
| 体验版 | mp 后台手动设 / `upload --rv 1` | dev preview（体验版不能扫）|
| 审核版 | 提交审核后 | dev preview |
| **已发布** | 走完提交审核 + 审核通过 + 点击发布 | dev preview + 体验版 + 正式 |
