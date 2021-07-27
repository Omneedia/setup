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
# o datastore:
#   ./setup.sh --databank --dir=/opt/store
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
INSTANCE=${INSTANCE:-prod}
URI_REGISTRY=${URI_REGISTRY:-registry}
URI_API=${URI_API:-manager}
URI_CONSOLE=${URI_CONSOLE:-console}
UUID=$(uuidgen)

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
    -b|--databank)
      TYPE="databank"
      shift # past argument=value
      ;;      
    -p=*|--proxy=*)
      PROXY="${i#*=}"
      shift # past argument=value
      ;;
    -w=*|--worker)
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
    -s=*|--datastore=*)
      DATASTORE="${i#*=}"
      shift # past argument=value
      ;;   
    -t=*|--token=*)
      TOKEN="${i#*=}"
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
  echo "You must provide one of the following : --databank --standalone --worker --cluster --manager"
  exit 1
fi

echo $TOKEN

mkdir -p /root/.ssh
touch /root/.ssh/authorized_keys
ssh-keygen -t rsa -N "" -C "omneedia-key" -f /root/.ssh/id_rsa

if ! [ -z "$PROXY" ]
then
  export http_proxy=$PROXY
  export https_proxy=$PROXY
  echo use_proxy=yes
  echo http_proxy=$PROXY >> ~/.wgetrc
  echo https_proxy=$PROXY >> ~/.wgetrc
fi

apt-get update
bash -c "$(wget -O - https://deb.nodesource.com/setup_14.x)"
apt update
apt-get --assume-yes install glances inotify-tools nodejs apt-transport-https ca-certificates curl git gnupg-agent software-properties-common nfs-common
apt-get --assume-yes remove docker docker-engine docker.io containerd runc 
wget -qO - https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

if [ "$TYPE" == "standalone" ]; then
  
  apt-get --assume-yes install nfs-kernel-server
  
  if [ -z "$ROOT" ]; then
    echo "You must provide a directory"
    exit 1;
  fi
  mkdir -p $ROOT
  chown -R nobody:nogroup $ROOT
  systemctl restart nfs-kernel-server
  
  grep -q 'omneedia-datastore-standalone' /etc/exports || 
  printf '# omneedia-datastore-standalone\n'$ROOT' 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports  
  exportfs -ra

  grep -q 'omneedia-datastore' /etc/fstab || 
  printf '# omneedia-datastore\n127.0.0.1:'$ROOT'    '$DATASTORE'    nfs    defaults    0 0\n' >> /etc/fstab  
  mount -a

fi

if [ "$TYPE" == "databank" ]; then
  
  apt-get --assume-yes install nfs-kernel-server
  
  if [ -z "$ROOT" ]; then
    echo "You must provide a directory"
    exit 1;
  fi
  mkdir -p $ROOT
  chown -R nobody:nogroup $ROOT
  systemctl restart nfs-kernel-server
  
  grep -q 'omneedia-databank' /etc/exports || 
  printf '# omneedia-databank\n'$ROOT' 127.0.0.1(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports  
  exportfs -ra
  
  printf 'DATASTORE='$DATASTORE > "/etc/default/omneedia"
  printf '\nROOT='$ROOT >> "/etc/default/omneedia"
  printf '\nUUID='$UUID >> "/etc/default/omneedia"

  printf '[Unit]' > "/etc/systemd/system/nfs-api.service"
  printf '\nDescription=My super nodejs app' >> "/etc/systemd/system/nfs-api.service"

  printf '\n[Service]' >> "/etc/systemd/system/nfs-api.service"

  printf '\nWorkingDirectory=/var/www/app' >> "/etc/systemd/system/nfs-api.service"

  printf '\nExecStart=/usr/bin/node api.js' >> "/etc/systemd/system/nfs-api.service"

  printf '\nRestart=always' >> "/etc/systemd/system/nfs-api.service"

  printf '\nRestartSec=500ms' >> "/etc/systemd/system/nfs-api.service"

  printf '\nStandardOutput=syslog' >> "/etc/systemd/system/nfs-api.service"
  printf '\nStandardError=syslog' >> "/etc/systemd/system/nfs-api.service"

  printf '\nSyslogIdentifier=nfs-api' >> "/etc/systemd/system/nfs-api.service"

  printf '\nUser=root' >> "/etc/systemd/system/nfs-api.service"
  printf '\nGroup=root' >> "/etc/systemd/system/nfs-api.service"

  printf '\nEnvironment=NODE_ENV=production' >> "/etc/systemd/system/nfs-api.service"


  printf '\n[Install]' >> "/etc/systemd/system/nfs-api.service"
  printf '\nWantedBy=multi-user.target' >> "/etc/systemd/system/nfs-api.service"

  systemctl enable nfs-api
  service nfs-api start
  
  exit
fi

apt update
apt --assume-yes install ansible docker-ce docker-ce-cli containerd.io

if [ "$TYPE" == "worker" ]; then
   if [ -z "$MANAGER" ]; then
       echo "You must provide a manager URI"
       exit 1;
   fi
   grep -q 'omneedia' /root/.ssh/authorized_keys ||
   printf '#omneedia\nssh-rsa '$MANAGER' omneedia-key' >> /root/.ssh/authorized_keys
   grep -q 'omneedia-datastore' /etc/fstab || 
   printf '# omneedia-datastore\n'$ROOT'    '$DATASTORE'    nfs    defaults    0 0\n' >> /etc/fstab  
   mount -a
   docker swarm join --token $TOKEN
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
  
  printf "" > "/etc/ansible/hosts"

  printf 'DATASTORE='$DATASTORE > "/etc/default/omneedia"
  printf '\nINSTANCE='$INSTANCE >> "/etc/default/omneedia"  
  printf '\nINTERFACE='${NETWORK_INTERFACE} >> "/etc/default/omneedia"  

  if ! [ -z "$PROXY" ]
  then
    printf '\nPROXY='$PROXY >> "/etc/default/omneedia"
  fi

  # activate convoy plugin
  docker run --rm -v vol1:/vol1 --volume-driver=convoy ubuntu
  convoy delete vol1

  # install Omneedia manager
  npm install -g oam@1.0.25
  clear
  oam install omneedia-core-web
  echo " "
  echo "Please type oam setup to finish the installation process."
  echo " "
  
fi
