#!/bin/sh
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################

echo
echo "Preparing safe install (pausing qhtlwaterfall during setup)..."
echo

# Create install guard so services/watchers don't start mid-install
GUARD_FILE="/var/lib/qhtlfirewall/.installing"
mkdir -p /var/lib/qhtlfirewall 2>/dev/null || true
chmod 700 /var/lib/qhtlfirewall 2>/dev/null || true
echo "1" > "$GUARD_FILE"
chmod 600 "$GUARD_FILE" 2>/dev/null || true

# If qhtlwaterfall is running, stop it now to avoid DIRWATCH on temp files
if command -v systemctl >/dev/null 2>&1; then
	systemctl stop qhtlwaterfall >/dev/null 2>&1 || true
	# also prevent firewalld interference
	systemctl stop firewalld >/dev/null 2>&1 || true
else
	if [ -x "/etc/init.d/qhtlwaterfall" ]; then /etc/init.d/qhtlwaterfall stop >/dev/null 2>&1 || true; fi
fi

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

# Remove install guard and start services safely now that temp files should be gone
if [ -f "$GUARD_FILE" ]; then
	rm -f "$GUARD_FILE" || true
fi

# Prefer canonical restart through qhtlfirewall wrapper which orders firewall then qhtlwaterfall
if [ -x "/usr/sbin/qhtlfirewall" ]; then
	/usr/sbin/qhtlfirewall --qhtlwaterfall restart >/dev/null 2>&1 || true
elif command -v systemctl >/dev/null 2>&1; then
	systemctl restart qhtlfirewall >/dev/null 2>&1 || true
	systemctl restart qhtlwaterfall >/dev/null 2>&1 || true
else
	if [ -x "/etc/init.d/qhtlfirewall" ]; then /etc/init.d/qhtlfirewall restart >/dev/null 2>&1 || true; fi
	if [ -x "/etc/init.d/qhtlwaterfall" ]; then /etc/init.d/qhtlwaterfall restart >/dev/null 2>&1 || true; fi
fi

echo
echo "qhtlwaterfall restart requested post-install. If you still see temporary DIRWATCH alerts referencing /tmp, they will clear once the OS cleans up temp dirs."
echo
