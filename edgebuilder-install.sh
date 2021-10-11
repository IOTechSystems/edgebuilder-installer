#!/bin/sh
COMPONENT=$1
FILE=$2
VER="1.1.3"

UBUNTU2104="Ubuntu 21.04"
UBUNTU2004="Ubuntu 20.04"
UBUNTU1804="Ubuntu 18.04"
DEBIAN10="Debian GNU/Linux 10"
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
  if [ "$1" = "$UBUNTU2104" ]; then
    echo "hirsute"
  elif [ "$1" = "$UBUNTU2004" ]; then
    echo "focal"
  elif  [ "$1" = "$UBUNTU1804" ]; then
    echo "bionic"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "buster"
  fi
}

# Gets the distribution number 20.04, 18.04 etc
get_dist_num()
{
  if [ "$1" = "$UBUNTU2104" ]; then
    echo "21.04"
  elif [ "$1" = "$UBUNTU2004" ]; then
    echo "20.04"
  elif  [ "$1" = "$UBUNTU1804" ]; then
    echo "18.04"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "10"
  fi
}

# Gets the basic distribution type ubuntu, debian etc
get_dist_type()
{
  if [ "$1" = "$UBUNTU2104" ] || [ "$1" = "$UBUNTU2004" ] || [ "$1" = "$UBUNTU1804" ]; then
    echo "ubuntu"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "debian"
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

  if dpkg -l | grep -qw docker-ce ;then
    # shellcheck disable=SC2062
    if dpkg -s docker-ce | grep -qw Status.*installed ;then
      echo  "ERRPR: docker-ce is installed, please uninstall before continuing"
      exit 1
    fi
  fi

  apt-get update -qq
  apt-get install -y -qq wget

  # check if using local file for dev purposes
  echo "INFO: Installing"
  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y ./$FILE
  else 
     echo "INFO: Setting up apt"
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    DIST_NAME=$(get_dist_name "$DIST")
    if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/iotech.list ;then
      echo "INFO: IoTech repo already added"
    else
      echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/iotech.list
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
  systemctl enable docker.service

  echo "INFO: Server installation complete"

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

  # shellcheck disable=SC2062
  if dpkg -l | grep -qw docker-ce ;then
    if dpkg -s docker-ce | grep -qw Status.*installed ;then
      echo  "ERROR: docker-ce is installed, please uninstall before continuing"
      exit 1
    fi
  fi

  apt-get update -qq
  apt-get install -y -qq wget curl

  echo "INFO: Setting up apt"
  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")

  if [ "$ARCH" = "x86_64" ];then

    if grep -q "deb https://repo.saltproject.io/py3/$DIST_TYPE/$DIST_NUM/amd64/3003 $DIST_NAME main" /etc/apt/sources.list.d/salt.list ;then
      echo "INFO: Salt repo already added"
    else
      sudo curl -fsSL -o /usr/share/keyrings/salt-archive-keyring.gpg "https://repo.saltproject.io/py3/$DIST_TYPE/$DIST_NUM/amd64/3003/salt-archive-keyring.gpg"
      echo "deb [signed-by=/usr/share/keyrings/salt-archive-keyring.gpg arch=amd64] https://repo.saltproject.io/py3/$DIST_TYPE/$DIST_NUM/amd64/3003 $DIST_NAME main" | sudo tee /etc/apt/sources.list.d/salt.list
    fi

  elif [ "$ARCH" = "aarch64" ];then
    wget -q "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest/salt-common_3003%2Bds-1_all.deb" & wget -q "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest/salt-minion_3003%2Bds-1_all.deb"
    apt-get install -y -qq ./*.deb
    rm salt-common_3003+ds-1_all.deb salt-minion_3003+ds-1_all.deb

  elif [ "$ARCH" = "armv7l" ];then
    wget -q -O - "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/armhf/latest/SALTSTACK-GPG-KEY.pub" | sudo apt-key add -
    if grep -q "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/armhf/latest $DIST_NAME main" /etc/apt/sources.list.d/saltstack.list ;then
      echo "INFO: Salt repo already added"
    else
      echo "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/armhf/latest $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/saltstack.list
    fi
  fi

  # check if using local file for dev purposes
  echo "INFO: Installing"
  echo "FILE = ${FILE}"
  if test -f "$FILE" ; then
    apt-get update -qq
    apt-get install -y ./"$FILE"
  else     
    wget -q -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
    if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/iotech.list ;then
      echo "INFO: IoTech repo already added"
    else
      echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/iotech.list
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
      echo "$USER     ALL=(ALL) NOPASSWD:ALL" | sudo EDITOR='tee -a' visudo
    fi
    usermod -aG docker $USER
  fi
  systemctl enable docker.service

  echo "INFO: Node installation complete"

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
    if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release all main" /etc/apt/sources.list.d/iotech.list ;then
      echo "INFO: IoTech repo already added"
    else
      echo "deb https://iotech.jfrog.io/artifactory/debian-release all main" | sudo tee -a /etc/apt/sources.list.d/iotech.list
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
  if grep -q "$RPM_REPO_DATA" /etc/yum.repos.d/iotech.repo ;then
    echo "INFO: IoTech repo already added"
  else
    echo "$RPM_REPO_DATA" | sudo tee -a /etc/yum.repos.d/iotech.repo
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
if [ -z $1 ];then
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
    if [ "$OS" = "$UBUNTU2104" ]||[ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU1804" ]||[ "$OS" = "$DEBIAN10" ];then
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
    if [ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU1804" ]||[ "$OS" = "$DEBIAN10" ];then
      install_node "$OS" "$ARCH"
    else
      echo "ERROR: The Edge Builder node components are not supported on $OS - $ARCH"
      exit 1
    fi
  elif [ "$ARCH" = "armv7l" ];then
    if [ "$OS" = "$RASPBIAN10" ]; then
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
