<?php
declare(strict_types=1);

// The request goes through the PHP runtime; the site is still the static store.
// There are no command endpoints, file uploads or input evaluation.
$html = file_get_contents(__DIR__ . '/index.html');
if ($html === false) {
    http_response_code(500);
    exit;
}
echo $html;
