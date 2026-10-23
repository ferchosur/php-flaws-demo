<?php
declare(strict_types=1);

$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH);
if ($path === '/healthz') {
    header('Content-Type: text/plain; charset=utf-8');
    echo "ok\n";
    return;
}
if ($path === '/') {
    require __DIR__ . '/index.php';
    return;
}
if (is_string($path) && str_starts_with($path, '/assets/') && is_file(__DIR__ . $path)) {
    return false;
}
http_response_code(404);
