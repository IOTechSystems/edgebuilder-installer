#!/bin/sh
COMPONENT=$1
UBUNTU2004="Ubuntu 20.04"
UBUNTU1804="Ubuntu 18.04"
DEBIAN10="Debian GNU/Linux 10"
RASPBIAN10="Raspbian GNU/Linux 10"

display_usage()
{
    echo "Usage: edgebuilder-install.sh [param]"
    echo "params: server, node, cli"
}

get_dist_name()
{
  if [ "$1" = "$UBUNTU2004" ]; then
    echo "focal"
  elif  [ "$1" = "$UBUNTU1804" ]; then
    echo "bionic"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "buster"
  fi
}

get_dist_num()
{
  if [ "$1" = "$UBUNTU2004" ]; then
    echo "20.04"
  elif  [ "$1" = "$UBUNTU1804" ]; then
    echo "18.04"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "10"
  fi
}

get_dist_type()
{
  if [ "$1" = "$UBUNTU2004" ]||[ "$1" = "$UBUNTU1804" ]; then
    echo "ubuntu"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "debian"
  fi

}

install_server()
{
  DIST=$1
  echo "INFO: Starting server install on $DIST"
  if dpkg -l | grep -qw edgebuilder-server ;then
    echo "INFO: Server already installed, exiting"
    exit 0
  fi

  apt-get update -qq
  apt-get install -y -qq wget

  echo "INFO: Setting up apt"
  wget -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
  DIST_NAME=$(get_dist_name "$DIST")
  if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/iotech.list ;then
    echo "INFO: IoTech repo already added"
  else
    echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/iotech.list
  fi

  echo "INFO: Installing"
  apt-get update -qq
  apt-get install -qq -y edgebuilder-server

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

  echo "INFO: Server installation complete"
}

install_node()
{
  DIST=$1
  ARCH=$2
  echo "INFO: Starting node install on $DIST - $ARCH"
  if dpkg -l | grep -qw edgebuilder-node ;then
    echo "INFO: Node components already installed, exiting"
    exit 0
  fi

  apt-get update -qq
  apt-get install -y -qq wget

  echo "INFO: Setting up apt"
  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")

  if [ "$ARCH" = "x86_64" ];then
    wget -O - "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest/SALTSTACK-GPG-KEY.pub" | sudo apt-key add -
    if grep -q "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest $DIST_NAME main" /etc/apt/sources.list.d/saltstack.list ;then
      echo "INFO: Salt repo already added"
    else
      echo "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/saltstack.list
    fi

  elif [ "$ARCH" = "aarch64" ];then
    wget "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest/salt-common_3003%2Bds-1_all.deb" & wget "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest/salt-minion_3003%2Bds-1_all.deb"
    apt-get install -y -qq ./*.deb
    rm salt-common_3003+ds-1_all.deb salt-minion_3003+ds-1_all.deb

  elif [ "$ARCH" = "armv7l" ];then
    wget -O - "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/armhf/latest/SALTSTACK-GPG-KEY.pub" | sudo apt-key add -
    if grep -q "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/armhf/latest $DIST_NAME main" /etc/apt/sources.list.d/saltstack.list ;then
      echo "INFO: Salt repo already added"
    else
      echo "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/armhf/latest $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/saltstack.list
    fi
  fi

  wget -O - https://iotech.jfrog.io/iotech/api/gpg/key/public | sudo apt-key add -
  if grep -q "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" /etc/apt/sources.list.d/iotech.list ;then
    echo "INFO: IoTech repo already added"
  else
    echo "deb https://iotech.jfrog.io/artifactory/debian-release $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/iotech.list
  fi

  apt-get update -qq

  echo "INFO: Installing"
  apt-get install -y -qq edgebuilder-node

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
  fi
  echo $OUTPUT
  echo "INFO: Validation succeeded"
}


# If no options are specified
if [ -z $1 ];then
    display_usage
    exit 1
fi

# If not run as sudo, exit
if [ "$(id -u)" -ne 0 ]
  then echo "ERROR: Insufficient permissions, please run as root/sudo"
  exit 2
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
    if [ "$OS" = "$UBUNTU2004" ]||[ "$OS" = "$UBUNTU1804" ]||[ "$OS" = "$DEBIAN10" ];then
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
      echo "do install"
    elif [ -x "$(command -v dnf)" ]; then
      echo "do install"
    else
      echo "ERROR: The Edge Builder CLI cannot be installed as no suitable package manager has been found (apt or dnf)"
      exit 1
    fi
  else
    echo "ERROR: The Edge Builder CLI is not supported on $ARCH"
    exit 1
  fi

fi
