#!/bin/sh

if [ -e "/usr/local/cpanel/bin/register_appconfig" ]; then
    if [ -e "/usr/local/cpanel/whostmgr/docroot/cgi/addon_qhtlfirewall.cgi" ]; then
        /bin/cp -af /usr/local/cpanel/whostmgr/docroot/cgi/configserver/qhtlfirewall/Driver/* /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver/
        /bin/touch /usr/local/cpanel/Cpanel/Config/ConfigObj/Driver
        /usr/local/cpanel/bin/register_appconfig /usr/local/cpanel/whostmgr/docroot/cgi/configserver/qhtlfirewall/qhtlfirewall.conf

        /bin/rm -f /usr/local/cpanel/whostmgr/docroot/cgi/addon_qhtlfirewall.cgi
        /bin/rm -Rf /usr/local/cpanel/whostmgr/docroot/cgi/qhtlfirewall
    fi
fi
