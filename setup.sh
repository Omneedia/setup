#!/bin/bash

#
# Omneedia Server
#

# setup.sh [args]
# args:
# -s standalone/manager
# -c cluster/manager
# -m manager
# -d datastore
# -w worker
# -p proxy
# -d mount point
#
# samples:
# --------
# o standalone:
#   ./setup.sh --standalone --dir=/opt/store --network=eth0
#   ./setup.sh --standalone --network=eth1 --dir=/opt/store
# o cluster/manager:
#   ./setup.sh --cluster --volume=myserver:/datastore
# o standalone (with proxy):
#   ./setup.sh --standalone --dir=/opt/store --proxy=http://monproxy.lan:8080

# settings defaults

NETWORK_INTERFACE=eth0
CONVOY_URI="https://github.com/rancher/convoy/releases/download/v0.5.2/convoy.tar.gz"
KEY=${KEY:-0mneediaRulez!}
DATASTORE=${DATASTORE:-/datastore}
INSTANCE=${DATASTORE:-prod}
URI_REGISTRY=${URI_REGISTRY:-registry}
URI_API=${URI_API:-manager}
URI_CONSOLE=${URI_CONSOLE:-console}

mkdir -p $DATASTORE

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
TZ=Europe/Paris
ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
DEBIAN_FRONTEND=noninteractive

# menu

for i in "$@"; do
  case $i in
    -s|--standalone)
      TYPE="standalone"
      shift # past argument=value
      ;;
    -p=*|--proxy=*)
      PROXY="${i#*=}"
      shift # past argument=value
      ;;
    -w=*|--worker=*)
      TYPE="worker"
      shift # past argument=value
      ;;
    -r=*|--master=*)
      TYPE="worker"
      shift # past argument=value
      ;;
    -m=*|--manager=*)
      MANAGER="${i#*=}"
      shift # past argument=value
      ;;
    -d=*|--dir=*)
      ROOT="${i#*=}"
      shift # past argument=value
      ;;
    -n=*|--network=*)
      NETWORK_INTERFACE="${i#*=}"
      shift # past argument=value
      ;;      
    *)
      # unknown option
      ;;
  esac
done

if [ -z "$TYPE" ]
then
  echo "You must provide one of the following : --standalone --worker --cluster --manager"
  exit 1
fi

mkdir -p /root/.ssh
ssh-keygen -t dsa -N "$KEY" -C "omneedia-key" -f /root/.ssh/id_rsa

if ! [ -z "$PROXY" ]
then
  export http_proxy=$PROXY
  export https_proxy=$PROXY
  echo use_proxy=yes
  echo http_proxy=$PROXY >> ~/.wgetrc
  echo https_proxy=$PROXY >> ~/.wgetrc
fi

if [ "$TYPE" == "worker" ]; then
   if [ -z "$MANAGER" ]; then
       echo "You must provide a manager URI"
       exit 1;
   fi
fi

apt-get update
bash -c "$(wget -O - https://deb.nodesource.com/setup_14.x)"
apt update
apt-get --assume-yes install glances inotify-tools nodejs apt-transport-https ca-certificates curl git gnupg-agent software-properties-common nfs-common nfs-kernel-server
apt-get --assume-yes remove docker docker-engine docker.io containerd runc 
wget -qO - https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt --assume-yes install ansible docker-ce docker-ce-cli containerd.io

if [ "$TYPE" == "standalone" ]; then

  if [ -z "$ROOT" ]; then
    echo "You must provide a directory"
    exit 1;
  fi
  mkdir -p $ROOT
  chown -R nobody:nogroup $ROOT
  systemctl restart nfs-kernel-server
  
  grep -q 'omneedia-datastore-standalone' /etc/exports || 
  printf '# omneedia-datastore-standalone\n'$ROOT' 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports  
  exportfs -ra

  grep -q 'omneedia-datastore' /etc/fstab || 
  printf '# omneedia-datastore\n127.0.0.1:'$ROOT'    '$DATASTORE'    nfs    defaults    0 0\n' >> /etc/fstab  
  mount -a

fi

systemctl enable rpc-statd
systemctl start rpc-statd

if ! [ -z "$PROXY" ]
then
  git config --global http.proxy $PROXY
  npm config set proxy $PROXY
fi


if ! [ -z "$PROXY" ]
then
	mkdir -p /etc/systemd/system/docker.service.d
	touch /etc/systemd/system/docker.service.d/http-proxy.conf
	echo "[Service]" >> /etc/systemd/system/docker.service.d/http-proxy.conf
	echo "Environment=\"HTTP_PROXY=$PROXY/\"" >> /etc/systemd/system/docker.service.d/http-proxy.conf
	echo "Environment=\"HTTPS_PROXY=$PROXY\"" >> /etc/systemd/system/docker.service.d/http-proxy.conf
	echo "Environment=\"NO_PROXY=localhost,127.0.0.1,.cerema.fr\"" >> /etc/systemd/system/docker.service.d/http-proxy.conf

	systemctl daemon-reload
	systemctl restart docker
fi

# install convoy

wget $CONVOY_URI
tar -xzvf convoy.tar.gz
sudo cp convoy/convoy convoy/convoy-pdata_tools /usr/local/bin/
mkdir -p /etc/docker/plugins/
bash -c 'echo "unix:///var/run/convoy/convoy.sock" > /etc/docker/plugins/convoy.spec'

echo '#!/bin/sh' > /etc/init.d/convoy
echo '### BEGIN INIT INFO' >> /etc/init.d/convoy
echo '# Provides:' >> /etc/init.d/convoy
echo '# Required-Start:    $remote_fs $syslog' >> /etc/init.d/convoy
echo '# Required-Stop:     $remote_fs $syslog' >> /etc/init.d/convoy
echo '# Default-Start:     2 3 4 5' >> /etc/init.d/convoy
echo '# Default-Stop:      0 1 6' >> /etc/init.d/convoy
echo '# Short-Description: Start daemon at boot time' >> /etc/init.d/convoy
echo '# Description:       Enable service provided by daemon.' >> /etc/init.d/convoy
echo '### END INIT INFO' >> /etc/init.d/convoy
echo ' ' >> /etc/init.d/convoy
echo 'dir="/usr/local/bin"' >> /etc/init.d/convoy
echo 'cmd="convoy daemon --drivers vfs --driver-opts vfs.path='$DATASTORE'"' >> /etc/init.d/convoy
echo 'user="root"' >> /etc/init.d/convoy
echo 'name="convoy"' >> /etc/init.d/convoy
echo ' ' >> /etc/init.d/convoy
echo 'pid_file="/var/run/$name.pid"' >> /etc/init.d/convoy
echo 'stdout_log="/var/log/$name.log"' >> /etc/init.d/convoy
echo 'stderr_log="/var/log/$name.err"' >> /etc/init.d/convoy
echo '' >> /etc/init.d/convoy
echo 'get_pid() {' >> /etc/init.d/convoy
echo '    cat "$pid_file"' >> /etc/init.d/convoy
echo '}' >> /etc/init.d/convoy
echo '' >> /etc/init.d/convoy
echo 'is_running() {' >> /etc/init.d/convoy
echo '    [ -f "$pid_file" ] && ps `get_pid` > /dev/null 2>&1' >> /etc/init.d/convoy
echo '}' >> /etc/init.d/convoy
echo '' >> /etc/init.d/convoy
echo 'case "$1" in' >> /etc/init.d/convoy
echo '    start)' >> /etc/init.d/convoy
echo '    if is_running; then' >> /etc/init.d/convoy
echo '        echo "Already started"' >> /etc/init.d/convoy
echo '    else' >> /etc/init.d/convoy
echo '        echo "Starting $name"' >> /etc/init.d/convoy
echo '        cd "$dir"' >> /etc/init.d/convoy
echo '        if [ -z "$user" ]; then' >> /etc/init.d/convoy
echo '            sudo $cmd >> "$stdout_log" 2>> "$stderr_log" &' >> /etc/init.d/convoy
echo '        else' >> /etc/init.d/convoy
echo '            sudo -u "$user" $cmd >> "$stdout_log" 2>> "$stderr_log" &' >> /etc/init.d/convoy
echo '        fi' >> /etc/init.d/convoy
echo '        echo $! > "$pid_file"' >> /etc/init.d/convoy
echo '        if ! is_running; then' >> /etc/init.d/convoy
echo '            echo "Unable to start, see $stdout_log and $stderr_log"' >> /etc/init.d/convoy
echo '            exit 1' >> /etc/init.d/convoy
echo '        fi' >> /etc/init.d/convoy
echo '    fi' >> /etc/init.d/convoy
echo '    ;;' >> /etc/init.d/convoy
echo '    stop)' >> /etc/init.d/convoy
echo '    if is_running; then' >> /etc/init.d/convoy
echo '        echo -n "Stopping $name.."' >> /etc/init.d/convoy
echo '        kill `get_pid`' >> /etc/init.d/convoy
echo '        for i in {1..10}' >> /etc/init.d/convoy
echo '        do' >> /etc/init.d/convoy
echo '            if ! is_running; then' >> /etc/init.d/convoy
echo '                break' >> /etc/init.d/convoy
echo '            fi' >> /etc/init.d/convoy
echo ' ' >> /etc/init.d/convoy
echo '            echo -n "."' >> /etc/init.d/convoy
echo '            sleep 1' >> /etc/init.d/convoy
echo '        done' >> /etc/init.d/convoy
echo '        echo' >> /etc/init.d/convoy
echo ' ' >> /etc/init.d/convoy
echo '        if is_running; then' >> /etc/init.d/convoy
echo '            echo "Not stopped; may still be shutting down or shutdown may have failed"' >> /etc/init.d/convoy
echo '            exit 1' >> /etc/init.d/convoy
echo '        else' >> /etc/init.d/convoy
echo '            echo "Stopped"' >> /etc/init.d/convoy
echo '            if [ -f "$pid_file" ]; then' >> /etc/init.d/convoy
echo '                rm "$pid_file"' >> /etc/init.d/convoy
echo '            fi' >> /etc/init.d/convoy
echo '        fi' >> /etc/init.d/convoy
echo '    else' >> /etc/init.d/convoy
echo '        echo "Not running"' >> /etc/init.d/convoy
echo '    fi' >> /etc/init.d/convoy
echo '    ;;' >> /etc/init.d/convoy
echo '    restart)' >> /etc/init.d/convoy
echo '    $0 stop' >> /etc/init.d/convoy
echo '    if is_running; then' >> /etc/init.d/convoy
echo '        echo "Unable to stop, will not attempt to start"' >> /etc/init.d/convoy
echo '        exit 1' >> /etc/init.d/convoy
echo '    fi' >> /etc/init.d/convoy
echo '    $0 start' >> /etc/init.d/convoy
echo '    ;;' >> /etc/init.d/convoy
echo '    status)' >> /etc/init.d/convoy
echo '    if is_running; then' >> /etc/init.d/convoy
echo '        echo "Running"' >> /etc/init.d/convoy
echo '    else' >> /etc/init.d/convoy
echo '        echo "Stopped"' >> /etc/init.d/convoy
echo '        exit 1' >> /etc/init.d/convoy
echo '    fi' >> /etc/init.d/convoy
echo '    ;;' >> /etc/init.d/convoy
echo '    *)' >> /etc/init.d/convoy
echo '    echo "Usage: $0 {start|stop|restart|status}"' >> /etc/init.d/convoy
echo '    exit 1' >> /etc/init.d/convoy
echo '    ;;' >> /etc/init.d/convoy
echo 'esac' >> /etc/init.d/convoy
echo ' ' >> /etc/init.d/convoy
echo 'exit 0' >> /etc/init.d/convoy

chmod +x /etc/init.d/convoy
sudo systemctl enable convoy
sudo /etc/init.d/convoy start

service docker restart

# create swarm cluster (standalone)
if [ "$TYPE" == "standalone" ]; then

  docker swarm init --advertise-addr $NETWORK_INTERFACE
  
  # create networks
  docker network create --driver overlay public
  docker network create --driver overlay omneedia

  # create configuration
  mkdir -p $ROOT/.omneedia-ci/stacks
  mkdir -p $ROOT/.omneedia-ci/api
  mkdir -p $ROOT/.omneedia-ci/certs  
  mkdir -p $ROOT/.snapshots  

  printf 'DATASTORE='$DATASTORE > "/etc/default/omneedia"

  printf 'OMNEEDIA_API_VERSION=1.0.0' > $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_TOKEN_MANAGER='`docker swarm join-token manager -q` >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_TOKEN_WORKER='`docker swarm join-token worker -q` >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_MANAGER_INTERFACE='${NETWORK_INTERFACE} >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_ROOT_NGINX='$DATASTORE'/omneedia-core-web-'$INSTANCE'_etc' >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_ROOT_CERTS='$DATASTORE'/omneedia-core-web-'$INSTANCE'_certs' >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_ROOT_LOGS='$DATASTORE'/omneedia-core-web-'$INSTANCE'_logs' >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_URI_REGISTRY='${URI_REGISTRY} >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_URI_API='${URI_API} >> $ROOT/.omneedia-ci/api/.env
  printf '\nOMNEEDIA_URI_CONSOLE='${URI_CONSOLE} >> $ROOT/.omneedia-ci/api/.env

  if ! [ -z "$PROXY" ]
  then
    printf '\nOMNEEDIA_PROXY='$PROXY >> $ROOT/.omneedia-ci/api/.env
  fi

  # activate convoy plugin
  docker run --rm -v vol1:/vol1 --volume-driver=convoy ubuntu
  convoy delete vol1

  # install Omneedia manager
  npm install -g oam@1.0.18
  clear
  oam config set datastore $DATASTORE
  oam config set certs $DATASTORE/omneedia-core-web-${INSTANCE}_certs
  oam config set nginx $DATASTORE/omneedia-core-web-${INSTANCE}_etc
  oam install omneedia-core-web
  oam install omneedia-core-certbot
  oam setup
  
fi
