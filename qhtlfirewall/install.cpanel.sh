#!/bin/sh
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################

umask 0177

# Parse flags
FORCE_WHM_INCLUDES=0
for arg in "$@"; do
    case "$arg" in
        --force-whm-includes)
            FORCE_WHM_INCLUDES=1
            ;;
    esac
done

# Env var override
if [ "${QHTL_FORCE_WHM_INCLUDES}" = "1" ]; then
    FORCE_WHM_INCLUDES=1
fi

echo "Installing qhtlfirewall and qhtlwaterfall"
echo

echo "Check we're running as root"
if [ ! `id -u` = 0 ]; then
	echo
	echo "FAILED: You have to be logged in as root (UID:0) to install qhtlfirewall"
    echo
	exit
fi
echo

if [ ! -e "install.sh" ]; then
	echo "You must cd to the package directory that you expanded"
	exit
fi

#First replace:
if [ -e "/usr/local/cpanel/3rdparty/bin/perl" ]; then
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' auto.pl
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' cpanel/qhtlfirewall.cgi
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' qhtlfirewall.pl
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' qhtlfirewalltest.pl
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' qhtlwaterfall.pl
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' os.pl
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' pt_deleted_action.pl
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' regex.custom.pm
    sed -i 's%^#\!/usr/bin/perl%#\!/usr/local/cpanel/3rdparty/bin/perl%' webmin/qhtlfirewall/index.cgi
fi

# Make sure target dirs exist without noisy errors
mkdir -p -m 0700 /etc/qhtlfirewall
cp -af install.txt /etc/qhtlfirewall/

echo
echo "Checking Perl modules..."
chmod 700 os.pl
RETURN=`./os.pl`
if [ "$RETURN" = 1 ]; then
	echo
	echo "FAILED: You MUST install the missing perl modules above before you can install qhtlfirewall. See /etc/qhtlfirewall/install.txt for installation details."
	exit
else
    echo "...Perl modules OK"
fi

# Create runtime directories (idempotent, quiet)
mkdir -p -m 0700 /var/lib/qhtlfirewall
    # Install and run daily updater under new name
    cp -af qhtlfirewallget.pl /etc/cron.daily/qhtlfirewallget
    chmod 700 /etc/cron.daily/qhtlfirewallget
    /etc/cron.daily/qhtlfirewallget --nosleep || true
mkdir -p -m 0700 /var/lib/qhtlfirewall/webmin
mkdir -p -m 0700 /var/lib/qhtlfirewall/zone
mkdir -p -m 0700 /var/lib/qhtlfirewall/Geo
mkdir -p -m 0700 /var/lib/qhtlfirewall/backup
mkdir -p -m 0700 /usr/local/qhtlfirewall
mkdir -p -m 0700 /usr/local/qhtlfirewall/lib
mkdir -p -m 0700 /usr/local/qhtlfirewall/tpl
mkdir -p -m 0700 /usr/local/qhtlfirewall/bin

if [ -e "/etc/qhtlfirewall/alert.txt" ]; then
	sh migratedata.sh
fi

if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.conf" ]; then
	cp -avf qhtlfirewall.conf /etc/qhtlfirewall/.
fi

if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.allow" ]; then
	cp -avf qhtlfirewall.allow /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.deny" ]; then
	cp -avf qhtlfirewall.deny /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.redirect" ]; then
	cp -avf qhtlfirewall.redirect /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.resellers" ]; then
	cp -avf qhtlfirewall.resellers /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.dirwatch" ]; then
	cp -avf qhtlfirewall.dirwatch /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.syslogs" ]; then
	cp -avf qhtlfirewall.syslogs /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.logfiles" ]; then
	cp -avf qhtlfirewall.logfiles /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.logignore" ]; then
	cp -avf qhtlfirewall.logignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.blocklists" ]; then
	cp -avf qhtlfirewall.blocklists /etc/qhtlfirewall/.
else
	cp -avf qhtlfirewall.blocklists /etc/qhtlfirewall/qhtlfirewall.blocklists.new
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.ignore" ]; then
	cp -avf qhtlfirewall.ignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.pignore" ]; then
	cp -avf qhtlfirewall.pignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.rignore" ]; then
	cp -avf qhtlfirewall.rignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.fignore" ]; then
	cp -avf qhtlfirewall.fignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.signore" ]; then
	cp -avf qhtlfirewall.signore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.suignore" ]; then
	cp -avf qhtlfirewall.suignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.uidignore" ]; then
	cp -avf qhtlfirewall.uidignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.mignore" ]; then
	cp -avf qhtlfirewall.mignore /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.sips" ]; then
	cp -avf qhtlfirewall.sips /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.dyndns" ]; then
	cp -avf qhtlfirewall.dyndns /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.syslogusers" ]; then
	cp -avf qhtlfirewall.syslogusers /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.smtpauth" ]; then
	cp -avf qhtlfirewall.smtpauth /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.rblconf" ]; then
	cp -avf qhtlfirewall.rblconf /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.cloudflare" ]; then
	cp -avf qhtlfirewall.cloudflare /etc/qhtlfirewall/.
fi

if [ ! -e "/usr/local/qhtlfirewall/tpl/alert.txt" ]; then
	cp -avf alert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/reselleralert.txt" ]; then
	cp -avf reselleralert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/logalert.txt" ]; then
	cp -avf logalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/logfloodalert.txt" ]; then
	cp -avf logfloodalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/syslogalert.txt" ]; then
	cp -avf syslogalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/integrityalert.txt" ]; then
	cp -avf integrityalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/exploitalert.txt" ]; then
	cp -avf exploitalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/queuealert.txt" ]; then
	cp -avf queuealert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/modsecipdbalert.txt" ]; then
	cp -avf modsecipdbalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/tracking.txt" ]; then
	cp -avf tracking.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/connectiontracking.txt" ]; then
	cp -avf connectiontracking.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/processtracking.txt" ]; then
	cp -avf processtracking.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/accounttracking.txt" ]; then
	cp -avf accounttracking.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/usertracking.txt" ]; then
	cp -avf usertracking.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/sshalert.txt" ]; then
	cp -avf sshalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/webminalert.txt" ]; then
	cp -avf webminalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/sualert.txt" ]; then
	cp -avf sualert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/sudoalert.txt" ]; then
	cp -avf sudoalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/consolealert.txt" ]; then
	cp -avf consolealert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/uialert.txt" ]; then
	cp -avf uialert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/cpanelalert.txt" ]; then
	cp -avf cpanelalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/scriptalert.txt" ]; then
	cp -avf scriptalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/relayalert.txt" ]; then
	cp -avf relayalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/filealert.txt" ]; then
	cp -avf filealert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/watchalert.txt" ]; then
	cp -avf watchalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/loadalert.txt" ]; then
	cp -avf loadalert.txt /usr/local/qhtlfirewall/tpl/.
else
	cp -avf loadalert.txt /usr/local/qhtlfirewall/tpl/loadalert.txt.new
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/resalert.txt" ]; then
	cp -avf resalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/portscan.txt" ]; then
	cp -avf portscan.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/uidscan.txt" ]; then
	cp -avf uidscan.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/permblock.txt" ]; then
	cp -avf permblock.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/netblock.txt" ]; then
	cp -avf netblock.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/portknocking.txt" ]; then
	cp -avf portknocking.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/forkbombalert.txt" ]; then
	cp -avf forkbombalert.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/recaptcha.txt" ]; then
	cp -avf recaptcha.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/apache.main.txt" ]; then
	cp -avf apache.main.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/apache.http.txt" ]; then
	cp -avf apache.http.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/apache.https.txt" ]; then
	cp -avf apache.https.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/litespeed.main.txt" ]; then
	cp -avf litespeed.main.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/litespeed.http.txt" ]; then
	cp -avf litespeed.http.txt /usr/local/qhtlfirewall/tpl/.
fi
if [ ! -e "/usr/local/qhtlfirewall/tpl/litespeed.https.txt" ]; then
	cp -avf litespeed.https.txt /usr/local/qhtlfirewall/tpl/.
fi
cp -avf x-arf.txt /usr/local/qhtlfirewall/tpl/.

if [ ! -e "/usr/local/qhtlfirewall/bin/regex.custom.pm" ]; then
	cp -avf regex.custom.pm /usr/local/qhtlfirewall/bin/.
fi
if [ ! -e "/usr/local/qhtlfirewall/bin/pt_deleted_action.pl" ]; then
	cp -avf pt_deleted_action.pl /usr/local/qhtlfirewall/bin/.
fi
if [ ! -e "/etc/qhtlfirewall/messenger" ]; then
	cp -avf messenger /etc/qhtlfirewall/.
fi
if [ ! -e "/etc/qhtlfirewall/messenger/index.recaptcha.html" ]; then
	cp -avf messenger/index.recaptcha.html /etc/qhtlfirewall/messenger/.
fi
if [ ! -e "/etc/qhtlfirewall/ui" ]; then
	cp -avf ui /etc/qhtlfirewall/.
fi
if [ -e "/etc/cron.d/qhtlfirewallcron.sh" ]; then
	mv -fv /etc/cron.d/qhtlfirewallcron.sh /etc/cron.d/qhtlfirewall-cron
fi
if [ ! -e "/etc/cron.d/qhtlfirewall-cron" ]; then
	cp -avf qhtlfirewallcron.sh /etc/cron.d/qhtlfirewall-cron
fi
if [ -e "/etc/cron.d/qhtlwaterfallcron.sh" ]; then
	mv -fv /etc/cron.d/qhtlwaterfallcron.sh /etc/cron.d/qhtlwaterfall-cron
fi
if [ ! -e "/etc/cron.d/qhtlwaterfall-cron" ]; then
	cp -avf qhtlwaterfallcron.sh /etc/cron.d/qhtlwaterfall-cron
fi
sed -i "s%/etc/init.d/qhtlwaterfall restart%/usr/sbin/qhtlfirewall --qhtlwaterfall restart%" /etc/cron.d/qhtlwaterfall-cron
if [ -e "/usr/local/qhtlfirewall/bin/servercheck.pm" ]; then
	rm -f /usr/local/qhtlfirewall/bin/servercheck.pm
fi
if [ -e "/etc/qhtlfirewall/qhtlmanagerui.pl" ]; then
    rm -f /etc/qhtlfirewall/qhtlmanagerui.pl
fi
if [ -e "/etc/qhtlfirewall/qhtlfirewallui.pl" ]; then
	rm -f /etc/qhtlfirewall/qhtlfirewallui.pl
fi
if [ -e "/etc/qhtlfirewall/qhtlfirewalluir.pl" ]; then
	rm -f /etc/qhtlfirewall/qhtlfirewalluir.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/qhtlmanagerui.pl" ]; then
    rm -f /usr/local/qhtlfirewall/bin/qhtlmanagerui.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/qhtlfirewallui.pl" ]; then
	rm -f /usr/local/qhtlfirewall/bin/qhtlfirewallui.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/qhtlfirewalluir.pl" ]; then
	rm -f /usr/local/qhtlfirewall/bin/qhtlfirewalluir.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/regex.pm" ]; then
    rm -f /usr/local/qhtlfirewall/bin/regex.pm
fi

OLDVERSION=0
if [ -e "/etc/qhtlfirewall/version.txt" ]; then
    OLDVERSION=`head -n 1 /etc/qhtlfirewall/version.txt`
fi

rm -f /etc/qhtlfirewall/qhtlfirewall.pl /usr/sbin/qhtlfirewall /etc/qhtlfirewall/qhtlwaterfall.pl /usr/sbin/qhtlwaterfall
chmod 700 qhtlfirewall.pl qhtlwaterfall.pl
cp -avf qhtlfirewall.pl /usr/sbin/qhtlfirewall
cp -avf qhtlwaterfall.pl /usr/sbin/qhtlwaterfall
chmod 700 /usr/sbin/qhtlfirewall /usr/sbin/qhtlwaterfall
ln -sf /usr/sbin/qhtlfirewall /etc/qhtlfirewall/qhtlfirewall.pl
ln -sf /usr/sbin/qhtlwaterfall /etc/qhtlfirewall/qhtlwaterfall.pl
ln -sf /usr/local/qhtlfirewall/bin/qhtlfirewalltest.pl /etc/qhtlfirewall/
ln -sf /usr/local/qhtlfirewall/bin/pt_deleted_action.pl /etc/qhtlfirewall/
ln -sf /usr/local/qhtlfirewall/bin/remove_apf_bfd.sh /etc/qhtlfirewall/
ln -sf /usr/local/qhtlfirewall/bin/uninstall.sh /etc/qhtlfirewall/
ln -sf /usr/local/qhtlfirewall/bin/regex.custom.pm /etc/qhtlfirewall/
ln -sf /usr/local/qhtlfirewall/lib/webmin /etc/qhtlfirewall/

# ...existing code...
# Ensure UI asset dirs exist (quiet)
mkdir -p webmin/qhtlfirewall/images
mkdir -p ui/images
mkdir -p da/images
mkdir -p interworx/images

# Quiet copies of UI assets
cp -af qhtlfirewall/* webmin/qhtlfirewall/images/
cp -af qhtlfirewall/* ui/images/
cp -af qhtlfirewall/* da/images/
cp -af qhtlfirewall/* interworx/images/

cp -avf messenger/*.php /etc/qhtlfirewall/messenger/
cp -avf qhtlfirewall/qhtlfirewall_small.png /usr/local/cpanel/whostmgr/docroot/addon_plugins/
cp -avf uninstall.sh /usr/local/qhtlfirewall/bin/
cp -avf qhtlfirewalltest.pl /usr/local/qhtlfirewall/bin/
cp -avf remove_apf_bfd.sh /usr/local/qhtlfirewall/bin/
cp -avf readme.txt /etc/qhtlfirewall/
cp -avf sanity.txt /usr/local/qhtlfirewall/lib/
cp -avf qhtlfirewall.rbls /usr/local/qhtlfirewall/lib/
cp -avf restricted.txt /usr/local/qhtlfirewall/lib/
cp -avf changelog.txt /etc/qhtlfirewall/
cp -avf downloadservers /etc/qhtlfirewall/
cp -avf install.txt /etc/qhtlfirewall/
cp -avf version.txt /etc/qhtlfirewall/
cp -avf license.txt /etc/qhtlfirewall/
cp -avf webmin /usr/local/qhtlfirewall/lib/
cp -avf QhtLink /usr/local/qhtlfirewall/lib/
cp -avf Net /usr/local/qhtlfirewall/lib/
cp -avf Geo /usr/local/qhtlfirewall/lib/
cp -avf Crypt /usr/local/qhtlfirewall/lib/
cp -avf HTTP /usr/local/qhtlfirewall/lib/
cp -avf JSON /usr/local/qhtlfirewall/lib/
cp -avf version/* /usr/local/qhtlfirewall/lib/
cp -avf qhtlfirewall.div /usr/local/qhtlfirewall/lib/
cp -avf qhtlfirewallajaxtail.js /usr/local/qhtlfirewall/lib/
cp -avf ui/images /etc/qhtlfirewall/ui/.
cp -avf profiles /usr/local/qhtlfirewall/
cp -avf qhtlfirewall.conf /usr/local/qhtlfirewall/profiles/reset_to_defaults.conf
cp -avf cpanel.comodo.ignore /etc/qhtlfirewall/
cp -avf cpanel.comodo.allow /etc/qhtlfirewall/
cp -avf cpanel.ignore /etc/qhtlfirewall/
cp -avf cpanel.allow /etc/qhtlfirewall/
cp -avf messenger/*.php /etc/qhtlfirewall/messenger/.
cp -avf qhtlwaterfall.logrotate /etc/logrotate.d/qhtlwaterfall

rm -fv /etc/qhtlfirewall/qhtlfirewall.spamhaus /etc/qhtlfirewall/qhtlfirewall.dshield /etc/qhtlfirewall/qhtlfirewall.tor /etc/qhtlfirewall/qhtlfirewall.bogon

mkdir -p /usr/local/man/man1/
cp -af qhtlfirewall.1.txt /usr/local/man/man1/qhtlfirewall.1
if man -w qhtlfirewall >/dev/null 2>&1; then
  man qhtlfirewall | col -b > qhtlfirewall.help && cp -af qhtlfirewall.help /usr/local/qhtlfirewall/lib/
fi

chmod 755 /usr/local/man/
chmod 755 /usr/local/man/man1/
chmod 644 /usr/local/man/man1/qhtlfirewall.1

# Secure permissions without stripping execute bit on directories
find /etc/qhtlfirewall -type d -exec chmod 700 {} + 2>/dev/null || true
find /etc/qhtlfirewall -type f -exec chmod 600 {} + 2>/dev/null || true
find /var/lib/qhtlfirewall -type d -exec chmod 700 {} + 2>/dev/null || true
find /var/lib/qhtlfirewall -type f -exec chmod 600 {} + 2>/dev/null || true
find /usr/local/qhtlfirewall -type d -exec chmod 700 {} + 2>/dev/null || true
find /usr/local/qhtlfirewall -type f -exec chmod 600 {} + 2>/dev/null || true
# Ensure scripts in bin are executable
chmod -v 700 /usr/local/qhtlfirewall/bin/*.pl /usr/local/qhtlfirewall/bin/*.sh /usr/local/qhtlfirewall/bin/*.pm 2>/dev/null || true
chmod 600 /var/log/qhtlwaterfall.log*

chmod -v 700 /etc/qhtlfirewall/*.pl /etc/qhtlfirewall/*.cgi /etc/qhtlfirewall/*.sh /etc/qhtlfirewall/*.php /etc/qhtlfirewall/*.py 2>/dev/null || true
chmod -v 700 /etc/qhtlfirewall/webmin/qhtlfirewall/index.cgi 2>/dev/null || true
chmod -v 644 /etc/cron.d/qhtlwaterfall-cron 2>/dev/null || true
chmod -v 644 /etc/cron.d/qhtlfirewall-cron 2>/dev/null || true

chmod -v 700 auto.pl
./auto.pl $OLDVERSION

mkdir -p /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink
chmod 700 /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink
mkdir -p /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall
chmod 700 /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall

cp -avf cpanel/qhtlfirewall.cgi /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall.cgi
chmod -v 700 /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall.cgi

cp -avf qhtlfirewall/ /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/
mkdir -p /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/Driver
# Install only the canonical QhtLinkFirewall driver
cp -avf cpanel/Driver/QhtLinkFirewall.pm /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/Driver/
cp -avf cpanel/Driver/QhtLinkFirewall /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/Driver/
if [ -d Geo ]; then cp -af Geo /usr/local/qhtlfirewall/lib/; fi
if [ -f ui/images/icon.gif ]; then cp -af ui/images/icon.gif /usr/local/cpanel/whostmgr/docroot/themes/x/icons/qhtlfirewall.gif; fi
cp -avf cpanel/qhtlfirewall.tmpl /usr/local/cpanel/whostmgr/docroot/templates/

VERSION=`cat /usr/local/cpanel/version | cut -d '.' -f2`
if [ "$VERSION" -lt "65" ]; then
    sed -i "s/^target=.*$/target=mainFrame/" cpanel/qhtlfirewall.conf
    echo "cPanel v$VERSION, target set to mainFrame"
else
    sed -i "s/^target=.*$/target=_self/" cpanel/qhtlfirewall.conf
    echo "cPanel v$VERSION, target set to _self"
fi

cp -af cpanel/qhtlfirewall.conf /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/qhtlfirewall.conf
cp -af cpanel/upgrade.sh /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/upgrade.sh
chmod 700 /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/upgrade.sh

# Optionally deploy a WHM global banner include to surface firewall status
# This uses cPanel's supported customization path. We only install if the admin
# hasn't provided their own banner include yet to avoid overriding.
if [ -d "/var/cpanel/customizations/whm/includes" ] || mkdir -p /var/cpanel/customizations/whm/includes ; then
    if [ $FORCE_WHM_INCLUDES -eq 1 ] || [ ! -f "/var/cpanel/customizations/whm/includes/global_banner.html.tt" ]; then
        cp -af cpanel/whm_global_banner.html.tt /var/cpanel/customizations/whm/includes/global_banner.html.tt
        chmod 644 /var/cpanel/customizations/whm/includes/global_banner.html.tt
        echo "Installed WHM global banner include for qhtlfirewall status." 
    else
        echo "WHM global_banner.html.tt exists; not overwriting. Use --force-whm-includes to replace."
    fi
    # Also place header/footer variants
    if [ $FORCE_WHM_INCLUDES -eq 1 ] || [ ! -f "/var/cpanel/customizations/whm/includes/global_header.html.tt" ]; then
        cp -af cpanel/global_header.html.tt /var/cpanel/customizations/whm/includes/global_header.html.tt
        chmod 644 /var/cpanel/customizations/whm/includes/global_header.html.tt
        echo "Installed WHM global header include for qhtlfirewall status."
    else
        echo "WHM global_header.html.tt exists; not overwriting. Use --force-whm-includes to replace."
    fi
    if [ $FORCE_WHM_INCLUDES -eq 1 ] || [ ! -f "/var/cpanel/customizations/whm/includes/global_footer.html.tt" ]; then
        cp -af cpanel/global_footer.html.tt /var/cpanel/customizations/whm/includes/global_footer.html.tt
        chmod 644 /var/cpanel/customizations/whm/includes/global_footer.html.tt
        echo "Installed WHM global footer include for qhtlfirewall status."
    else
        echo "WHM global_footer.html.tt exists; not overwriting. Use --force-whm-includes to replace."
    fi
fi

# Ensure Jupiter (WHM root) path renders our badge by leveraging cp_analytics_whm.html.tt
ANALYTICS_TT="/var/cpanel/customizations/whm/includes/cp_analytics_whm.html.tt"
if [ -f "$ANALYTICS_TT" ] || mkdir -p "/var/cpanel/customizations/whm/includes" ; then
        if ! grep -q 'qhtlfirewall analytics inject v2' "$ANALYTICS_TT" 2>/dev/null; then
                echo "Injecting qhtlfirewall snippet into cp_analytics_whm.html.tt (v2)"
                cat >> "$ANALYTICS_TT" <<'QHTL_EOF'

[%# qhtlfirewall analytics inject v2 %]
<script>
(function(){
    try {
        var m = String(location.pathname).match(/\/cpsess[^/]+/);
        var base = (m && m[0]) ? (m[0] + '/') : '/';
        // Inject external JS for smart placement, guarded in the script itself
        var s = document.createElement('script');
        s.src = base + 'cgi/qhtlink/qhtlfirewall.cgi?action=banner_js';
        s.defer = true;
        (document.head||document.documentElement).appendChild(s);
        // Ensure a small visible badge even if JS gets blocked later
        if (!document.getElementById('qhtlfw-frame')) {
            var f = document.createElement('iframe');
            f.id = 'qhtlfw-frame';
            f.src = base + 'cgi/qhtlink/qhtlfirewall.cgi?action=banner_frame';
            f.title = 'QhtLink Firewall';
            f.style.position = 'fixed';
            f.style.top = '10px';
            f.style.right = '16px';
            f.style.zIndex = '2147483647';
            f.style.border = '0';
            f.style.width = '200px';
            f.style.height = '24px';
            f.style.overflow = 'hidden';
            f.style.background = 'transparent';
            f.setAttribute('loading','lazy');
            (document.body||document.documentElement).appendChild(f);
        }
    } catch(e) {}
})();
</script>

QHTL_EOF
                chmod 644 "$ANALYTICS_TT" || true
        else
                echo "cp_analytics_whm.html.tt already contains qhtlfirewall snippet v2; skipping."
        fi
fi

if [ -e "/usr/local/cpanel/bin/register_appconfig" ]; then
    # Copy only the canonical QhtLinkFirewall driver into cPanel's driver path
    /bin/cp -af /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/Driver/QhtLinkFirewall* /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver/
    /bin/touch /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver

    /usr/local/cpanel/bin/register_appconfig /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/qhtlfirewall.conf
    /bin/rm -f /usr/local/cpanel/whostmgr/docroot/cgi/addon_qhtlfirewall.cgi
    /bin/rm -Rf /usr/local/cpanel/whostmgr/docroot/cgi/qhtlfirewall
else
    cp -avf cpanel/qhtlfirewall.cgi /usr/local/cpanel/whostmgr/docroot/cgi/addon_qhtlfirewall.cgi
    chmod -v 700 /usr/local/cpanel/whostmgr/docroot/cgi/addon_qhtlfirewall.cgi
    cp -avf qhtlfirewall/ /usr/local/cpanel/whostmgr/docroot/cgi/
    if [ ! -d "/var/cpanel/apps" ]; then
        mkdir /var/cpanel/apps
        chmod 755 /var/cpanel/apps
    fi
    /bin/cp -avf cpanel/qhtlfirewall.conf.old /var/cpanel/apps/qhtlfirewall.conf
    chmod 600 /var/cpanel/apps/qhtlfirewall.conf
fi

if test `cat /proc/1/comm` = "systemd"
then
    if [ -e /etc/init.d/qhtlwaterfall ]; then
        if [ -f /etc/redhat-release ]; then
            /sbin/chkconfig qhtlfirewall off
            /sbin/chkconfig qhtlwaterfall off
            /sbin/chkconfig qhtlfirewall --del
            /sbin/chkconfig qhtlwaterfall --del
        elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
            update-rc.d -f qhtlwaterfall remove
            update-rc.d -f qhtlfirewall remove
        elif [ -f /etc/gentoo-release ]; then
            rc-update del qhtlwaterfall default
            rc-update del qhtlfirewall default
        elif [ -f /etc/slackware-version ]; then
            rm -vf /etc/rc.d/rc3.d/S80qhtlfirewall
            rm -vf /etc/rc.d/rc4.d/S80qhtlfirewall
            rm -vf /etc/rc.d/rc5.d/S80qhtlfirewall
            rm -vf /etc/rc.d/rc3.d/S85qhtlwaterfall
            rm -vf /etc/rc.d/rc4.d/S85qhtlwaterfall
            rm -vf /etc/rc.d/rc5.d/S85qhtlwaterfall
        else
            /sbin/chkconfig qhtlfirewall off
            /sbin/chkconfig qhtlwaterfall off
            /sbin/chkconfig qhtlfirewall --del
            /sbin/chkconfig qhtlwaterfall --del
        fi
        rm -fv /etc/init.d/qhtlfirewall
        rm -fv /etc/init.d/qhtlwaterfall
    fi

    mkdir -p /etc/systemd/system/
    mkdir -p /usr/lib/systemd/system/
    cp -af qhtlwaterfall.service /usr/lib/systemd/system/
    cp -af qhtlfirewall.service /usr/lib/systemd/system/

    chcon -h system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/qhtlwaterfall.service
    chcon -h system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/qhtlfirewall.service

    systemctl daemon-reload >/dev/null 2>&1 || true

    systemctl enable qhtlfirewall.service >/dev/null 2>&1 || true
    systemctl enable qhtlwaterfall.service >/dev/null 2>&1 || true

    systemctl disable firewalld >/dev/null 2>&1 || true
    systemctl stop firewalld >/dev/null 2>&1 || true
    systemctl mask firewalld >/dev/null 2>&1 || true
else
    cp -af qhtlwaterfall.sh /etc/init.d/qhtlwaterfall
    cp -af qhtlfirewall.sh /etc/init.d/qhtlfirewall
    chmod -v 755 /etc/init.d/qhtlwaterfall
    chmod -v 755 /etc/init.d/qhtlfirewall

    if [ -f /etc/redhat-release ]; then
        /sbin/chkconfig qhtlwaterfall on
        /sbin/chkconfig qhtlfirewall on
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
        update-rc.d -f qhtlwaterfall remove
        update-rc.d -f qhtlfirewall remove
        update-rc.d qhtlwaterfall defaults 80 20
        update-rc.d qhtlfirewall defaults 20 80
    elif [ -f /etc/gentoo-release ]; then
        rc-update add qhtlwaterfall default
        rc-update add qhtlfirewall default
    elif [ -f /etc/slackware-version ]; then
    ln -sf /etc/init.d/qhtlfirewall /etc/rc.d/rc3.d/S80qhtlfirewall
    ln -sf /etc/init.d/qhtlfirewall /etc/rc.d/rc4.d/S80qhtlfirewall
    ln -sf /etc/init.d/qhtlfirewall /etc/rc.d/rc5.d/S80qhtlfirewall
    ln -sf /etc/init.d/qhtlwaterfall /etc/rc.d/rc3.d/S85qhtlwaterfall
    ln -sf /etc/init.d/qhtlwaterfall /etc/rc.d/rc4.d/S85qhtlwaterfall
    ln -sf /etc/init.d/qhtlwaterfall /etc/rc.d/rc5.d/S85qhtlwaterfall
    else
        /sbin/chkconfig qhtlwaterfall on
        /sbin/chkconfig qhtlfirewall on
    fi
fi

#Second replace
if [ -e "/usr/local/cpanel/3rdparty/bin/perl" ]; then
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' auto.pl
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' cpanel/qhtlfirewall.cgi
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' qhtlfirewall.pl
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' qhtlfirewalltest.pl
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' qhtlwaterfall.pl
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' os.pl
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' pt_deleted_action.pl
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' regex.custom.pm
    sed -i 's%^#\!/usr/local/cpanel/3rdparty/bin/perl%#\!/usr/bin/perl%' webmin/qhtlfirewall/index.cgi
fi

chown -Rf root:root /etc/qhtlfirewall /var/lib/qhtlfirewall /usr/local/qhtlfirewall
chown -f root:root /usr/sbin/qhtlfirewall /usr/sbin/qhtlwaterfall /etc/logrotate.d/qhtlwaterfall /etc/cron.d/qhtlfirewall-cron /etc/cron.d/qhtlwaterfall-cron /usr/local/man/man1/qhtlfirewall.1 /usr/lib/systemd/system/qhtlwaterfall.service /usr/lib/systemd/system/qhtlfirewall.service /etc/init.d/qhtlwaterfall /etc/init.d/qhtlfirewall

cd webmin ; tar -czf /usr/local/qhtlfirewall/qhtlfirewallwebmin.tgz ./*
ln -sf /usr/local/qhtlfirewall/qhtlfirewallwebmin.tgz /etc/qhtlfirewall/

echo
echo "Installation Completed"
echo
