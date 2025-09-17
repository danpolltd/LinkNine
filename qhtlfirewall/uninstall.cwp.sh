#!/bin/sh
echo "Uninstalling qhtlfirewall and qhtlwaterfall..."
echo


/usr/sbin/qhtlfirewall -f

if test `cat /proc/1/comm` = "systemd"
then
    systemctl disable qhtlfirewall.service
    systemctl disable qhtlwaterfall.service
    systemctl stop qhtlwaterfall.service
    systemctl stop qhtlfirewall.service

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

rm -fv /etc/chkserv.d/qhtlwaterfall
rm -fv /usr/sbin/qhtlfirewall
rm -fv /usr/sbin/qhtlwaterfall
rm -fv /etc/cron.d/qhtlfirewall_update
rm -fv /etc/cron.d/qhtlwaterfall-cron
rm -fv /etc/cron.d/qhtlfirewall-cron
rm -fv /etc/logrotate.d/qhtlwaterfall
rm -fv /usr/local/man/man1/qhtlfirewall.man.1

rm -fv /usr/local/cwpsrv/htdocs/resources/admin/modules/qhtlfirewallofficial.php
rm -fv /usr/local/cwpsrv/htdocs/resources/admin/modules/qhtlfirewall.pl
rm -fv /usr/local/cwpsrv/htdocs/resources/admin/addons/ajax/ajax_qhtlfirewallframe.php
rm -Rfv /usr/local/cwpsrv/htdocs/admin/design/qhtlfirewall/
rm -fv /usr/local/cwpsrv/htdocs/resources/admin/include/qhtlfirewall.php
## Do not touch legacy include anymore; legacy removal has been dropped as part of the no-fallback policy

echo
echo "...Done"
