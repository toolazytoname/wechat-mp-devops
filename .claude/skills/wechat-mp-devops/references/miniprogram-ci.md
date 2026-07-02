# miniprogram-ci 完整说明

微信官方 CI 工具，封装了"代码上传/编译/二维码生成"等所有跟 WeChat 平台的交互。

## 安装

```bash
# 在项目里
npm install --save-dev miniprogram-ci
# 或在 CI runner 上
npm install -g miniprogram-ci
```

要求 Node.js >= 16.1。

## 子命令

| 子命令 | 作用 | 关键参数 |
|---|---|---|
| `build` | 只编译，输出到 `--uv` 指定的版本目录 | `--appid` `--pkp` `--pp` `--uv` |
| `upload` | 编译 + 上传代码到 mp 平台 | `--appid` `--pkp` `--pp` `--uv` `--rv` `--desc` |
| `preview` | 编译 + 上传 + 生成 dev preview QR | `--appid` `--pkp` `--pp` `--uv` `--enable-qrcode` `--qrcode-format` `--qrcode-output-dest` |

> **`preview` 是最常用的**——一条命令搞定 build + upload + QR。

## 关键参数

```
--appid, -a                  # 必填，小程序 appid
--private-key-path, --pkp    # 必填，PEM 私钥文件路径（不是字符串！）
--project-path, --pp         # 必填，小程序项目根目录
--upload-version, --uv       # 必填，上传版本号（任意字符串，如 "1.0.0"）
--robot-version, --rv        # 可选，设为 1 表示自动设为"体验版"
--upload-description, --ud   # 可选，版本描述
--enable-qrcode              # preview 专用，启用 QR 生成
--qrcode-format              # base64 | image | terminal（默认 terminal）
--qrcode-output-dest         # image 格式的输出文件路径
--enable-minify-js/wxml/wxss # 启用压缩
--threads                    # 编译线程数（0=自动）
```

## 完整 preview 示例

```bash
# 1. 私钥写到临时文件（miniprogram-ci 只接文件路径）
mkdir -p .keys
printf '%s' "$WX_PRIVATE_KEY" > .keys/wx.pem
chmod 600 .keys/wx.pem

# 2. preview 一条命令
./node_modules/.bin/miniprogram-ci preview \
  --appid "$WX_APPID" \
  --pkp ./.keys/wx.pem \
  --pp ./ \
  --uv 1 --rv 1 \
  --enable-es6 true --enable-es7 true \
  --enable-minifyWXSS true --enable-minifyWXML true --enable-minifyJS true \
  --enable-qrcode \
  --qrcode-format image \
  --qrcode-output-dest ./qrcode.png

# 3. 清理私钥
rm -f .keys/wx.pem
```

## 关于 `--uv` 和 `--rv`

- `--uv 1` — upload version 是 `1`（任意字符串）
- `--rv 1` — robot version 是 `1`，**自动把上传的代码设为"体验版"**（不用手动去 mp 后台设）
- 如果不传 `--rv`，代码上传后是**开发版**（开发者工具里能看到，但体验成员扫不到）

## QR 格式详解

| `--qrcode-format` | 输出 | 用途 |
|---|---|---|
| `terminal` | ASCII QR 到 stdout | 本地预览 |
| `base64` | base64 字符串到 stdout | 嵌入 HTML |
| **`image`** | **图片文件到 `--qrcode-output-dest`** | **CI 上传 artifact 用这个** |

`--qrcode-output-dest` 只能配 `image` 格式。

## Dev preview QR 的限制

`miniprogram-ci preview` 生成的 QR 是**开发版预览链接**，**30 分钟内有效**：
- ✅ **不需要**小程序已发布
- ✅ 任何状态（开发/体验/已发布）都能用
- ❌ 30 分钟后失效，要重新生成
- ❌ 普通微信用户扫码可能进不去（需要是**开发者**或**已加入体验成员**的微信号）

**对比体验版 QR**（用 `getwxacodeunlimit` HTTP API 生成）：
- ❌ 需要小程序**已发布**
- ✅ **长期有效**
- ✅ 任何微信扫码可进

详见 `wechat-qr-api.md`。

## 常见错误

### `errcode: 20002, errmsg: "key format error"`

你把 AppSecret（32位hex）填到了 `--pkp` 路径，**或者** PEM 私钥本身格式错。
→ 检查 PEM 是不是多行、含 `-----BEGIN/END-----`。

### `getCodeFiles: count: 0`

项目根目录不对（`--pp ./` 解析到了空目录）。
→ `--pp` 指向**含 `app.json` 的目录**。

### `[DEP0040] DeprecationWarning: punycode`

Node 18+ 警告，无害。可以忽略。

### `miniprogram-ci is using proxy: http://127.0.0.1:7890`

本地有 HTTP_PROXY 环境变量。CI runner 上**不会有**这个代理，所以 CI 不会受影响。
