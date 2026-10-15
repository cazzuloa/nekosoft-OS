 # NekoSoft OS

**SAE 103**  
*Installation d'un poste pour le développement. Basé sur Trisquel 12.0 Mini*

![NekoSoft OS](wallpapers/nekosoft-wallpaper-1920x1080.png)

# Description

Le projet consiste en la création et la programmation d'une VM en groupe.

### Contexte

Nous sommes issue d'une entreprise nommé NekoSoft et nous avons comme but de créer et paramétrer une VM
qui sera par la suite utilisée par les développeurs de notre entreprise.

### Attentes

notre VM doit contenir :
1. Des outils de dévelopemments (Apache, MariahDB, PHP, phpMyAdmin).
2. avoir la possibilitée de développer des sites dans /var/www/html.
3. un système de sauvegarde automatique.
4. fond d'écran et personnalisation visuelles en rapport avec notre entreprise.
5. navigateur par défaut : ABrowser + Ublock Origin.


> Pour plus de détails, dirigez-vous vers le wiki : [Wiki](https://github.com/cazzuloa/nekosoft-OS/wiki)

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

# Todo 

- [x] Finir le markdown et le wiki.

# License

Ce projet est sous licence MIT — voir le fichier LICENSE pour plus de détails.
