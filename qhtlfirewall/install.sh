#!/bin/sh
###############################################################################
# Copyright (C) 2006-2025 Jonathan Michaelson
#
# https://github.com/waytotheweb/scripts
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <https://www.gnu.org/licenses>.
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
