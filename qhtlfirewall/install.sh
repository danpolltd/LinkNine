#!/bin/sh
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################

echo
echo "Selecting installer..."
echo

if [ -e "/usr/local/cpanel/version" ]; then
	echo "Running qhtlfirewall cPanel installer"
	echo
	sh install.cpanel.sh
elif [ -e "/usr/local/directadmin/directadmin" ]; then
	echo "Running qhtlfirewall DirectAdmin installer"
	echo
	sh install.directadmin.sh
elif [ -e "/usr/local/interworx" ]; then
	echo "Running qhtlfirewall InterWorx installer"
	echo
	sh install.interworx.sh
elif [ -e "/usr/local/cwpsrv" ]; then
	echo "Running qhtlfirewall CentOS Web Panel installer"
	echo
	sh install.cwp.sh
elif [ -e "/usr/local/vesta" ]; then
	echo "Running qhtlfirewall VestaCP installer"
	echo
	sh install.vesta.sh
elif [ -e "/usr/local/CyberCP" ]; then
	echo "Running qhtlfirewall CyberPanel installer"
	echo
	sh install.cyberpanel.sh
else
	echo "Running qhtlfirewall generic installer"
	echo
	sh install.generic.sh
fi
