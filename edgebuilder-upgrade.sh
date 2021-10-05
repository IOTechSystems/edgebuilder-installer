#!/bin/sh

set -x
LATEST_VER="1.1.2"
INSTALLED_VER=""
COMPONENT=$1
TARGET_VER=$2
FILE=$3

UBUNTU2004="Ubuntu 20.04"
UBUNTU1804="Ubuntu 18.04"
DEBIAN10="Debian GNU/Linux 10"
RASPBIAN10="Raspbian GNU/Linux 10"

RPM_REPO_DATA='[IoTech]
name=IoTech
baseurl=https://iotech.jfrog.io/artifactory/rpm-release
enabled=1
gpgcheck=0'

# Checks if the installed version is older than the latest version available
installed_version_older(){

  eb_component=edgebuilder-$1

    # Check for existing installation
    if dpkg -l | grep -qw "$eb_component" ;then
      if dpkg -s "$eb_component" | grep -qw "Status.*installed" ;then
        INSTALLED_VER=$(dpkg -s "$eb_component" | grep -i version | sed 's/^.*: //')
        if [ "$INSTALLED_VER" = "$TARGET_VER" ]; then
          echo "INFO: $1 (Version: $INSTALLED_VER) already installed, exiting upgrade"
          return 0
        else
          # Check if the installed version is older than target version
          if dpkg --compare-versions "$INSTALLED_VER" lt "$TARGET_VER" ; then
            echo "INFO: Upgrading $1 version ($INSTALLED_VER) to version ($TARGET_VER)"
            return 1

          else
            echo "INFO: Installed $1 version ($INSTALLED_VER) is newer than the requested version ($TARGET_VER), exiting upgrade"
            return 0
          fi
        fi
      else
        # TODO: We should be able to continue upgrade here, TBD
        echo "WARN: Broken $1 installation, exiting upgrade"
        return 0
      fi
    else
      # No current installation, install the package
      echo "INFO: $1 not currently installed"
      ./edgebuilder-install.sh "$1" "$TARGET_VER" "" "$FILE"
      return 1
    fi
}


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
  echo "Usage: edgebuilder-upgrade.sh [component] [version] [file]"
  echo "component: The Edge Builder component to upgrade (server, node, cli)"
  echo "version: The version to upgrade to (e.g. 1.1.3)"
  echo "file: Path to the file "
}

# Gets the distribution 'name' bionic, focal etc
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

# Gets the distribution number 20.04, 18.04 etc
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

# Gets the basic distribution type ubuntu, debian etc
get_dist_type()
{
  if [ "$1" = "$UBUNTU2004" ]||[ "$1" = "$UBUNTU1804" ]; then
    echo "ubuntu"
  elif  [ "$1" = "$DEBIAN10" ] || [ "$1" = "$RASPBIAN10" ]; then
    echo "debian"
  fi

}

# Updates the server components
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
    apt-get install -y ./"$FILE"
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
      echo  "ERRPR: docker-ce is installed, please uninstall before continuing"
      exit 1
    fi
  fi

  apt-get update -qq
  apt-get install -y -qq wget

  echo "INFO: Setting up apt"
  DIST_NAME=$(get_dist_name "$DIST")
  DIST_NUM=$(get_dist_num "$DIST")
  DIST_TYPE=$(get_dist_type "$DIST")

  if [ "$ARCH" = "x86_64" ];then
    wget -q -O - "https://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest/SALTSTACK-GPG-KEY.pub" | sudo apt-key add -
    if grep -q "deb http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest $DIST_NAME main" /etc/apt/sources.list.d/saltstack.list ;then
      echo "INFO: Salt repo already added"
    else
      echo "deb [arch=amd64] http://repo.saltstack.com/py3/$DIST_TYPE/$DIST_NUM/amd64/latest $DIST_NAME main" | sudo tee -a /etc/apt/sources.list.d/saltstack.list
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
    usermod -aG docker "$USER"
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



# Main starts here:

# If no options are specified
if [ -z "$1" ];then
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

# Find the target version
if [ "$TARGET_VER" = "" ]; then
  TARGET_VER=$LATEST_VER
fi

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
      installed_version_older "$COMPONENT"
      if [ $? -ne 1 ]; then
          echo "ERROR: Exiting Edge Builder upgrade"
          exit 1
      else
          sh ./edgebuilder-install.sh cli "$INSTALLED_VER" remove ""

      fi
      echo "INFO: Installing cli version ($TARGET_VER)"
      sh ./edgebuilder-install.sh cli "$TARGET_VER" "" ""
    elif [ -x "$(command -v dnf)" ]; then
      upgrade_cli_rpm "$OS" "$ARCH" "dnf"
    elif [ -x "$(command -v yum)" ]; then
      upgrade_cli_rpm "$OS" "$ARCH" "yum"
    else
      echo "ERROR: The Edge Builder CLI cannot be installed as no suitable package manager has been found (apt, dnf or yum)"
      exit 1
    fi
  else
    echo "ERROR: The Edge Builder CLI is not supported on $ARCH"
    exit 1
  fi
fi

set +x
