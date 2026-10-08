# zbp-app-lint

对 Z-BlogPHP 插件 / 主题仓库统一执行 **ESLint**（JS）与 **PHP-CS-Fixer**（PHP）检查或自动修复。

## 使用

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: wdssmq/zbp-app-lint@v1
```

带参数（默认 `changed-only: 'true'`，仅处理本次事件变更的文件）：

```yaml
      - uses: wdssmq/zbp-app-lint@v1
        with:
          path: 'live2d2'        # 要检查的目录（相对仓库根），默认 '.'
          mode: 'check'          # 'check'（默认）或 'fix'
          eslint: 'true'         # 是否运行 ESLint
          php: 'true'            # 是否运行 PHP-CS-Fixer
          fixer-version: 'v3.7.0'  # php-cs-fixer phar 版本
```

全量扫描整个 `path` 目录（关闭增量）：

```yaml
      - uses: wdssmq/zbp-app-lint@v1
        with:
          path: 'live2d2'
          changed-only: 'false'   # 关闭增量，跑整个目录
```

## Inputs

| name            | 默认值   | 说明                                                                                 |
| --------------- | -------- | ------------------------------------------------------------------------------------ |
| `path`          | `.`      | 检查目标目录，相对仓库根目录                                                         |
| `mode`          | `check`  | `check`：仅检查，发现问题输出 diff 并使 action 失败；`fix`：自动修复，改动留在工作区 |
| `eslint`        | `true`   | 是否运行 ESLint                                                                      |
| `php`           | `true`   | 是否运行 PHP-CS-Fixer                                                                |
| `fixer-version` | `v3.7.0` | php-cs-fixer phar 的 GitHub Release tag                                              |
| `php-version`   | `7.4`    | 通过 [shivammathur/setup-php@v2](https://github.com/shivammathur/setup-php) 安装的 PHP 版本 |
| `changed-only`  | `true`   | 仅检查/修复本次事件中变更的 PHP/JS 文件；设 `false` 走全量扫描（见「增量模式」）      |

## Outputs

| name            | 取值                                                  | 说明              |
| --------------- | ----------------------------------------------------- | ----------------- |
| `eslint-status` | `passed` / `failed` / `fixed-with-issues` / `skipped` | ESLint 结果       |
| `php-status`    | 同上                                                  | PHP-CS-Fixer 结果 |
| `any-changed`   | `true` / `false`                                      | 本次事件是否存在变更文件（仅在 `changed-only=true` 时有意义），可用于决定是否执行后续 commit/push |

## 模式说明

- **check**（默认）：ESLint 直接报告问题；php-cs-fixer 以 `--dry-run --diff` 运行并输出 diff；任一工具发现问题即 `exit 1`。问题详情会同时写入日志与 Step Summary。
- **fix**：ESLint `--fix`、php-cs-fixer `fix`，改动留在工作区由调用方决定如何提交。例如配合 [git-auto-commit-action](https://github.com/stefanzweifel/git-auto-commit-action)：

```yaml
      - uses: wdssmq/zbp-app-lint@v1
        with:
          mode: 'fix'
      - uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: 'style: auto-fix by zbp-app-lint'
```

  默认增量模式下，无变更时不会产生任何改动；为避免空 commit/空 push，可在后续步骤加 `if: steps.lint.outputs.any-changed == 'true'`。

## 配置解析（内置 + 可覆盖）

- **ESLint**：若目标目录或仓库根存在 `eslint.config.{js,mjs,cjs}` 则优先使用调用方配置（此时需调用方自行安装配置中依赖的插件，如仓库内有 `package.json` + `node_modules` 即可）；否则使用 action 内置配置（见 `config/eslint.config.mjs`，含 `zbp` / `bloghost` / `jQuery` 等 Z-Blog 全局变量，缩进 2、双引号、强制分号等）。
- **PHP-CS-Fixer**：若目标目录或仓库根存在 `.php-cs-fixer.dist.php` / `.php-cs-fixer.php` 则优先使用；否则使用内置规则，见 `config/.php-cs-fixer.dist.php`。

内置规则仅通过 `--config` 参数引用，不会写入调用方仓库；npm 安装产物与 phar 均落在 action 目录内。

## 增量模式（默认开启）

`changed-only` 默认 `true`。action 在执行前会调用 [`tj-actions/changed-files@v47`](https://github.com/tj-actions/changed-files) 收集本次事件中新增/修改的 `*.php` / `*.js` / `*.mjs` / `*.cjs` 文件，然后仅对这些文件运行 ESLint 与 PHP-CS-Fixer；无任何匹配文件时直接跳过所有步骤（不安装 PHP、不下载 phar、不 npm install）并以成功结束。

### 各事件的变更集语义

| 事件 | 变更基准 |
| --- | --- |
| `push` | 与本次推送前的提交比较 |
| `pull_request` | 与 PR base 提交比较 |
| `workflow_dispatch` / `schedule` | 通常没有差异，会整体跳过（请显式设 `changed-only: 'false'` 跑全量） |

### 调用方要求

- `actions/checkout` 需要足够的 git 历史，否则 `tj-actions/changed-files` 拿不到 `before` 提交。建议 `with: fetch-depth: 0`（与本仓库自检的 checkout 一致）。
- action 引用时建议 pin 到带新增 `changed-only` 输入的 tag。

### 已知限制

- 变更文件列表以空格分隔传递，**文件名含空格会被错误拆分**，无法正确归属到工具。
- 增量模式跳过的不只是 lint，**整个 action 步骤（包括 setup-php / phar 下载 / npm install）都会被短路**——这是省时间的设计，但请勿将本 action 视为"流程前置"，否则后续步骤会拿不到 PHP/Node 工具链。如确有依赖，需关闭 `changed-only` 或前置单独跑 setup。

### 需要全量扫描时

```yaml
      - uses: wdssmq/zbp-app-lint@v1
        with:
          changed-only: 'false'
```

## 环境要求

Runner 需自带 Node.js ≥ 18.18（ESLint 9 要求）。PHP 由本 action 通过 [`shivammathur/setup-php@v2`](https://github.com/shivammathur/setup-php) 安装，默认版本见 `php-version` 输入。

## 本仓库自检

`.github/workflows/lint.yml` 会用本 action 检查 `config/` 目录下内置配置文件本身（check 模式），并对 `tests/fixtures/` 中的故意不规范样例做 fix 冒烟测试（验证改动确实产生、修复后 check 通过）；由于默认 `changed-only: 'true'` 会让自检被短路，自检调用全部显式传 `changed-only: 'false'`，并新增一个直接调 `scripts/lint.sh` 的"增量空列表短路"冒烟。

## 本地调试

脚本兼容 Git Bash：

```bash
GITHUB_WORKSPACE=/path/to/your-plugin bash scripts/lint.sh --path . --mode check
```

## 缓存说明

action 内置 `actions/cache` 步骤缓存 `node_modules` 与 `php-cs-fixer.phar`，key 中含 fixer 版本。若升级 `package.json` 中的 eslint 依赖版本，需同步修改 `action.yml` 中缓存 key 的 `eslint-9.39` 字样以失效旧缓存。
