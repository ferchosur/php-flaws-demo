<?php
declare(strict_types=1);

// The request goes through the vulnerable PHP runtime (Apache/mod_php); the site
// is still the static Worst Market store. No command endpoints, uploads or eval.
$html = file_get_contents(__DIR__ . '/index.html');
if ($html === false) {
    http_response_code(500);
    exit;
}
echo $html;
