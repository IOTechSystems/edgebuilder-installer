# Edge Builder Installer

## Overview:

This installer is designed to make it easy to install or uninstall any of the following Edge Builder components:

1. Server Components
2. Node Components
3. CLI

The installer assumes that the current user would be used if adding a node by ssh

## Usage:

Usage: sudo ./edgebuilder-install.sh [param]

params: server, node, cli

to uninstall, use optional param : -u  

to install docker (and compose), use optional param : --install-docker

## Dev info only:

You can supply a second param with either server, node or cli with a path to the file you want to install.