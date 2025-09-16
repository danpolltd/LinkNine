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
## no critic (RequireUseWarnings, ProhibitExplicitReturnUndef, ProhibitMixedBooleanOperators, RequireBriefOpen)
# start main
package ConfigServer::Service;

use strict;
use lib '/usr/local/qhtlfirewall/lib';
use Carp;
use IPC::Open3;
use Fcntl qw(:DEFAULT :flock);
use ConfigServer::Config;

use Exporter qw(import);
our $VERSION     = 1.01;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = qw();

my $config = ConfigServer::Config->loadconfig();
my %config = $config->config();

open (my $IN, "<", "/proc/1/comm");
flock ($IN, LOCK_SH);
my $sysinit = <$IN>;
close ($IN);
chomp $sysinit;
if ($sysinit ne "systemd") {$sysinit = "init"}

# end main
###############################################################################
# start type
sub type {
	return $sysinit;
}
# end type
###############################################################################
# start startqhtlwaterfall
sub startqhtlwaterfall {
	if ($sysinit eq "systemd") {
		&printcmd($config{SYSTEMCTL},"start","qhtlwaterfall.service");
		&printcmd($config{SYSTEMCTL},"status","qhtlwaterfall.service");
	} else {
		&printcmd("/etc/init.d/qhtlwaterfall","start");
	}

	return;
}
# end startqhtlwaterfall
###############################################################################
# start stopqhtlwaterfall
sub stopqhtlwaterfall {
	if ($sysinit eq "systemd") {
		&printcmd($config{SYSTEMCTL},"stop","qhtlwaterfall.service");
	}
	else {
		&printcmd("/etc/init.d/qhtlwaterfall","stop");
	}

	return;
}
# end stopqhtlwaterfall
###############################################################################
# start restartqhtlwaterfall
sub restartqhtlwaterfall {
	if ($sysinit eq "systemd") {
		&printcmd($config{SYSTEMCTL},"restart","qhtlwaterfall.service");
		&printcmd($config{SYSTEMCTL},"status","qhtlwaterfall.service");
	}
	else {
		&printcmd("/etc/init.d/qhtlwaterfall","restart");
	}

	return;
}
# end restartqhtlwaterfall
###############################################################################
# start restartqhtlwaterfall
sub statusqhtlwaterfall {
	if ($sysinit eq "systemd") {
		&printcmd($config{SYSTEMCTL},"status","qhtlwaterfall.service");
	}
	else {
		&printcmd("/etc/init.d/qhtlwaterfall","status");
	}

	return 0
}
# end restartqhtlwaterfall
###############################################################################
# start printcmd
sub printcmd {
	my @command = @_;

	if ($config{DIRECTADMIN}) {
		my $doublepid = fork;
		if ($doublepid == 0) {
			my ($childin, $childout);
			my $pid = open3($childin, $childout, $childout, @command);
			while (<$childout>) {print $_}
			waitpid ($pid, 0);
			exit;
		}
		waitpid ($doublepid, 0);
	} else {
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, @command);
		while (<$childout>) {print $_}
		waitpid ($pid, 0);
	}
	return;
}
# end printcmd
###############################################################################

1;