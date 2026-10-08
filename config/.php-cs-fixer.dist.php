<?php

/**
 * zbp-app-lint built-in PHP-CS-Fixer config.
 *
 * Target directory is provided via the ZBP_LINT_PATH environment
 * variable (absolute path, exported by scripts/lint.sh). Falls back
 * to the current working directory when not set (e.g. local runs).
 */

$target = getenv('ZBP_LINT_PATH');

if (false === $target || '' === $target) {
    $target = getcwd();
}

$finder = (new PhpCsFixer\Finder())
    ->in($target)
    ->exclude([
        'vendor',
        'node_modules',
        '.history',
    ]);

return (new PhpCsFixer\Config())
    ->setRiskyAllowed(false)
    ->setRules([
        '@PSR12' => true,
    ])
    ->setFinder($finder);
