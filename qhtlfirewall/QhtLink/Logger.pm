###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################
## no critic (RequireUseWarnings, ProhibitExplicitReturnUndef, ProhibitMixedBooleanOperators, RequireBriefOpen)
# start main
package QhtLink::Logger;

use strict;
use lib '/usr/local/qhtlfirewall/lib';
use Carp;
use Fcntl qw(:DEFAULT :flock);
use QhtLink::Config;

use Exporter qw(import);
our $VERSION     = 1.02;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = qw(logfile);

my $config = QhtLink::Config->loadconfig();
my %config = $config->config();
my $hostname;
if (-e "/proc/sys/kernel/hostname") {
	open (my $IN, "<", "/proc/sys/kernel/hostname");
	flock ($IN, LOCK_SH);
	$hostname = <$IN>;
	chomp $hostname;
	close ($IN);
} else {
	$hostname = "unknown";
}
my $hostshort = (split(/\./,$hostname))[0];

my $sys_syslog;
if ($config{SYSLOG}) {
	eval('use Sys::Syslog;'); ##no critic
	unless ($@) {$sys_syslog = 1}
}

# end main
###############################################################################
# start logfile
sub logfile {
	my $line = shift;
	my @ts = split(/\s+/,scalar localtime);
	if ($ts[2] < 10) {$ts[2] = " ".$ts[2]}

	my $logfile = "/var/log/qhtlwaterfall.log";
	if ($< != 0) {$logfile = "/var/log/qhtlwaterfall_messenger.log"}
	
	sysopen (my $LOGFILE, $logfile, O_WRONLY | O_APPEND | O_CREAT);
	flock ($LOGFILE, LOCK_EX);
	print $LOGFILE "$ts[1] $ts[2] $ts[3] $hostshort qhtlwaterfall[$$]: $line\n";
	close ($LOGFILE);

	if ($config{SYSLOG} and $sys_syslog) {
		eval {
			local $SIG{__DIE__} = undef;
			openlog('qhtlwaterfall', 'ndelay,pid', 'user');
			syslog('info', $line);
			closelog();
		}
	}
	return;
}
# end logfile
###############################################################################

1;