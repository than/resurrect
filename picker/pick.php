<?php

/**
 * res picker — the interactive multiselect, rendered with Laravel Prompts.
 *
 * Presentation only. The `res` CLI owns data and launching; this script just
 * makes a nice selection. Contract:
 *   - argv[1] is a path to a JSON file: [{id, label, hint, checked}, ...]
 *   - The interactive UI renders to STDERR (a TTY); keypresses read from STDIN.
 *   - Selected ids are printed to STDOUT, one per line, for the caller to act on.
 *
 * This stdout/stderr split lets the Python side capture the result while the
 * TUI still draws to the terminal.
 */

require __DIR__ . '/vendor/autoload.php';

use Laravel\Prompts\Prompt;
use Symfony\Component\Console\Output\StreamOutput;

use function Laravel\Prompts\multiselect;

$path = $argv[1] ?? null;
if (!$path || !is_file($path)) {
    fwrite(STDERR, "res picker: missing items file\n");
    exit(2);
}

$items = json_decode(file_get_contents($path), true);
if (!is_array($items) || count($items) === 0) {
    exit(0);
}

// Render the entire Prompts UI (and its ANSI/cursor control codes) to STDERR,
// keeping STDOUT clean for the selected ids.
Prompt::setOutput(new StreamOutput(fopen('php://stderr', 'w')));

$options = [];   // id => label
$default = [];   // ids checked by default
foreach ($items as $it) {
    $label = $it['label'] ?? $it['id'];
    if (!empty($it['hint'])) {
        $label .= "  \e[2m" . $it['hint'] . "\e[0m";   // dim hint
    }
    $options[$it['id']] = $label;
    if (!empty($it['checked'])) {
        $default[] = $it['id'];
    }
}

$selected = multiselect(
    label: 'Resurrect which sessions?',
    options: $options,
    default: $default,
    scroll: 15,
    hint: 'Space to toggle · ↑↓ to move · Enter to launch',
);

foreach ($selected as $id) {
    fwrite(STDOUT, $id . "\n");
}
