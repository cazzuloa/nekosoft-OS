<?php
declare(strict_types=1);
/*
 * NekoSoft - page d'accueil de démonstration (déployée par demo.sh).
 *
 * Chaque carte teste réellement le service côté serveur : si la page s'affiche
 * avec tout en vert, c'est que Apache, PHP, MariaDB et Forgejo répondent vraiment.
 * Aucune ressource externe : la page fonctionne hors-ligne.
 */

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
<title>NekoSoft · poste de développement Web</title>
<style>
  :root {
    --bg: #1e1b2e; --card: #2a2640; --line: #3d3860;
    --text: #f2eefc; --muted: #a79fc9; --accent: #d787ff;
    --up: #5be38f; --down: #ff6b81;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 2rem 1rem 3rem; min-height: 100vh;
    background: var(--bg); color: var(--text);
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; line-height: 1.5;
  }
  main { max-width: 860px; margin: 0 auto; }
  h1 { margin: 0 0 .25rem; font-size: 2rem; color: var(--accent); }
  .sub { margin: 0 0 1.5rem; color: var(--muted); }
  .banner {
    padding: .9rem 1.1rem; border-radius: 10px; margin-bottom: 1.5rem; font-weight: 600;
    border: 1px solid var(--line); background: var(--card);
  }
  .banner.ok   { border-color: var(--up);   color: var(--up); }
  .banner.fail { border-color: var(--down); color: var(--down); }
  .grid { display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }
  .card {
    background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 1rem 1.1rem;
  }
  .card h2 { margin: 0 0 .4rem; font-size: 1.05rem; display: flex; align-items: center; gap: .55rem; }
  .dot { width: .7rem; height: .7rem; border-radius: 50%; background: var(--down); flex: none; }
  .card[data-up="1"] .dot { background: var(--up); box-shadow: 0 0 8px var(--up); }
  .info { margin: 0; color: var(--muted); font-size: .9rem; word-break: break-word; }
  .card a { display: inline-block; margin-top: .6rem; color: var(--accent); text-decoration: none; font-size: .9rem; }
  .card a:hover { text-decoration: underline; }
  footer { margin-top: 2rem; color: var(--muted); font-size: .85rem; border-top: 1px solid var(--line); padding-top: 1rem; }
  code { background: var(--card); padding: .1rem .35rem; border-radius: 4px; }
</style>
</head>
<body>
<main>
  <h1>NekoSoft 🐾</h1>
  <p class="sub">Poste de développement Web · Trisquel 12 Mini</p>

  <div class="banner <?= $allUp ? 'ok' : 'fail' ?>">
    <?= $allUp ? 'Tous les services répondent : le poste est prêt.' : 'Au moins un service ne répond pas (voir ci-dessous).' ?>
  </div>

  <section class="grid">
<?php foreach ($services as $key => [$name, $up, $info, $link]): ?>
    <article class="card" data-service="<?= h($key) ?>" data-up="<?= $up ? '1' : '0' ?>">
      <h2><span class="dot"></span><?= h($name) ?></h2>
      <p class="info"><?= h($up ? $info : 'ne répond pas') ?></p>
<?php if ($link !== null && $up): ?>
      <a href="<?= h($link) ?>">Ouvrir <?= h($name) ?> →</a>
<?php endif; ?>
    </article>
<?php endforeach; ?>
  </section>

  <footer>
    Machine <strong><?= h((string) gethostname()) ?></strong> ·
    <?= h(php_uname('s') . ' ' . php_uname('r')) ?> ·
    <?= h(date('d/m/Y H:i')) ?><br>
    Dossier de développement : <code>/var/www/html</code> · page générée par <code>demo.sh</code>
  </footer>
</main>
</body>
</html>