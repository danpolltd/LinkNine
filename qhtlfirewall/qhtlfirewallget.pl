#!/usr/bin/perl
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################
use strict;
use warnings;
use diagnostics;

if (my $pid = fork) {
	exit 0;
} elsif (defined($pid)) {
	$pid = $$;
} else {
	die "Error: Unable to fork: $!";
}
chdir("/");
close (STDIN);
close (STDOUT);
close (STDERR);
open STDIN, "<","/dev/null";
open STDOUT, ">","/dev/null";
open STDERR, ">","/dev/null";

$0 = "QhtLink Firewall Version Check";

# Load download servers from /etc/qhtlfirewall/downloadservers with sane defaults
sub load_downloadservers {
	my @defaults = (
		'https://download.qhtlf.danpol.co.uk',
		'https://download2.qhtlf.danpol.co.uk',
	);

	my %seen;
	my @servers;

	my $list = '/etc/qhtlfirewall/downloadservers';
	if (-r $list) {
		if (open my $fh, '<', $list) {
			while (my $line = <$fh>) {
				chomp $line;
				$line =~ s/[\r\n]+$//;             # strip CRLF
				$line =~ s/#.*$//;                   # drop comments
				$line =~ s/^\s+|\s+$//g;            # trim
				next unless length $line;
				# If no scheme provided, assume https
				if ($line !~ m{^https?://}i) {
					$line = 'https://' . $line;
				}
				# Remove trailing slash
				$line =~ s{/+\z}{};
				next if $seen{lc $line}++;
				push @servers, $line;
			}
			close $fh;
		}
	}

	# Fallback to defaults if none loaded
	if (!@servers) {
		for my $d (@defaults) {
			my $s = $d;
			$s =~ s{/+\z}{};
			next if $seen{lc $s}++;
			push @servers, $s;
		}
	}

	return @servers;
}

my @downloadservers = load_downloadservers();

system("mkdir -p /var/lib/qhtlfirewall/");
system("rm -f /var/lib/qhtlfirewall/*.txt /var/lib/qhtlfirewall/*error");

my $cmd;
# Use a consistent User-Agent for outbound requests
my $UA = 'QHTL';
if (-e "/usr/bin/curl") {$cmd = "/usr/bin/curl -A $UA -skLf -m 120 -o"}
elsif (-e "/usr/bin/wget") {$cmd = "/usr/bin/wget --user-agent=$UA -q -T 120 -O"}
else {
	open (my $ERROR, ">", "/var/lib/qhtlfirewall/error");
	print $ERROR "Cannot find /usr/bin/curl or /usr/bin/wget to retrieve product versions\n";
	close ($ERROR);
	exit;
}
my $GET;
if (-e "/usr/bin/GET") {$GET = "/usr/bin/GET -sd -t 120"}

my %versions;
if (-e "/etc/qhtlfirewall/qhtlfirewall.pl") {$versions{"/qhtlfirewall/version.txt"} = "/var/lib/qhtlfirewall/qhtlfirewall.txt"}
if (-e "/etc/qhtlwatcher/qhtlwatcher.pl") {$versions{"/qhtlwatcher/version.txt"} = "/var/lib/qhtlfirewall/qhtlwatcher.txt"}
if (-e "/etc/qhtlmoderator/qhtlmoderator.pl") {$versions{"/qhtlmoderator/version.txt"} = "/var/lib/qhtlfirewall/qhtlmoderator.txt"}
if (-e "/usr/msfe/version.txt") {$versions{"/version.txt"} = "/var/lib/qhtlfirewall/msinstall.txt"}
if (-e "/usr/msfe/msfeversion.txt") {$versions{"/msfeversion.txt"} = "/var/lib/qhtlfirewall/msfe.txt"}

if (scalar(keys %versions) == 0) {
	unlink $0;
	exit;
}

unless ($ARGV[0] eq "--nosleep") {
	system("sleep",int(rand(60 * 60 * 6)));
}
for (my $x = @downloadservers; --$x;) {
		my $y = int(rand($x+1));
		if ($x == $y) {next}
		@downloadservers[$x,$y] = @downloadservers[$y,$x];
}

foreach my $server (@downloadservers) {
	foreach my $version (keys %versions) {
		unless (-e $versions{$version}) {
			if (-e $versions{$version}.".error") {unlink $versions{$version}.".error"}
			my $status = system("$cmd $versions{$version} $server$version");
#			print "$cmd $versions{$version} $server$version\n";
			if ($status) {
				if ($GET ne "") {
					open (my $ERROR, ">", $versions{$version}.".error");
					print $ERROR "$server$version - ";
					close ($ERROR);
					my $GETstatus = system("$GET $server$version >> $versions{$version}".".error");
				} else {
					open (my $ERROR, ">", $versions{$version}.".error");
					print $ERROR "Failed to retrieve latest version from Danpol update server";
					close ($ERROR);
				}
			}
		}
	}
}
