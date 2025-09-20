#!/bin/sh
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################

umask 0177

if [ -e "/usr/local/cpanel/version" ]; then
	echo "Running qhtlfirewall cPanel installer"
	echo
	sh install.cpanel.sh
	exit 0
elif [ -e "/usr/local/directadmin/directadmin" ]; then
	echo "Running qhtlfirewall DirectAdmin installer"
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

mkdir -v -m 0700 /etc/qhtlfirewall
cp -avf install.txt /etc/qhtlfirewall/

echo "Checking Perl modules..."
chmod 700 os.pl
RETURN=`./os.pl`
if [ "$RETURN" = 1 ]; then
	echo
	echo "FAILED: You MUST install the missing perl modules above before you can install qhtlfirewall. See /etc/qhtlfirewall/install.txt for installation details."
    echo
	exit
else
    echo "...Perl modules OK"
    echo
fi

mkdir -v -m 0700 /etc/qhtlfirewall
mkdir -v -m 0700 /var/lib/qhtlfirewall
mkdir -v -m 0700 /var/lib/qhtlfirewall/backup
mkdir -v -m 0700 /var/lib/qhtlfirewall/Geo
mkdir -v -m 0700 /var/lib/qhtlfirewall/ui
mkdir -v -m 0700 /var/lib/qhtlfirewall/stats
mkdir -v -m 0700 /var/lib/qhtlfirewall/lock
mkdir -v -m 0700 /var/lib/qhtlfirewall/webmin
mkdir -v -m 0700 /var/lib/qhtlfirewall/zone
mkdir -v -m 0700 /usr/local/qhtlfirewall
mkdir -v -m 0700 /usr/local/qhtlfirewall/bin
mkdir -v -m 0700 /usr/local/qhtlfirewall/lib
mkdir -v -m 0700 /usr/local/qhtlfirewall/tpl

if [ -e "/etc/qhtlfirewall/alert.txt" ]; then
	sh migratedata.sh
fi

if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.conf" ]; then
	cp -avf qhtlfirewall.cyberpanel.conf /etc/qhtlfirewall/qhtlfirewall.conf
fi

if [ ! -d /var/lib/qhtlfirewall ]; then
	mkdir -v -p -m 0700 /var/lib/qhtlfirewall
fi
if [ ! -d /usr/local/qhtlfirewall/lib ]; then
	mkdir -v -p -m 0700 /usr/local/qhtlfirewall/lib
fi
if [ ! -d /usr/local/qhtlfirewall/bin ]; then
	mkdir -v -p -m 0700 /usr/local/qhtlfirewall/bin
fi
if [ ! -d /usr/local/qhtlfirewall/tpl ]; then
	mkdir -v -p -m 0700 /usr/local/qhtlfirewall/tpl
fi

if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.allow" ]; then
	cp -avf qhtlfirewall.cyberpanel.allow /etc/qhtlfirewall/qhtlfirewall.allow
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
	cp -avf qhtlfirewall.cyberpanel.ignore /etc/qhtlfirewall/qhtlfirewall.ignore
fi
if [ ! -e "/etc/qhtlfirewall/qhtlfirewall.pignore" ]; then
	cp -avf qhtlfirewall.cyberpanel.pignore /etc/qhtlfirewall/qhtlfirewall.pignore
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
if [ -e "/etc/qhtlfirewall/qhtlfirewallui.pl" ]; then
	rm -f /etc/qhtlfirewall/qhtlfirewallui.pl
fi
if [ -e "/etc/qhtlfirewall/qhtlfirewalluir.pl" ]; then
	rm -f /etc/qhtlfirewall/qhtlfirewalluir.pl
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

if [ -e "/etc/qhtlfirewall/qhtlmanagerui.pl" ]; then
	rm -f /etc/qhtlfirewall/qhtlmanagerui.pl
fi
if [ -e "/usr/local/qhtlfirewall/bin/qhtlmanagerui.pl" ]; then
	rm -f /usr/local/qhtlfirewall/bin/qhtlmanagerui.pl
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
ln -svf /usr/sbin/qhtlfirewall /etc/qhtlfirewall/qhtlfirewall.pl
ln -svf /usr/sbin/qhtlwaterfall /etc/qhtlfirewall/qhtlwaterfall.pl
ln -svf /usr/local/qhtlfirewall/bin/qhtlfirewalltest.pl /etc/qhtlfirewall/
ln -svf /usr/local/qhtlfirewall/bin/pt_deleted_action.pl /etc/qhtlfirewall/
ln -svf /usr/local/qhtlfirewall/bin/remove_apf_bfd.sh /etc/qhtlfirewall/
ln -svf /usr/local/qhtlfirewall/bin/uninstall.sh /etc/qhtlfirewall/
ln -svf /usr/local/qhtlfirewall/bin/regex.custom.pm /etc/qhtlfirewall/
ln -svf /usr/local/qhtlfirewall/lib/webmin /etc/qhtlfirewall/
if [ ! -e "/etc/qhtlfirewall/alerts" ]; then
    ln -svf /usr/local/qhtlfirewall/tpl /etc/qhtlfirewall/alerts
fi
chcon -h system_u:object_r:bin_t:s0 /usr/sbin/qhtlwaterfall
chcon -h system_u:object_r:bin_t:s0 /usr/sbin/qhtlfirewall

mkdir webmin/qhtlfirewall/images
mkdir ui/images
mkdir da/images
mkdir interworx/images

cp -avf qhtlfirewall/* webmin/qhtlfirewall/images/
cp -avf qhtlfirewall/* ui/images/
cp -avf qhtlfirewall/* da/images/
cp -avf qhtlfirewall/* interworx/images/

cp -avf messenger/*.php /etc/qhtlfirewall/messenger/
cp -avf uninstall.cyberpanel.sh /usr/local/qhtlfirewall/bin/uninstall.sh
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
cp -avf qhtlwaterfall.logrotate /etc/logrotate.d/qhtlwaterfall
chcon --reference /etc/logrotate.d /etc/logrotate.d/qhtlwaterfall
cp -avf apf_stub.pl /etc/qhtlfirewall/

rm -fv /etc/qhtlfirewall/qhtlfirewall.spamhaus /etc/qhtlfirewall/qhtlfirewall.dshield /etc/qhtlfirewall/qhtlfirewall.tor /etc/qhtlfirewall/qhtlfirewall.bogon

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
chmod -v 700 /etc/qhtlfirewall/*.pl /etc/qhtlfirewall/*.cgi /etc/qhtlfirewall/*.sh /etc/qhtlfirewall/*.php /etc/qhtlfirewall/*.py
chmod -v 700 /etc/qhtlfirewall/webmin/qhtlfirewall/index.cgi
chmod -v 644 /etc/cron.d/qhtlwaterfall-cron
chmod -v 644 /etc/cron.d/qhtlfirewall-cron

cp -af qhtlfirewallget.pl /etc/cron.daily/qhtlfirewallget
chmod 700 /etc/cron.daily/qhtlfirewallget
/etc/cron.daily/qhtlfirewallget --nosleep || true

chmod -v 700 auto.cyberpanel.pl
./auto.cyberpanel.pl $OLDVERSION

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
	cp -avf qhtlfirewall.service /usr/lib/systemd/system/

	chcon -h system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/qhtlwaterfall.service
	chcon -h system_u:object_r:systemd_unit_file_t:s0 /usr/lib/systemd/system/qhtlfirewall.service

    systemctl daemon-reload

	systemctl enable qhtlfirewall.service >/dev/null 2>&1 || true
	systemctl enable qhtlwaterfall.service >/dev/null 2>&1 || true

	systemctl disable firewalld >/dev/null 2>&1 || true
	systemctl stop firewalld >/dev/null 2>&1 || true
	systemctl mask firewalld >/dev/null 2>&1 || true
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

# Install CyberPanel static assets and Django app for qhtlfirewall
mkdir -vp /usr/local/CyberCP/public/static/qhtlfirewall/
cp -avf qhtlfirewall/* /usr/local/CyberCP/public/static/qhtlfirewall/
chmod 755 /usr/local/CyberCP/public/static/qhtlfirewall/

cp cyberpanel/cyberpanel.pl /usr/local/qhtlfirewall/bin/
chmod 700 /usr/local/qhtlfirewall/bin/cyberpanel.pl
cp -avf cyberpanel/qhtlfirewall /usr/local/CyberCP/

mkdir -p /home/cyberpanel/plugins
touch /home/cyberpanel/plugins/qhtlfirewall

if ! cat /usr/local/CyberCP/CyberCP/settings.py | grep -q qhtlfirewall; then
	sed -i "/pluginHolder/ i \ \ \ \ 'qhtlfirewall'," /usr/local/CyberCP/CyberCP/settings.py
fi
if ! cat /usr/local/CyberCP/CyberCP/urls.py | grep -q qhtlfirewall; then
	sed -i "/pluginHolder/ i \ \ \ \ url(r'^qhtlfirewall/',include('qhtlfirewall.urls'))," /usr/local/CyberCP/CyberCP/urls.py
fi
# Add sidebar menu include for qhtlfirewall if not already present
if ! cat /usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html | grep -q qhtlfirewall; then
	sed -i "/trans 'Plugins'/ i \{\% include \"/usr/local/CyberCP/qhtlfirewall/templates/qhtlfirewall/menu.html\" \%\}" /usr/local/CyberCP/baseTemplate/templates/baseTemplate/index.html
fi

service lscpd restart

echo
echo "Installation Completed"
echo
