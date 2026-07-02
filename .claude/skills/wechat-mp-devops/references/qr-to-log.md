# 把 QR code 渲染到 CI log（不用下载图片）

## 痛点

CI 生成的 QR code 默认作为 artifact 上传（`.png` 或 `.jpg`）。**每次要扫码都得**：
1. 打开 GitHub Actions run 页面
2. 找到 artifact
3. 下载
4. 打开图片
5. 用微信扫

**能不能在 log 里直接看到 QR，扫码就行？**

## 解决方案：Unicode block QR

GitHub Actions log 是**纯文本** + **monospace 字体**。用 **Unicode block characters** 画 QR：

| 字符 | 含义 |
|---|---|
| `██` | 全块（黑黑）|
| `▀▀` | 上半块（黑空）|
| `▄▄` | 下半块（空白）|
| `  ` | 空白 |

每个字符占 2 行高度（top + bottom），每列 1 个字符宽度。

**优点**：
- ✅ 不依赖任何系统工具（只需 `python3 + Pillow`）
- ✅ 不用下载图片
- ✅ 打开 log 直接扫码
- ✅ 在手机浏览器看 GitHub log 也能扫

**缺点**：
- ❌ QR 缩放到 ~60 字符宽，分辨率比原始 PNG 低
- ❌ log 文件变大（几 KB）
- ❌ 字体非 monospace 时 QR 变畸形

## 完整实现

加一个 step 到 workflow：

```yaml
- name: Render QR to log (Unicode block)
  if: always()
  working-directory: apps/mp
  run: |
    if [ ! -f qrcode.png ]; then
      echo "(qrcode.png not found, skip)"
      exit 0
    fi
    python3 -m pip install --quiet --break-system-packages Pillow 2>&1 | tail -2
    python3 << 'EOF'
    from PIL import Image
    img = Image.open('qrcode.png').convert('1')
    target = 60  # log 显示宽度（字符数）
    w, h = img.size
    scale = max(1, max(w, h) // target)
    img = img.resize((max(1, w // scale), max(1, h // scale)))
    w, h = img.size
    print(f"\n>>> dev preview QR (PNG: {w*scale}x{h*scale}, log 中扫码用) <<<\n")
    for y in range(0, h, 2):
        line = ''
        for x in range(w):
            top = img.getpixel((x, y))
            bottom = img.getpixel((x, y+1)) if y+1 < h else 0
            if top and bottom: line += '██'
            elif top: line += '▀▀'
            elif bottom: line += '▄▄'
            else: line += '  '
        print(line)
    print(f"\n>>> 扫码后进 dev preview，30 分钟内有效 <<<\n")
    EOF
```

**注意**：
- `if: always()` 让 build 失败时也跑（生成 partial QR）
- `python3 -m pip install --break-system-packages` 装 Pillow（GitHub Actions runner 默认没 PIL）
- `target = 60` 调节 QR 宽度 — 越大越清晰，log 越长
- `if [ ! -f qrcode.png ]` 跳过缺失情况

## 替代方案

### 方案 1：直接用 `qrencode` 命令（如果 runner 有）

```bash
sudo apt-get install -y qrencode
# 但需要 URL 作为输入，miniprogram-ci 不暴露 URL
```

→ **不推荐**：依赖 apt + 拿不到 URL。

### 方案 2：用 `miniprogram-ci preview --qrcode-format terminal` 跑第二次

```bash
# 第一次：生成 PNG (artifact)
miniprogram-ci preview --qrcode-format image --qrcode-output-dest qrcode.png ...
# 第二次：生成 ASCII QR (log) — 但也会再上传一次到 WeChat
miniprogram-ci preview --qrcode-format terminal ...
```

→ **不推荐**：每次 push 上传 2 次到 WeChat，可能触发频率限制。

### 方案 3：✅ Unicode block (本文方案)

不依赖外部工具，不重复上传，只用 Pillow（miniprogram-ci 间接依赖之一）。

## 实际效果示例

```
>>> dev preview QR (PNG: 470x470, log 中扫码用) <<<

██▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄██
██ ▀▀▀ ████ ███ ████ █▀▀▀▀▀█ ██ ▀▀▀█ ██  ▀▀▀ ████ ████ ▀▀▀▀▀▀▄▄▄▄▀▀▀▄▄▄▄▄▄▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀██
...
██▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀██

>>> 扫码后进 dev preview，30 分钟内有效 <<<
```

每个 ASCII QR 字符画 ~30 行（QR version 3 = 29x29 像素 → 15 行 block + 半行）。

## 性能

- `pip install Pillow` 冷启动 ~5-10s，缓存后 ~1s
- PNG → ASCII 转换 ~100-500ms
- 整个 step 通常 < 15s

## 测试

1. push 一次
2. 打开 GitHub Actions run 页面
3. 找到 "Render QR to log" step
4. **展开 log**
5. 用微信扫 log 里的 QR（**注意 GitHub 默认折叠 log** —— 要点开）

> 实际生产中，可以让 step 默认 `set -e` + echo 成功标志，
> 但 `if: always()` + `exit 0` 防止它失败阻塞 CI。
