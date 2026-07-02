# CI/CD 常见坑（8 个真实踩过的）

## 1. pnpm-lock.yaml specifier 跟 package.json 不同步

**症状**：
```
ERR_PNPM_OUTDATED_LOCKFILE
Cannot install with "frozen-lockfile" because pnpm-lock.yaml is not up to date
specifiers in the lockfile ({"miniprogram-ci":"^2.1.0"})
don't match specs in package.json ({"miniprogram-ci":"^2.1.31"})
```

**根因**：本地 `apps/mp/node_modules` 已存在时，pnpm 跳过 lockfile 校验。**CI 干净环境**（无 node_modules）立刻报。

**修法**：
- 改 lockfile specifier 行（最快）：
  ```yaml
  apps/mp:
    devDependencies:
      miniprogram-ci:
        specifier: ^2.1.31      # 跟 package.json 一致
        version: 2.1.31(eslint@8.57.1)
  ```
- 或 `pnpm install --no-frozen-lockfile` 让 lockfile 同步

**预防**：每次改 `package.json` 后跑一次 `pnpm install` 并 commit lockfile。

## 2. workflow `paths` filter 漏掉 lockfile

**症状**：改了 `pnpm-lock.yaml` 后 push，**MP CI 没跑**。

**根因**：
```yaml
on:
  push:
    paths:
      - 'apps/mp/**'
      - '.github/workflows/mp-ci.yml'  # 缺 'pnpm-lock.yaml'!
```

lockfile 改了不影响 `apps/mp/**` 也不影响 workflow 文件本身，filter 把它过滤掉。

**修法**：
```yaml
paths:
  - 'apps/mp/**'
  - '.github/workflows/mp-ci.yml'
  - 'pnpm-lock.yaml'         # lockfile 改了也会影响 miniprogram-ci 解析
```

## 3. YAML block literal 里 `:` 被当 key 分隔符

**症状**：
```yaml
python3 -c "
import sys
try:
  with open('qrcode.raw','rb') as f: d=f.read(4)
"
```

→ YAML 解析失败，workflow 0 秒 fail。

**根因**：`with open('qrcode.raw','rb') as f:` 里的 `:` 后面有空格，YAML 当成 key-value。

**修法**：
- 多行 Python 用 `> ` 折叠 scalar（仍可能有问题）
- 写成一行（用 `;` 分隔）
- 用 heredoc 写到文件再执行

## 4. Python f-string + 反斜杠 `\"`

**症状**：
```python
print(f"errcode={d.get(\"errcode\",\"-\")}")
```

→ `SyntaxError: f-string: expression part cannot include a backslash`

**根因**：Python 3.10/3.11 的 f-string 表达式里**不能用反斜杠转义**（3.12+ 解禁）。

**修法**：
- 拆成两个变量：`ERR_CODE` 和 `ERR_MSG` 各自一个 `print`
- 用 `format()` 代替 f-string
- 用 `%` 格式化

## 5. `print(None)` 输出字符串 `"None"`

**症状**：
```python
import json, sys
print(json.load(sys.stdin).get("access_token",""))
# 如果 JSON 是 {"errcode":40001}，输出 ""（OK）
# 如果 JSON 是 {"access_token": null}，输出 None 字符串（4字符！）
```

→ bash `$()` 拿到 `"None"`，`if [ -z ]` 检查非空通过，后续 API 用 `"None"` 当 token，WeChat 返 40001。

**修法**：
```python
v = d.get("access_token")
print(v if v else "")   # None → ""；"" → ""；"abc" → "abc"
```

## 6. GitHub Actions 默认 GITHUB_TOKEN 无写权限

**症状**：
- `gh issue create` / `git push` / 写 commit status **静默失败**（`set -e` 关掉时）

**根因**：默认 `permissions: read-all`。要写需显式声明。

**修法**：
```yaml
permissions:
  contents: write        # git push
  issues: write          # gh issue / API
  statuses: write        # commit status
```

## 7. 临时目录里 git push 失败

**症状**：`actions/checkout@v4` 配的 SSH key 只对**原 checkout 目录**有效。`cd /tmp/foo && git init && git push` 找不到 key。

**修法**：用 HTTPS + access token URL：
```bash
git push "https://x-access-token:${GITHUB_TOKEN}@github.com/owner/repo.git" branch
```

## 8. YAML `**foo**` markdown 被当 alias

**症状**：
```yaml
echo "排查：去 mp.weixin.qq.com 确认 WX_APP_SECRET 是**小程序**的"
```

→ `yaml.scanner.ScannerError: while scanning an alias ... expected alphabetic or numeric character, but found '*'`

**根因**：YAML `|` block literal 里 `*` 开头被当成 alias 标记（`*foo`）。

**修法**：
- 把字符串写到文件（`gh issue create --body-file`）
- 用 `>` 折叠 scalar + 双引号包（要 escape）
- 把 `*` 换成 `**` 之外的强调符号（如 `「」` 或 反引号）
