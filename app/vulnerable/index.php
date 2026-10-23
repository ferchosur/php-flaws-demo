<?php
declare(strict_types=1);

// La petición pasa por el runtime PHP; el sitio sigue siendo la tienda estática.
// No hay endpoints de comandos, carga de archivos ni evaluación de entradas.
$html = file_get_contents(__DIR__ . '/index.html');
if ($html === false) {
    http_response_code(500);
    exit;
}
echo $html;
