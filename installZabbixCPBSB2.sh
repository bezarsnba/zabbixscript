#!/bin/bash
#-------------------------------------------------------
# Author:       Adail Spinola <the.spaww@gmail.com>
# Date:         29-jun-2018
# Objective:    Install Zabbix 3.4 Final
# Update Log:
# 20180629 - First version
#-------------------------------------------------------
## vi installZBX.sh; chmod +x installZBX.sh; ./installZBX.sh

## Generic functions -----------------------------------------------------------
paramValue() {
    echo $( echo $1 | awk -F'=' '{print $2}' );
}

function infoOk() {
    echo -e "\e[36m==>\e[32m $1 \e[39m";
}

function infoError() {
    echo -e "\e[31m==>\e[91m $1 \e[39m";
}

function message() {
    echo -e "\e[36m==>\e[37m $1 \e[39m";
}

# Enable install parts (for debug propouses) -----------------------------------
INSTALL_MYSQL="S";
INSTALL_PKG="S";
INSTALL_HTTP="S";
DOWNLOAD_SOURCE="S";

INSTALL_ZBX_DB="S";
CONFIGURE_APACHE="S";
CREATE_USER="S";
CREATE_FRONTEND="S";
SERVER="S";
SERVICES="S";


## Enviroment configuration  ---------------------------------------------------
MYSQL_ROOT_PASS="zabbix";
ZABBIX_DB_PASS="zabbix";
DBNAME="zabbix";
DBUSER="zabbix";
ZBX_VER="3.4.11";
BUILD="$ZBX_VER";
WWW_PATH="/var/www/html";
SOURCE_PATH="/tmp/install/zabbix-$BUILD";
ZABBIXPORT="10051";
INSTALLNAME="PRTE - Zabbix - EveryZ";


message "Atualizando pacotes do S.O.";
sudo apt update -y
if [ ! -d "/tmp/install/" ]; then
   mkdir /tmp/install/
fi


message "Instalando MySQL";
if [ $INSTALL_MYSQL == "S" ]; then
  sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASS"
  sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASS"
  sudo apt -y install mysql-server
fi

message "Instalando dependencias";
if [ $INSTALL_PKG == "S" ]; then
  sudo apt -y install libmysqlclient-dev gcc libxml2-utils libxml2-dev libsnmp-dev libevent-dev libcurl4-gnutls-dev libpcre3-dev make wget curl fping
fi

message "Instalando Apache e PHP";
if [ $INSTALL_HTTP == "S" ]; then
  sudo apt -y install apache2 php7.0 php7.0-common php7.0-mcrypt php7.0-bcmath php7.0-gd php7.0-xml php7.0-mysql  php7.0-mbstring libapache2-mod-php7.0  php7.0-ldap
fi

if [ $CONFIGURE_APACHE == "S" ]; then
  if [ -f "/etc/apache2/sites-enabled/000-default.conf" ]; then
    sudo rm /etc/apache2/sites-enabled/000-default.conf;
  fi

  TEMPLATE="<VirtualHost *:80>\n
        ServerAdmin webmaster@localhost\n
        DocumentRoot /var/www/html\n
        Options FollowSymLinks\n
        DirectoryIndex index.php\n
        ErrorLog \${APACHE_LOG_DIR}/error.log\n
        CustomLog \${APACHE_LOG_DIR}/access.log combined\n
</VirtualHost>\n
";
  #sudo touch /etc/apache2/sites-available/zabbix.conf;
  sudo echo -e $TEMPLATE > /tmp/install/zabbix.conf;
  sudo mv /tmp/install/zabbix.conf /etc/apache2/sites-available/zabbix.conf
  sudo chown root: /etc/apache2/sites-available/zabbix.conf
  sudo ln -s /etc/apache2/sites-available/zabbix.conf /etc/apache2/sites-enabled/zabbix.conf
  message "Reiniciando o apache";
  sudo service apache2 restart
fi

message "Baixando codigo fonte do Zabbix";
if [ $DOWNLOAD_SOURCE == "S" ]; then
  URL_DOWN="https://ufpr.dl.sourceforge.net/project/zabbix/ZABBIX%20Latest%20Stable/$ZBX_VER/zabbix-$ZBX_VER.tar.gz";
  message "Download do codigo fonte do zabbix ($URL_DOWN)";
  cd "/tmp/install"
  curl -L "$URL_DOWN" -o zabbix.tgz
  message "Descompactando codigo fonte do zabbix...";
  tar -xzf zabbix.tgz
fi

if [ $INSTALL_ZBX_DB == "S" ]; then
  message "Criando banco de dados e usuário para o zabbix";
  mysql -u root -p$MYSQL_ROOT_PASS -e " create database zabbix character set utf8 collate utf8_bin; grant all privileges on zabbix.* to zabbix@localhost identified by '$ZABBIX_DB_PASS'";
  cd "$SOURCE_PATH"
  message "ZabbixDB - Criando tabelas";
  cat database/mysql/schema.sql | mysql -u $DBUSER -p$ZABBIX_DB_PASS $DBNAME;
  message "ZabbixDB - Adicionando imagens";
  cat database/mysql/images.sql | mysql -u $DBUSER -p$ZABBIX_DB_PASS $DBNAME;
  message "ZabbixDB - Adicionado dados default";
  cat database/mysql/data.sql | mysql -u $DBUSER -p$ZABBIX_DB_PASS $DBNAME;
fi

message "Criando usuario Zabbix no sistema operacional";
if [ $CREATE_USER == "S" ]; then
  sudo groupadd zabbix
  sudo useradd -g zabbix zabbix
fi

message "Configurando frontend do Zabbix";
if [ $CREATE_FRONTEND == "S" ]; then
  cd "$SOURCE_PATH";
  sudo cp -r frontends/php/* $WWW_PATH
  sudo echo -e "<?php
// Zabbix GUI configuration file. - Created by Adail Horst
global \$DB;

\$DB['TYPE']			= 'MYSQL';
\$DB['SERVER']                  = 'localhost';
\$DB['PORT']			= '0';
\$DB['DATABASE']		= '$DBNAME';
\$DB['USER']			= '$DBUSER';
\$DB['PASSWORD']		= '$ZABBIX_DB_PASS';
// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA']                  = '';

\$ZBX_SERVER			= 'localhost';
\$ZBX_SERVER_PORT		= '$ZABBIXPORT';
\$ZBX_SERVER_NAME		= '$INSTALLNAME';

\$IMAGE_FORMAT_DEFAULT	= IMAGE_FORMAT_PNG;
?>
" > /tmp/install/zabbix.conf.php;
  sudo mv /tmp/install/zabbix.conf.php $WWW_PATH/conf/zabbix.conf.php
  sudo chmod 755 "$WWW_PATH/conf/zabbix.conf.php";
  sudo chown -R www-data $WWW_PATH
fi

message "Criando binários do zabbix-server e zabbix-agent";
if [ $SERVER == "S" ]; then
  cd $SOURCE_PATH;
  sudo ./configure --enable-server --enable-agent --with-mysql --enable-ipv6 --with-net-snmp --with-libcurl --with-libxml2
  sudo make install
  sudo curl -L "https://raw.githubusercontent.com/bezarsnba/zabbixscript/master/zabbix-server" -o /etc/init.d/zabbix-server
  sudo curl -L "https://raw.githubusercontent.com/bezarsnba/zabbixscript/master/zabbix_server.conf" -o /usr/local/etc/zabbix_server.conf

  sudo chmod 755 /etc/init.d/zabbix-server
  sudo update-rc.d zabbix-server defaults
  sudo systemctl enable zabbix-server
  sudo curl -L "https://raw.githubusercontent.com/bezarsnba/zabbixscript/master/zabbix-agent" -o /etc/init.d/zabbix-agent
  sudo chmod 755 /etc/init.d/zabbix-agent
  sudo update-rc.d zabbix-agent defaults
  sudo systemctl enable zabbix-agent
fi

if [ $SERVICES == "S" ]; then
  message "Iniciando Zabbix Server";
  sudo systemctl restart zabbix-server
  sudo systemctl restart zabbix-agent
fi
exit;
