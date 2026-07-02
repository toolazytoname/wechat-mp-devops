# WX_PRIVATE_KEY vs WX_APP_SECRET

微信小程序**有两个看起来很像但完全不同的 secret**，混用会出各种错。

## 速查表

| Secret | 格式 | 来源 | 用途 | 字符数 |
|---|---|---|---|---|
| **`WX_PRIVATE_KEY`** | PEM 多行（`-----BEGIN RSA PRIVATE KEY-----` ... `-----END RSA PRIVATE KEY-----`）| mp.weixin.qq.com → 开发管理 → 开发设置 → "小程序代码上传" → 生成密钥 | 给 `miniprogram-ci` 上传/编译 | 1500+ 字符 |
| **`WX_APP_SECRET`** | 32 位 hex（`[0-9a-f]{32}`，一行）| mp.weixin.qq.com → 开发管理 → 开发设置 → "公众号开发信息" → AppSecret（重置后才会显示）| 给 WeChat HTTP API（`cgi-bin/token` 等）取 `access_token` | 32 字符 |

## 关键区别

1. **不同来源** — 同一个 mp.weixin.qq.com 账号下，**公众号 AppSecret ≠ 小程序 AppSecret**
   - 即使你只有小程序没公众号，mp 平台也会给一个"公众号开发信息"区，**那个 AppSecret 不能用在小程序 HTTP API**
   - 必须用"小程序 AppSecret"（**重置后才会显示**）

2. **不同格式** — 一个多行，一个一行
   - 把 32 位 hex 填到 `WX_PRIVATE_KEY`，miniprogram-ci 报 `errcode 20002`（密钥格式错）
   - 把 PEM 填到 `WX_APP_SECRET`，WeChat API 报 `40001 invalid credential`

3. **不同用途** — 一个给工具，一个给 API
   - `miniprogram-ci` 内部用 PEM 走 **TLS mutual auth** 直接连 WeChat，**不需要 access_token**
   - WeChat HTTP API 必须先调 `cgi-bin/token` 拿 `access_token` 才能调后续接口

## 获取步骤

### WX_PRIVATE_KEY（PEM）

1. 登录 https://mp.weixin.qq.com
2. **开发管理** → **开发设置**
3. 找到 **"小程序代码上传"** 区块
4. 点 **"生成"**（会弹窗提醒：旧的密钥会失效）
5. **复制生成的密钥**（整段含 `-----BEGIN/END-----` 头尾）
6. **立即**粘贴到 GitHub Secrets

> ⚠️ 旧密钥会**立即失效**，所以在 CI 用之前**别在 mp 后台换**。

### WX_APP_SECRET（hex）

1. 登录 https://mp.weixin.qq.com
2. **开发管理** → **开发设置**
3. 找到 **"公众号开发信息"** 区块（不是"小程序代码上传"！）
4. 看到 **AppSecret** 字段（默认是 `********` 隐藏）
5. 点 **"重置"**（如果有"显示"按钮直接显示也行）
6. 复制新生成的 32 位 hex

> ⚠️ 重置后**等待 5-10 分钟**让 WeChat 后端同步。立即用可能返 `invalid credential`。

## GitHub Secrets 配置

```
WX_APPID          = wxREDACTED_APPID  (项目固定, 来自 project.config.json)
WX_PRIVATE_KEY    = -----BEGIN RSA PRIVATE KEY-----\nREDACTED_PEM_BODY\n-----END RSA PRIVATE KEY-----
WX_APP_SECRET     = REDACTED_APPSECRET
```

## 排查混淆问题

### 症状 1：miniprogram-ci 报 `20002`

```
errcode: 20002, errmsg: "key format error"
```

→ 你把 32 位 hex 的 AppSecret 填到了 `WX_PRIVATE_KEY`。
→ **修法**：重新生成 PEM 私钥。

### 症状 2：cgi-bin/token 报 `40001`

```json
{"errcode":40001,"errmsg":"invalid credential"}
```

→ AppSecret 错。三种可能：
1. AppSecret 字符串有空格/换行
2. AppSecret 是**公众号**的，不是**小程序**的
3. AppSecret 刚重置还没生效（等 5-10 分钟）

→ **修法**：用 `printf '%s' "$WX_APP_SECRET" | wc -c` 确认是 32 字符无空格/换行。

### 症状 3：getwxacodeunlimit 报 `41001 access_token missing`

```json
{"errcode":41001,"errmsg":"access_token missing"}
```

→ token 拿到了，但传错位置。**不是** secret 类型错。
→ **修法**：把 access_token 移到 URL query（`?access_token=...`），**不要在 body**。详见 `wechat-qr-api.md`。
