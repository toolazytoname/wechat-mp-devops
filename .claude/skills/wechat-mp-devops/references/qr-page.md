# QR 显示到 Web 页面（HTML + Cloudflare Pages）

## 场景

CI 生成的 QR 怎么**方便开发者/团队**扫码？
- ❌ **下载 PNG → 打开图片 → 扫**：3 步
- ❌ **GitHub Actions log 输出 ASCII QR**：GitHub log 字体 aspect ratio 不可控，扫不出（monospace 字体 char cell 是 1:2，不是 1:1，QR 被压成长方形）
- ❌ **GitHub Pages 子路径**：`toolazytoname.github.io/GridGo/` 被 personal blog 占用，404
- ❌ **jsDelivr CDN**：设了 `X-Content-Type-Options: nosniff` + `Content-Type: text/plain`，浏览器不渲染

## 推荐方案：HTML + Cloudflare Pages

CI 生成单个 HTML 文件（含 base64 embed 的 QR），部署到 Cloudflare Pages，给一个永久链接 `https://xxx.pages.dev/`。

**优势**：
- ✅ 浏览器渲染 SVG / base64 image（保证 1:1）
- ✅ Cloudflare Pages 无限带宽 + 最快 CDN
- ✅ 跟 personal blog 域名（`*.github.io`）完全独立
- ✅ 每次 push 自动更新
- ✅ 一次 push 一个 URL（dev preview + experience QR 同页面）

## 完整实现

### Step 1：CI 生成 HTML（base64 embed PNG）

```yaml
- name: Generate HTML QR (base64 embed PNG)
  if: always()
  working-directory: apps/mp
  run: |
    if [ ! -f qrcode.png ]; then
      echo "(qrcode.png not found, skip)"
      exit 0
    fi
    python3 << 'EOF'
    import base64
    from datetime import datetime, timedelta, timezone
    # 用 UTC+8 北京时间 (中国 user 友好)
    tz_beijing = timezone(timedelta(hours=8))
    now = datetime.now(tz_beijing)
    exp = now + timedelta(minutes=30)
    ts_now = now.strftime('%Y-%m-%d %H:%M:%S')
    ts_exp = exp.strftime('%Y-%m-%d %H:%M:%S')
    with open('qrcode.png', 'rb') as f:
        img_b64 = base64.b64encode(f.read()).decode('ascii')
    # 不用 f-string (避开 { 在 YAML block literal 解析错)
    # 不用 chr(123) (避免代码晦涩)
    # 用 + 字符串拼接
    html = (
        '<!DOCTYPE html><html><head><meta charset=utf-8>'
        '<title>GridGo QR</title>'
        '<style>body{font-family:sans-serif;background:#fafafa;margin:0;padding:24px;text-align:center}'
        '.card{max-width:380px;margin:0 auto;background:white;border-radius:16px;padding:32px;box-shadow:0 4px 20px rgba(0,0,0,.08)}'
        'h1{color:#3b6df6;margin:0 0 8px}'
        'h2{color:#1a1a1a;margin:24px 0 8px;font-size:18px;border-top:1px solid #eee;padding-top:24px}'
        '.ts{background:#f3f4f6;border-radius:8px;padding:12px;margin:16px 0;font-size:13px;color:#374151;text-align:left}'
        '.qr{padding:16px;display:inline-block}'
        '.qr img{display:block;width:280px;height:280px}'
        'p{color:#7a7a82;font-size:13px}'
        '</style></head><body><div class=card>'
        '<h1>格行 GridGo</h1>'
        '<div class=ts>生成（UTC+8 北京）: ' + ts_now + '<br>过期（UTC+8 北京）: ' + ts_exp + '</div>'
        '<h2>Dev preview · 30 分钟有效</h2>'
        '<div class=qr><img src="data:image/png;base64,' + img_b64 + '"></div>'
        '<p>开发者本地扫码测试</p>'
        '<div id=experience-slot></div>'   # ← experience QR 追加到这里
        '</div></body></html>'
    )
    with open('qrcode.html', 'w', encoding='utf-8') as f:
        f.write(html)
    print('qrcode.html: ' + str(len(html)) + ' bytes (base64 embed PNG ' + str(len(img_b64)) + ' bytes)')
    EOF
```

**为什么 base64 embed 比 SVG path 好**：

| 方案 | HTML 大小 | 需要 Pillow? | 优点 |
|---|---|---|---|
| SVG path | 几 MB (470×470 cells) | ✅ | 矢量可缩放 |
| base64 embed | ~70KB | ❌ | 小 30 倍，标准库即可 |

### Step 2：CI 生成 Experience QR (追加到同页面)

```yaml
- name: Generate experience QR (long-lived)
  if: always()
  working-directory: apps/mp
  env:
    WX_APPID: ${{ secrets.WX_APPID }}
    WX_APP_SECRET: ${{ secrets.WX_APP_SECRET }}
  run: |
    set +e  # 任何失败 exit 0 — 不阻塞 dev preview
    # 1. 拿 access_token
    TOKEN_RESP=$(curl -sS --max-time 15 "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=$WX_APPID&secret=$WX_APP_SECRET")
    ACCESS_TOKEN=$(printf '%s' "$TOKEN_RESP" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("access_token"); print(v if v else "")')
    if [ -z "$ACCESS_TOKEN" ]; then
      echo "❌ access_token 取不到: $TOKEN_RESP"
      exit 0
    fi
    # 2. 调 getwxacodeunlimit (access_token 在 URL query)
    curl -sS --max-time 15 -X POST \
      "https://api.weixin.qq.com/wxa/getwxacodeunlimit?access_token=${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"scene":"dev","path":"pages/matrix/matrix","width":430}' \
      -o experience-qrcode.bin
    # 3. 判定 JPEG / PNG
    FIRST2=$(head -c 2 experience-qrcode.bin 2>/dev/null | od -An -tx1 | tr -d ' \n')
    FIRST4=$(head -c 4 experience-qrcode.bin 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ "$FIRST2" = "ffd8" ]; then
      mv experience-qrcode.bin experience-qrcode.jpg
      EXT="jpg"
    elif [ "$FIRST4" = "89504e47" ]; then
      mv experience-qrcode.bin experience-qrcode.png
      EXT="png"
    else
      echo "❌ not image (小程序可能未发布): $(head -c 200 experience-qrcode.bin)"
      exit 0
    fi
    # 4. 追加到 qrcode.html
    export EXT
    python3 << 'PYEOF'
    import base64, os
    ext = os.environ.get('EXT', 'png')
    with open('qrcode.html', 'r', encoding='utf-8') as f:
        html = f.read()
    with open('experience-qrcode.' + ext, 'rb') as f:
        exp_b64 = base64.b64encode(f.read()).decode('ascii')
    exp_block = (
        '<h2>Experience · 长期有效</h2>'
        '<div class=qr><img src="data:image/' + ext + ';base64,' + exp_b64 + '"></div>'
        '<p>团队成员扫码进体验版<br>需先在 mp.weixin.qq.com 发布 + 成员管理添加</p>'
    )
    slot = '<div id=experience-slot></div>'
    if slot in html:
        html = html.replace(slot, exp_block)
    else:
        html = html.replace('</div></body>', exp_block + '</div></body>')
    with open('qrcode.html', 'w', encoding='utf-8') as f:
        f.write(html)
    print('appended experience QR (' + str(len(exp_b64)) + ' bytes base64) to qrcode.html')
    PYEOF
```

### Step 3：部署到 Cloudflare Pages

```yaml
# GitHub Secrets 需要:
#   CLOUDFLARE_API_TOKEN  - Cloudflare Dashboard → My Profile → API Tokens → Create Custom Token
#   CLOUDFLARE_ACCOUNT_ID  - Dashboard 右下角 "Account ID"

- name: Ensure Cloudflare Pages project exists
  if: always()
  env:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
  run: |
    # wrangler 4.x 不会自动创建 Pages project
    npx wrangler pages project create gridgo-mp-qr --production-branch=main 2>&1 | tail -10 || echo "(project may already exist)"

- name: Deploy QR to Cloudflare Pages
  if: always()
  env:
    CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
  run: |
    if [ ! -f apps/mp/qrcode.html ]; then
      echo "(no qrcode.html, skip)"
      exit 0
    fi
    DEPLOY_DIR=$(mktemp -d)
    mkdir -p "$DEPLOY_DIR/mp-qrcode"
    cp apps/mp/qrcode.html "$DEPLOY_DIR/mp-qrcode/index.html"
    cp apps/mp/qrcode.png "$DEPLOY_DIR/mp-qrcode/qrcode.png"
    [ -f apps/mp/experience-qrcode.jpg ] && cp apps/mp/experience-qrcode.jpg "$DEPLOY_DIR/mp-qrcode/"
    [ -f apps/mp/experience-qrcode.png ] && cp apps/mp/experience-qrcode.png "$DEPLOY_DIR/mp-qrcode/"
    # 根 index.html 重定向
    printf '%s' '<!DOCTYPE html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0;url=mp-qrcode/"></head><body></body></html>' > "$DEPLOY_DIR/index.html"
    cd "$DEPLOY_DIR"
    npx wrangler pages deploy . --project-name=gridgo-mp-qr --commit-dirty=true 2>&1 | tail -10
    if [ $? = "0" ]; then
      echo ""
      echo "📱 扫码链接：https://gridgo-mp-qr.pages.dev/mp-qrcode/"
    fi
```

## Cloudflare API Token 设置步骤

1. https://dash.cloudflare.com → My Profile → API Tokens → Create Token
2. **Create Custom Token**
3. 权限：
   - Account → Cloudflare Pages → **Edit**
   - Account → Account Settings → **Read**
4. 不用 IP filtering（GitHub Actions 动态 IP）
5. Create → 复制 token
6. `CLOUDFLARE_ACCOUNT_ID` = Dashboard 右下角 "Account ID"（32 位 hex）

把 token 加到 GitHub Secrets：
- `CLOUDFLARE_API_TOKEN` = 复制的 token
- `CLOUDFLARE_ACCOUNT_ID` = 32 位 hex

## 为什么不推荐其他方案

| 方案 | 失败原因 |
|---|---|
| **GitHub Pages** | `<user>.github.io` 被 personal blog 占用，子路径 404 |
| **jsDelivr** | `nosniff` + `text/plain`，浏览器不渲染 |
| **raw.githack** | 服务不稳定 |
| **Statically** | API 格式常变，404 |
| **surge.sh** | 需注册账号 + token，配置稍多 |
| **ASCII QR to log** | monospace 字体 char aspect 不可控，QR 长方形扫不出 |
| **Netlify Drop** | 每次 push 要手动重拖（除非配 token 自动化） |

**Cloudflare Pages** 是唯一同时满足：
- 0 配置（除了 2 个 GitHub Secret）
- 无限带宽
- 正确 content-type
- 不依赖个人域名
- 每次 push 自动更新

## 时间戳时区选择

```python
# 北京时间 (UTC+8) - 中国 user 推荐
from datetime import timezone, timedelta
tz = timezone(timedelta(hours=8))
now = datetime.now(tz)

# UTC - 国际 / CI 默认
from datetime import timezone
now = datetime.now(timezone.utc)
```

显示建议：
- 中国 user: `生成（UTC+8 北京）: 2026-07-03 19:21:13`
- 国际 user: `Generated (UTC): 2026-07-03T11:21:13Z`
