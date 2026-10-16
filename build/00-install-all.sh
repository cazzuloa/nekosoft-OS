#!/bin/bash
# NekoSoft - installation base (LAMP + outils)
# Usage: sudo bash 00-install-all.sh
set -eux

export DEBIAN_FRONTEND=noninteractive

DEV_USER="${DEV_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"
echo "== NekoSoft install - user dev: $DEV_USER =="

apt update

apt install -y \
  apache2 mariadb-server \
  php libapache2-mod-php php-mysql php-cli php-mbstring php-zip php-gd php-curl \
  phpmyadmin \
  geany geany-plugins \
  abrowser abrowser-locale-fr \
  openssh-server \
  borgbackup gnupg \
  lightdm-gtk-greeter-settings \
  wget curl unzip

# Expose phpMyAdmin via Apache
if [ ! -e /etc/apache2/conf-enabled/phpmyadmin.conf ] && [ -e /etc/phpmyadmin/apache.conf ]; then
  ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
  a2enconf phpmyadmin
fi

systemctl enable --now apache2 mariadb ssh

# Securisation MariaDB
mysql -e "CREATE USER 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
mysql -e "FLUSH PRIVILEGES;"
mysql -e "ALTER USER 'root'@'localhost' ACCOUNT LOCK;"
mysql -e "FLUSH PRIVILEGES;"

usermod -aG www-data "$DEV_USER"
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
chmod g+s /var/www/html

echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown www-data:www-data /var/www/html/info.php

echo "== Install OK =="
