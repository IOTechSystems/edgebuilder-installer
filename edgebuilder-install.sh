#!/bin/sh
COMPONENT=$1
shift

FILE=""
REPOAUTH=""
VER="2.1.0.dev"
SALT_MINION_VER="3005"

while [ "$1" != "" ]; do
    case $1 in
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
        *)
            UNKNOWN_ARG="$1"
            echo "$NODE_ERROR_PREFIX unknown argument '$UNKNOWN_ARG'"
            display_usage
            exit 3
            ;;
    esac
done

UBUNTU2204="Ubuntu 22.04"
UBUNTU2004="Ubuntu 20.04"
UBUNTU1804="Ubuntu 18.04"
DEBIAN10="Debian GNU/Linux 10"
DEBIAN11="Debian GNU/Linux 11"
RASPBIAN10="Raspbian GNU/Linux 10"

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

# Displays simple usage prompt
display_usage()
{
  echo "Usage: edgebuilder-install.sh [param]"
  echo "params: server, node, cli"
}

# Gets the distribution 'name' bionic, focal etc
get_dist_name()
{
  if [ "$1" = "$UBUNTU2204" ]; then
    echo "jammy"
  elif [ "$1" = "$UBUNTU2004" ]; then
    echo "focal"
  elif  [ "$1" = "$UBUNTU1804" ]; then
    echo "bionic"
  elif  [ "$1" = "$DEBIAN11" ]; then
      echo "bullseye"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "buster"
  fi
}

# Gets the distribution number 20.04, 18.04 etc
get_dist_num()
{
  if [ "$1" = "$UBUNTU2204" ]; then
    echo "22.04"
  elif [ "$1" = "$UBUNTU2004" ]; then
    echo "20.04"
  elif  [ "$1" = "$UBUNTU1804" ]; then
    echo "18.04"
  elif  [ "$1" = "$DEBIAN11" ]; then
    echo "11"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "10"
  fi
}

# Gets the basic distribution type ubuntu, debian etc
get_dist_type()
{
  if [ "$1" = "$UBUNTU2204" ] || [ "$1" = "$UBUNTU2004" ] || [ "$1" = "$UBUNTU1804" ]; then
    echo "ubuntu"
  elif  [ "$1" = "$DEBIAN11" ] || [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "debian"
  fi

}

# Get the dist mapping for salt repos
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

# Installs the server components
# Args: Distribution
install_server()
{
  DIST=$1
  echo "INFO: Starting server ($VER) install on $DIST"
  if dpkg -l | grep -qw edgebuilder-server ;then
    # shellcheck disable=SC2062
    if dpkg -s edgebuilder-server | grep -qw Status.*installed ;then
      PKG_VER=$(dpkg -s edgebuilder-server | grep -i version)
      echo "INFO: Server ($PKG_VER) already installed, exiting"
      exit 0
    fi
  fi

  apt-get update -qq
  apt-get install -y -qq wget ca-certificates curl gnupg lsb-release

  # check if using local file for dev purposes
  echo "INFO: Installing"

  echo "INFO: Setting up apt for Edge Builder"
  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")
  DIST_ARCH=$(get_dist_arch "$ARCH")

  # Install docker using the repo (TODO : This method isn't supported for Raspbian see install instructions here https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script)
  # Remove any previous non docker-ce installs ( FIXME : This does not work for Ubuntu22.04. For Ubuntu22.04 if docker.io was installed, the user needs to uninstall docker.io and reboot before running the installer)
  # Check if the docker.service and/or docker.socket are running
  if [ "$(systemctl is-enabled docker.service)" = "enabled" ]; then
     echo "WARN: docker.service is enabled, disabling..."
     systemctl disable docker.service
     if [ "$DIST_NAME" = "jammy" ]; then
        echo "ERROR: Exiting installation due to (old version) docker already present. Please uninstall docker.io manually and reboot before trying to install Edge Builder"
        exit 1
     fi
  fi

  if [ "$(systemctl is-enabled docker.socket)" = "enabled" ]; then
    echo "WARN: docker.socket is enabled, disabling..."
    systemctl disable docker.socket
  fi
  for i in docker docker-engine docker.io containerd runc; do
    echo "INFO: Attempting to remove $i"
    apt-get remove -y $i  # Do not pause on missing packages
  done
  # Refresh systemctl services
  systemctl daemon-reload
  systemctl reset-failed
  # Add Docker's official GPG key
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/"$DIST_TYPE"/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$DIST_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DIST_TYPE $DIST_NAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y ./$FILE
  else
    echo "INFO: Setting up apt for Edge Builder"
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    DIST_NAME=$(get_dist_name "$DIST")
    if [ "$REPOAUTH" != "" ]; then
      if grep -q "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
        echo "INFO: IoTech PRIVATE repo already added"
      else
        echo "INFO: Adding IoTech PRIVATE repo"
        echo "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
      fi
    else
      if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
        echo "INFO: IoTech repo already added"
      else
        echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
      fi
    fi

    apt-get update -qq
    apt-get install -qq -y edgebuilder-server="$VER"
  fi

  echo "INFO: Configuring user"
  USER=$(logname)
  if [ "$USER" != "root" ]; then
    if grep -q "$USER     ALL=(ALL) NOPASSWD:ALL" /etc/sudoers ;then
      echo "User already in sudoers"
    else
      echo "$USER     ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
    fi
    usermod -aG docker "$USER"
  fi

  # start docker services
  echo "INFO: Enabling docker services..."
  systemctl enable docker.service
  systemctl enable docker.socket
  systemctl is-active --quiet docker.service || systemctl start docker.service
  systemctl is-active --quiet docker.socket || systemctl start docker.socket

  echo "INFO: Validating installation"
  OUTPUT=$(edgebuilder-server)
  if [ "$OUTPUT" = "" ]; then
    echo "ERROR: Server installation could not be validated"
  else
    echo "INFO: Server validation succeeded"
  fi
}

# Installs the node components
# Args: Distribution, Architecture
install_node()
{
  DIST=$1
  ARCH=$2
  echo "INFO: Starting node ($VER) install on $DIST - $ARCH"
  if dpkg -l | grep -qw edgebuilder-node ;then
    # shellcheck disable=SC2062
    if dpkg -s edgebuilder-node | grep -qw Status.*installed ;then
      PKG_VER=$(dpkg -s edgebuilder-node | grep -i version)
      echo "INFO: Node Components ($PKG_VER) already installed, exiting"
      exit 0
    fi
  fi


  apt-get update -qq
  apt-get install -y -qq wget ca-certificates curl gnupg lsb-release

  echo "INFO: Setting up apt"
  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")
  DIST_ARCH=$(get_dist_arch "$ARCH")
  SALT_REPO_PREFIX="salt/py3"
  echo "Setting up sources for salt..."
  echo "$DIST_NAME"

  if [ "$DIST_NAME" = "jammy" ]; then
    export DEBIAN_FRONTEND=noninteractive  # Note: this selects the default to avoid the user prompt, another way is to find the offending library and set its restart without asking flag in debconf-set-selections to 'true'
  fi

  if [ "$DIST_ARCH" = "arm64" ]||[ "$DIST_ARCH" = "armhf "]; then
    SALT_REPO_PREFIX="py3"
  fi

  KEY_DIR="/etc/apt/keyrings"
  if [ ! -d "$KEY_DIR" ]; then
     mkdir -p /etc/apt/keyrings
  fi
  if fgrep -q "deb [signed-by=$KEY_DIR/salt-archive-keyring.gpg arch=$DIST_ARCH] https://repo.saltproject.io/$SALT_REPO_PREFIX/$DIST_TYPE/$DIST_NUM/$DIST_ARCH/$SALT_MINION_VER $DIST_NAME main" /etc/apt/sources.list.d/eb-salt.list ;then
     echo "INFO: Salt repo already added"
  else
     # Download key
     sudo curl -fsSL -o "$KEY_DIR"/salt-archive-keyring.gpg https://repo.saltproject.io/$SALT_REPO_PREFIX/"$DIST_TYPE"/"$DIST_NUM"/"$DIST_ARCH"/$SALT_MINION_VER/salt-archive-keyring.gpg
     # Create apt sources list file
     echo "deb [signed-by=$KEY_DIR/salt-archive-keyring.gpg arch=$DIST_ARCH] https://repo.saltproject.io/$SALT_REPO_PREFIX/$DIST_TYPE/$DIST_NUM/$DIST_ARCH/$SALT_MINION_VER $DIST_NAME main" | sudo tee /etc/apt/sources.list.d/eb-salt.list
  fi

  echo "Setting up sources for docker..."
  # Install docker using the repo (TODO : This method isn't supported for Raspbian see install instructions here https://docs.docker.com/engine/install/debian/#install-using-the-convenience-script)
  # Remove any previous non docker-ce installs ( FIXME : This does not work for Ubuntu22.04. For Ubuntu22.04 if docker.io was installed, the user needs to uninstall docker.io and reboot before running the installer)
  # Check if the docker.service and/or docker.socket are running
  if [ "$(systemctl is-enabled docker.service)" = "enabled" ]; then
     echo "WARN: docker.service is enabled, disabling..."
     systemctl disable docker.service
     if [ "$DIST_NAME" = "jammy" ]; then
       echo "ERROR: Exiting installation due to (old version) docker already present. Please uninstall docker.io manually and reboot before trying to install Edge Builder"
       exit 1
     fi
  fi

  if [ "$(systemctl is-enabled docker.socket)" = "enabled" ]; then
    echo "WARN: docker.socket is enabled, disabling..."
    systemctl disable docker.socket
  fi
  for i in docker docker-engine docker.io containerd runc docker-ce docker-ce-cli docker-compose-plugin; do
    echo "INFO: Attempting to remove $i"
    apt-get remove -y $i  # Do not pause on missing packages
  done
  # Refresh systemctl services
  systemctl daemon-reload
  systemctl reset-failed

  # Add Docker's official GPG key
  curl -fsSL https://download.docker.com/linux/"$DIST_TYPE"/gpg | sudo gpg --dearmor --yes -o "$KEY_DIR"/docker.gpg
  echo "deb [arch=$DIST_ARCH signed-by=$KEY_DIR/docker.gpg] https://download.docker.com/linux/$DIST_TYPE $DIST_NAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # check if using local file for dev purposes
  echo "INFO: Installing"
  echo "FILE = ${FILE}"
  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y ./"$FILE"
  else
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    if [ "$REPOAUTH" != "" ]; then
      if grep -q "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
        echo "INFO: IoTech PRIVATE repo already added"
      else
        echo "INFO: Adding IoTech PRIVATE repo"
        echo "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
      fi
    else
      if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/eb-iotech.list ;then
        echo "INFO: IoTech repo already added"
      else
        echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech.list
      fi
    fi
    apt-get update -qq
    apt-get install -y -qq edgebuilder-node="$VER"
  fi


  echo "INFO: Configuring user"
  USER=$(logname)
  if [ "$USER" != "root" ]; then
    if grep -q "$USER     ALL=(ALL) NOPASSWD:ALL" /etc/sudoers ;then
      echo "User already in sudoers"
    else
      echo "Adding user \"$USER\" to sudoers"
      echo "$USER     ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
    fi
    echo "Adding user \"$USER\" to docker group"
    usermod -aG docker "$USER"
  fi

  # start docker services
  echo "INFO: Enabling docker services..."
  systemctl enable docker.service
  systemctl enable docker.socket
  systemctl is-active --quiet docker.service || systemctl start docker.service
  systemctl is-active --quiet docker.socket || systemctl start docker.socket

  echo "INFO: Validating installation"
  OUTPUT=$(edgebuilder-node)
  if [ "$OUTPUT" = "" ]; then
    echo "ERROR: Node installation could not be validated"
  else
    echo "INFO: Node validation succeeded"
  fi
}

# Installs the CLI using apt
# Args: Distribution, Architecture
install_cli_deb()
{
  DIST=$1
  ARCH=$2
  # shellcheck disable=SC2062
  echo "INFO: Starting CLI ($VER) install on $DIST - $ARCH"

  if dpkg -l | grep -qw edgebuilder-cli ;then
    # shellcheck disable=SC2062
    if dpkg -s edgebuilder-cli | grep -qw Status.*installed ;then
      PKG_VER=$(dpkg -s edgebuilder-node | grep -i version)
      echo "INFO: CLI ($PKG_VER) already installed, exiting"
      exit 0
    fi
  fi

  if version_under_2_6_23; then
    echo "ERROR: Kernel version $(uname -r), requires 2.6.23 or above"
    exit 1
  fi

  # check if using local file for dev purposes
  echo "INFO: Installing"
  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y ./$FILE
  else
    echo "INFO: Setting up apt"
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    if [ "$REPOAUTH" != "" ]; then
      if grep -q "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev all main" /etc/apt/sources.list.d/eb-iotech-cli.list ;then
        echo "INFO: IoTech PRIVATE repo already added"
      else
        echo "INFO: Adding IoTech PRIVATE repo"
        echo "deb https://$REPOAUTH@iotech.jfrog.io/artifactory/debian-dev all main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech-cli.list
      fi
    else
      if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release all main" /etc/apt/sources.list.d/eb-iotech-cli.list ;then
        echo "INFO: IoTech repo already added"
      else
        echo "deb https://iotech.jfrog.io/artifactory/debian-release all main" | sudo tee -a /etc/apt/sources.list.d/eb-iotech-cli.list
      fi
    fi

    sudo apt-get update -qq
    sudo apt-get install -y -qq edgebuilder-cli="$VER"
  fi

  echo "INFO: Validating installation"
  OUTPUT=$(edgebuilder-cli -v)
  if [ "$OUTPUT" = "" ]; then
    echo "ERROR: CLI installation could not be validated"
  else
    echo "INFO: CLI validation succeeded"
  fi
}

# Installs the CLI using dnf
# Args: Distribution, Architecture
install_cli_rpm()
{
  DIST=$1
  ARCH=$2
  PKG_MNGR=$3

  echo "INFO: Starting CLI ($VER) install on $DIST - $ARCH"
  if rpm -qa | grep -qw edgebuilder-cli ;then
    PKG_VER=$("$PKG_MNGR" info --installed edgebuilder-cli | grep Version)
    echo "INFO: CLI ($PKG_VER) already installed, exiting"
    exit 0
  fi

  if version_under_2_6_23; then
    echo "ERROR: Kernel version $(uname -r), requires 2.6.23 or above"
    exit 1
  fi

  echo "INFO: Setting up yum/dnf"
  if grep -q "$RPM_REPO_DATA" /etc/yum.repos.d/eb-iotech-cli.repo ;then
    echo "INFO: IoTech repo already added"
  else
    echo "$RPM_REPO_DATA" | sudo tee -a /etc/yum.repos.d/eb-iotech-cli.repo
  fi

  echo "INFO: Installing"
  "$PKG_MNGR" install -y edgebuilder-cli-"$VER"*

  echo "INFO: Validating installation"
  OUTPUT=$(edgebuilder-cli -v)
  if [ "$OUTPUT" = "" ]; then
    echo "ERROR: CLI installation could not be validated"
  else
    echo "INFO: CLI validation succeeded"
  fi
}

# Main starts here:

# If no options are specified
if [ -z $COMPONENT ];then
    display_usage
    exit 1
fi

# If not run as sudo, exit
if [ "$(id -u)" -ne 0 ]
  then echo "ERROR: Insufficient permissions, please run as root/sudo"
  exit 1
fi

echo "INFO: Detecting OS and Architecture"

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
echo "INFO: Checking compatibility"
if [ "$COMPONENT" = "server" ];then
  if [ "$ARCH" = "x86_64" ];then
    if [ "$OS" = "$UBUNTU2204" ]||[ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU1804" ]||[ "$OS" = "$DEBIAN11" ]||[ "$OS" = "$DEBIAN10" ];then
      install_server "$OS"
    else
      echo "ERROR: The Edge Builder server components are not supported on $OS - $ARCH"
    fi
  else
    echo "ERROR: The Edge Builder server components are not supported on $ARCH"
    exit 1
  fi
elif [ "$COMPONENT" = "node" ]; then
  if [ "$ARCH" = "x86_64" ]||[ "$ARCH" = "aarch64" ];then
    if [ "$OS" = "$UBUNTU2204" ]||[ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU1804" ]||[ "$OS" = "$DEBIAN11" ];then
      install_node "$OS" "$ARCH"
    else
      echo "ERROR: The Edge Builder node components are not supported on $OS - $ARCH"
      exit 1
    fi
  elif [ "$ARCH" = "armv7l" ];then
    if [ "$OS" = "$RASPBIAN10" ] || [ "$OS" = "$DEBIAN11" ] || [ "$OS" = "$DEBIAN10" ]; then
      install_node "$OS" "$ARCH"
    else
      echo "ERROR: The Edge Builder node components are not supported on $OS - $ARCH"
      exit 1
    fi
  else
    echo "ERROR: The Edge Builder node components are not supported on $ARCH"
    exit 1
  fi
elif [ "$COMPONENT" = "cli" ]; then

  if [ "$ARCH" = "x86_64" ]||[ "$ARCH" = "aarch64" ]||[ "$ARCH" = "armv7l" ];then
    if [ -x "$(command -v apt-get)" ]; then
      install_cli_deb "$OS" "$ARCH"
    elif [ -x "$(command -v dnf)" ]; then
      install_cli_rpm "$OS" "$ARCH" "dnf"
    elif [ -x "$(command -v yum)" ]; then
      install_cli_rpm "$OS" "$ARCH" "yum"
    else
      echo "ERROR: The Edge Builder CLI cannot be installed as no suitable package manager has been found (apt, dnf or yum)"
      exit 1
    fi
  else
    echo "ERROR: The Edge Builder CLI is not supported on $ARCH"
    exit 1
  fi
fi
