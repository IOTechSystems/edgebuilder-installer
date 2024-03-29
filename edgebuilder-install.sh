#!/bin/sh
LOGFILE=eb-installer.log
log() {
    echo "[$(date +"%T-%D")]" "$@"
}
exec 3>&1 1>"$LOGFILE" 2>&1
set -x

# Progress bar, used to indicate progress from 0 to 40
bar_size=40
bar_char_done="#"
bar_char_todo="-"
total=40
show_progress() {
  progress="$1"
  todo=$((total - progress))
  # build the done and todo sub-bars
  done_sub_bar=$(printf "%${progress}s" | tr " " "${bar_char_done}")
  todo_sub_bar=$(printf "%${todo}s" | tr " " "${bar_char_todo}")
  # output the bar
  printf "\rProgress : [${done_sub_bar}${todo_sub_bar}]" >&3
  if [ $total -eq $progress ]; then
      printf "\n" >&3
  fi
}


UNINSTALL=false
FILE=""
OFFLINE_PROVISION=false
REPOAUTH=""
VER="3.0.0.dev"
FRP_VERSION="0.52.3"

UBUNTU2204="Ubuntu 22.04"
UBUNTU2004="Ubuntu 20.04"
DEBIAN10="Debian GNU/Linux 10"
DEBIAN11="Debian GNU/Linux 11"
RASPBIAN10="Raspbian GNU/Linux 10"

KEYRINGS_DIR="/etc/apt/keyrings"

RPM_REPO_DATA='[IoTech]
name=IoTech
baseurl=https://iotech.jfrog.io/artifactory/rpm-release
enabled=1
gpgcheck=0'

# Checks that the kernel is compatible with Golang
version_under_2_6_23(){
    # shellcheck disable=SC2046
    return $(uname -r | awk -F '.' '{
      if ($1 < 2) {
        print 0;
      } else if ($1 == 2) {
        if ($2 <= 6) {
          print 0;
        } else if ($2 == 6) {
          if ($3 <= 23) {
            print 0
          } else {
            print 1
          }
        } else {
          print 1;
        }
      } else {
        print 1;
      }
    }')
}

# Gets the distribution 'name' bionic, focal etc
get_dist_name()
{
  if [ "$1" = "$UBUNTU2204" ]; then
    echo "jammy"
  elif [ "$1" = "$UBUNTU2004" ]; then
    echo "focal"
  elif  [ "$1" = "$DEBIAN11" ]; then
    echo "bullseye"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "buster"
  fi
}

# Gets the distribution number 20.04, 22.04 etc
get_dist_num()
{
  if [ "$1" = "$UBUNTU2204" ]; then
    echo "22.04"
  elif [ "$1" = "$UBUNTU2004" ]; then
    echo "20.04"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "10"
  elif  [ "$1" = "$DEBIAN11" ]; then
    echo "11"
  fi
}

# Gets the basic distribution type ubuntu, debian etc
get_dist_type()
{
  if [ "$1" = "$UBUNTU2204" ] || [ "$1" = "$UBUNTU2004" ]; then
    echo "ubuntu"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$DEBIAN11" ]; then
    echo "debian"
  fi

}

# Get the dist mapping
get_dist_arch()
{
  if [ "$1" = "x86_64" ]; then
    echo "amd64"
  elif [ "$1" = "aarch64" ]; then
    echo "arm64"
  elif [ "$1" = "armv7l" ]; then
    echo "armhf"
  fi
}

# Get the arch names for FRP archives (https://github.com/fatedier/frp/releases)
get_frp_dist_arch()
{
  if [ "$1" = "armhf" ]; then
    echo "arm"
  else
    echo "$1"
  fi
}

# Installs the server components
# Args: Distribution
install_server()
{
  DIST=$1
  log "Starting server ($VER) install on $DIST"
  show_progress 1
  if dpkg -l | grep -qw edgebuilder-server ;then
    # shellcheck disable=SC2062
    if dpkg -s edgebuilder-server | grep -qw Status.*installed ;then
      PKG_VER=$(dpkg -s edgebuilder-server | grep -i version)
       show_progress 40
      log "Server ($PKG_VER) already installed, exiting" >&3
      exit 0
    fi
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq wget ca-certificates curl gnupg lsb-release

  show_progress 5
  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")
  DIST_ARCH=$(get_dist_arch "$ARCH")

  # Install docker using the repo (TODO : This method isn't supported for Raspbian see install instructions here https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script)
  # Remove any previous non docker-ce installs ( FIXME : This does not work for Ubuntu22.04. For Ubuntu22.04 if docker.io was installed, the user needs to uninstall docker.io and reboot before running the installer)
  # Check if the docker.service and/or docker.socket are running
  if [ "$(systemctl is-enabled docker.service)" = "enabled" ]; then
     systemctl disable docker.service
     if [ "$DIST_NAME" = "jammy" ]; then
        show_progress 40
        log "ERROR: Exiting installation due to (old version) docker already present. Please uninstall docker.io manually and reboot before trying to install Edge Builder" >&3
        exit 1
     fi
  fi

  if [ "$(systemctl is-enabled docker.socket)" = "enabled" ]; then
    systemctl disable docker.socket
  fi
  for i in docker docker-engine docker.io containerd runc; do
    apt-get remove -y $i  # Do not pause on missing packages
  done
  # Refresh systemctl services
  systemctl daemon-reload
  systemctl reset-failed

  show_progress 15
  # Add Docker's official GPG key
  install -m 0755 -d "$KEYRINGS_DIR"
  curl -fsSL https://download.docker.com/linux/"$DIST_TYPE"/gpg | sudo gpg --dearmor --yes -o "$KEYRINGS_DIR"/docker.gpg
  chmod a+r "$KEYRINGS_DIR"/docker.gpg
  echo "deb [arch=$DIST_ARCH signed-by=$KEYRINGS_DIR/docker.gpg] https://download.docker.com/linux/$DIST_TYPE $DIST_NAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  show_progress 18
  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y "$FILE"
  else
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    DIST_NAME=$(get_dist_name "$DIST")
    if [ "$REPOAUTH" != "" ]; then
      if ! grep -q "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
        echo "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
      fi
    else
      if ! grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
        echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
      fi
    fi

    apt-get update -qq
    apt-get install -qq -y edgebuilder-server="$VER"
  fi

  show_progress 30

  USER=$(logname)
  if [ "$USER" != "root" ]; then
    if ! grep -q "$USER     ALL=(ALL) NOPASSWD:ALL" /etc/sudoers ;then
      echo "$USER     ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
    fi
    usermod -aG docker "$USER"
  fi

  show_progress 35
  # start docker services
  systemctl enable docker.service
  systemctl enable docker.socket
  systemctl is-active --quiet docker.service || systemctl start docker.service
  systemctl is-active --quiet docker.socket || systemctl start docker.socket

  show_progress 40
  log " Validating installation" >&3
  OUTPUT=$(edgebuilder-server)
  if [ "$OUTPUT" = "" ]; then
    log "Server installation could not be validated" >&3
  else
    log "Server validation succeeded" >&3
  fi
}

# Installs the node components
# Args: Distribution, Architecture
install_node()
{
  DIST=$1
  ARCH=$2

  log "Starting node ($VER) install on $DIST - $ARCH" >&3
    show_progress 1
  if dpkg -l | grep -qw edgebuilder-node ;then
    # shellcheck disable=SC2062
    if dpkg -s edgebuilder-node | grep -qw Status.*installed ;then
      PKG_VER=$(dpkg -s edgebuilder-node | grep -i version)
      show_progress 40
      log "Node Components ($PKG_VER) already installed, exiting" >&3
      exit 0
    fi
  fi

  show_progress 2

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq wget ca-certificates curl gnupg lsb-release unzip

  show_progress 5

  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")
  DIST_ARCH=$(get_dist_arch "$ARCH")
  FRP_DIST_ARCH=$(get_frp_dist_arch "$DIST_ARCH")

  # Install docker using the repo (TODO : This method isn't supported for Raspbian see install instructions here https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script)
  # Remove any previous non docker-ce installs ( FIXME : This does not work for Ubuntu22.04. For Ubuntu22.04 if docker.io was installed, the user needs to uninstall docker.io and reboot before running the installer)
  # Check if the docker.service and/or docker.socket are running
  if [ "$(systemctl is-enabled docker.service)" = "enabled" ]; then
     systemctl disable docker.service
     if [ "$DIST_NAME" = "jammy" ]; then
        show_progress 40
        log "Exiting installation due to (old version) docker already present. Please uninstall docker.io manually and reboot before trying to install Edge Builder" >&3
        exit 1
     fi
  fi

  if [ "$(systemctl is-enabled docker.socket)" = "enabled" ]; then
    systemctl disable docker.socket
  fi
  for i in docker docker-engine docker.io containerd runc docker-ce docker-ce-cli docker-compose-plugin docker-ce-rootless-extras; do
    apt-get remove -y $i  # Do not pause on missing packages
  done
  # Refresh systemctl services
  systemctl daemon-reload
  systemctl reset-failed

  show_progress 18

  # Add Docker's official GPG key
  install -m 0755 -d "$KEYRINGS_DIR"
  curl -fsSL https://download.docker.com/linux/"$DIST_TYPE"/gpg | sudo gpg --dearmor --yes -o "$KEYRINGS_DIR"/docker.gpg
  chmod a+r "$KEYRINGS_DIR"/docker.gpg
  echo "deb [arch=$DIST_ARCH signed-by=$KEYRINGS_DIR/docker.gpg] https://download.docker.com/linux/$DIST_TYPE $DIST_NAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Setting up repos to access iotech packages
  wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
  if [ "$REPOAUTH" != "" ]; then
    if ! grep -q "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
      echo "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
    fi
  else
    if ! grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
      echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
    fi
  fi

  show_progress 28

  # check if using local file for dev purposes
  echo "FILE = ${FILE}"
  apt-get update -qq
  if test -f "$FILE" ; then
    apt-get install -y "$FILE"
  else
    apt-get install -y -qq edgebuilder-node="$VER"
  fi

  show_progress 28

  USER=$(logname)
  if [ "$USER" != "root" ]; then
    if ! grep -q "$USER     ALL=(ALL) NOPASSWD:ALL" /etc/sudoers ;then
      echo "$USER     ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
    fi
    usermod -aG docker "$USER"
  fi

  show_progress 30

  # Install the FRP client on the node
  curl -LO https://github.com/fatedier/frp/releases/download/v"$FRP_VERSION"/frp_"$FRP_VERSION"_linux_"$FRP_DIST_ARCH".tar.gz && \
    tar -xf frp_"$FRP_VERSION"_linux_"$FRP_DIST_ARCH".tar.gz && cd frp_"$FRP_VERSION"_linux_"$FRP_DIST_ARCH" && cp frpc /usr/local/bin/

  show_progress 35

  # Reconfigure the /etc/pam.d/sshd file to apply edgebuilder user specific settings so that it can use vault OTP authentication
  # Note: All other users should use the default or their own custom pam configurations
  commonAuth="#@include common-auth" # We should disable common-auth for vault authentication
  pamSSHConfigFile="/etc/pam.d/sshd"
  if [ -f /etc/pam.d/sshd ] && [ "$(grep '@include common-auth' ${pamSSHConfigFile})" != "" ]
  then
    commonAuth=$(grep  '@include common-auth' ${pamSSHConfigFile})
  fi
  sed -i 's/^.*@include common-auth//' ${pamSSHConfigFile} # Remove the common-auth line and replace with the below settings
  {
    # IMP: DO NOT ADD/REMOVE any of the following lines
    echo "auth [success=2 default=ignore] pam_succeed_if.so user = edgebuilder"
    echo "${commonAuth}"
    echo "auth [success=ignore default=1] pam_succeed_if.so user = edgebuilder"
    echo "auth requisite pam_exec.so quiet expose_authtok log=/var/log/vault-ssh.log /usr/local/bin/vault-ssh-helper -config=/etc/vault-ssh-helper.d/config.hcl"
    echo "auth optional pam_unix.so use_first_pass nodelay"
  } >> ${pamSSHConfigFile}

  show_progress 40
  # start services
  log "Enabling docker services..." >&3
  systemctl enable docker.service
  systemctl enable docker.socket
  systemctl is-active --quiet docker.service || systemctl start docker.service
  systemctl is-active --quiet docker.socket || systemctl start docker.socket
  # enable builderd service
  systemctl enable builderd.service
  # enable eb-node service for offline node provision
  if [ "$OFFLINE_PROVISION" ]; then
    systemctl enable eb-node.service
    systemctl start eb-node.service
  fi

  log "Validating installation" >&3
  OUTPUT=$(edgebuilder-node)
  if [ "$OUTPUT" = "" ]; then
    log "Node installation could not be validated" >&3
  else
    log "Node validation succeeded" >&3
  fi
}

# Installs the CLI using apt
# Args: Distribution, Architecture
install_cli_deb()
{

  DIST=$1
  ARCH=$2
  # shellcheck disable=SC2062
  log "Starting CLI ($VER) install on $DIST - $ARCH"  >&3

  show_progress 1

  if dpkg -l | grep -qw edgebuilder-cli ;then
    # shellcheck disable=SC2062
    if dpkg -s edgebuilder-cli | grep -qw Status.*installed ;then
      PKG_VER=$(dpkg -s edgebuilder-node | grep -i version)
      show_progress 40
      log "CLI ($PKG_VER) already installed, exiting"  >&3
      exit 0
    fi
  fi
   show_progress 2

  if version_under_2_6_23; then
    show_progress 40
    log "Kernel version $(uname -r), requires 2.6.23 or above"  >&3
    exit 1
  fi
  show_progress 5
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq wget ca-certificates curl gnupg lsb-release
  show_progress 15
  # check if using local file for dev purposes
  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y "$FILE"
  else
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    if [ "$REPOAUTH" != "" ]; then
      if ! grep -q "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev all main" /etc/apt/sources.list.d/eb-iotech-cli.list ;then
        echo "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev all main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech-cli.list
      fi
    else
      if ! grep -q "deb https://iotech.jfrog.io/artifactory/debian-release all main" /etc/apt/sources.list.d/eb-iotech-cli.list ;then
        echo "deb https://iotech.jfrog.io/artifactory/debian-release all main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech-cli.list
      fi
    fi
  fi
  show_progress 25

  # check if using local file for dev pur
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  if test -f "$FILE" ; then
    apt-get install -y "$FILE"
  else
    sudo apt-get install -y -qq edgebuilder-cli="$VER"
  fi

  show_progress 40

  log "Validating installation"  >&3
  OUTPUT=$(edgebuilder-cli -v)
  if [ "$OUTPUT" = "" ]; then
    log "CLI installation could not be validated"  >&3
    show_progress 40
    exit 1
  else
    log "CLI validation succeeded"  >&3
  fi
}

# Installs the CLI using dnf
# Args: Distribution, Architecture
install_cli_rpm()
{
  DIST=$1
  ARCH=$2
  PKG_MNGR=$3

  log  "Starting CLI ($VER) install on $DIST - $ARCH" >&3
  show_progress 1
  if rpm -qa | grep -qw edgebuilder-cli ;then
    PKG_VER=$("$PKG_MNGR" info --installed edgebuilder-cli | grep Version)
    show_progress 40
    log "CLI ($PKG_VER) already installed, exiting" >&3
    exit 0
  fi

  if version_under_2_6_23; then
    log "Kernel version $(uname -r), requires 2.6.23 or above" >&3
    show_progress 40
    exit 1
  fi

  if ! grep -q "$RPM_REPO_DATA" /etc/yum.repos.d/eb-iotech-cli.repo ;then
    echo "$RPM_REPO_DATA" | sudo tee -a /etc/yum.repos.d/eb-iotech-cli.repo
  fi
  show_progress 15

  "$PKG_MNGR" install -y edgebuilder-cli-"$VER"*

  show_progress 40

  log "Validating installation" >&3
  OUTPUT=$(edgebuilder-cli -v)
  if [ "$OUTPUT" = "" ]; then
    log "CLI installation could not be validated" >&3
  else
    log "CLI validation succeeded" >&3
  fi
}

# Uninstall the Server components
uninstall_server()
{
    export DEBIAN_FRONTEND=noninteractive
    if dpkg -s edgebuilder-server; then

        sudo rm -rf /opt/edgebuilder/server/vault
        # attempt autoremove
        if sudo apt autoremove -qq edgebuilder-server -y ;then
            log "Successfully autoremoved server components" >&3
        else
            log "Failed to autoremove Server Components" >&3
            exit 1
        fi

        # attempt purge
        if sudo apt-get -qq purge edgebuilder-server -y ;then
            log "Successfully purged Server Components" >&3
        else
            log "Failed to purge Server Components" >&3
            exit 1
        fi

        # Successfully installed, exit
        log "Server Components Uninstalled" >&3
        exit 0
    else
        # package not currently installed, so exit
        log "edgebuilder-server NOT currently installed" >&3
        exit 0
    fi
}

# Uninstall the Node components
uninstall_node()
{
  if dpkg -s edgebuilder-node; then

      # attempt autoremove
      if sudo apt autoremove -qq edgebuilder-node -y ;then
          log "Successfully autoremoved node components" >&3
      else
          log "Failed to autoremove node components" >&3
          exit 1
      fi

      # attempt purge
      if sudo apt-get purge -qq edgebuilder-node -y ;then
          log  "Successfully purged Node Components" >&3
      else
          log "Failed to purge Node Components" >&3
          exit 1
      fi

      # Successfully installed, exit
      log "Node Components Uninstalled" >&3
      exit 0
  else
      # package not currently installed, so exit
      log "edgebuilder-node NOT currently installed" >&3
      exit 0
  fi
}

# Uninstall the CLI components
uninstall_cli()
{
  # check if edgebuilder-cli is currently installed
  if dpkg -s edgebuilder-cli; then

      # attempt autoremove
      if sudo apt autoremove -qq edgebuilder-cli -y ;then
          log "Successfully autoremoved CLI" >&3
      else
          log "Failed to autoremove CLI" >&3
          exit 1
      fi

      # attempt purge
      if sudo apt-get -qq purge edgebuilder-cli -y ;then
          log "Successfully purged CLI" >&3
      else
          log "Failed to purge CLI" >&3
          exit 1
      fi

      # Successfully installed, exit
      log "CLI Components Uninstalled" >&3
      exit 0
  else
      # package not currently installed, so exit
      log "edgebuilder-cli NOT currently installed" >&3
      exit 0
  fi
}

# Displays simple usage prompt
display_usage()
{
  echo "Usage: edgebuilder-install.sh [param] [options]"
  echo "params: server, node, cli"
  echo "options: "
  echo "     -r, --repo-auth          : IoTech repo auth token to access packages"
  echo "     -u, --uninstall          : Uninstall the package"
  echo "     -f, --file               : Absolute path to local package"
  echo "     --offline-provision      : Enable offline node provision"
}

## Main starts here: ##
# If no options are specified, print help
while [ "$1" != "" ]; do
    case $1 in
        node | server | cli)
            COMPONENT="$1"
            shift
            ;;
        -f | --file)
            FILE="$2"
            shift
            shift
            ;;
        -r | --repo-auth)
            REPOAUTH="$2"
            shift
            shift
            ;;
        -u | --uninstall)
            UNINSTALL=true
            shift
            ;;
        --offline-provision)
            OFFLINE_PROVISION=true
            shift
            ;;
        *)
            UNKNOWN_ARG="$1"
            echo "$NODE_ERROR_PREFIX unknown argument '$UNKNOWN_ARG'"
            display_usage
            exit 3
            ;;
    esac
done
if [ -z "$COMPONENT" ];then
    display_usage
    exit 1
fi

# If not run as sudo, exit
if [ "$(id -u)" -ne 0 ]
  then log "Insufficient permissions, please run as root/sudo" >&3
  exit 1
fi

# if the FILE argument has been supplied and is not a valid path to a file, output an error then exit
if [ "$FILE" != "" ] && ! [ -f "$FILE" ]; then
  log "File $FILE does not exist."  >&3
  exit 1
fi

log "Detecting OS and Architecture"  >&3

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS="$NAME $VERSION_ID"
elif type lsb_release >/dev/null 2>&1; then
    OS="$(lsb_release -si) $(lsb_release -sr)"
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS="$DISTRIB_ID $DISTRIB_RELEASE"
elif [ -f /etc/debian_version ]; then
    OS="Debian $(cat /etc/debian_version)"
else
    OS="$(uname -s) $(uname -r)"
fi

# Detect Arch
ARCH="$(uname -m)"

# Check compatibility
log "Checking compatibility"  >&3
if [ "$COMPONENT" = "server" ];then

  if "$UNINSTALL"; then
      uninstall_server
  fi

  if [ "$ARCH" = "x86_64" ]||[ "$ARCH" = "aarch64" ];then
    if [ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU2204" ]||[ "$OS" = "$DEBIAN10" ]||[ "$OS" = "$DEBIAN11" ];then
      install_server "$OS"
    else
      log "The Edge Builder server components are not supported on $OS - $ARCH"  >&3
    fi
  else
    log "The Edge Builder server components are not supported on $ARCH"  >&3
    exit 1
  fi
elif [ "$COMPONENT" = "node" ]; then

  if "$UNINSTALL"; then
    uninstall_node
  fi

  if [ "$ARCH" = "x86_64" ]||[ "$ARCH" = "aarch64" ]||[ "$ARCH" = "armv7l" ];then
    if [ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU2204" ]||[ "$OS" = "$DEBIAN10" ]||[ "$OS" = "$DEBIAN11" ];then
      install_node "$OS" "$ARCH"
    else
      log "The Edge Builder node components are not supported on $OS - $ARCH"  >&3
      exit 1
    fi
  else
    log "The Edge Builder node components are not supported on $ARCH"  >&3
    exit 1
  fi
elif [ "$COMPONENT" = "cli" ]; then

  if "$UNINSTALL"; then
      uninstall_cli
  fi

  if [ "$ARCH" = "x86_64" ]||[ "$ARCH" = "aarch64" ]||[ "$ARCH" = "armv7l" ];then
    if [ -x "$(command -v apt-get)" ]; then
      install_cli_deb "$OS" "$ARCH"
    elif [ -x "$(command -v dnf)" ]; then
      install_cli_rpm "$OS" "$ARCH" "dnf"
    elif [ -x "$(command -v yum)" ]; then
      install_cli_rpm "$OS" "$ARCH" "yum"
    else
      log "The Edge Builder CLI cannot be installed as no suitable package manager has been found (apt, dnf or yum)"  >&3
      exit 1
    fi
  else
    log "The Edge Builder CLI is not supported on $ARCH"  >&3
    exit 1
  fi
fi
