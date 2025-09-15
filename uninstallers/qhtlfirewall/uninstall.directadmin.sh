#!/bin/sh
echo "Uninstalling qhtlfirewall and qhtlwaterfall..."
echo

# Disable DA service monitor entry if present
sed -i 's/lfd=ON/lfd=OFF/' /usr/local/directadmin/data/admin/services.status 2>/dev/null

# Flush firewall rules before removing binaries
/usr/sbin/qhtlfirewall -f 2>/dev/null || true

if test "$(cat /proc/1/comm)" = "systemd"
then
    systemctl disable qhtlfirewall.service 2>/dev/null || true
    systemctl disable qhtlwaterfall.service 2>/dev/null || true
    systemctl stop qhtlwaterfall.service 2>/dev/null || true
    systemctl stop qhtlfirewall.service 2>/dev/null || true

    rm -fv /usr/lib/systemd/system/qhtlfirewall.service
    rm -fv /usr/lib/systemd/system/qhtlwaterfall.service
    systemctl daemon-reload 2>/dev/null || true
else
    if [ -f /etc/redhat-release ]; then
        /sbin/chkconfig qhtlfirewall off 2>/dev/null || true
        /sbin/chkconfig qhtlwaterfall off 2>/dev/null || true
        /sbin/chkconfig qhtlfirewall --del 2>/dev/null || true
        /sbin/chkconfig qhtlwaterfall --del 2>/dev/null || true
    elif [ -f /etc/debian_version ] || [ -f /etc/lsb-release ]; then
        update-rc.d -f qhtlwaterfall remove 2>/dev/null || true
        update-rc.d -f qhtlfirewall remove 2>/dev/null || true
    elif [ -f /etc/gentoo-release ]; then
        rc-update del qhtlwaterfall default 2>/dev/null || true
        rc-update del qhtlfirewall default 2>/dev/null || true
        rm -fv /etc/init.d/qhtlfirewall
        rm -fv /etc/init.d/qhtlwaterfall
        rm -vf /etc/rc.d/rc3.d/S80qhtlfirewall
        rm -vf /etc/rc.d/rc4.d/S80qhtlfirewall
        rm -vf /etc/rc.d/rc5.d/S80qhtlfirewall
        rm -vf /etc/rc.d/rc3.d/S85qhtlwaterfall
        rm -vf /etc/rc.d/rc4.d/S85qhtlwaterfall
        rm -vf /etc/rc.d/rc5.d/S85qhtlwaterfall
    else
        /sbin/chkconfig qhtlfirewall off 2>/dev/null || true
        /sbin/chkconfig qhtlwaterfall off 2>/dev/null || true
        /sbin/chkconfig qhtlfirewall --del 2>/dev/null || true
        /sbin/chkconfig qhtlwaterfall --del 2>/dev/null || true
    fi
    # Clean up any legacy init names if they happen to exist
    rm -fv /etc/init.d/qhtlfirewall /etc/init.d/qhtlwaterfall /etc/init.d/csf /etc/init.d/lfd
fi

# Remove scheduled tasks and logrotate
rm -fv /etc/cron.d/qhtlwaterfall-cron /etc/cron.d/qhtlfirewall-cron /etc/cron.d/csf_update
rm -fv /etc/logrotate.d/qhtlwaterfall

# Remove binaries and manpage
rm -fv /usr/sbin/qhtlfirewall /usr/sbin/qhtlwaterfall
rm -fv /usr/local/man/man1/qhtlfirewall.1

# Remove DirectAdmin plugin
rm -Rfv /usr/local/directadmin/plugins/csf

# Remove configuration and data directories
rm -Rfv /etc/qhtlfirewall /usr/local/qhtlfirewall /var/lib/qhtlfirewall

echo
echo "...Done"
