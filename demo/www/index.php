<?php
declare(strict_types=1);
date_default_timezone_set('Europe/Paris');

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/** MariaDB : on se connecte à la socket Unix et on lit le paquet d'accueil (qui contient la version). */
function probe_mariadb(): array
{
    $sock = @stream_socket_client('unix:///run/mysqld/mysqld.sock', $errno, $errstr, 1);
    if (!$sock) {
        return [false, 'injoignable'];
    }
    stream_set_timeout($sock, 1);
    $hello = (string) @fread($sock, 128);
    fclose($sock);

    // Paquet d'accueil : 4 octets d'en-tête, 1 octet de protocole, puis la version terminée par \0
    $ver = strlen($hello) > 5 ? explode("\0", substr($hello, 5), 2)[0] : '';
    $ver = preg_replace('/^5\.5\.5-/', '', $ver) ?? '';
    return [true, preg_match('/^[\w.\-+~:]+$/', $ver) === 1 ? $ver : 'en ligne'];
}

/** Forgejo : API de version sur 127.0.0.1:3000, sinon simple test du port. */
function probe_forgejo(): array
{
    $ctx  = stream_context_create(['http' => ['timeout' => 2]]);
    $json = @file_get_contents('http://127.0.0.1:3000/api/v1/version', false, $ctx);
    if ($json !== false) {
        $data = json_decode($json, true);
        $ver  = is_array($data) ? (string) ($data['version'] ?? '') : '';
        return [true, $ver !== '' ? explode('+', $ver)[0] : 'en ligne'];
    }
    $s = @fsockopen('127.0.0.1', 3000, $en, $es, 1);
    if ($s) {
        fclose($s);
        return [true, 'en ligne'];
    }
    return [false, 'injoignable'];
}

[$dbUp, $dbInfo]   = probe_mariadb();
[$gitUp, $gitInfo] = probe_forgejo();

$services = [
    'apache'     => ['Apache',     true,  (string) ($_SERVER['SERVER_SOFTWARE'] ?? 'en ligne'), null],
    'php'        => ['PHP',        true,  PHP_VERSION . ' · ' . count(get_loaded_extensions()) . ' modules', null],
    'mariadb'    => ['MariaDB',    $dbUp, $dbInfo, null],
    'phpmyadmin' => ['phpMyAdmin', is_dir('/usr/share/phpmyadmin'), 'installé', '/phpmyadmin/'],
    'forgejo'    => ['Forgejo',    $gitUp, $gitInfo, 'http://localhost:3000/'],
];
$allUp = !in_array(false, array_column($services, 1), true);
?>
<!DOCTYPE html>
<!-- nekosoft-demo-page -->
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NekoSoft - état des services</title>
<style>
  body {
    font-family: Arial, Helvetica, sans-serif;
    background: #fff; color: #222;
    max-width: 680px; margin: 2rem auto; padding: 0 1rem;
    line-height: 1.5;
  }
  h1 { font-size: 1.35rem; margin: 0 0 .15rem; }
  .lead { color: #555; margin: 0 0 1.2rem; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; }
  th, td { border: 1px solid #ccc; padding: .45rem .6rem; text-align: left; font-size: .95rem; }
  th { background: #f2f2f2; font-weight: bold; }
  .ok { color: #1a7f37; font-weight: bold; }
  .ko { color: #c0392b; font-weight: bold; }
  .summary { font-weight: bold; }
  footer {
    margin-top: 1.5rem; font-size: .8rem; color: #777;
    border-top: 1px solid #ddd; padding-top: .6rem;
  }
  code { background: #f5f5f5; padding: 0 .2rem; }
</style>
</head>
<body>

<h1>NekoSoft - état des services</h1>

<p class="summary<?= $allUp ? '' : ' ko' ?>">
<?php if ($allUp): ?>
  Testé à <?= h(date('H:i')) ?> : tous les services répondent.
<?php else: ?>
  Attention : y en a un qui marche pas :sob:
<?php endif; ?>
</p>

<table>
  <tr>
    <th>Service</th>
    <th>État</th>
    <th>Détails</th>
  </tr>
<?php foreach ($services as $key => [$name, $up, $info, $link]): ?>
  <tr data-service="<?= h($key) ?>" data-up="<?= $up ? '1' : '0' ?>">
    <td><?= h($name) ?></td>
    <td class="<?= $up ? 'ok' : 'ko' ?>"><?= $up ? 'OK' : 'erreur' ?></td>
    <td>
      <?= h($up ? $info : 'ne répond pas') ?>
<?php if ($link !== null && $up): ?>
      — <a href="<?= h($link) ?>">ouvrir</a>
<?php endif; ?>
    </td>
  </tr>
<?php endforeach; ?>
</table>
</body>
</html>