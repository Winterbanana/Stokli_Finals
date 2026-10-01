<?php
declare(strict_types=1);

return [
    'host' => getenv('STOKLI_DB_HOST') ?: '127.0.0.1',
    'port' => getenv('STOKLI_DB_PORT') ?: '3306',
    'database' => getenv('STOKLI_DB_NAME') ?: 'stokli_bmc',
    'username' => getenv('STOKLI_DB_USER') ?: 'root',
    'password' => getenv('STOKLI_DB_PASSWORD') ?: '',
];
