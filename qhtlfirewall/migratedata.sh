#!/bin/sh
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################

umask 0177

touch /etc/qhtlfirewall/qhtlfirewall.disable
/etc/init.d/qhtlwaterfall stop

# temp data:

cp -avf /etc/qhtlfirewall/qhtlfirewall.4.saved /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.6.saved /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.AUTOSHUN /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.BFB /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.BOGON /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.CIARMY /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.DSHIELD /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.HONEYPOT /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.MAXMIND /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.OPENBL /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.RBN /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.SPAMDROP /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.SPAMEDROP /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.block.TOR /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.ccignore /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.cclookup /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.div /usr/local/qhtlfirewall/lib/
cp -avf /etc/qhtlfirewall/qhtlfirewall.dnscache /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.dwdisable /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.gallow /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.gdeny /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.gdyndns /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.gignore /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.load /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.lock /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.logmax /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.logrun /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.logtemp /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.queue /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.restart /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempallow /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempban /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempconf /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempdisk /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempdyn /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempexp /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempexploit /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempfiles /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempgdyn /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempint /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempip /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.temppids /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempusers /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlfirewall.tempwatch /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/Geo/GeoIP.dat /var/lib/qhtlfirewall/Geo/
cp -avf /etc/qhtlfirewall/Geo/GeoLiteCity.dat /var/lib/qhtlfirewall/Geo/
cp -avf /etc/qhtlfirewall/qhtlwaterfall.enable /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlwaterfall.restart /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/qhtlwaterfall.start /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/lock/ /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/nocheck /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/sanity.txt /usr/local/qhtlfirewall/lib/
cp -avf /etc/qhtlfirewall/stats/ /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/suspicious.tar /var/lib/qhtlfirewall/
cp -avf /etc/qhtlfirewall/ui/ui.session /var/lib/qhtlfirewall/ui/
cp -avf /etc/qhtlfirewall/webmin/ /usr/local/qhtlfirewall/lib/
cp -avf /etc/qhtlfirewall/zone/ /var/lib/qhtlfirewall/

rm -fv /etc/qhtlfirewall/qhtlfirewall.4.saved
rm -fv /etc/qhtlfirewall/qhtlfirewall.6.saved
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.AUTOSHUN
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.BFB
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.BOGON
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.CIARMY
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.DSHIELD
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.HONEYPOT
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.MAXMIND
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.OPENBL
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.RBN
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.SPAMDROP
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.SPAMEDROP
rm -fv /etc/qhtlfirewall/qhtlfirewall.block.TOR
rm -fv /etc/qhtlfirewall/qhtlfirewall.ccignore
rm -fv /etc/qhtlfirewall/qhtlfirewall.cclookup
rm -fv /etc/qhtlfirewall/qhtlfirewall.div
rm -fv /etc/qhtlfirewall/qhtlfirewall.dnscache
rm -fv /etc/qhtlfirewall/qhtlfirewall.dwdisable
rm -fv /etc/qhtlfirewall/qhtlfirewall.gallow
rm -fv /etc/qhtlfirewall/qhtlfirewall.gdeny
rm -fv /etc/qhtlfirewall/qhtlfirewall.gdyndns
rm -fv /etc/qhtlfirewall/qhtlfirewall.gignore
rm -fv /etc/qhtlfirewall/qhtlfirewall.load
rm -fv /etc/qhtlfirewall/qhtlfirewall.lock
rm -fv /etc/qhtlfirewall/qhtlfirewall.logmax
rm -fv /etc/qhtlfirewall/qhtlfirewall.logrun
rm -fv /etc/qhtlfirewall/qhtlfirewall.logtemp
rm -fv /etc/qhtlfirewall/qhtlfirewall.queue
rm -fv /etc/qhtlfirewall/qhtlfirewall.restart
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempallow
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempban
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempconf
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempdisk
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempdyn
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempexp
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempexploit
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempfiles
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempgdyn
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempint
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempip
rm -fv /etc/qhtlfirewall/qhtlfirewall.temppids
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempusers
rm -fv /etc/qhtlfirewall/qhtlfirewall.tempwatch
rm -fv /etc/qhtlfirewall/Geo/GeoIP.dat
rm -fv /etc/qhtlfirewall/Geo/GeoLiteCity.dat
rm -fv /etc/qhtlfirewall/qhtlwaterfall.enable
rm -fv /etc/qhtlfirewall/qhtlwaterfall.restart
rm -fv /etc/qhtlfirewall/qhtlwaterfall.start
rm -Rfv /etc/qhtlfirewall/lock/
rm -fv /etc/qhtlfirewall/nocheck
rm -fv /etc/qhtlfirewall/sanity.txt
rm -Rfv /etc/qhtlfirewall/stats/
rm -fv /etc/qhtlfirewall/suspicious.tar
rm -fv /etc/qhtlfirewall/ui/ui.session
rm -Rfv /etc/qhtlfirewall/webmin/
rm -Rfv /etc/qhtlfirewall/zone/

# email alert templates:

cp -avf /etc/qhtlfirewall/accounttracking.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/alert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/connectiontracking.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/consolealert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/cpanelalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/exploitalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/filealert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/forkbombalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/integrityalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/loadalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/logalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/logfloodalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/netblock.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/permblock.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/portknocking.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/portscan.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/processtracking.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/queuealert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/relayalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/resalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/reselleralert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/scriptalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/sshalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/sualert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/syslogalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/tracking.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/uialert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/uidscan.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/usertracking.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/watchalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/webminalert.txt /usr/local/qhtlfirewall/tpl/
cp -avf /etc/qhtlfirewall/x-arf.txt /usr/local/qhtlfirewall/tpl/

rm -fv /etc/qhtlfirewall/accounttracking.txt
rm -fv /etc/qhtlfirewall/alert.txt
rm -fv /etc/qhtlfirewall/connectiontracking.txt
rm -fv /etc/qhtlfirewall/consolealert.txt
rm -fv /etc/qhtlfirewall/cpanelalert.txt
rm -fv /etc/qhtlfirewall/exploitalert.txt
rm -fv /etc/qhtlfirewall/filealert.txt
rm -fv /etc/qhtlfirewall/forkbombalert.txt
rm -fv /etc/qhtlfirewall/integrityalert.txt
rm -fv /etc/qhtlfirewall/loadalert.txt
rm -fv /etc/qhtlfirewall/logalert.txt
rm -fv /etc/qhtlfirewall/logfloodalert.txt
rm -fv /etc/qhtlfirewall/netblock.txt
rm -fv /etc/qhtlfirewall/permblock.txt
rm -fv /etc/qhtlfirewall/portknocking.txt
rm -fv /etc/qhtlfirewall/portscan.txt
rm -fv /etc/qhtlfirewall/processtracking.txt
rm -fv /etc/qhtlfirewall/queuealert.txt
rm -fv /etc/qhtlfirewall/relayalert.txt
rm -fv /etc/qhtlfirewall/resalert.txt
rm -fv /etc/qhtlfirewall/reselleralert.txt
rm -fv /etc/qhtlfirewall/scriptalert.txt
rm -fv /etc/qhtlfirewall/sshalert.txt
rm -fv /etc/qhtlfirewall/sualert.txt
rm -fv /etc/qhtlfirewall/syslogalert.txt
rm -fv /etc/qhtlfirewall/tracking.txt
rm -fv /etc/qhtlfirewall/uialert.txt
rm -fv /etc/qhtlfirewall/uidscan.txt
rm -fv /etc/qhtlfirewall/usertracking.txt
rm -fv /etc/qhtlfirewall/watchalert.txt
rm -fv /etc/qhtlfirewall/webminalert.txt
rm -fv /etc/qhtlfirewall/x-arf.txt

# perl modules:

rm -Rfv /etc/qhtlfirewall/Crypt
rm -Rfv /etc/qhtlfirewall/Geo
rm -Rfv /etc/qhtlfirewall/HTTP
rm -Rfv /etc/qhtlfirewall/Net

# scripts:

cp -avf /etc/qhtlfirewall/cseui.pl /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/qhtlfirewalltest.pl /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/qhtlfirewallui.pl /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/qhtlfirewalluir.pl /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/migratedata.pl /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/pt_deleted_action.pl /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/regex.custom.pm /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/regex.pm /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/remove_apf_bfd.sh /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/servercheck.pm /usr/local/qhtlfirewall/bin/
cp -avf /etc/qhtlfirewall/uninstall.sh /usr/local/qhtlfirewall/bin/

rm -fv /etc/qhtlfirewall/cseui.pl
rm -fv /etc/qhtlfirewall/qhtlfirewalltest.pl
rm -fv /etc/qhtlfirewall/qhtlfirewallui.pl
rm -fv /etc/qhtlfirewall/qhtlfirewalluir.pl
rm -fv /etc/qhtlfirewall/migratedata.pl
rm -fv /etc/qhtlfirewall/pt_deleted_action.pl
rm -fv /etc/qhtlfirewall/regex.custom.pm
rm -fv /etc/qhtlfirewall/regex.pm
rm -fv /etc/qhtlfirewall/remove_apf_bfd.sh
rm -fv /etc/qhtlfirewall/servercheck.pm
rm -fv /etc/qhtlfirewall/uninstall.sh

# other:

rm -fv /etc/qhtlfirewall/*.new
rm -fv /etc/qhtlfirewall/dd_test
rm -fv /etc/qhtlfirewall/qhtlfirewallwebmin.tgz
rm -fv /etc/qhtlfirewall/qhtlfirewall.spamhaus /etc/qhtlfirewall/qhtlfirewall.dshield /etc/qhtlfirewall/qhtlfirewall.tor /etc/qhtlfirewall/qhtlfirewall.bogon
rm -Rfv /etc/qhtlfirewall/File
rm -Rfv /etc/qhtlfirewall/Geography
rm -Rfv /etc/qhtlfirewall/IP
rm -Rfv /etc/qhtlfirewall/Math
rm -Rfv /etc/qhtlfirewall/Sys

rm -fv /etc/qhtlfirewall/qhtlfirewall.disable
