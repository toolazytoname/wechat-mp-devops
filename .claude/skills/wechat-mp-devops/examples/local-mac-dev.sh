#!/usr/bin/env bash
# local-mac-dev.sh — macOS 本地一键 preview + 上传 + 打开 QR
#
# 用法:
#   1. 复制到项目 bin/mp-preview.sh，chmod +x
#   2. 项目根目录准备 .env.local，含 WX_APPID / WX_PRIVATE_KEY / WX_APP_SECRET
#   3. ./bin/mp-preview.sh                  # 默认 apps/mp 子项目
#      ./bin/mp-preview.sh apps/foo         # 指定子项目
#      ./bin/mp-preview.sh --no-open         # 不自动打开
#      ./bin/mp-preview.sh --qr-only        # 只生成 QR（不重新 build）
#
# 跟 CI workflow (examples/mp-ci.yml) 的区别:
#   - 加载 .env.local 而不是 GitHub Secrets
#   - QR 生成完直接 `open` 在 Preview.app 里（不用 upload artifact）
#   - 失败立刻 exit，不跳过（本地要看到错）

set -euo pipefail

# ---------- 参数解析 ----------
MP_DIR="apps/mp"
NO_OPEN=0
QR_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-open)   NO_OPEN=1; shift ;;
    --qr-only)   QR_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,18p' "$0"; exit 0 ;;
    *)
      MP_DIR="$1"; shift ;;
  esac
done

# ---------- 路径解析 ----------
# 脚本可能在 bin/ 下，回退到项目根
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR" == */bin ]]; then
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

cd "$PROJECT_ROOT"
echo "📁 project root: $PROJECT_ROOT"
echo "📦 mp dir:       $MP_DIR"

# ---------- 加载 .env.local ----------
ENV_FILE="$PROJECT_ROOT/.env.local"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌ 找不到 $ENV_FILE"
  echo "   在项目根目录创建 .env.local，含 WX_APPID / WX_PRIVATE_KEY / WX_APP_SECRET"
  echo "   （参考 .claude/skills/wechat-mp-devops/references/macos-setup.md）"
  exit 1
fi

# set -a: 自动 export 所有变量；set +a: 关掉
set -a
# shellcheck disable=SC1091
source "$ENV_FILE"
set +a

# ---------- 校验 ----------
missing=()
for v in WX_APPID WX_PRIVATE_KEY WX_APP_SECRET; do
  if [[ -z "${!v:-}" ]]; then
    missing+=("$v")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ .env.local 缺变量: ${missing[*]}"
  exit 1
fi

# WX_PRIVATE_KEY 是多行 PEM，校验头尾
if [[ "$WX_PRIVATE_KEY" != *"BEGIN RSA PRIVATE KEY"* ]] && \
   [[ "$WX_PRIVATE_KEY" != *"BEGIN PRIVATE KEY"* ]]; then
  echo "⚠️  WX_PRIVATE_KEY 看起来不是 PEM 格式"
  echo "   必须是 -----BEGIN ... PRIVATE KEY----- 开头"
  echo "   如果是 32 位 hex，那是 WX_APP_SECRET，填错了"
  exit 1
fi

# ---------- 检查 node_modules ----------
if [[ ! -x "$MP_DIR/node_modules/.bin/miniprogram-ci" ]]; then
  echo "⚙️  装 miniprogram-ci..."
  (cd "$MP_DIR" && npm install --no-audit --no-fund)
fi

# ---------- 写 PEM 到临时文件 ----------
# Mac 上 chmod 600 在 APFS 正常生效，不需要额外操作
KEY_DIR="$MP_DIR/.keys"
mkdir -p "$KEY_DIR"
PEM_FILE="$KEY_DIR/wx.pem"
printf '%s' "$WX_PRIVATE_KEY" > "$PEM_FILE"
chmod 600 "$PEM_FILE"
echo "🔑 PEM written: $PEM_FILE ($(wc -c < "$PEM_FILE") bytes, mode 600)"

# 清理函数：脚本退出（成功/失败）时删 PEM
cleanup() {
  rm -f "$PEM_FILE"
}
trap cleanup EXIT

# ---------- QR-only 模式：复用上次 build ----------
if [[ $QR_ONLY -eq 0 ]]; then
  echo ""
  echo "🚀 miniprogram-ci preview..."
  echo "   appid:    $WX_APPID"
  echo "   pp:       $MP_DIR/"
  echo ""

  (cd "$MP_DIR" && ./node_modules/.bin/miniprogram-ci preview \
    --appid "$WX_APPID" \
    --pkp "./.keys/wx.pem" \
    --pp ./ \
    --uv 1 --rv 1 \
    --enable-es6 true --enable-es7 true \
    --enable-minifyWXSS true --enable-minifyWXML true --enable-minifyJS true \
    --enable-qrcode \
    --qrcode-format image \
    --qrcode-output-dest ./qrcode.png)
fi

# ---------- 判定输出 ----------
QR_FILE="$MP_DIR/qrcode.png"
if [[ ! -f "$QR_FILE" ]]; then
  echo "❌ QR 没生成: $QR_FILE"
  exit 1
fi

# Magic bytes 校验 PNG (89504e47) 或 JPEG (ffd8)
FIRST4=$(head -c 4 "$QR_FILE" | od -An -tx1 | tr -d ' \n')
FIRST2=$(head -c 2 "$QR_FILE" | od -An -tx1 | tr -d ' \n')
case "$FIRST4" in
  89504e47) echo "✅ PNG: $QR_FILE ($(wc -c < "$QR_FILE") bytes)" ;;
  *)
    case "$FIRST2" in
      ffd8*) echo "✅ JPEG: $QR_FILE ($(wc -c < "$QR_FILE") bytes)" ;;
      *)     echo "❌ 输出不是图片 (magic=$FIRST4): $QR_FILE"; exit 1 ;;
    esac
    ;;
esac

# ---------- 计算 dev preview 过期时间 ----------
# 用 date 计算 +30 分钟（Mac BSD date 没有 -d，用 -v +30M）
EXPIRE_TS=$(date -v +30M "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || \
            python3 -c "from datetime import datetime, timedelta; print((datetime.now()+timedelta(minutes=30)).strftime('%Y-%m-%d %H:%M:%S'))")
echo "⏰ 过期: $EXPIRE_TS (30 分钟内有效)"

# ---------- 生成 HTML（30 分钟倒计时 + UTC+8 时间戳）----------
HTML_FILE="$MP_DIR/qrcode.html"
echo "🌐 生成 HTML: $HTML_FILE"
python3 << PYEOF
import base64
from datetime import datetime, timedelta, timezone

tz_beijing = timezone(timedelta(hours=8))
now = datetime.now(tz_beijing)
exp = now + timedelta(minutes=30)
ts_now = now.strftime('%Y-%m-%d %H:%M:%S')
ts_exp = exp.strftime('%Y-%m-%d %H:%M:%S')

# 判定图片格式，决定 mime
with open("$QR_FILE", "rb") as f:
    head = f.read(4)
mime = "image/jpeg" if head[:2] == b"\xff\xd8" else "image/png"
img_b64 = base64.b64encode(open("$QR_FILE","rb").read()).decode("ascii")

html = (
    '<!DOCTYPE html><html><head><meta charset=utf-8>'
    '<title>Dev Preview QR</title>'
    '<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#fafafa;margin:0;padding:24px;text-align:center}'
    '.card{max-width:380px;margin:0 auto;background:white;border-radius:16px;padding:32px;box-shadow:0 4px 20px rgba(0,0,0,.08)}'
    'h1{color:#3b6df6;margin:0 0 8px}'
    '.ts{background:#f3f4f6;border-radius:8px;padding:12px;margin:16px 0;font-size:13px;color:#374151;text-align:left}'
    '.qr{padding:16px;display:inline-block}'
    '.qr img{display:block;width:280px;height:280px}'
    'p{color:#7a7a82;font-size:13px}'
    '</style></head><body><div class=card>'
    '<h1>Dev Preview</h1>'
    '<div class=ts>生成（UTC+8 北京）: ' + ts_now + '<br>过期（UTC+8 北京）: ' + ts_exp + '</div>'
    '<div class=qr><img src="data:' + mime + ';base64,' + img_b64 + '"></div>'
    '<p>本地扫码测试 · 30 分钟有效</p>'
    '</div></body></html>'
)
with open("$HTML_FILE", "w", encoding="utf-8") as f:
    f.write(html)
print("✅ HTML: " + str(len(html)) + " bytes")
PYEOF

# ---------- 自动打开 ----------
if [[ $NO_OPEN -eq 0 ]]; then
  echo ""
  echo "📱 打开 QR..."
  # 用 -a Preview 强制 Preview.app；不写 -a 会用默认应用
  open -a Preview "$QR_FILE"
  # 顺便打开 HTML（浏览器，30 分钟倒计时明显）
  sleep 0.3
  open "$HTML_FILE"
fi

echo ""
echo "✅ 完成。下次改完代码再跑一次就行。"
echo "   不自动打开: $0 --no-open"
echo "   只重生成 QR: $0 --qr-only"