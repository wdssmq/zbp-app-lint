/* eslint indent: ["error", 4] */
/* zbp-app-lint 内置 ESLint 配置（移植自 ZBP_PLUGIN/eslint.config.mjs） */

import globals from "globals";
import pluginJs from "@eslint/js";

export default [
    {
        // 全局忽略：不在 lint 范围内的目录
        ignores: [
            "**/node_modules/**",
            "**/vendor/**",
            "**/.history/**",
            "**/dist/**",
        ],
    },
    {
        languageOptions: {
            globals: {
                ...globals.browser,
                "$": "readonly",
                "ajaxurl": "readonly",
                "bloghost": "readonly",
                "ClipboardJS": "readonly",
                "editor_api": "readonly",
                "GetCookie": "readonly",
                "jQuery": "readonly",
                "module": "readonly",
                "SetCookie": "readonly",
                "zbp": "readonly",
            },
        },
    },
    pluginJs.configs.recommended,
    {
        rules: {
            // 缩进
            "indent": [
                "error",
                2,
                {
                    "SwitchCase": 1,
                },
            ],
            // 换行符
            "linebreak-style": [
                "error",
                "unix",
            ],
            // 引号
            "quotes": [
                "error",
                "double",
            ],
            // 分号
            "semi": [
                "error",
                "always",
            ],
            // 单行注释的空格
            "spaced-comment": [
                "error",
                "always",
                {
                    "line": {
                        // 继下述字符后再加空格
                        "markers": ["!", "#", "/"],
                    },
                },
            ],

            /* ---------------- */

            // 禁止使用不必要的转义字符
            "no-useless-escape": 0,

            // 对象或数组的拖尾逗号
            // always-multiline 表示只有在多行时才需要拖尾逗号
            "comma-dangle": [
                1,
                "always-multiline",
            ],

            // 箭头函数参数括号
            // as-needed 表示只有在需要时才添加括号
            "arrow-parens": [
                1,
                "as-needed",
                {
                    // requireForBlockBody 表示在块体中需要括号
                    "requireForBlockBody": true,
                },
            ],

            // 变量声明后未使用
            // args: "none" 表示不检查函数参数是否被使用
            "no-unused-vars": [
                1,
                {
                    "args": "none",
                },
            ],

            // 函数圆括号之前的空格
            // 分别对匿名函数、异步箭头函数、命名函数设置
            "space-before-function-paren": [
                1,
                {
                    "anonymous": "never",
                    "asyncArrow": "always",
                    "named": "never",
                },
            ],

            // 禁止不规则的空白
            "no-irregular-whitespace": [
                2,
                {
                    "skipStrings": true,
                    "skipRegExps": true,
                },
            ],

        },
    },
];
