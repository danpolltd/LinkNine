#!/bin/sh
echo "Uninstalling qhtlfirewall and qhtlwaterfall..."
echo

sed -i 's/qhtlwaterfall=ON/qhtlwaterfall=OFF/' /usr/local/directadmin/data/admin/services.status

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
rm -Rfv /usr/local/directadmin/plugins/qhtlfirewall
rm -fv /etc/logrotate.d/qhtlwaterfall
rm -fv /usr/local/man/man1/qhtlfirewall.man.1

rm -Rfv /etc/qhtlfirewall /usr/local/qhtlfirewall /var/lib/qhtlfirewall

echo
echo "...Done"
