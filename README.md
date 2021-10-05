# Edge Builder Installer

## Overview:

This installer is designed to make it easy to install any of the following Edge Builder components:

1. Server Components
2. Node Components
3. CLI

The installer assumes that the current user would be used if adding a node by ssh

## Usage:

Usage: sudo ./edgebuilder-install.sh [component] [version] [remove] 

component: Edge Builder component to install/uninstall (server, node, cli)
version: The component version ( defaults to the latest version set in the script)
remove: Flag to indicate uninstallation (remove)

## Dev info only:

You can supply a fourth param with either server, node or cli with a path to the file you want to install.