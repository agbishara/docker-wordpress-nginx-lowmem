#!/bin/bash
#set -euo pipefail

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

: ${SSL_KEYSIZE:="2048"}
: ${DH_SIZE:="1024"}

if [[ ! -f /etc/nginx/conf.d/sslbundle.pem ]]; then
   err "Generating SSL bundle pair..."
   openssl req -x509 -newkey rsa:${SSL_KEYSIZE} -keyout /etc/nginx/conf.d/sslbundle.pem -out /etc/nginx/conf.d/sslbundle.pem -days 3650 -nodes -subj '/CN=localhost'
fi
if [[ ! -f /etc/nginx/conf.d/dhparam.pem ]]; then
   err "Generating DH param file..."
   openssl dhparam -outform PEM -out /etc/nginx/conf.d/dhparam.pem ${DH_SIZE}
fi

if [[ ! -z "$LOW_MEM" ]]; then
   if [[ ! -f /etc/mysql/conf.d/mysql-low-mem.cnf ]] && [[ ! -f /etc/mysql/conf.d/mysql-low-mem.cnf.disabled ]]; then
      err "/etc/mysql/conf.d/mysql-low-mem.cnf.disabled missing - caanot enable low memory config"
      exit 1
   fi
   if [[ ! -f /etc/mysql/conf.d/mysql-low-mem.cnf ]]; then
      mv /etc/mysql/conf.d/mysql-low-mem.cnf.disabled /etc/mysql/conf.d/mysql-low-mem.cnf
   fi
fi

if [[ -f /etc/mysql/conf.d/mysql-low-mem.cnf ]]; then
   err "LOW MEMORY mysql enabled!"
fi

if [[ ! -f /usr/share/nginx/www/wp-config.php ]]; then
  #mysql has to be started this way as it doesn't work to call from /etc/init.d
  /usr/bin/mysqld_safe &
  sleep 10s
  # Here we generate random passwords (thank you pwgen!). The first two are for mysql users, the last batch for random keys in wp-config.php
  WORDPRESS_DB="wordpress"
  MYSQL_PASSWORD=$(pwgen -s -1 18)
  WORDPRESS_PASSWORD=$(pwgen -s -1 18)
  #This is so the passwords show up in logs.
  err mysql root password: $MYSQL_PASSWORD
  err wordpress password: $WORDPRESS_PASSWORD
  echo $MYSQL_PASSWORD > /mysql-root-pw.txt
  echo $WORDPRESS_PASSWORD > /wordpress-db-pw.txt

  sed -e "s/database_name_here/$WORDPRESS_DB/
  s/username_here/$WORDPRESS_DB/
  s/password_here/$WORDPRESS_PASSWORD/
  /'AUTH_KEY'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'SECURE_AUTH_KEY'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'LOGGED_IN_KEY'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'NONCE_KEY'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'AUTH_SALT'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'SECURE_AUTH_SALT'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'LOGGED_IN_SALT'/s/put your unique phrase here/$(pwgen -s -1 65)/
  /'NONCE_SALT'/s/put your unique phrase here/$(pwgen -s -1 65)/" /usr/share/nginx/www/wp-config-sample.php > /usr/share/nginx/www/wp-config.php

  PLUGINS="nginx-helper w3-total-cache"
  # Download nginx helper plugin

  for PLUG in $PLUGINS; do
     curl -s -O $(curl -i -s https://wordpress.org/plugins/${PLUG}/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+")
     find . -type f -name "*.zip" -print0 | xargs -0 -I % unzip -q -o % -d /usr/share/nginx/www/wp-content/plugins
     #unzip -o *.zip -d /usr/share/nginx/www/wp-content/plugins
     chown -R www-data:www-data /usr/share/nginx/www/wp-content/plugins
  done

  # Activate nginx plugin
  cat << ENDL >> /usr/share/nginx/www/wp-config.php
\$plugins = get_option( 'active_plugins' );
if ( count( \$plugins ) === 0 ) {
  require_once(ABSPATH .'/wp-admin/includes/plugin.php');
  \$pluginsToActivate = array( 'nginx-helper/nginx-helper.php' );
  foreach ( \$pluginsToActivate as \$plugin ) {
    if ( !in_array( \$plugin, \$plugins ) ) {
      activate_plugin( '/usr/share/nginx/www/wp-content/plugins/' . \$plugin );
    }
  }
}
ENDL

  chown www-data:www-data /usr/share/nginx/www/wp-config.php

  mysqladmin -u root password $MYSQL_PASSWORD
  mysql -uroot -p$MYSQL_PASSWORD -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  mysql -uroot -p$MYSQL_PASSWORD -e "CREATE DATABASE wordpress; GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost' IDENTIFIED BY '$WORDPRESS_PASSWORD'; FLUSH PRIVILEGES;"
  killall mysqld
  cat <<EOF > /root/.my.cnf
[client]
user=root
password="$MYSQL_PASSWORD"
EOF

err 'Container running...'
fi

# start all the services
/usr/local/bin/supervisord -n
