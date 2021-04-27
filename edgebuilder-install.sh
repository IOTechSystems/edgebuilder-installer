#!/bin/sh
COMPONENT=$1
UBUNTU2004="Ubuntu 20.04"
UBUNTU1804="Ubuntu 18.04"
DEBIAN10="Debian GNU/Linux 10"

display_usage()
{
    echo "Usage: edgebuilder-install.sh [param]"
    echo "params: server, node, cli"
}

if [ -z $1 ];then
    display_usage
    exit 1
fi

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
fi
# Detect Arch
ARCH="$(uname -m)"

#If compatiable
if [ "$COMPONENT" = "server" ];then
  if [ "$ARCH" = "x86_64" ];then
    case $OS in
      $UBUNTU2004)
        echo "do install"
        ;;
      $UBUNTU1804)
        echo "do install"
        ;;
      $DEBIAN10)
        echo "do install"
        ;;
      *)
        echo "ERROR: The Edge Builder server components are not supported on $OS"
    esac
  else
    echo "ERROR: The Edge Builder server components are not supported on $ARCH"
    exit 1
  fi
elif [ "$COMPONENT" = "node" ]; then

elif [ "$COMPONENT" = "cli" ]; then

fi

#Install chosen component, assume current user

#If not compatiable, error and quit
