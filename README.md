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

带参数：

```yaml
      - uses: wdssmq/zbp-app-lint@v1
        with:
          path: 'live2d2'        # 要检查的目录（相对仓库根），默认 '.'
          mode: 'check'          # 'check'（默认）或 'fix'
          eslint: 'true'         # 是否运行 ESLint
          php: 'true'            # 是否运行 PHP-CS-Fixer
          fixer-version: 'v3.64.0'  # php-cs-fixer phar 版本
```

## Inputs

| name            | 默认值    | 说明                                                                                 |
| --------------- | --------- | ------------------------------------------------------------------------------------ |
| `path`          | `.`       | 检查目标目录，相对仓库根目录                                                         |
| `mode`          | `check`   | `check`：仅检查，发现问题输出 diff 并使 action 失败；`fix`：自动修复，改动留在工作区 |
| `eslint`        | `true`    | 是否运行 ESLint                                                                      |
| `php`           | `true`    | 是否运行 PHP-CS-Fixer                                                                |
| `fixer-version` | `v3.64.0` | php-cs-fixer phar 的 GitHub Release tag                                              |

## Outputs

| name            | 取值                                                  | 说明              |
| --------------- | ----------------------------------------------------- | ----------------- |
| `eslint-status` | `passed` / `failed` / `fixed-with-issues` / `skipped` | ESLint 结果       |
| `php-status`    | 同上                                                  | PHP-CS-Fixer 结果 |

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

## 配置解析（内置 + 可覆盖）

- **ESLint**：若目标目录或仓库根存在 `eslint.config.{js,mjs,cjs}` 则优先使用调用方配置（此时需调用方自行安装配置中依赖的插件，如仓库内有 `package.json` + `node_modules` 即可）；否则使用 action 内置配置（见 `config/eslint.config.mjs`，含 `zbp` / `bloghost` / `jQuery` 等 Z-Blog 全局变量，缩进 2、双引号、强制分号等）。
- **PHP-CS-Fixer**：若目标目录或仓库根存在 `.php-cs-fixer.dist.php` / `.php-cs-fixer.php` 则优先使用；否则使用内置规则（`@PSR12`，排除 `vendor` / `node_modules` / `.history`），见 `config/.php-cs-fixer.dist.php`。

内置规则仅通过 `--config` 参数引用，不会写入调用方仓库；npm 安装产物与 phar 均落在 action 目录内。

## 环境要求

Runner 需自带 Node.js ≥ 18.18（ESLint 9 要求）与 PHP ≥ 7.4（php-cs-fixer 3.x 运行要求）。`ubuntu-latest` 默认满足。

## 本仓库自检

`.github/workflows/lint.yml` 会用本 action 检查 `config/` 目录下内置配置文件本身（check 模式），并对 `tests/fixtures/` 中的故意不规范样例做 fix 冒烟测试（验证改动确实产生、修复后 check 通过）。

## 本地调试

脚本兼容 Git Bash：

```bash
GITHUB_WORKSPACE=/path/to/your-plugin bash scripts/lint.sh --path . --mode check
```

## 缓存说明

action 内置 `actions/cache` 步骤缓存 `node_modules` 与 `php-cs-fixer.phar`，key 中含 fixer 版本。若升级 `package.json` 中的 eslint 依赖版本，需同步修改 `action.yml` 中缓存 key 的 `eslint-9.39` 字样以失效旧缓存。
