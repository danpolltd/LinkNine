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

umask 0177

if [ -e "/usr/local/cpanel/version" ]; then
	echo "Running csf cPanel installer"
	echo
	sh install.cpanel.sh
	exit 0
elif [ -e "/usr/local/directadmin/directadmin" ]; then
	echo "Running csf DirectAdmin installer"
	echo
	sh install.directadmin.sh
	exit 0
fi

echo "Installing qhtlfirewall and qhtlwaterfall"
echo

echo "Check we're running as root"
if [ ! `id -u` = 0 ]; then
	echo
	echo "FAILED: You have to be logged in as root (UID:0) to install qhtlfirewall"
	exit
fi
echo

mkdir -v -m 0600 /etc/qhtlfirewall
cp -avf install.txt /etc/qhtlfirewall/

echo "Checking Perl modules..."
chmod 700 os.pl
RETURN=`./os.pl`
if [ "$RETURN" = 1 ]; then
	echo
	echo "FAILED: You MUST install the missing perl modules above before you can install QHTL. See /etc/qhtlfirewall/install.txt for installation details."
    echo
	exit
else
    echo "...Perl modules OK"
    echo
fi

mkdir -v -m 0600 /etc/qhtlfirewall
mkdir -v -m 0600 /var/lib/qhtlfirewall
mkdir -v -m 0600 /var/lib/qhtlfirewall/backup
mkdir -v -m 0600 /var/lib/qhtlfirewall/Geo
mkdir -v -m 0600 /var/lib/qhtlfirewall/ui
mkdir -v -m 0600 /var/lib/qhtlfirewall/stats
mkdir -v -m 0600 /var/lib/qhtlfirewall/lock
mkdir -v -m 0600 /var/lib/qhtlfirewall/webmin
mkdir -v -m 0600 /var/lib/qhtlfirewall/zone
mkdir -v -m 0600 /usr/local/qhtlfirewall
mkdir -v -m 0600 /usr/local/qhtlfirewall/bin
mkdir -v -m 0600 /usr/local/qhtlfirewall/lib
mkdir -v -m 0600 /usr/local/qhtlfirewall/tpl

if [ -e "/etc/qhtlfirewall/alert.txt" ]; then
	sh migratedata.sh
fi

if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.conf" ]; then
	cp -avf csf.vesta.conf /etc/qhtlfirewall/qhtlfirewall.conf
fi

if [ ! -d /var/lib/qhtlfirewall ]; then
	mkdir -v -p -m 0600 /var/lib/qhtlfirewall
fi
if [ ! -d /usr/local/qhtlfirewall/lib ]; then
	mkdir -v -p -m 0600 /usr/local/qhtlfirewall/lib
fi
if [ ! -d /usr/local/qhtlfirewall/bin ]; then
	mkdir -v -p -m 0600 /usr/local/qhtlfirewall/bin
fi
if [ ! -d /usr/local/qhtlfirewall/tpl ]; then
	mkdir -v -p -m 0600 /usr/local/qhtlfirewall/tpl
fi

if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.allow" ]; then
	cp -avf csf.vesta.allow /etc/qhtlfirewall/qhtlfirewall.allow
	sed -i 's#/etc/csf/#/etc/qhtlfirewall/#g' /etc/qhtlfirewall/qhtlfirewall.allow
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.deny" ]; then
	cp -avf csf.deny /etc/qhtlfirewall/qhtlfirewall.deny
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.redirect" ]; then
	cp -avf csf.redirect /etc/qhtlfirewall/qhtlfirewall.redirect
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.resellers" ]; then
	cp -avf csf.resellers /etc/qhtlfirewall/qhtlfirewall.resellers
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.dirwatch" ]; then
	cp -avf csf.dirwatch /etc/qhtlfirewall/qhtlfirewall.dirwatch
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.syslogs" ]; then
	cp -avf csf.syslogs /etc/qhtlfirewall/qhtlfirewall.syslogs
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.logfiles" ]; then
	cp -avf csf.logfiles /etc/qhtlfirewall/qhtlfirewall.logfiles
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.logignore" ]; then
	cp -avf csf.logignore /etc/qhtlfirewall/qhtlfirewall.logignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.blocklists" ]; then
	cp -avf csf.blocklists /etc/qhtlfirewall/qhtlfirewall.blocklists
else
	cp -avf csf.blocklists /etc/qhtlfirewall/qhtlfirewall.blocklists.new
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.ignore" ]; then
	cp -avf csf.vesta.ignore /etc/qhtlfirewall/qhtlfirewall.ignore
	sed -i 's#/etc/csf/#/etc/qhtlfirewall/#g' /etc/qhtlfirewall/qhtlfirewall.ignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.pignore" ]; then
	cp -avf csf.vesta.pignore /etc/qhtlfirewall/qhtlfirewall.pignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.rignore" ]; then
	cp -avf csf.rignore /etc/qhtlfirewall/qhtlfirewall.rignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.fignore" ]; then
	cp -avf csf.fignore /etc/qhtlfirewall/qhtlfirewall.fignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.signore" ]; then
	cp -avf csf.signore /etc/qhtlfirewall/qhtlfirewall.signore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.suignore" ]; then
	cp -avf csf.suignore /etc/qhtlfirewall/qhtlfirewall.suignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.uidignore" ]; then
	cp -avf csf.uidignore /etc/qhtlfirewall/qhtlfirewall.uidignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.mignore" ]; then
	cp -avf csf.mignore /etc/qhtlfirewall/qhtlfirewall.mignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.sips" ]; then
	cp -avf csf.sips /etc/qhtlfirewall/qhtlfirewall.sips
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.dyndns" ]; then
	cp -avf csf.dyndns /etc/qhtlfirewall/qhtlfirewall.dyndns
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.syslogusers" ]; then
	cp -avf csf.syslogusers /etc/qhtlfirewall/qhtlfirewall.syslogusers
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.smtpauth" ]; then
	cp -avf csf.smtpauth /etc/qhtlfirewall/qhtlfirewall.smtpauth
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.rblconf" ]; then
	cp -avf csf.rblconf /etc/qhtlfirewall/qhtlfirewall.rblconf
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.cloudflare" ]; then
	cp -avf csf.cloudflare /etc/qhtlfirewall/qhtlfirewall.cloudflare
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
if [ -e "/etc/cron.d/csfcron.sh" ]; then
	mv -fv /etc/cron.d/csfcron.sh /etc/cron.d/qhtlfirewall-cron
fi
if [ ! -e "/etc/cron.d/qhtlfirewall-cron" ]; then
	cp -avf qhtlfirewall.cron /etc/cron.d/qhtlfirewall-cron
fi
if [ -e "/etc/cron.d/lfdcron.sh" ]; then
	mv -fv /etc/cron.d/lfdcron.sh /etc/cron.d/qhtlwaterfall-cron
fi
if [ ! -e "/etc/cron.d/qhtlwaterfall-cron" ]; then
	cp -avf qhtlwaterfall.cron /etc/cron.d/qhtlwaterfall-cron
fi
if [ -e "/usr/local/qhtlfirewall/bin/servercheck.pm" ]; then
	rm -f /usr/local/qhtlfirewall/bin/servercheck.pm
fi
if [ -e "/etc/qhtlfirewall/cseui.pl" ]; then
	rm -f /etc/qhtlfirewall/cseui.pl
fi
if [ -e "/etc/qhtlfirewall/csfui.pl" ]; then
	rm -f /etc/qhtlfirewall/csfui.pl
fi
if [ -e "/etc/qhtlfirewall/csfuir.pl" ]; then
	rm -f /etc/qhtlfirewall/csfuir.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/cseui.pl" ]; then
	rm -f /usr/local/qhtlfirewall/bin/cseui.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/csfui.pl" ]; then
	rm -f /usr/local/qhtlfirewall/bin/csfui.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/csfuir.pl" ]; then
	rm -f /usr/local/qhtlfirewall/bin/csfuir.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/regex.pm" ]; then
	rm -f /usr/local/qhtlfirewall/bin/regex.pm
fi

OLDVERSION=0
if [ -e "/etc/qhtlfirewall/version.txt" ]; then
	OLDVERSION=`head -n 1 /etc/qhtlfirewall/version.txt`
fi

rm -f /usr/sbin/qhtlfirewall /usr/sbin/qhtlwaterfall /usr/sbin/csf /usr/sbin/lfd
chmod 700 qhtlfirewall.pl qhtlwaterfall.pl
cp -avf qhtlfirewall.pl /usr/sbin/qhtlfirewall
cp -avf qhtlwaterfall.pl /usr/sbin/qhtlwaterfall
chmod 700 /usr/sbin/qhtlfirewall /usr/sbin/qhtlwaterfall
chcon -h system_u:object_r:bin_t:s0 /usr/sbin/qhtlwaterfall
chcon -h system_u:object_r:bin_t:s0 /usr/sbin/qhtlfirewall

mkdir -p webmin/csf/images
mkdir -p ui/images
mkdir -p da/images
mkdir -p interworx/images

cp -avf csf/* webmin/csf/images/
cp -avf csf/* ui/images/
cp -avf csf/* da/images/
cp -avf csf/* interworx/images/

cp -avf messenger/*.php /etc/qhtlfirewall/messenger/
cp -avf uninstall.vesta.sh /usr/local/qhtlfirewall/bin/uninstall.sh
cp -avf csftest.pl /usr/local/qhtlfirewall/bin/
cp -avf remove_apf_bfd.sh /usr/local/qhtlfirewall/bin/
cp -avf readme.txt /etc/qhtlfirewall/
cp -avf sanity.txt /usr/local/qhtlfirewall/lib/
cp -avf csf.rbls /usr/local/qhtlfirewall/lib/
cp -avf restricted.txt /usr/local/qhtlfirewall/lib/
cp -avf changelog.txt /etc/qhtlfirewall/
cp -avf downloadservers /etc/qhtlfirewall/
cp -avf install.txt /etc/qhtlfirewall/
cp -avf version.txt /etc/qhtlfirewall/
cp -avf license.txt /etc/qhtlfirewall/
cp -avf webmin /usr/local/qhtlfirewall/lib/
cp -avf ConfigServer /usr/local/qhtlfirewall/lib/
cp -avf Net /usr/local/qhtlfirewall/lib/
cp -avf Geo /usr/local/qhtlfirewall/lib/
cp -avf Crypt /usr/local/qhtlfirewall/lib/
cp -avf HTTP /usr/local/qhtlfirewall/lib/
cp -avf JSON /usr/local/qhtlfirewall/lib/
cp -avf version/* /usr/local/qhtlfirewall/lib/
cp -avf csf.div /usr/local/qhtlfirewall/lib/
cp -avf csfajaxtail.js /usr/local/qhtlfirewall/lib/
cp -avf ui/images /etc/qhtlfirewall/ui/.
cp -avf profiles /usr/local/qhtlfirewall/
cp -avf csf.conf /usr/local/qhtlfirewall/profiles/reset_to_defaults.conf
cp -avf qhtlwaterfall.logrotate /etc/logrotate.d/qhtlwaterfall

if [ -e "/usr/local/ispconfig/interface/web/csf/ispconfig_csf" ]; then
	rm -Rfv /usr/local/ispconfig/interface/web/csf/
fi

rm -fv /etc/qhtlfirewall/csf.spamhaus /etc/qhtlfirewall/csf.dshield /etc/qhtlfirewall/csf.tor /etc/qhtlfirewall/csf.bogon

mkdir -p /usr/local/man/man1/
cp -avf qhtlfirewall.1.txt /usr/local/man/man1/qhtlfirewall.1
cp -avf qhtlfirewall.help /usr/local/qhtlfirewall/lib/
chmod 755 /usr/local/man/
chmod 755 /usr/local/man/man1/
chmod 644 /usr/local/man/man1/qhtlfirewall.1

chmod -R 600 /etc/qhtlfirewall
chmod -R 600 /var/lib/qhtlfirewall
chmod -R 600 /usr/local/qhtlfirewall/bin
chmod -R 600 /usr/local/qhtlfirewall/lib
chmod -R 600 /usr/local/qhtlfirewall/tpl
chmod -R 600 /usr/local/qhtlfirewall/profiles
chmod 600 /var/log/qhtlwaterfall.log*

chmod -v 700 /usr/local/qhtlfirewall/bin/*.pl /usr/local/qhtlfirewall/bin/*.sh /usr/local/qhtlfirewall/bin/*.pm
chmod -v 700 /usr/local/qhtlfirewall/lib/webmin/csf/index.cgi
chmod -v 644 /etc/cron.d/qhtlwaterfall-cron
chmod -v 644 /etc/cron.d/qhtlfirewall-cron

cp -avf csget.pl /etc/cron.daily/csget
chmod 700 /etc/cron.daily/csget
/etc/cron.daily/csget --nosleep

chmod -v 700 auto.vesta.pl
./auto.vesta.pl $OLDVERSION

if test `cat /proc/1/comm` = "systemd"
then
	if [ -e /etc/init.d/qhtlwaterfall ] || [ -e /etc/init.d/lfd ]; then
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
		rm -fv /etc/init.d/qhtlfirewall /etc/init.d/qhtlwaterfall /etc/init.d/csf /etc/init.d/lfd
    fi

    mkdir -p /etc/systemd/system/
    mkdir -p /usr/lib/systemd/system/
	cp -avf qhtlwaterfall.service /usr/lib/systemd/system/
	cp -avf qhtlfirewall.service /usr/lib/systemd/system/

	chcon -h system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/qhtlwaterfall.service
	chcon -h system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/qhtlfirewall.service

    systemctl daemon-reload

	systemctl enable qhtlfirewall.service
	systemctl enable qhtlwaterfall.service

	systemctl disable firewalld
	systemctl stop firewalld
	systemctl mask firewalld
else
	cp -avf qhtlwaterfall.sh /etc/init.d/qhtlwaterfall
	cp -avf qhtlfirewall.sh /etc/init.d/qhtlfirewall
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
	ln -svf /etc/init.d/qhtlfirewall /etc/rc.d/rc3.d/S80qhtlfirewall
	ln -svf /etc/init.d/qhtlfirewall /etc/rc.d/rc4.d/S80qhtlfirewall
	ln -svf /etc/init.d/qhtlfirewall /etc/rc.d/rc5.d/S80qhtlfirewall
	ln -svf /etc/init.d/qhtlwaterfall /etc/rc.d/rc3.d/S85qhtlwaterfall
	ln -svf /etc/init.d/qhtlwaterfall /etc/rc.d/rc4.d/S85qhtlwaterfall
	ln -svf /etc/init.d/qhtlwaterfall /etc/rc.d/rc5.d/S85qhtlwaterfall
	else
		/sbin/chkconfig qhtlwaterfall on
		/sbin/chkconfig qhtlfirewall on
    fi
fi

chown -Rf root:root /etc/qhtlfirewall /var/lib/qhtlfirewall /usr/local/qhtlfirewall
chown -f root:root /usr/sbin/qhtlfirewall /usr/sbin/qhtlwaterfall /etc/logrotate.d/qhtlwaterfall /etc/cron.d/qhtlfirewall-cron /etc/cron.d/qhtlwaterfall-cron /usr/local/man/man1/qhtlfirewall.1 /usr/lib/systemd/system/qhtlwaterfall.service /usr/lib/systemd/system/qhtlfirewall.service /etc/init.d/qhtlwaterfall /etc/init.d/qhtlfirewall

mkdir -v -m 0600 /usr/local/vesta/web/list/csf/
cp -avf vestacp/* /usr/local/vesta/web/list/csf/
cp -avf csf /usr/local/vesta/web/list/csf/images/
find /usr/local/vesta/web/list/csf -type d -exec chmod -v 755 {} \;
find /usr/local/vesta/web/list/csf -type f -exec chmod -v 644 {} \;
mv /usr/local/vesta/web/list/csf/qhtlfirewall.pl /usr/local/vesta/bin/
chmod 700 /usr/local/vesta/bin/qhtlfirewall.pl

cd webmin ; tar -czf /usr/local/qhtlfirewall/qhtlfirewallwebmin.tgz ./*
ln -svf /usr/local/qhtlfirewall/qhtlfirewallwebmin.tgz /etc/qhtlfirewall/

echo
echo "Installation Completed"
echo
