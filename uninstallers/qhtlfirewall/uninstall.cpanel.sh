#!/bin/sh
echo "Uninstalling qhtlfirewall and qhtlwaterfall..."
echo

/usr/sbin/qhtlfirewall -f

if test `cat /proc/1/comm` = "systemd"
then
    systemctl disable qhtlfirewall.service
    systemctl disable qhtlwaterfall.service
    systemctl stop qhtlfirewall.service
    systemctl stop qhtlwaterfall.service

    rm -fv /usr/lib/systemd/system/qhtlfirewall.service
    rm -fv /usr/lib/systemd/system/qhtlwaterfall.service
    systemctl daemon-reload
else
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

if [ -e "/usr/local/cpanel/bin/unregister_appconfig" ]; then
    cd /
	/usr/local/cpanel/bin/unregister_appconfig qhtlfirewall
fi

rm -fv /etc/chkserv.d/qhtlwaterfall
rm -fv /usr/sbin/qhtlfirewall
rm -fv /usr/sbin/qhtlwaterfall
rm -fv /etc/cron.d/qhtlfirewall_update
rm -fv /etc/cron.d/qhtlwaterfall-cron
rm -fv /etc/cron.d/qhtlfirewall-cron
rm -fv /etc/logrotate.d/qhtlwaterfall
rm -fv /usr/local/man/man1/qhtlfirewall.man.1

## Intentionally do not remove legacy addon/old paths

/bin/rm -fv /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver/QhtLinkFirewall.pm
/bin/rm -Rfv /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver/QhtLinkFirewall
/bin/touch /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver

rm -fv /var/run/chkservd/qhtlwaterfall
sed -i 's/qhtlwaterfall:1//' /etc/chkserv.d/chkservd.conf
/scripts/restartsrv_chkservd

rm -Rfv /etc/qhtlfirewall /usr/local/qhtlfirewall /var/lib/qhtlfirewall

# Remove all UI CSS/JS/image folders and files for qhtlfirewall
/bin/rm -Rfv /usr/local/qhtlfirewall/ui/images/
/bin/rm -Rfv /usr/local/qhtlfirewall/ui/images/bootstrap/
/bin/rm -Rfv /usr/local/qhtlfirewall/ui/images/holiday/
/bin/rm -Rfv /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/ui/images/
/bin/rm -Rfv /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/ui/images/bootstrap/
/bin/rm -Rfv /usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/ui/images/holiday/
# Remove DirectAdmin/Webmin/DA panel UI assets if present
/bin/rm -Rfv /usr/local/directadmin/plugins/qhtlfirewall/images/
/bin/rm -Rfv /usr/local/directadmin/plugins/qhtlfirewall/images/bootstrap/
/bin/rm -Rfv /usr/local/directadmin/plugins/qhtlfirewall/images/holiday/
/bin/rm -Rfv /usr/local/webmin/qhtlfirewall/images/
/bin/rm -Rfv /usr/local/webmin/qhtlfirewall/images/bootstrap/
/bin/rm -Rfv /usr/local/webmin/qhtlfirewall/images/holiday/
# Remove DA and Webmin plugin folders if present
/bin/rm -Rfv /usr/local/directadmin/plugins/qhtlfirewall/
/bin/rm -Rfv /usr/local/webmin/qhtlfirewall/

echo
echo "...Done"
