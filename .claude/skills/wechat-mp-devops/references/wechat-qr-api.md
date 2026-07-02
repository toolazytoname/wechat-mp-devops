# WeChat QR API（getwxacodeunlimit / getwxacode / getwxacodeunlimit）

WeChat 提供 **3 个**生成小程序二维码的 HTTP API，加上 miniprogram-ci 自带 1 个，一共 4 条路径。

## API 对比

| API | access_token 位置 | 返回图片 | 需要已发布？ | 限制 |
|---|---|---|---|---|
| `cgi-bin/token` | 都不需要 | （拿 token）| ❌ | 2000 次/天 per appid |
| **`wxa/getwxacodeunlimit`** | **URL query** | **JPEG** | ✅ | 5 万次/月 per appid |
| `wxa/getwxacode` | URL query | PNG | ✅ | 5 万次/月 per appid |
| `wxa/createwxaqrcode` | URL query | PNG | ✅ | 几乎无限 |
| `miniprogram-ci preview` | 不需要（走 TLS 私钥）| JPEG | ❌ | **30 分钟有效** |

## ⚠️ 关键陷阱：access_token 必须在 URL query

`getwxacodeunlimit`（2017 年的老 API）**要求 access_token 在 URL query**：
```
POST https://api.weixin.qq.com/wxa/getwxacodeunlimit?access_token=ACCESS_TOKEN
Content-Type: application/json

{"scene":"dev","path":"pages/matrix/matrix","width":430}
```

**如果 access_token 放在 body 里**（`{"access_token": "...", "scene": "..."}`）：
```json
{"errcode": 41001, "errmsg": "access_token missing rid: xxx"}
```

## ⚠️ 关键陷阱：实际返 JPEG，不是 PNG

`getwxacodeunlimit` 文档说返 image，**没说 PNG/JPEG**。**实际返 JPEG**（FF D8 FF E0）。

判定逻辑：
```bash
FIRST2=$(head -c 2 response.bin | od -An -tx1 | tr -d ' \n')
if [ "$FIRST2" = "ffd8" ]; then
  # JPEG
  mv response.bin response.jpg
elif [ "$FIRST4" = "89504e47" ]; then
  # PNG
  mv response.bin response.png
fi
```

**很多现成代码**只检查 PNG magic (`89504e47`)，**会把 70KB 的 JPEG 误判为"非 PNG"**而不保存。

## ⚠️ 关键陷阱：要求小程序"已发布"

`getwxacodeunlimit` 严格要求**已发布**的版本。"体验版"**不算**。

- 未发布 → 扫码提示"小程序尚未发布"
- 仅设体验版 → 同上
- 走完"提交审核 → 审核通过 → 点击发布" → ✅

**dev preview QR 不需要已发布**——未发布的小程序也能用。

## 完整 curl 示例

```bash
# 1. 拿 access_token
TOKEN_RESP=$(curl -sS "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=$WX_APPID&secret=$WX_APP_SECRET")
ACCESS_TOKEN=$(echo "$TOKEN_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token") or "")')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ access_token 取不到: $TOKEN_RESP"
  exit 1
fi

# 2. 生成 QR（access_token 在 URL query！）
curl -sS -X POST \
  "https://api.weixin.qq.com/wxa/getwxacodeunlimit?access_token=${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"scene":"dev","path":"pages/matrix/matrix","width":430}' \
  -o qrcode.bin

# 3. 判定图片格式
FIRST2=$(head -c 2 qrcode.bin | od -An -tx1 | tr -d ' \n')
if [ "$FIRST2" = "ffd8" ]; then
  mv qrcode.bin qrcode.jpg
elif [ "$(head -c 4 qrcode.bin | od -An -tx1 | tr -d ' \n')" = "89504e47" ]; then
  mv qrcode.bin qrcode.png
else
  # 不是图片，dump 错误
  head -c 500 qrcode.bin
fi
```

## 完整 errcode 速查

| errcode | 含义 | 修法 |
|---|---|---|
| `40001` invalid credential | AppSecret 错 | 重置 + 确认是小程序 secret |
| `40125` invalid appsecret | 填了公众号 secret | 用小程序 secret |
| `41001` access_token missing | access_token 位置错 | 移到 URL query |
| `40013` invalid appid | appid 错 | 重新核对 WX_APPID |
| `40066` invalid path | path 不在 app.json pages | 修 path |
| `40159` | path 不合法 | path 必须在小程序中已声明 |
| `45009` | 调用频率超限（5万/月）| 等下个月 |
| `45002` | 频次超限 | 等几分钟 |
| `85009` | stale state（刚 reset secret）| 等 5-10 分钟 |
| `-1` / system error | WeChat 系统繁忙 | 重试 |

## access_token 处理 Python 模板

```python
import json, sys
data = json.load(sys.stdin)
token = data.get("access_token")
# ⚠️ 关键：用 `or ""` 处理 None（access_token=null 时 print(None) 会输出 "None" 字符串）
print(token if token else "")
```

```bash
ACCESS_TOKEN=$(echo "$TOKEN_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("access_token"); print(v if v else "")')
```

**不写 `or ""` 的坑**：如果 `data` 是 `{"access_token": null}`，`data.get("access_token")` 返回 `None`，`print(None)` 输出字符串 `"None"`（4字符），bash 拿到非空字符串，以为拿到 token，实际上是字面 "None" — 后续 API 报 40001 让人一头雾水。
