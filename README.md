 # NekoSoft OS

![License](https://img.shields.io/badge/License-MIT-green.svg)
![OS](https://img.shields.io/badge/OS-Trisquel%2012.0%20Mini-blue.svg)
![Virtualisation](https://img.shields.io/badge/Virtualisation-QEMU-orange.svg)
![Projet](https://img.shields.io/badge/Projet-SAE%20103-purple.svg)
![GitHub last commit](https://img.shields.io/github/last-commit/cazzuloa/nekosoft-OS)
![GitHub repo size](https://img.shields.io/github/repo-size/cazzuloa/nekosoft-OS)

**SAE 103**  
*Installation d'un poste pour le développement. Basé sur Trisquel 12.0 Mini*

![NekoSoft OS](wallpapers/nekosoft-wallpaper-1920x1080.png)

# Description

Le projet consiste en la création et la configuration d'une VM en groupe.

### Contexte

Nous sommes issus d'une entreprise nommée NekoSoft et nous avons pour but de créer et paramétrer une VM qui sera par la suite utilisée par les développeurs de notre entreprise.

### Attentes

Notre VM doit contenir :
1. Des outils de développement (Apache, MariaDB, PHP, phpMyAdmin).
2. La possibilité de développer des sites dans /var/www/html.
3. Un système de sauvegarde automatique.
4. Un fond d'écran et une personnalisation visuelle en rapport avec notre entreprise.
5. Abrowser comme navigateur par défaut, avec uBlock Origin.

> Pour plus de détails, dirigez-vous vers le wiki : [Wiki](https://github.com/cazzuloa/nekosoft-OS/wiki)

## Fonctionnalités et technologies

| Fonctionnalité | Technologie | Description |
|---|---|---|
| Système d'exploitation | Trisquel 12.0 Mini | Système de base de la VM |
| Serveur web | Apache | Hébergement des sites web |
| Base de données | MariaDB | Stockage des données |
| Backend | PHP | Exécution du code serveur |
| Administration BDD | phpMyAdmin | Gestion des bases de données |
| Navigateur | Abrowser + uBlock Origin | Navigation web |
| Virtualisation | QEMU | Exécution de la machine virtuelle |
| Sauvegardes | À préciser | Sauvegarde automatique des données |

# Installation

## Prérequis

1. Machine hôte Linux recommandée
2. Installer QEMU x86-64
3. ISO : **trisquel-mini_12.0_amd64.iso**
4. Installer Git
5. Avoir à minima 30 Go d'espace libre

> Vous pouvez installer Trisquel Mini 12 ici : [Trisquel Mini](https://trisquel.info/fr/download)

## Premier lancement

### Clonage du dépôt

```bash
git clone https://github.com/cazzuloa/nekosoft-OS.git
cd nekosoft-OS
```

> Assurez-vous d'avoir mis le .iso de Trisquel dans le dossier scripts.

### Création du disque virtuel

```bash
qemu-img create -f qcow2 trisquel-disk.img 20G
```

### Lancer le live boot

```bash
chmod +x ./scripts/boot-live.sh
./scripts/boot-live.sh
```

Si vous avez une machine avec Trisquel 12 Mini de déjà installer, vous pouvez utiliser le script suivant
```bash
curl -fsSL https://raw.githubusercontent.com/cazzuloa/nekosoft-OS/refs/heads/main/setup.sh | bash
```

# Todo 

- [x] Finir le markdown et le wiki.

# License

Ce projet est sous licence MIT — voir le fichier LICENSE pour plus de détails.
