#!/usr/bin/perl
#WHMADDON:qhtlfirewall:QhtLink Firewall
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################
## no critic (RequireUseWarnings, ProhibitExplicitReturnUndef, ProhibitMixedBooleanOperators, RequireBriefOpen)
use strict;
use File::Find;
use Fcntl qw(:DEFAULT :flock);
use Sys::Hostname qw(hostname);
use IPC::Open3;

use lib '/usr/local/qhtlfirewall/lib';
# Defer heavy config/UI module loading; only Slurp is needed early for simple IO helpers
require QhtLink::Slurp;

use lib '/usr/local/cpanel';
# IMPORTANT: Do NOT require cPanel modules here; some environments lack optional deps (e.g., Class::XSAccessor)
# We'll require them after lightweight endpoints are handled.
###############################################################################
# start main

our ($reseller, $script, $images, %rprivs, $myv, %FORM);
# Minimal GET query parser to avoid pulling cPanel deps early
sub _qhtl_parse_get_query {
	my $qs = $ENV{QUERY_STRING} // '';
	my %h;
	for my $pair (split /[&;]/, $qs) {
		next unless length $pair;
		my ($k,$v) = split(/=/, $pair, 2);
		for ($k,$v) {
			$_ = '' unless defined $_;
			s/\+/ /g;
			s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		}
		$h{$k} = $v;
	}
	return %h;
}

%FORM = _qhtl_parse_get_query();
my $is_ajax = 0;
eval {
	my $xrw = lc($ENV{HTTP_X_REQUESTED_WITH} // '');
	if ($xrw eq 'xmlhttprequest' || (defined $FORM{ajax} && $FORM{ajax} =~ /^(?:1|true|yes)$/i)) { $is_ajax = 1; }
	1;
} or do { $is_ajax = 0; };

## Postpone config and regex setup until after lightweight endpoints
# Avoid calling cPanel Rlimit before we ensure cPanel deps are available

# Defensive: If this CGI is fetched as a <script> (or otherwise JS-like) without an action,
# emit a tiny JS no-op. Otherwise, fall through and render the HTML UI. Some environments
# omit Sec-Fetch headers, so default to HTML unless we have strong evidence it's a script.
my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
my $sec_mode = lc($ENV{HTTP_SEC_FETCH_MODE} // '');
my $sec_user = lc($ENV{HTTP_SEC_FETCH_USER} // ''); # '?1' for user navigations
my $accept   = lc($ENV{HTTP_ACCEPT} // '');
if (!defined $FORM{action} || $FORM{action} eq '') {
	# Consider it script-like only if explicitly requested as a script or Accept prefers JS
	my $is_script_like = (
		$sec_dest eq 'script' ||
		$accept =~ /\b(?:application|text)\/(?:x-)?javascript\b/ ||
		$accept =~ /\btext\/ecmascript\b/ ||
		$accept =~ /\bapplication\/ecmascript\b/
	);
	if ($is_script_like) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	# Otherwise, proceed to render HTML normally (no early exit)
}

# Serve wstatus.js via controlled endpoint to guarantee correct MIME and avoid nosniff issues on static paths
if (defined $FORM{action} && $FORM{action} eq 'diag') {
	my $ok = 0;
	my $out = '';
	eval {
		# Simple JSON escaper (sufficient for our values)
		my $esc = sub {
			my ($s) = @_;
			$s = '' unless defined $s;
			$s =~ s/\\/\\\\/g;  # backslashes
			$s =~ s/\"/\\\"/g;  # quotes
			$s =~ s/\r/\\r/g;     # CR
			$s =~ s/\n/\\n/g;     # LF
			$s =~ s/\t/\\t/g;     # TAB
			return $s;
		};
		my $j = '{'
		  . '"version":"' . $esc->($myv) . '",' 
		  . '"is_ajax":' . ($is_ajax ? 1 : 0) . ','
		  . '"sec_fetch":{'
			  . '"dest":"' . $esc->($sec_dest) . '",' 
			  . '"mode":"' . $esc->($sec_mode) . '",' 
			  . '"user":"' . $esc->($sec_user) . '"},'
		  . '"accept":"' . $esc->($accept) . '",' 
		  . '"rule":"noaction => js-noop when (dest==script) OR (not navigate AND Accept not text/html)",' 
		  . '"now":"' . $esc->(scalar localtime()) . '"' 
		  . '}';
		$out = $j;
		$ok = 1;
		1;
	} or do {
		$ok = 0;
		$out = $@ || 'diag failed';
	};
	if ($ok) {
		print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print $out;
	} else {
		print "Content-type: text/plain\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print "diag error: ".$out."\n";
	}
	exit 0;
}
if (defined $FORM{action} && $FORM{action} eq 'widget_js') {
	my %allowed = map { $_ => 1 } qw(
		wignore.js wdirwatch.js wddns.js walerts.js wscanner.js wblocklist.js wusers.js uupdate.js uchange.js triangle.css qhtlrex.js qhtlmpass.js qhtlmshield.js
	);
	my $name = $FORM{name} // ''; 
	$name =~ s/[^a-zA-Z0-9_.-]//g; # sanitize
	if (!$allowed{$name}) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my $ctype = ($name =~ /\.css\z/i) ? 'text/css' : 'application/javascript';
	print "Content-type: $ctype\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	my @paths = (
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/ui/images/$name",
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/$name",
		"/etc/qhtlfirewall/ui/images/$name",
		"/usr/local/qhtlfirewall/ui/images/$name",
	);
	my $done = 0;
	for my $p (@paths) {
		next unless -e $p;
		if (open(my $FH, '<', $p)) {
			local $/ = undef; my $data = <$FH> // ''; close $FH; print $data; $done = 1; last;
		}
	}
	if (!$done) { print ";\n"; }
	exit 0;
}

# Serve wstatus.js via controlled endpoint to guarantee correct MIME and avoid nosniff issues
if (defined $FORM{action} && $FORM{action} eq 'wstatus_js') {
	print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	my @paths = (
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/ui/images/wstatus.js",
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/wstatus.js",
		"/etc/qhtlfirewall/ui/images/wstatus.js",
		"/usr/local/qhtlfirewall/ui/images/wstatus.js",
	);
	my $done = 0;
	for my $p (@paths) {
		next unless -e $p;
		if (open(my $FH, '<', $p)) {
			local $/ = undef; my $data = <$FH> // ''; close $FH; print $data; $done = 1; last;
		}
	}
	if (!$done) { print ";\n"; }
	exit 0;
}

# Serve holiday decoration assets (SVG/CSS) from known locations with strict sanitization
if (defined $FORM{action} && $FORM{action} eq 'holiday_asset') {
	my $name = $FORM{name} // '';
	$name =~ s/[^a-zA-Z0-9_.-]//g; # sanitize
	# Allowlist of files
	my %ok = map { $_ => 1 } qw(pumpkin.svg bat.svg style.css);
	if (!$ok{$name}) {
		print "Content-type: application/octet-stream\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ""; exit 0;
	}
	my $ctype = 'application/octet-stream';
	$ctype = 'image/svg+xml' if $name =~ /\.svg$/i;
	$ctype = 'text/css; charset=UTF-8' if $name =~ /\.css$/i;
	print "Content-type: $ctype\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	my @paths = (
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/ui/images/holiday/$name",
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/holiday/$name",
		"/etc/qhtlfirewall/ui/images/holiday/$name",
		"/usr/local/qhtlfirewall/ui/images/holiday/$name",
	);
	my $done = 0;
	for my $p (@paths) {
		next unless -e $p;
		if (open(my $FH, '<', $p)) { local $/ = undef; my $data = <$FH> // ''; close $FH; print $data; $done = 1; last; }
	}
	if (!$done) { print ""; }
	exit 0;
}


# Serve generic fallback assets (currently the idle content GIF)
if (defined $FORM{action} && $FORM{action} eq 'fallback_asset') {
	my $name = $FORM{name} // '';
	$name =~ s/[^a-zA-Z0-9_.-]//g; # sanitize
	# Allowlist of files
	my %ok = map { $_ => 1 } qw(idle_fallback.gif);
	if (!$ok{$name}) {
		print "Content-type: application/octet-stream\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ""; exit 0;
	}
	my $ctype = 'application/octet-stream';
	$ctype = 'image/gif' if $name =~ /\.gif$/i;
	print "Content-type: $ctype\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	my @paths = (
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/qhtlfirewall/$name",
		"/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/$name",
		"/etc/qhtlfirewall/qhtlfirewall/$name",
		"/usr/local/qhtlfirewall/qhtlfirewall/$name",
	);
	my $done = 0;
	for my $p (@paths) {
		next unless -e $p;
		if (open(my $FH, '<', $p)) { binmode $FH; local $/ = undef; my $data = <$FH> // ''; close $FH; print $data; $done = 1; last; }
	}
	if (!$done) { print ""; }
	exit 0;
}


if (-e "/usr/local/cpanel/bin/register_appconfig") {
	$script = "qhtlfirewall.cgi";
	$images = "qhtlfirewall";
} else {
	$script = "addon_qhtlfirewall.cgi";
	$images = "qhtlfirewall";
}

## Reseller ACL resolution is moved after lightweight endpoints

# Read version non-fatally to avoid breaking lightweight endpoints if the file is missing
$myv = 'unknown';
if (open(my $IN, '<', '/etc/qhtlfirewall/version.txt')) {
	my $line = <$IN>;
	close($IN);
	if (defined $line) {
		chomp $line;
		$myv = $line;
	}
}

# Lightweight JSON status endpoint for sanctioned WHM includes
# Usage: /cgi/qhtlink/qhtlfirewall.cgi?action=status_json
if (defined $FORM{action} && $FORM{action} eq 'status_json') {
	# If this endpoint is accidentally loaded as a <script>, emit a JS no-op to avoid parse errors
	my $sj_sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	# Allow XHR/fetch (Sec-Fetch-Dest usually "empty"); only block when explicitly requested as a script
	if ($sj_sec_dest eq 'script') {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	# Load minimal config in a guarded way to avoid failing the endpoint
	my %cfg = (
		IPTABLES => '/sbin/iptables',
		IPTABLESWAIT => '',
		TESTING => 0,
	);
	eval {
		require QhtLink::Config;
		my $c = QhtLink::Config->loadconfig();
		my %full = $c->config;
		$cfg{IPTABLES}    = $full{IPTABLES}    if defined $full{IPTABLES};
		$cfg{IPTABLESWAIT}= $full{IPTABLESWAIT}if defined $full{IPTABLESWAIT};
		$cfg{TESTING}     = $full{TESTING}     ? 1 : 0;
		1;
	} or do { # fall back to defaults
	};

	my $is_disabled = -e "/etc/qhtlfirewall/qhtlfirewall.disable" ? 1 : 0;
	my $is_test     = $cfg{TESTING} ? 1 : 0;
	# Determine running state of the qhtlwaterfall daemon: PID file, then systemd
	my $run_ok = 0; my $ipt_ok = 0;
	eval {
		my @pidfiles = ('/var/run/qhtlwaterfall.pid','/run/qhtlwaterfall.pid');
		PIDFILE: for my $pidfile (@pidfiles) {
			next unless -r $pidfile;
			if (open(my $PF, '<', $pidfile)) {
				my $pid = <$PF>; close $PF; chomp $pid; $pid =~ s/\D//g;
				if ($pid && -d "/proc/$pid") { $run_ok = 1; last PIDFILE; }
			}
		}
		# As a last resort, consult systemd (non-fatal if unavailable)
		my $systemctl = (-x '/bin/systemctl') ? '/bin/systemctl' : ((-x '/usr/bin/systemctl') ? '/usr/bin/systemctl' : undef);
		if (!$run_ok && !$ipt_ok && $systemctl) {
			my ($cin,$cout);
			my $sp = open3($cin, $cout, $cout, $systemctl,'is-active','qhtlwaterfall.service');
			my @out = <$cout>; waitpid($sp, 0);
			my $ans = lc(join('', @out)); $ans =~ s/\s+//g;
			if ($ans eq 'active') { $run_ok = 1; }
		}
		1;
	} or do { };

	# Optional: keep iptables status for future use, but do NOT use it to infer daemon running
	eval {
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, "$cfg{IPTABLES} $cfg{IPTABLESWAIT} -L LOCALINPUT -n");
		my @iptstatus = <$childout>;
		waitpid($pid, 0);
		chomp @iptstatus;
		if ($iptstatus[0] && $iptstatus[0] =~ /# Warning: iptables-legacy tables present/) { shift @iptstatus }
		$ipt_ok = ($iptstatus[0] && $iptstatus[0] =~ /^Chain LOCALINPUT/) ? 1 : 0;
		1;
	} or do { $ipt_ok = 0; };

	my ($enabled, $running, $class, $text, $status_key);
	if ($is_disabled) {
		# Disabled state
		($enabled, $running, $class, $text, $status_key) = (0, 0, 'danger', 'Disabled', 'disabled_stopped');
	} elsif ($run_ok) {
		# Running
		if ($is_test) {
			($enabled, $running, $class, $text, $status_key) = (1, 1, 'warning', 'Testing', 'enabled_test');
		} else {
			($enabled, $running, $class, $text, $status_key) = (1, 1, 'success', 'Enabled', 'enabled_running');
		}
	} elsif ($is_test) {
		# Testing requested but process not detected
		($enabled, $running, $class, $text, $status_key) = (1, 0, 'warning', 'Testing', 'enabled_test');
	} else {
		# Not running
		($enabled, $running, $class, $text, $status_key) = (1, 0, 'danger', 'Stopped', 'enabled_stopped');
	}

	# Simple JSON response, no external modules required here
	my $json = sprintf(
		'{"enabled":%d,"running":%d,"test_mode":%d,"status":"%s","text":"%s","class":"%s","iptables_ok":%d,"version":"%s"}',
		$enabled, $running, $is_test, $status_key, $text, $class, $ipt_ok, $myv
	);
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\n\r\n";
	print $json;
	exit 0;
}

# Diagnostic endpoint to verify routing, headers, and version on live servers
if (defined $FORM{action} && $FORM{action} eq 'diag') {
	my %info = (
		version     => $myv // 'unknown',
		is_ajax     => $is_ajax ? 1 : 0,
		sec_fetch   => {
			dest => $sec_dest,
			mode => $sec_mode,
			user => $sec_user,
		},
		accept      => $accept,
		script_like_noaction_logic => 'noaction => js-noop when (dest==script) OR (not navigate AND Accept not text/html)',
		now         => scalar localtime(),
	);
	# Render compact JSON without external modules
	my $json = '{'
		. '"version":"'.($info{version} =~ s/"/\\"/gr).'",'
		. '"is_ajax":'.($info{is_ajax} ? 1 : 0).','
		. '"sec_fetch":{'
			. '"dest":"'.($info{sec_fetch}{dest} =~ s/"/\\"/gr).'",' 
			. '"mode":"'.($info{sec_fetch}{mode} =~ s/"/\\"/gr).'",' 
			. '"user":"'.($info{sec_fetch}{user} =~ s/"/\\"/gr).'"},'
		. '"accept":"'.($info{accept} =~ s/"/\\"/gr).'",' 
		. '"rule":"'.$info{script_like_noaction_logic}.'",'
		. '"now":"'.($info{now} =~ s/"/\\"/gr).'"' 
		. '}';
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	print $json;
	exit 0;
}

# Lightweight API to (re)start qhtlwaterfall via qhtlfirewall -q
if (defined $FORM{action} && $FORM{action} eq 'api_restartq') {
	# Prevent browsers from treating this as a script include
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	# Allow XHR/fetch and form POSTs; only block when explicitly loaded as a script
	my $scriptish = ($sec_dest eq 'script');
	if ($scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my $ok = 0; my $err = '';
	eval {
		my $rc = system('/usr/sbin/qhtlfirewall','-q');
		if ($rc == 0) { $ok = 1; } else { $err = 'exec_failed'; }
		1;
	} or do { $err = 'exception'; };
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	if ($ok) { print '{"ok":1}'; } else { print '{"ok":0,"error":"'.$err.'"}'; }
	exit 0;
}

# Lightweight API to start qhtlwaterfall daemon via systemd
if (defined $FORM{action} && $FORM{action} eq 'api_startwf') {
	# Prevent browsers from treating this as a script include
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $scriptish = ($sec_dest eq 'script');
	if ($scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my $ok = 0; my $err = '';
	eval {
		# Prefer systemd
		my $systemctl = (-x '/bin/systemctl') ? '/bin/systemctl' : ((-x '/usr/bin/systemctl') ? '/usr/bin/systemctl' : undef);
		if ($systemctl) {
			my $rc = system($systemctl,'start','qhtlwaterfall.service');
			$ok = ($rc == 0) ? 1 : 0;
			$err = 'systemctl_failed' if !$ok;
		} else {
			# Fallback: attempt to exec the daemon directly in background
			my $pid = fork();
			if (!defined $pid) { $ok = 0; $err = 'fork_failed'; }
			elsif ($pid == 0) { exec('/usr/sbin/qhtlwaterfall'); exit 0; }
			else { $ok = 1; }
		}
		1;
	} or do { $err = 'exception'; };
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	if ($ok) { print '{"ok":1}'; } else { print '{"ok":0,"error":"'.$err.'"}'; }
	exit 0;
}

# Lightweight API to restart qhtlwaterfall daemon via systemd
if (defined $FORM{action} && $FORM{action} eq 'api_restartwf') {
	# Prevent browsers from treating this as a script include
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $scriptish = ($sec_dest eq 'script');
	if ($scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my $ok = 0; my $err = '';
	eval {
		# Prefer systemd restart; otherwise flag + best-effort signal
		my $systemctl = (-x '/bin/systemctl') ? '/bin/systemctl' : ((-x '/usr/bin/systemctl') ? '/usr/bin/systemctl' : undef);
		if ($systemctl) {
			my $rc = system($systemctl,'restart','qhtlwaterfall.service');
			$ok = ($rc == 0) ? 1 : 0;
			$err = 'systemctl_failed' if !$ok;
		} else {
			# Create restart flag for daemon to self-restart if running
			eval { open(my $OUT, '>', '/var/lib/qhtlfirewall/qhtlwaterfall.restart'); close $OUT; 1; };
			# Try to HUP the daemon if PID is known (optional)
			eval {
				my $pid='';
				for my $pf ('/var/run/qhtlwaterfall.pid','/run/qhtlwaterfall.pid') {
					if (-r $pf) { open(my $P,'<',$pf); $pid=<$P>; close $P; chomp $pid; $pid=~s/\D//g; last; }
				}
				if ($pid) { kill 'HUP', $pid; }
				1;
			};
			$ok = 1; # best-effort on non-systemd systems
		}
		1;
	} or do { $err = 'exception'; };
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	if ($ok) { print '{"ok":1}'; } else { print '{"ok":0,"error":"'.$err.'"}'; }
	exit 0;
}

# Lightweight API to stop qhtlwaterfall daemon via systemd (without disabling firewall)
if (defined $FORM{action} && $FORM{action} eq 'api_stopwf') {
	# Prevent browsers from treating this as a script include
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $scriptish = ($sec_dest eq 'script');
	if ($scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my $ok = 0; my $err = '';
	eval {
		my $systemctl = (-x '/bin/systemctl') ? '/bin/systemctl' : ((-x '/usr/bin/systemctl') ? '/usr/bin/systemctl' : undef);
		if ($systemctl) {
			my $rc = system($systemctl,'stop','qhtlwaterfall.service');
			$ok = ($rc == 0) ? 1 : 0;
			$err = 'systemctl_failed' if !$ok;
		} else {
			# Best-effort: try to signal the daemon via PID file
			my $pid='';
			for my $pf ('/var/run/qhtlwaterfall.pid','/run/qhtlwaterfall.pid') {
				if (-r $pf) { open(my $P,'<',$pf); $pid=<$P>; close $P; chomp $pid; $pid=~s/\D//g; last; }
			}
			if ($pid) { eval { kill 'TERM', $pid; 1; }; $ok = 1; } else { $ok = 0; $err = 'no_systemd_no_pid'; }
		}
		1;
	} or do { $err = 'exception'; };
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	if ($ok) { print '{"ok":1}'; } else { print '{"ok":0,"error":"'.$err.'"}'; }
	exit 0;
}

# Lightweight API to completely disable firewall and stop waterfall
if (defined $FORM{action} && $FORM{action} eq 'api_disablewf') {
	# Prevent browsers from treating this as a script include
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $scriptish = ($sec_dest eq 'script');
	if ($scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my $ok = 0; my $err = '';
	eval {
		# First, ask qhtlfirewall to disable itself (creates disable flag and stops rules)
		my $rc1 = system('/usr/sbin/qhtlfirewall','-x');
		# Then, best-effort stop the waterfall service via systemd if present
		my $rc2 = 0; my $systemctl = (-x '/bin/systemctl') ? '/bin/systemctl' : ((-x '/usr/bin/systemctl') ? '/usr/bin/systemctl' : undef);
		if ($systemctl) {
			$rc2 = system($systemctl,'stop','qhtlwaterfall.service');
		}
		# Consider it ok if qhtlfirewall -x succeeded; systemctl stop may be a no-op on oneshot
		if ($rc1 == 0) { $ok = 1; } else { $err = 'qhtlfirewall_disable_failed'; }
		1;
	} or do { $err = 'exception'; };
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	if ($ok) { print '{"ok":1}'; } else { print '{"ok":0,"error":"'.$err.'"}'; }
	exit 0;
}

# Back-compat: handle qhtlwaterfallrestart both for navigation and XHR
if (defined $FORM{action} && $FORM{action} eq 'qhtlwaterfallrestart') {
	my $sec_mode = lc($ENV{HTTP_SEC_FETCH_MODE} // '');
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $is_nav = ($sec_mode eq 'navigate' || $sec_dest eq 'document' || $sec_dest eq 'frame' || $sec_dest eq 'iframe');
	my $systemctl = (-x '/bin/systemctl') ? '/bin/systemctl' : ((-x '/usr/bin/systemctl') ? '/usr/bin/systemctl' : undef);
	my $ok = 0; my $err='';
	eval {
		if ($systemctl) {
			my $rc = system($systemctl,'restart','qhtlwaterfall.service');
			$ok = ($rc == 0) ? 1 : 0;
			$err = 'systemctl_failed' if !$ok;
		} else {
			# Create flag so daemon restarts itself
			eval { open(my $OUT, '>', '/var/lib/qhtlfirewall/qhtlwaterfall.restart'); close $OUT; 1; };
			$ok = 1;
		}
		1;
	} or do { $err = 'exception'; };
	if ($is_nav) {
		print "Content-type: text/html\r\n\r\n";
		print "<div style='padding:10px'><h4>Restart qhtlwaterfall</h4>";
		print $ok ? "<div class='alert alert-success'>Restart issued.</div>" : "<div class='alert alert-danger'>Restart failed ($err)</div>";
	# Legacy Return button removed; navigation can be done via tabs or browser back
	print "</div>";
	} else {
		print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		if ($ok) { print '{"ok":1}'; } else { print '{"ok":0,"error":"'.$err.'"}'; }
	}
	exit 0;
}

# Lightweight JavaScript endpoint to render a header badge without relying on inline JS in templates.
# Usage: /cgi/qhtlink/qhtlfirewall.cgi?action=banner_js (builds an absolute cpsess-aware URL internally)
if (defined $FORM{action} && $FORM{action} eq 'banner_js') {
	# Admin kill-switch to completely disable the WHM badge without reinstall
	if (-e "/etc/qhtlfirewall/disable_whm_badge") {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	# If this endpoint is navigated to as a document, send a JS no-op (do not emit HTML)
	my $bj_sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $bj_mode     = lc($ENV{HTTP_SEC_FETCH_MODE} // '');
	if ($bj_mode eq 'navigate' || $bj_sec_dest eq 'document' || $bj_sec_dest eq 'iframe' || $bj_sec_dest eq 'frame') {
	    print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	    print ";\n";
	    exit 0;
	}
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
				print <<'JS';
(function(){
  // Global one-time loader guard to avoid multiple executions from multiple include points
  if (window.__QHTLFW_INIT__) { return; }
  window.__QHTLFW_INIT__ = true;

						function onReady(fn){
							if(document.readyState!=='loading'){ fn(); }
							else {
								var handler = function(){ document.removeEventListener('DOMContentLoaded', handler); fn(); };
								document.addEventListener('DOMContentLoaded', handler, false);
							}
						}

						onReady(function(){
						// Don't inject on our own firewall UI page to avoid doubling there
						var path = String(location.pathname || '');
						var href = path + String(location.search || '');
						try {
							if (href.indexOf('/qhtlfirewall.cgi') !== -1) { return; }
						} catch(_) {}
			// Run only when a cpsess token is present (login pages won't have it)

	function cps(){ try { var p = String(location.pathname||''); var i = p.indexOf('/cpsess'); if (i === -1) return ''; var j = p.indexOf('/', i+8); return (j === -1) ? p.substring(i) : p.substring(i, j); } catch(_) { return ''; } }
		function origin(){ return (location && (location.origin || (location.protocol+'//'+location.host))) || ''; }
		var token = cps();
		if (!token) { return; } // avoid CSRF/login redirects that return HTML
		if (!window.fetch) { return; }

				var lastData = null;
				function getJSON(url, done){
					// Try fetch with credentials: include first
					if (window.fetch) {
						var controller = (typeof AbortController!=='undefined') ? new AbortController() : null;
						var to = controller ? setTimeout(function(){ if (controller && typeof controller.abort==='function') { controller.abort(); } }, 2500) : null;
						var opts = { credentials: 'include' };
						if (controller) opts.signal = controller.signal;
						fetch(url, opts).then(function(r){ return (r && r.ok) ? r.json() : null; })
						.then(function(data){ if (to) clearTimeout(to); done(data||null); })
						.catch(function(){ tryXHR(url, done); });
					} else {
						tryXHR(url, done);
					}
				}
				function tryXHR(url, done){
					try {
						var xhr = new XMLHttpRequest();
						xhr.open('GET', url, true);
						xhr.withCredentials = true;
						xhr.onreadystatechange = function(){
							if (xhr.readyState === 4){
								if (xhr.status >= 200 && xhr.status < 300){
									try { done(JSON.parse(xhr.responseText)); } catch(e){ done(null); }
								} else { done(null); }
							}
						};
						xhr.send(null);
					} catch(e){ done(null); }
				}
				// Fire the request immediately; do not wait for header to exist
				(function(){
					var url = origin()+token+'/cgi/qhtlink/qhtlfirewall.cgi?action=status_json';
					getJSON(url, function(data){
						lastData = data;
						try { tryInject(); } catch(e){}
					});
				})();

				function computeStyle(data){
					var cls = (data && data['class']) || 'default';
					var txt = (data && data['text']) || 'Firewall';
					// Bubble-style radial gradient palettes by state
					var palette = {
						 success: { grad: 'radial-gradient(circle at 30% 30%, #b9f6ca 0%, #66e08a 45%, #34a853 80%)', border: '#2f8f49', glow: 'rgba(76,175,80,0.20)' },
						 warning: { grad: 'radial-gradient(circle at 30% 30%, #ffe6a1 0%, #ffc766 45%, #f0ad4e 80%)', border: '#d69339', glow: 'rgba(240,173,78,0.20)' },
						 danger:  { grad: 'radial-gradient(circle at 30% 30%, #ffb3ad 0%, #ff6f69 45%, #d9534f 80%)', border: '#b94441', glow: 'rgba(217,83,79,0.20)' },
						 default: { grad: 'radial-gradient(circle at 30% 30%, #e0e0e0 0%, #bdbdbd 45%, #757575 80%)', border: '#616161', glow: 'rgba(117,117,117,0.20)' }
					};
					var p = palette[cls] || palette.default;
					return {bg:p.grad, border:p.border, glow:p.glow, txt:txt};
				}

				function tryInject(){
					// Do not inject until we have real data to avoid gray placeholder
					if (!lastData) return false;
					var stats = document.querySelector('cp-whm-header-stats-control');
					if (!stats || !stats.shadowRoot) return false;
					var host = stats.shadowRoot.querySelector('.header-stats, header, div');
					if (!host) return false;
					// Ensure a scoped style inside the shadow root for bubble highlight and layout
					(function(){
					  try {
					    var styleEl = stats.shadowRoot.getElementById('qhtlfw-bubble-style');
					    if (!styleEl) {
					      styleEl = document.createElement('style');
					      styleEl.id = 'qhtlfw-bubble-style';
					      styleEl.textContent = [
					        '#qhtlfw-header-badge{ position:relative; display:inline-flex; align-items:center; justify-content:center; text-shadow:0 1px 2px rgba(0,0,0,0.25); }',
					        '#qhtlfw-header-badge:before{ content:\'\'; position:absolute; top:4px; left:10px; right:10px; height:40%; border-radius:999px; background:linear-gradient(to bottom, rgba(255,255,255,0.55), rgba(255,255,255,0)); pointer-events:none; }'
					      ].join('\n');
					      stats.shadowRoot.appendChild(styleEl);
					    }
					  } catch(_) {}
					})();
					var sty = computeStyle(lastData);
					var existing = stats.shadowRoot.getElementById('qhtlfw-header-badge');
					if (existing) {
						// existing is the inner span; update its style/text and bubble visuals
						existing.style.background = sty.bg;
						existing.style.border = '1px solid '+(sty.border||'#616161');
						existing.style.boxShadow = 'inset 0 2px 6px rgba(255,255,255,0.35), 0 6px 14px '+(sty.glow||'rgba(0,0,0,0.15)');
						existing.textContent = sty.txt;
						existing.style.borderRadius = '999px';
						// Keep compact badge without forcing font size or extra margins to avoid header shrink
						existing.style.padding = '4px 8px';
						existing.style.minWidth = '67px';
						existing.style.display = 'inline-flex';
						existing.style.alignItems = 'center';
						existing.style.justifyContent = 'center';
						return true;
					}
					// Build clickable link to the Firewall UI (cpsess-aware)
					var a = document.createElement('a');
					a.href = origin()+token+'/cgi/qhtlink/qhtlfirewall.cgi';
					a.target = '_self';
					a.setAttribute('aria-label','Open QhtLink Firewall');
					a.style.textDecoration = 'none';
					// Avoid margins that could influence header layout sizing
					// Inner badge span for color/status
					var span = document.createElement('span');
					span.id = 'qhtlfw-header-badge';
					// Scale down ~30% for WHM header badge
					span.style.padding = '4px 8px';
					span.style.borderRadius = '999px';
					span.style.color = '#fff';
					span.style.background = sty.bg;
					span.style.border = '1px solid '+(sty.border||'#616161');
					span.style.cursor = 'pointer';
					// inset highlight + outer glow for bubble feel
					span.style.boxShadow = 'inset 0 2px 6px rgba(255,255,255,0.35), 0 6px 14px '+(sty.glow||'rgba(0,0,0,0.15)');
					span.style.minWidth = '67px';
					span.style.display = 'inline-flex';
					span.style.alignItems = 'center';
					span.style.justifyContent = 'center';
					span.style.textShadow = '0 1px 2px rgba(0,0,0,0.25)';
					span.textContent = sty.txt;
					a.appendChild(span);
					host.appendChild(a);
					return true;
				}

				// Retry header injection for up to ~6 seconds
				var attempts = 0, maxAttempts = 30; // 30 * 200ms = 6000ms
				var iv = setInterval(function(){
					attempts++;
					if (tryInject() || attempts >= maxAttempts) { clearInterval(iv); }
				}, 200);
	});
})();
JS
		;
		exit 0;
}

# Lightweight JSON for Watcher log list (avoids template capture)
if (defined $FORM{action} && $FORM{action} eq 'watcher_meta_logs') {
	eval {
		my @data = ();
		# Safely read syslogs file
		if (-r '/etc/qhtlfirewall/qhtlfirewall.syslogs') {
			open(my $IN, '<', '/etc/qhtlfirewall/qhtlfirewall.syslogs');
			@data = <$IN>; close $IN;
		}
		# Expand Include lines
		my @expanded = ();
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my $inc = $1; $inc =~ s/[\r\n]+$//;
				if (-r $inc) { eval { open(my $A,'<',$inc); my @x=<$A>; close $A; push @expanded, @x; 1; }; }
			} else { push @expanded, $line; }
		}
		@data = sort @expanded;
		my @opts = (); my $cnt=0; my $default = '/var/log/qhtlwaterfall.log';
		foreach my $file (@data) {
			$file =~ s/[\r\n]+$//; next if $file eq '';
			next if $file =~ /^\s*#/ || $file =~ /\bInclude\b/;
			my @globfiles = ($file =~ /[\*\?\[]/) ? glob($file) : ($file);
			foreach my $gf (@globfiles) {
				if (-f $gf) {
					my $size = (stat($gf))[7]; $size = defined $size ? int($size/1024) : 0;
					my $sel = ($gf eq $default) ? 1 : 0;
					$gf =~ s/"/\\"/g; # escape quotes for JSON label
					push @opts, { value => $cnt, label => "$gf ($size kb)", selected => $sel };
					$cnt++;
				}
			}
		}
		# Emit JSON array
		print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		my @parts = map { '{"value":'.($_->{value}+0).',"label":"'.$_->{label}.'","selected":'.(($_->{selected})?1:0).'}' } @opts;
		print '['.join(',', @parts).']';
	};
	exit 0;
}

# Lightweight endpoint to expose the upgrade log for AJAX polling
if (defined $FORM{action} && $FORM{action} eq 'upgrade_log') {
	my $ulog = "/var/log/qhtlfirewall-ui-upgrade.log";
	# If this endpoint is accidentally loaded as a <script>, emit a JS no-op
	my $ul_sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	if ($ul_sec_dest eq 'script') {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	my ($data, $len, $done) = ('', 0, 0);
	if (open(my $UIN, '<', $ulog)) {
		local $/ = undef; $data = <$UIN> // '';
		close $UIN;
		$len = length($data);
		# Consider upgrade finished if the log contains an "All done" marker
		$done = ($data =~ /\bAll done\b|\.\.\.All done/i) ? 1 : 0;
	} else {
		$data = '';
		$len = 0;
		$done = 0;
	}
	# Emit verification and progress hint headers
	print "Content-type: text/plain; charset=UTF-8\r\nX-QHTL-ULOG: 1\r\nX-QHTL-ULOG-LEN: $len\r\nX-QHTL-ULOG-DONE: $done\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	print $data;
	exit 0;
}

# API endpoint to start the upgrade in the background (no navigation)
if (defined $FORM{action} && $FORM{action} eq 'api_start_upgrade') {
	my $ulog = "/var/log/qhtlfirewall-ui-upgrade.log";
	my $pfile = "/var/lib/qhtlfirewall/ui-postinstall.txt";
	# If accidentally loaded as a <script>, emit a JS no-op
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	if ($sec_dest eq 'script') {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
	# Pre-create/clear the log with a header
	eval {
		if (open(my $LF, '>', $ulog)) {
			my $now = scalar localtime();
			print $LF "=== QhtLink Firewall upgrade started at $now ===\n";
			close $LF;
		}
		1;
	};
	# Ensure progress file directory exists and mark starting
	eval {
		my $dir = '/var/lib/qhtlfirewall';
		if (!-d $dir) { mkdir $dir, 0755; }
		if (open(my $PF, '>', $pfile)) {
			my $now = scalar localtime();
			print $PF "status:starting time=$now\n";
			close $PF;
		}
		1;
	} or do { };
	# Launch upgrade in background
	my $nohup = (-x '/usr/bin/nohup') ? '/usr/bin/nohup' : ((-x '/bin/nohup') ? '/bin/nohup' : '');
	my $shell = (-x '/bin/sh') ? '/bin/sh' : '/usr/bin/sh';
	my $cmd;
	my $inner = "echo status:running time=\$(date -Is) > $pfile; /usr/sbin/qhtlfirewall -uf >> $ulog 2>&1; ec=\$?; echo status:done exit=\$ec time=\$(date -Is) > $pfile";
	if ($nohup ne '') {
		$cmd = "$nohup $shell -c '$inner' >> $ulog 2>&1 &";
	} else {
		$cmd = "($inner) >> $ulog 2>&1 &";
	}
	system($cmd);
	# Respond JSON
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	print '{"ok":1}';
	exit 0;
}

# API endpoint to report upgrade progress using the progress file and log
if (defined $FORM{action} && $FORM{action} eq 'upgrade_progress') {
	my $pfile = "/var/lib/qhtlfirewall/ui-postinstall.txt";
	my $ulog  = "/var/log/qhtlfirewall-ui-upgrade.log";
	my ($status, $exit, $time, $pct) = ('unknown', -1, '', -1);
	if (-r $pfile) {
		if (open(my $PF, '<', $pfile)) {
			my @lines = <$PF>; close $PF;
			my $last = pop @lines; $last = '' unless defined $last; chomp $last;
			if ($last =~ /status:(\w+)/) { $status = $1; }
			if ($last =~ /exit=(\-?\d+)/) { $exit = $1+0; }
			if ($last =~ /time=([^\s]+)/) { $time = $1; }
			if ($last =~ /pct=(\d{1,3})/) { $pct = $1+0; $pct = 100 if $pct>100; }
		}
	}
	my $done = 0;
	if ($status eq 'done') { $done = 1; }
	else {
		# Fallback to log marker if progress file missing
		if (open(my $UL, '<', $ulog)) {
			local $/ = undef; my $data = <$UL>; close $UL; $done = ($data =~ /\bAll done\b|\.\.\.All done/i) ? 1 : 0;
		}
	}
	# Emit JSON
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	my $json = '{'
	  . '"ok":1,'
	  . '"status":"'.$status.'",'
	  . '"done":'.($done?1:0).','
	  . '"exit":'.$exit.','
	  . '"time":"'.$time.'",'
	  . '"pct":'.$pct
	  . '}';
	print $json;
	exit 0;
}

# API endpoint to manually check for the latest available version (used by the Upgrade tab/button)
if (defined $FORM{action} && $FORM{action} eq 'api_manual_check') {
	# If accidentally loaded as a <script>, emit a JS no-op
	my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	if ($sec_dest eq 'script') {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}

	# Helper: semantic version compare (returns 1 if a>b, -1 if a<b, 0 if equal)
	my $ver_cmp = sub {
		my ($a,$b) = @_;
		my @a = split /\./, ($a // '');
		my @b = split /\./, ($b // '');
		for (my $i=0; $i < @a || $i < @b; $i++) {
			my $ai = $i < @a ? int($a[$i]||0) : 0;
			my $bi = $i < @b ? int($b[$i]||0) : 0;
			return 1 if $ai > $bi;
			return -1 if $ai < $bi;
		}
		return 0;
	};

	# Load minimal config safely
	my %cfg = (
		URLGET         => 1,                    # prefer HTTP::Tiny
		URLPROXY       => '',
		DOWNLOADSERVER => '',
	);
	my $cleanreg;
	eval {
		require QhtLink::Config;
		require QhtLink::Slurp;
		my $c = QhtLink::Config->loadconfig();
		my %full = $c->config;
		$cfg{URLGET}         = $full{URLGET}         if defined $full{URLGET};
		$cfg{URLPROXY}       = $full{URLPROXY}       if defined $full{URLPROXY};
		$cfg{DOWNLOADSERVER} = $full{DOWNLOADSERVER} if defined $full{DOWNLOADSERVER};
		$cleanreg = QhtLink::Slurp->cleanreg;
		1;
	} or do { };

	# Initialize HTTP client
	my $urlget;
	my $ua_ok = eval { require QhtLink::URLGet; 1 } ? 1 : 0;
	if ($ua_ok) {
		$urlget = QhtLink::URLGet->new($cfg{URLGET}, "qhtlfirewall/$myv", $cfg{URLPROXY});
		if (!defined $urlget) {
			# Fallback to HTTP::Tiny mode
			$cfg{URLGET} = 1;
			$urlget = QhtLink::URLGet->new($cfg{URLGET}, "qhtlfirewall/$myv", $cfg{URLPROXY});
		}
	}

	my $ok = 0; my $err = '';
	my $avail = ''; my $src = '';
	my $curr = $myv // '';

	if (!$ua_ok || !defined $urlget) {
		$err = 'HTTP client not initialized';
	} else {
		eval {
			# Build mirrors list from file and config
			my %seen; my @mirrors;
			my $list = '/etc/qhtlfirewall/downloadservers';
			if (eval { -r $list }) {
				eval {
					require QhtLink::Slurp;
					my @lines = QhtLink::Slurp::slurp($list);
					foreach my $line (@lines) {
						$line =~ s/$cleanreg//g if defined $cleanreg;
						$line =~ s/#.*$//; $line =~ s/^\s+|\s+$//g;
						next unless length $line;
						$line =~ s{^https?://}{}i;   # drop scheme
						$line =~ s{/.*$}{};          # drop path
						$line =~ s{/+\z}{};         # drop trailing slash
						next if $seen{lc $line}++;
						push @mirrors, $line;
					}
					1;
				} or do { };
			}
			if (defined $cfg{DOWNLOADSERVER} && $cfg{DOWNLOADSERVER} ne '') {
				my $c = $cfg{DOWNLOADSERVER};
				$c =~ s{^https?://}{}i; $c =~ s{/.*$}{}; $c =~ s{/+\z}{};
				if (!$seen{lc $c}++) { unshift @mirrors, $c; }
			}
			# Fallback legacy host only if none explicitly provided
			push @mirrors, 'update.qhtl.link' if !@mirrors;

			# Shuffle for resilience
			for (my $x = @mirrors; --$x;) {
				my $y = int(rand($x+1));
				next if $x == $y;
				@mirrors[$x,$y] = @mirrors[$y,$x];
			}

			my $last_err = '';
			MIRROR: for my $host (@mirrors) {
				for my $scheme ('https','http') {
					my $url = "$scheme://$host/qhtlfirewall/version.txt";
					my ($rc, $data) = $urlget->urlget($url);
					if (!$rc && defined $data) {
						# Strip BOM and parse for a version token
						$data =~ s/^\xEF\xBB\xBF//;
						my $found = '';
						for my $line (split /\r?\n/, $data) {
							$line =~ s/^\s+|\s+$//g; next unless length $line;
							if ($line =~ /^v?(\d+(?:\.\d+){1,3})\b/i) { $found = $1; last; }
						}
						if (!$found && $data =~ /^\s*v?(\d+(?:\.\d+){1,3})\s*$/m) { $found = $1; }
						if ($found) { $avail = $found; $src = $host; }
					}
					if ($avail) { last MIRROR; }
					else {
						my $why = defined $data ? $data : '';
						$why =~ s/[\r\n]+/ /g; $why =~ s/\s{2,}/ /g; $why = substr($why,0,180);
						$last_err = ($why ne '' ? $why : 'Unknown error');
					}
				}
			}
			if (!$avail) { $err = 'Version check failed: '.($last_err||''); }
			1;
		} or do { $err = 'Version check failed'; };
	}

	my $need_up = 0;
	if ($avail && $curr) {
		# Remove leading v's if present
		(my $a = $avail) =~ s/^v//i; (my $c = $curr) =~ s/^v//i;
		$need_up = ($ver_cmp->($a, $c) == 1) ? 1 : 0;
	}

	my $okflag = ($avail ne '' && $err eq '') ? 1 : 0;
	# Emit JSON
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
	my $json = '{'
		. '"ok":'.($okflag?1:0).','
		. '"current":"'.($curr//'') .'",'
		. '"available":"'.($avail//'').'",'
		. '"upgrade":'.($need_up?1:0).','
		. '"source":"'.($src//'').'",'
		. '"error":"'.($err//'').'"'
		. '}';
	print $json;
	exit 0;
}

	# Minimal HTML banner for iframe embedding (no JS required in parent)
	if (defined $FORM{action} && $FORM{action} eq 'banner_frame') {
		# If loaded as a <script>, emit a JS no-op instead of HTML to prevent parse errors
		my $bf_sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
		my $bf_accept   = lc($ENV{HTTP_ACCEPT} // '');
		if ($bf_sec_dest eq 'script' || $bf_accept =~ /(?:application|text)\/javascript/) {
			print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
			print ";\n";
			exit 0;
		}
		# Load minimal config in a guarded way to avoid failing the endpoint
		my %cfg = (
			IPTABLES => '/sbin/iptables',
			IPTABLESWAIT => '',
			TESTING => 0,
		);
		eval {
			require QhtLink::Config;
			my $c = QhtLink::Config->loadconfig();
			my %full = $c->config;
			$cfg{IPTABLES}    = $full{IPTABLES}    if defined $full{IPTABLES};
			$cfg{IPTABLESWAIT}= $full{IPTABLESWAIT}if defined $full{IPTABLESWAIT};
			$cfg{TESTING}     = $full{TESTING}     ? 1 : 0;
			1;
		} or do { # fall back to defaults
		};

		my $is_disabled = -e "/etc/qhtlfirewall/qhtlfirewall.disable" ? 1 : 0;
		my $is_test     = $cfg{TESTING} ? 1 : 0;
		my $ipt_ok      = 0;
		eval {
			my ($childin, $childout);
			my $pid = open3($childin, $childout, $childout, "$cfg{IPTABLES} $cfg{IPTABLESWAIT} -L LOCALINPUT -n");
			my @iptstatus = <$childout>;
			waitpid($pid, 0);
			chomp @iptstatus;
			if ($iptstatus[0] && $iptstatus[0] =~ /# Warning: iptables-legacy tables present/) { shift @iptstatus }
			$ipt_ok = ($iptstatus[0] && $iptstatus[0] =~ /^Chain LOCALINPUT/) ? 1 : 0;
		};
		my ($cls, $txt);
		if ($is_disabled) {
			($cls, $txt) = ('danger', 'Disabled');
		} elsif (!$ipt_ok) {
			($cls, $txt) = ('danger', 'Stopped');
		} elsif ($is_test) {
			($cls, $txt) = ('warning', 'Testing');
		} else {
			($cls, $txt) = ('success', 'Enabled');
		}
		print "Content-type: text/html\r\n";
		print "X-Content-Type-Options: nosniff\r\n";
		print "X-Frame-Options: SAMEORIGIN\r\n";
		print "Content-Security-Policy: frame-ancestors 'self';\r\n\r\n";
		print "<!doctype html><html><head><meta charset=\"utf-8\">\n";
		print "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'\">\n";
		# Bubble-style badge using radial gradient and pill shape in the iframe fallback
		print "<style>html,body{margin:0;padding:0;background:transparent} .bubble{display:inline-block;font:12px/1.2 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#fff;border-radius:999px;padding:6px 12px;border:1px solid transparent;min-width:96px;box-shadow:inset 0 2px 6px rgba(255,255,255,0.35),0 6px 14px rgba(0,0,0,0.15);white-space:nowrap} .bubble-success{background:radial-gradient(circle at 30% 30%, #b9f6ca 0%, #66e08a 45%, #34a853 80%);border-color:#2f8f49} .bubble-warning{background:radial-gradient(circle at 30% 30%, #ffe6a1 0%, #ffc766 45%, #f0ad4e 80%);border-color:#d69339} .bubble-danger{background:radial-gradient(circle at 30% 30%, #ffb3ad 0%, #ff6f69 45%, #d9534f 80%);border-color:#b94441}</style>\n";
	my $bcls = ($cls eq 'success') ? 'bubble-success' : ($cls eq 'warning' ? 'bubble-warning' : 'bubble-danger');
	print "</head><body style=\"margin:0\"><span class=\"bubble $bcls\">$txt</span></body></html>";
		exit 0;
	}

	## From here onwards, load full config and regex helpers, then resolve reseller ACLs
	# Now that lightweight endpoints are done, it's safe to pull in cPanel modules
	require Cpanel::Form;
	require Cpanel::Config;
	require Whostmgr::ACLS;
	require Cpanel::Rlimit;
	require Cpanel::Template;
	require Cpanel::Version::Tiny;

	# Parse full form (including POST) with cPanel's parser when available
	eval { %FORM = Cpanel::Form::parseform(); 1; };

	Cpanel::Rlimit::set_rlimit_to_infinity();

	require QhtLink::Config;
	my $config = QhtLink::Config->loadconfig();
	my %config = $config->config;
	my $slurpreg = QhtLink::Slurp->slurpreg;
	my $cleanreg = QhtLink::Slurp->cleanreg;

Whostmgr::ACLS::init_acls();

foreach my $line (QhtLink::Slurp::slurp("/etc/qhtlfirewall/qhtlfirewall.resellers")) {
	$line =~ s/$cleanreg//g;
	my ($user,$alert,$privs) = split(/\:/,$line);
	$privs =~ s/\s//g;
	foreach my $priv (split(/\,/, $privs)) {
		$rprivs{$user}{$priv} = 1;
	}
	$rprivs{$user}{ALERT} = $alert;
}

$reseller = 0;
if (!Whostmgr::ACLS::hasroot()) {
	if ($rprivs{$ENV{REMOTE_USER}}{USE}) {
		$reseller = 1;
	} else {
		print "Content-type: text/html\r\n\r\n";
		print "You do not have access to this feature\n";
		exit();
	}
}

my $bootstrapcss = "<link rel='stylesheet' href='$images/bootstrap/css/bootstrap.min.css'>";
my $jqueryjs = "<script src='$images/jquery.min.js'></script>";
my $bootstrapjs = "<script src='$images/bootstrap/js/bootstrap.min.js'></script>";

my @header;
my @footer;
my $htmltag = "data-post='$FORM{action}'";
if (-e "/etc/qhtlfirewall/qhtlfirewall.header") {
	open (my $HEADER, "<", "/etc/qhtlfirewall/qhtlfirewall.header");
	flock ($HEADER, LOCK_SH);
	@header = <$HEADER>;
	close ($HEADER);
}
if (-e "/etc/qhtlfirewall/qhtlfirewall.footer") {
	open (my $FOOTER, "<", "/etc/qhtlfirewall/qhtlfirewall.footer");
	flock ($FOOTER, LOCK_SH);
	@footer = <$FOOTER>;
	close ($FOOTER);
}
unless ($config{STYLE_CUSTOM}) {
	undef @header;
	undef @footer;
	$htmltag = "";
}

# Replace any VERSION/placeholder tokens in header/footer with installed version
for my $frag (\@header, \@footer) {
    next unless @$frag;
	for (@$frag) {
        s/\bVERSION\b/$myv/g;
        s/\bv\.?VERSION\b/v$myv/gi;
        s/\bqhtlfirewall_version\b/$myv/gi;
	# Sanitize legacy script includes that point to our CGI without an action
	# Convert .../qhtlink/qhtlfirewall.cgi to .../qhtlink/qhtlfirewall.cgi?action=banner_js
	s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['"]) }{$1$2?action=banner_js$3 }ig;
	# Also handle cases without assuming a trailing space after the closing quote
	s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['"]) }{$1$2?action=banner_js$3 }ig;
	# Robust form without requiring whitespace after the attribute
	s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['"]) }{$1$2?action=banner_js$3}ig;
	# If a query exists but no action= present, insert action=banner_js at the start of the query string
	s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)\?(?![^'"\>]*?action=)([^'"\>]*)(['"]) }{$1$2?action=banner_js&$3$4 }ig;
	s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)\?(?![^'"\>]*?action=)([^'"\>]*)(['"]) }{$1$2?action=banner_js&$3$4}ig;
    }
}

# If footer contains legacy Danpol branding or bare version text, replace it with a compact version link
if (@footer) {
	my $ft = join('', @footer);
	# Remove just 'Danpol Limited' from any footer lines, keep everything else (e.g., year and name)
	$ft =~ s/Danpol\s+Limited\s*\(?\)?//ig;
	# Remove stray commas left behind like ", ," or preceding/trailing commas next to parentheses
	$ft =~ s/\(\s*,\s*\)/()/g;          # remove lone comma inside parentheses
	$ft =~ s/\s*,\s*\)/)/g;              # comma before )
	$ft =~ s/\(\s*,\s*/(/g;              # comma after (
	$ft =~ s/\s+,\s+,\s+/, /g;           # double commas
	$ft =~ s/\s+,\s+/, /g;                # normalize commas
	$ft =~ s/\s{2,}/ /g;                   # collapse multiple spaces
	$ft =~ s/^\s+|\s+$//g;                # trim
	# If legacy right-side 'qhtlfirewall: vX' exists, strip it; we will add our own link consistently
	$ft =~ s/qhtlfirewall:\s*v\S+//ig;
	# If after sanitization left side is empty or missing the author, force the exact text requested
	my $left_text = $ft;
	if (!defined $left_text || $left_text !~ /\S/) {
		$left_text = "©2025 (Daniel Nowakowski)";
	}
	# Recompose sanitized footer and append our right-aligned version link
	my $right = "<div style='font-size:12px;'><a href='$script?action=readme' target='_self' style='text-decoration:none;'>Qht Link Firewall v$myv</a></div>";
	my $container_start = "<div style='display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:8px;'>";
	my $container_end = "</div>\n";
	@footer = ($container_start, "<div style='font-size:12px;'>$left_text</div>", $right, $container_end);
}

my $thisapp = "qhtlfirewall";
my $reregister;
my $modalstyle;
if ($Cpanel::Version::Tiny::major_version >= 65) {
	if (-e "/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/${thisapp}/${thisapp}.conf") {
		sysopen (my $CONF, "/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/${thisapp}/${thisapp}.conf", O_RDWR | O_CREAT);
		flock ($CONF, LOCK_EX);
		my @confdata = <$CONF>;
		chomp @confdata;
		for (0..scalar(@confdata)) {
			if ($confdata[$_] =~ /^target=mainFrame/) {
				$confdata[$_] = "target=_self";
				$reregister = 1;
			}
		}
		if ($reregister) {
			seek ($CONF, 0, 0);
			truncate ($CONF, 0);
			foreach (@confdata) {
				print $CONF "$_\n";
			}
			&printcmd("/usr/local/cpanel/bin/register_appconfig","/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/${thisapp}/${thisapp}.conf");
			$reregister = "<div class='bs-callout bs-callout-info'><h4>Updated application. The next time you login to WHM this will open within the native WHM main window instead of launching a separate window</h4></div>\n";
		}
		close ($CONF);
	}
}

# If an action other than our lightweight endpoints is being requested in a true script-like context,
# emit a JS no-op to prevent browsers from parsing full HTML as JavaScript. Do not block XHR/fetch.
if (defined $FORM{action} && $FORM{action} ne '' && $FORM{action} !~ /^(?:status_json|banner_js|banner_frame|diag)$/) {
	my $g_sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $g_is_script_dest = ($g_sec_dest eq 'script');
	my $g_sec_mode = lc($ENV{HTTP_SEC_FETCH_MODE} // '');
	my $g_accept   = lc($ENV{HTTP_ACCEPT} // '');
	my $g_is_nav   = ($g_sec_mode eq 'navigate' || $g_sec_dest eq 'document' || $g_sec_dest eq 'frame' || $g_sec_dest eq 'iframe');
	my $g_accepts_html = ($g_accept =~ /\btext\/html\b/);
    # Treat explicit XHR/fetch or ajax=1 as safe (not script-like)
    my $g_is_ajax_hdr = (lc($ENV{HTTP_X_REQUESTED_WITH} // '') eq 'xmlhttprequest');
    my $g_has_ajax_qs = (defined $FORM{ajax} && $FORM{ajax} =~ /^(?:1|true|yes)$/i) ? 1 : 0;
	# Block when explicitly a script destination, OR when not a navigation and Accept does not include text/html
	my $g_scriptish = ($g_is_script_dest || (!$g_is_nav && !$g_accepts_html)) ? 1 : 0;
    if ($g_is_ajax_hdr || $g_has_ajax_qs) { $g_scriptish = 0; }
	if ($g_scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
}

print "Content-type: text/html\r\nX-Content-Type-Options: nosniff\r\n\r\n";
#if ($Cpanel::Version::Tiny::major_version < 65) {$modalstyle = "style='top:120px'"}

my $templatehtml;
my $SCRIPTOUT;
my $skip_capture = (
	$FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd" or $FORM{action} eq "viewlist" or $FORM{action} eq "editlist" or $FORM{action} eq "savelist"
);
# For AJAX requests, do not skip capture—always capture so we can return bare content
$skip_capture = 0 if $is_ajax;
unless ($skip_capture) {
#	open(STDERR, ">&STDOUT");
	open ($SCRIPTOUT, '>', \$templatehtml);
	select $SCRIPTOUT;

	# Provide a direct modal opener for Watcher without fallback navigation
	if (!$is_ajax) {
print <<HTML_SMART_WRAPPER;
<script>
(function(){
	window.__qhtlOpenWatcherSmart = function(){
		if (window.__qhtlQuickViewShim && typeof window.__qhtlRealOpenWatcher==='function') { try{ window.__qhtlRealOpenWatcher(); } catch(e){} return false; }
		var attempts = 0, iv = setInterval(function(){
			attempts++;
			if (window.__qhtlQuickViewShim && typeof window.__qhtlRealOpenWatcher==='function'){
				clearInterval(iv);
				try{ window.__qhtlRealOpenWatcher(); } catch(e){}
			} else if (attempts >= 30) {
				clearInterval(iv);
			}
		}, 100);
		return false;
	};

		// Define a minimal Quick View modal shim early so Watcher can open without navigation
	if (!window.__qhtlQuickViewShim) {
		window.__qhtlQuickViewShim = true;
		function ensureQuickViewModal(){
			var modal = document.getElementById('quickViewModalShim');
			if (modal) return modal;
			modal = document.createElement('div');
			modal.id = 'quickViewModalShim';
			modal.setAttribute('role','dialog');
			var parent = document.querySelector('.qhtl-bubble-bg') || document.body;
			var inScoped = (parent.classList && parent.classList.contains('qhtl-bubble-bg'));
			if (inScoped) {
				// Anchor to container so it scrolls with the page content
				modal.style.position='absolute'; modal.style.left='0'; modal.style.top='0'; modal.style.right='0'; modal.style.bottom='0';
			} else {
				modal.style.position='fixed'; modal.style.inset='0';
			}
			modal.style.background='rgba(0,0,0,0.5)'; modal.style.display='none'; modal.style.zIndex='9999';
			var dialog = document.createElement('div');
			dialog.style.width='660px'; dialog.style.maxWidth='calc(100% - 40px)'; dialog.style.height='500px'; dialog.style.background='linear-gradient(180deg, #f7fafc 0%, #ffffff 40%, #f7fafc 100%)'; dialog.style.borderRadius='6px'; dialog.style.display='flex'; dialog.style.flexDirection='column'; dialog.style.overflow='hidden'; dialog.style.boxSizing='border-box'; dialog.style.position='absolute'; dialog.style.top='20px'; dialog.style.left='50%'; dialog.style.transform='translate(-50%, 0)'; dialog.style.margin='0';
			var body = document.createElement('div'); body.id='quickViewBodyShim'; body.style.flex='1 1 auto'; body.style.overflowX='hidden'; body.style.overflowY='auto'; body.style.padding='10px'; body.style.minHeight='0';
			var title = document.createElement('h4'); title.id='quickViewTitleShim'; title.style.margin='10px'; title.textContent='Quick View';
			// Header-right container for countdown next to title
			var headerRight = document.createElement('div'); headerRight.id='quickViewHeaderRight'; headerRight.style.display='inline-flex'; headerRight.style.alignItems='center'; headerRight.style.gap='6px'; headerRight.style.whiteSpace='nowrap'; headerRight.style.marginRight='10px'; headerRight.style.flex='0 0 auto';
			var footer = document.createElement('div'); footer.style.display='flex'; footer.style.flexWrap='wrap'; footer.style.justifyContent='flex-start'; footer.style.alignItems='center'; footer.style.gap='8px'; footer.style.padding='10px'; footer.style.marginTop='auto';
			var left = document.createElement('div'); left.id='quickViewFooterLeft'; var mid = document.createElement('div'); mid.id='quickViewFooterMid'; var right = document.createElement('div'); right.id='quickViewFooterRight';
			left.style.display='flex'; left.style.alignItems='center'; left.style.flexWrap='wrap'; left.style.gap='8px'; left.style.minWidth='240px';
			right.style.display='flex'; right.style.alignItems='center'; right.style.flexWrap='wrap'; right.style.gap='8px'; right.style.justifyContent='flex-end'; right.style.marginLeft='auto';
			left.style.flex='1 1 auto';
			// Watcher controls
			var logSelect = document.createElement('select'); logSelect.id='watcherLogSelect'; logSelect.className='form-control'; logSelect.style.display='inline-block'; logSelect.style.width='auto'; logSelect.style.maxWidth='48vw'; logSelect.style.marginRight='8px';
			var linesInput = document.createElement('input'); linesInput.id='watcherLines'; linesInput.type='text'; linesInput.value='100'; linesInput.size='4'; linesInput.className='form-control'; linesInput.style.display='inline-block'; linesInput.style.width='70px'; linesInput.style.marginRight='8px';
			var refreshBtn = document.createElement('button'); refreshBtn.id='watcherRefresh'; refreshBtn.className='btn btn-default'; refreshBtn.textContent='Autocheck'; refreshBtn.style.marginRight='0';
			var refreshLabel = document.createElement('span'); refreshLabel.id='watcherRefreshLabel'; refreshLabel.textContent=' Refresh in ';
			var timerSpan = document.createElement('span'); timerSpan.id='watcherTimer'; timerSpan.textContent='0';
			// Place countdown in header (right side of title)
			headerRight.appendChild(refreshLabel); headerRight.appendChild(timerSpan);
			var pauseBtn = document.createElement('button'); pauseBtn.id='watcherPause'; pauseBtn.className='btn btn-default'; pauseBtn.textContent='Pause';
			// Arrange: inputs row + button column (refresh/pause stacked)
			var inputsRow = document.createElement('div'); inputsRow.style.display='inline-flex'; inputsRow.style.flexWrap='wrap'; inputsRow.style.alignItems='center'; inputsRow.style.gap='6px'; inputsRow.style.marginRight='8px';
			inputsRow.appendChild(logSelect); inputsRow.appendChild(document.createTextNode(' Lines: ')); inputsRow.appendChild(linesInput);
			// (Timer moved to header)
			var btnCol = document.createElement('div'); btnCol.style.display='inline-flex'; btnCol.style.flexDirection='column'; btnCol.style.gap='6px'; btnCol.style.alignItems='flex-end';
			// Restore normal size and style (match Close button brightness and font)
			refreshBtn.style.width='103px'; refreshBtn.style.marginRight='8px'; refreshBtn.style.transform='none';
			// Light green (success-like) gradient, dark text, soft border
			refreshBtn.style.background='linear-gradient(180deg, #d4edda 0%, #c3e6cb 100%)';
			refreshBtn.style.color='#155724';
			refreshBtn.style.borderColor='#b1dfbb';
			refreshBtn.style.fontWeight='normal';
			pauseBtn.style.width='77px'; pauseBtn.style.marginRight='0'; pauseBtn.style.transform='none';
			// Light orange (warning-like) gradient, dark text, soft border
			pauseBtn.style.background='linear-gradient(180deg, #fff3cd 0%, #ffe8a1 100%)';
			pauseBtn.style.color='#856404';
			pauseBtn.style.borderColor='#ffe8a1';
			pauseBtn.style.fontWeight='normal';
			refreshBtn.style.whiteSpace='nowrap'; refreshBtn.style.overflow='hidden'; refreshBtn.style.textOverflow='ellipsis';
			pauseBtn.style.whiteSpace='nowrap'; pauseBtn.style.overflow='hidden'; pauseBtn.style.textOverflow='ellipsis';
			// Place Autocheck to the left of Pause in a horizontal row
			btnCol.style.flexDirection='row'; btnCol.style.alignItems='center'; btnCol.style.gap='6px'; btnCol.style.flexWrap='wrap'; btnCol.style.justifyContent='flex-end';
			btnCol.appendChild(refreshBtn); btnCol.appendChild(pauseBtn);
			left.appendChild(inputsRow);
			// No edit/save/cancel in watcher mode
			mid.style.display='none';
			var closeBtn = document.createElement('button'); closeBtn.id='quickViewCloseShim'; closeBtn.className='btn btn-default'; closeBtn.textContent='Close'; closeBtn.style.background='linear-gradient(180deg, #f8d7da 0%, #f5c6cb 100%)'; closeBtn.style.color='#721c24'; closeBtn.style.borderColor='#f1b0b7';
			// Right container: place control buttons before Close
			right.style.display='inline-flex'; right.style.alignItems='center'; right.style.gap='8px';
			right.appendChild(btnCol); right.appendChild(closeBtn);
			// Populate log options
			function populateLogs(){
				try{
					var xhr = new XMLHttpRequest();
					// Direct JSON endpoint (no scaffolding)
					var url = '$script?action=watcher_meta_logs';
					xhr.open('GET', url, true);
					try{ xhr.setRequestHeader('X-Requested-With','XMLHttpRequest'); }catch(_){ }
					xhr.onreadystatechange = function(){
						if (xhr.readyState === 4){
							if (xhr.status >= 200 && xhr.status < 300){
								var text = xhr.responseText || '[]';
								try {
									var opts = JSON.parse(text);
									logSelect.innerHTML = '';
									for (var i=0;i<opts.length;i++){
										var o = document.createElement('option');
										o.value = opts[i].value;
										o.textContent = opts[i].label;
										if (opts[i].selected){ o.selected = true; }
										logSelect.appendChild(o);
									}
								} catch(parseErr){
									// If server sent HTML (e.g., login), stay in modal and show a hint
									try { var b=document.getElementById('quickViewBodyShim'); if(b){ b.innerHTML = "<div class='alert alert-warning'>Unable to load log list (login or permissions required). Try reloading the page.</div>"; } } catch(__){}
								}
							} else {
								// Non-2xx: keep modal open and show an error
								try { var b2=document.getElementById('quickViewBodyShim'); if(b2){ b2.innerHTML = "<div class='alert alert-danger'>Failed to load log list ("+xhr.status+").</div>"; } } catch(__){}
							}
						}
					};
					xhr.send();
				}catch(e){}
			}
			// Refresh logic: 5s autocheck or 1s real-time mode; in-flight guard
			var watcherPaused=false, watcherTick=5, watcherTimerId=null, watcherMode='auto'; window.__qhtlWatcherMode = 'auto'; window.__qhtlWatcherLoading = false;
			// Define normal and more intense color sets for mode/state emphasis
			var REFRESH_BG_NORMAL='linear-gradient(180deg, #d4edda 0%, #c3e6cb 100%)', REFRESH_BORDER_NORMAL='#b1dfbb';
			var REFRESH_BG_INTENSE='linear-gradient(180deg, #b9e2c7 0%, #9fd8ae 100%)', REFRESH_BORDER_INTENSE='#8fd19d';
			var PAUSE_BG_NORMAL='linear-gradient(180deg, #fff3cd 0%, #ffe8a1 100%)', PAUSE_BORDER_NORMAL='#ffe8a1';
			var PAUSE_BG_INTENSE='linear-gradient(180deg, #ffe8a1 0%, #ffd66b 100%)', PAUSE_BORDER_INTENSE='#ffcf66';
			function updateIntensity(){
				var mode = window.__qhtlWatcherMode || watcherMode;
				var isLive = (mode==='live');
				var isPaused = !!watcherPaused; // 'Start' when paused
				// Real Time button gets intense style only in live mode
				refreshBtn.style.background = isLive ? REFRESH_BG_INTENSE : REFRESH_BG_NORMAL;
				refreshBtn.style.borderColor = isLive ? REFRESH_BORDER_INTENSE : REFRESH_BORDER_NORMAL;
				// Start button (pauseBtn while paused) gets intense style; otherwise normal Pause style
				pauseBtn.style.background = isPaused ? PAUSE_BG_INTENSE : PAUSE_BG_NORMAL;
				pauseBtn.style.borderColor = isPaused ? PAUSE_BORDER_INTENSE : PAUSE_BORDER_NORMAL;
			}
			function scheduleTick(){ if(watcherTimerId){ clearInterval(watcherTimerId);} watcherTick=5; var mode = window.__qhtlWatcherMode || watcherMode; if(mode==='auto'){ refreshLabel.textContent=' Refresh in '; timerSpan.textContent=String(watcherTick); } else { refreshLabel.textContent=' '; timerSpan.textContent='live mode'; }
				updateIntensity();
				watcherTimerId=setInterval(function(){ if(watcherPaused){ return; } if(window.__qhtlWatcherLoading){ return; } if(window.__qhtlWatcherClosed){ return; }
					if((window.__qhtlWatcherMode||watcherMode)==='auto'){
						watcherTick--; timerSpan.textContent=String(watcherTick);
						if(watcherTick<=0){ doRefresh(); watcherTick=5; timerSpan.textContent=String(watcherTick); }
					} else {
						// Real-time: refresh every second
						timerSpan.textContent='live mode'; doRefresh();
					}
				},1000);
			}
			window.__qhtlScheduleTick = scheduleTick;
			function setWatcherMode(mode){ watcherMode = (mode==='live') ? 'live' : 'auto'; window.__qhtlWatcherMode = watcherMode; window.__qhtlWatcherState = { lines: [] }; if(watcherMode==='live'){ refreshBtn.textContent='Real Time'; refreshLabel.textContent=' '; timerSpan.textContent='live mode'; } else { refreshBtn.textContent='Autocheck'; refreshLabel.textContent=' Refresh in '; timerSpan.textContent=String(watcherTick); } updateIntensity(); scheduleTick(); }
			function doRefresh(){ if(window.__qhtlWatcherLoading){ return; } if(window.__qhtlWatcherClosed){ return; } var url='$script?action=logtailcmd&lines='+encodeURIComponent(linesInput.value||'100')+'&lognum='+encodeURIComponent(logSelect.value||'0')+'&ajax=1'; quickViewLoad(url); }
			// Mode toggle: Autocheck (5s) <-> Real Time (1s)
			refreshBtn.addEventListener('click', function(e){ e.preventDefault(); setWatcherMode(watcherMode==='auto' ? 'live' : 'auto'); });
			pauseBtn.addEventListener('click', function(e){ e.preventDefault(); watcherPaused=!watcherPaused; pauseBtn.textContent=watcherPaused?'Start':'Pause'; updateIntensity(); });
			logSelect.addEventListener('change', function(){ window.__qhtlWatcherState = { lines: [] }; doRefresh(); scheduleTick(); });
			linesInput.addEventListener('change', function(){ window.__qhtlWatcherState = { lines: [] }; doRefresh(); scheduleTick(); });
			closeBtn.addEventListener('click', function(){ if(watcherTimerId){ clearInterval(watcherTimerId); watcherTimerId=null; } window.__qhtlWatcherClosed = true; if(typeof dialog!=='undefined' && dialog){ dialog.classList.remove('fire-blue'); } modal.style.display='none'; });
			populateLogs();
			// Initialize emphasis based on defaults (auto mode, not paused)
			updateIntensity();
			var inner = document.createElement('div'); inner.style.padding='10px'; inner.style.display='flex'; inner.style.flexDirection='column'; inner.style.flex='1 1 auto'; inner.style.minHeight='0'; inner.style.minWidth='0';
			var headerBar = document.createElement('div'); headerBar.style.display='flex'; headerBar.style.justifyContent='space-between'; headerBar.style.alignItems='center'; headerBar.style.gap='8px'; headerBar.style.flexWrap='wrap';
			headerBar.appendChild(title); headerBar.appendChild(headerRight);
			inner.appendChild(headerBar); inner.appendChild(body);
			footer.appendChild(left); footer.appendChild(mid); footer.appendChild(right);
			dialog.appendChild(inner); dialog.appendChild(footer); modal.appendChild(dialog); parent.appendChild(modal);
			modal.addEventListener('click', function(e){ if(e.target===modal){ if(watcherTimerId){ clearInterval(watcherTimerId); watcherTimerId=null; } window.__qhtlWatcherClosed = true; if(typeof dialog!=='undefined' && dialog){ dialog.classList.remove('fire-blue'); } modal.style.display='none'; } });
			return modal;
		}

		function quickViewLoad(url, done){
			var m=document.getElementById('quickViewModalShim') || ensureQuickViewModal();
			var b=document.getElementById('quickViewBodyShim');
			if(!b){ return; }
			if(window.__qhtlWatcherClosed){ return; }
			if(!window.__qhtlWatcherMode || window.__qhtlWatcherMode !== 'live'){
				b.textContent='Loading...';
			}
			var x=new XMLHttpRequest();
			window.__qhtlWatcherLoading=true;
			x.open('GET', url, true);
			try{ x.setRequestHeader('X-Requested-With','XMLHttpRequest'); }catch(__){}
			x.onreadystatechange=function(){
				if(x.readyState===4){
					try{
						if(x.status>=200 && x.status<300){
							var html = x.responseText || '';
							// Note: Scripts inserted via innerHTML generally do not execute; this is acceptable for log output.
							b.innerHTML = html;
								// Auto-scroll to top if not in live mode (newest-first); in live mode, respect user scroll position
								if (window.__qhtlWatcherMode !== 'live') {
									try { b.scrollTop = 0; } catch(_) {}
								}
							if (typeof done==='function') { try{ done(); }catch(_){} }
						} else {
							b.innerHTML = "<div class='alert alert-danger'>Failed to load content ("+x.status+"). Staying in Quick View.</div>";
						}
					} finally {
						window.__qhtlWatcherLoading=false;
					}
				}
			};
			x.send(null);
			if(!window.__qhtlWatcherClosed){ m.style.display='block'; }
		}

		// Global watcher opener that sets size and starts auto-refresh
		window.__qhtlRealOpenWatcher = function(){ window.__qhtlWatcherClosed = false; var m=ensureQuickViewModal(); var t=document.getElementById('quickViewTitleShim'); var d=m.querySelector('div'); t.textContent='Watcher'; if(d){
			var parent = document.querySelector('.qhtl-bubble-bg') || document.body;
			var w = (parent && parent.classList && parent.classList.contains('qhtl-bubble-bg')) ? (parent.clientWidth || window.innerWidth) : window.innerWidth;
			var h = (parent && parent.classList && parent.classList.contains('qhtl-bubble-bg')) ? (parent.clientHeight || window.innerHeight) : window.innerHeight;
			w = Math.min(800, Math.floor(w * 0.95));
			// Enforce global modal max height 480px
			h = Math.min(480, Math.floor(h * 0.9));
			d.style.width = w + 'px'; d.style.height = h + 'px';
			d.style.maxWidth='calc(100% - 40px)'; d.style.maxHeight='480px';
			d.style.position='absolute'; d.style.top='20px'; d.style.left='50%'; d.style.transform='translateX(-50%)'; d.style.margin='0';
		}
				// Ensure blue pulsating glow CSS exists and apply class
				(function(){ var css=document.getElementById('qhtl-blue-style'); if(!css){ css=document.createElement('style'); css.id='qhtl-blue-style'; css.textContent=String.fromCharCode(64)+'keyframes qhtl-blue {0%,100%{box-shadow: 0 0 12px 5px rgba(0,123,255,0.55), 0 0 20px 9px rgba(0,123,255,0.3);}50%{box-shadow: 0 0 22px 12px rgba(0,123,255,0.95), 0 0 36px 16px rgba(0,123,255,0.55);}} .fire-blue{ animation: qhtl-blue 2.2s infinite ease-in-out; }'; document.head.appendChild(css);} if(d){ d.classList.add('fire-blue'); } var bodyEl=document.getElementById('quickViewBodyShim'); if(bodyEl){ bodyEl.style.background='white'; bodyEl.style.borderRadius='4px'; bodyEl.style.padding='10px'; } })();
			// initial load and start timer (no synthetic change event to avoid loops)
			(function(){ var ls=document.getElementById('watcherLines'), sel=document.getElementById('watcherLogSelect'); var url='$script?action=logtailcmd&lines='+(ls?encodeURIComponent(ls.value||'100'):'100')+'&lognum='+(sel?encodeURIComponent(sel.value||'0'):'0')+'&ajax=1'; quickViewLoad(url, function(){ var timer=document.getElementById('watcherTimer'); if(timer){ timer.textContent='5'; } if(typeof setWatcherMode==='function'){ setWatcherMode('auto'); } else if(window.__qhtlScheduleTick){ window.__qhtlScheduleTick(); } }); })();
				m.style.display='block'; return false; };
		// Also expose the real opener on the original name for direct callers
		window.openWatcher = window.__qhtlRealOpenWatcher;
	}
})();
</script>
HTML_SMART_WRAPPER
}

		if (!$is_ajax) {
print <<HTML_HEADER_ASSETS;
				<!-- Intentionally omit Bootstrap CSS here to avoid WHM header/layout side-effects -->
				<link href='$images/qhtlfirewall.css' rel='stylesheet' type='text/css'>
				<!-- Provide a stable absolute script URL for all inline widgets/APIs (resolves WHM token path) -->
				<script>
					(function(){
						try {
							var loc = window.location || {};
							var origin = loc.origin || (loc.protocol + '//' + loc.host);
							// Extract cpsess token without regex to avoid parsing issues
							var pth = String(loc.pathname || '');
							var idx = pth.indexOf('/cpsess');
							var token = '';
							if (idx !== -1) {
								var end = pth.indexOf('/', idx + 1);
								token = (end === -1) ? pth.substring(idx) : pth.substring(idx, end);
							}
							// Build absolute path to our CGI, e.g., https://host:2087/cpsessXXXX/cgi/qhtlink/qhtlfirewall.cgi
							window.QHTL_SCRIPT = origin + token + '/cgi/qhtlink/' + '$script';
						} catch(e) {
							// Fallback: relative script name (works when already inside our CGI context)
							window.QHTL_SCRIPT = '$script';
						}
					})();
				</script>
				<script src='$script?action=wstatus_js&v=$myv'></script>
		<script>
	// Fallback if wstatus.js fails to load or is blocked (e.g., MIME nosniff)
	(function(){
	  try{
	    if (!window.WStatus) {
	      window.WStatus = {
	        open: function(){
	          try { window.location = '$script?action=qhtlwaterfallstatus'; } catch(_){ window.location='?action=qhtlwaterfallstatus'; }
	          return false;
	        }
	      };
	    }
	  }catch(_){ }
	})();
		</script>
	$jqueryjs
	<!-- Enable Bootstrap JS for modals/popovers used by Quick Actions and Promo (CSS intentionally not included) -->
	$bootstrapjs
		<style>
HTML_HEADER_ASSETS
	}
	if (!$is_ajax) {
	print <<'HTML_INLINE_CSS';
	.toplink {
	top: 140px;
	}
	.mobilecontainer {
	display:none;
	}
	.normalcontainer {
	display:block;
	}
HTML_INLINE_CSS
	}
	if ($config{STYLE_MOBILE} or $reseller) {
	    	# On small screens, allow the optional mobilecontainer to display,
	    	# but do NOT hide the normalcontainer (tabs live there). This keeps
	    	# the tabbed UI visible on mobile while still allowing any simplified
	    	# mobile elements to show if present.
	    	if (!$is_ajax) {
	print <<'HTML_MEDIA_CSS';
	\@media (max-width: 600px) {
	.mobilecontainer { display:block; }
	.normalcontainer { display:block; }
	}
HTML_MEDIA_CSS
	    	}
	}
	if (!$is_ajax) { print "</style>\n"; print @header; }

	if (!$is_ajax) {
print <<'EXTRA_BUBBLE_STYLE';
<style id="qhtl-plugin-bubble-style">
  /* Water bubble highlight for the plugin header status */
  #qhtl-status-btn{ position:relative; display:inline-flex; align-items:center; justify-content:center; text-shadow:0 1px 2px rgba(0,0,0,0.25); }
  #qhtl-status-btn::before{ content:''; position:absolute; top:4px; left:10px; right:10px; height:40%; border-radius:999px; background:linear-gradient(to bottom, rgba(255,255,255,0.55), rgba(255,255,255,0)); pointer-events:none; }
</style>
EXTRA_BUBBLE_STYLE
}
}



my $ui_error = '';
eval {
	require QhtLink::DisplayUI;
	require QhtLink::DisplayResellerUI;
	1;
} or do { $ui_error = $@ || 'Failed to load UI modules'; };


# After UI module is loaded and modal JS is injected, render header and Watcher button
# Do not render the header panel for AJAX inline loads
unless ($skip_capture || $is_ajax) {
		# Build a compact status badge for the header's right column
	my $status_badge = "<span class='label label-success'>Enabled</span>";
		my $status_buttons = '';
		my $is_test = $config{TESTING} ? 1 : 0;
		my $is_disabled = -e "/etc/qhtlfirewall/qhtlfirewall.disable" ? 1 : 0;
		my $ipt_ok = 0;
		eval {
				my ($childin, $childout);
				my $pid = open3($childin, $childout, $childout, "$config{IPTABLES} $config{IPTABLESWAIT} -L LOCALINPUT -n");
				my @iptstatus = <$childout>;
				waitpid ($pid, 0);
				chomp @iptstatus;
				if ($iptstatus[0] =~ /# Warning: iptables-legacy tables present/) {shift @iptstatus}
				$ipt_ok = ($iptstatus[0] && $iptstatus[0] =~ /^Chain LOCALINPUT/) ? 1 : 0;
		};
		if ($is_disabled) {
				$status_badge = "<span class='label label-danger'>Disabled</span>";
				$status_buttons = "<form action='$script' method='post' style='display:inline;margin-left:8px'>".
													"<input type='hidden' name='action' value='enable'>".
													"<input type='submit' class='btn btn-xs btn-default' value='Enable'></form>";
		} elsif ($is_test) {
				$status_badge = "<span class='label label-warning'>Testing</span>";
		} elsif (!$ipt_ok) {
				$status_badge = "<span class='label label-danger'>Disabled</span>";
				$status_buttons = "<form action='$script' method='post' style='display:inline;margin-left:8px'>".
													"<input type='hidden' name='action' value='start'>".
													"<input type='submit' class='btn btn-xs btn-default' value='Start'></form>";
		}

	print <<EOF;
<div class='panel panel-default' style='padding: 10px; margin:0;'>
	<div class='row' style='display:flex;align-items:center;'>
		<div class='col-sm-8 col-xs-12' style='display:flex;align-items:center;gap:10px;'>
			<img src='$images/qhtlfirewall_small.gif' onerror="this.onerror=null;this.src='$images/qhtlfirewall_small.png';" style='width:48px;height:48px;vertical-align:middle' alt='Logo'>
			<h4 style='margin:5px 0;'>
				<a href='$script' style='text-decoration:none;' title='Open QhtLink Firewall'
					onclick="try{ if(window.QHTL_SCRIPT){ window.location = window.QHTL_SCRIPT; return false; } }catch(e){}">
					QhtLink Firewall
				</a>
				&nbsp;v$myv
			</h4>
		</div>
		<div class='col-sm-4 col-xs-12'>
			<div style='display:flex;flex-direction:row;align-items:center;justify-content:flex-end;gap:10px;padding-right:10px;'>
				<button type='button' class='btn btn-watcher-bubble'
					onclick="return (window.__qhtlOpenWatcherSmart ? window.__qhtlOpenWatcherSmart() : (typeof window.openWatcher==='function' ? (openWatcher(), false) : (window.location='$script?action=logtail', false)));">
					Watcher
				</button>
				<span class='btn-status success' id='qhtl-status-btn' style='text-transform:none;'>Enabled</span>
			</div>
		</div>
	</div>
<script>
// Keep the status text within the green button centered and sync with computed status_badge
(function(){
	if (window.__QHTL_STATUS_HEADER_STYLED) return; window.__QHTL_STATUS_HEADER_STYLED = true;
  try {
    var el = document.getElementById('qhtl-status-btn');
    if (!el) return;
	var txt = (function(){ var d = document.createElement('div'); d.innerHTML = "${status_badge}"; var s=d.querySelector('.label'); return s ? s.textContent.trim() : 'Enabled'; })();
	el.textContent = txt;
		el.classList.remove('success','warning','danger');
		var lct = String(txt||'').toLowerCase();
		if (lct.indexOf('disabled')!==-1 || lct.indexOf('stopped')!==-1) { el.classList.add('danger'); }
		else if (lct.indexOf('testing')!==-1) { el.classList.add('warning'); }
	else { el.classList.add('success'); }

		// Squeeze font size to fit inside the button without wrapping
		var min = 10, max = 16; // px
		var size = parseFloat(window.getComputedStyle(el).fontSize) || 14;
		size = Math.min(max, Math.max(min, size));
		el.style.fontSize = size + 'px';
		var guard = 0;
		while (el.scrollWidth > el.clientWidth && size > min && guard < 12) {
			size -= 1; el.style.fontSize = size + 'px'; guard++;
		}
		// Match width to the Watcher button for visual balance and reduce both by ~20%
		try {
			var watcher = document.querySelector('.btn-watcher-bubble');
			if (watcher) {
				// Use computed width to include padding/border
				var cs = window.getComputedStyle(watcher);
				var cw = parseFloat(cs.width);
				if (!isNaN(cw) && cw > 0) {
					var target = Math.max(60, Math.round(cw * 0.8)); // reduce ~20%
					// shrink watcher width similarly by applying a min-width
					watcher.style.minWidth = target + 'px';
					el.style.display = 'inline-block';
					el.style.minWidth = target + 'px';
					el.style.textAlign = 'center';
				}
			}
		} catch(_) {}

		// Apply bubble-style radial gradient styling to status to mirror Watcher feel
		try {
			var palette = {
				 success: { grad: 'radial-gradient(circle at 30% 30%, #b9f6ca 0%, #66e08a 45%, #34a853 80%)', border: '#2f8f49', glow: 'rgba(76,175,80,0.20)' },
				 warning: { grad: 'radial-gradient(circle at 30% 30%, #ffe6a1 0%, #ffc766 45%, #f0ad4e 80%)', border: '#d69339', glow: 'rgba(240,173,78,0.20)' },
				 danger:  { grad: 'radial-gradient(circle at 30% 30%, #ffb3ad 0%, #ff6f69 45%, #d9534f 80%)', border: '#b94441', glow: 'rgba(217,83,79,0.20)' }
			};
			var mode = el.classList.contains('warning') ? 'warning' : (el.classList.contains('danger') ? 'danger' : 'success');
			var p = palette[mode];
			el.style.background = p.grad;
			el.style.color = '#fff';
			el.style.border = '1px solid ' + p.border;
			el.style.borderRadius = '999px';
			el.style.padding = '6px 10px';
			el.style.boxShadow = 'inset 0 2px 6px rgba(255,255,255,0.35), 0 6px 14px ' + p.glow;
		} catch(_) {}
	} catch(e){}
})();
</script>
EOF
		if ($reregister ne "") {print $reregister}
}

# Open gradient wrapper just before main content (exclude header)
unless ($skip_capture) {
	print "<div class='qhtl-bubble-bg'>\n";
}

if (!$ui_error) {
	eval {
		if ($reseller) {
			QhtLink::DisplayResellerUI::main(\%FORM, $script, 0, $images, $myv, 'cpanel');
		} else {
			QhtLink::DisplayUI::main(\%FORM, $script, 0, $images, $myv, 'cpanel');
		}
		1;
	} or do { $ui_error = $@ || 'Unknown error in UI renderer'; };
}

# Close gradient wrapper right after main content (not for AJAX inline loads)
unless ($skip_capture) {
	if (!$is_ajax) {
		print "</div>\n";
	}
}

if ($ui_error) {
	print qq{<div class="alert alert-danger" role="alert" style="margin:10px">QhtLink Firewall UI error: <code>} . ( $ui_error =~ s/</&lt;/gr ) . qq{</code></div>};
}

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd" or $FORM{action} eq "viewlist" or $FORM{action} eq "editlist" or $FORM{action} eq "savelist") {
	if (!$is_ajax) {
		# Print sanitized footer if provided; otherwise print a minimal version link with the exact left text
		if (@footer) {
			# Print array content, not a symbol reference
			print join('', @footer);
		} else {
			print "<div style='display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:8px;'><div style='font-size:12px;'>©2025 (Daniel Nowakowski)</div><div style='font-size:12px;'><a href='$script?action=readme' target='_self' style='text-decoration:none;'>Qht Link Firewall v$myv</a></div></div>\n";
		}
	}
}
close ($SCRIPTOUT) unless ($skip_capture);
select STDOUT;

# Defensive cleanup: rewrite any legacy includes in the captured template HTML
if (!$skip_capture && defined $templatehtml && length $templatehtml) {
	# Do not strip inline scripts here; UI relies on them for tabs and interactions.
	$templatehtml =~ s{(src=\s*['\"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['\"]) }{$1$2?action=banner_js$3 }ig;
	# Also handle cases without assuming a trailing space after the closing quote
	$templatehtml =~ s{(src=\s*['\"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['\"]) }{$1$2?action=banner_js$3 }ig;
	# Robust form without requiring whitespace after the attribute
	$templatehtml =~ s{(src=\s*['\"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['\"]) }{$1$2?action=banner_js$3}ig;

	# Replace legacy inline loader block (starting with var areaId = 'qhtl-inline-area') with the updated, safer version
	{
		my $new_loader = <<'JSLOADER';
<script>(function(){
	// Inline loader (singleton)
	if (window.__QHTL_INLINE_LOADER_ACTIVE) { return; }
	window.__QHTL_INLINE_LOADER_ACTIVE = true;
  var areaId = 'qhtl-inline-area';
  function sameOrigin(u){ try{ var a=document.createElement('a'); a.href=u; return (!a.host || a.host===location.host); }catch(e){ return false; } }
  function isQhtlAction(u, form){ try{ if (String(u).indexOf('?action=')!==-1) return true; if (form && form.querySelector && form.querySelector('[name=\x61ction]')) return true; return false; }catch(e){ return false; } }
  function loadInto(url, method, data){ try{ var area=document.getElementById(areaId); if(!area){ location.href=url; return; } if (window.jQuery){ if(method==='POST'){ jQuery(area).html('<div class="text-muted">Loading...</div>').load(url, data); } else { jQuery(area).html('<div class="text-muted">Loading...</div>').load(url); } } else { var x=new XMLHttpRequest(); x.open(method||'GET', url, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} if(method==='POST'){ try{x.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=UTF-8');}catch(__){} } x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ area.innerHTML = x.responseText; } else { location.href=url; } } }; x.send(data||null); } } catch(e){ try{ location.href=url; }catch(_){} } }
  var __qhtl_lastSubmitter=null;
  function serialize(form, submitter){ try{ var p=[]; for(var i=0;i<form.elements.length;i++){ var el=form.elements[i]; if(!el || !el.name || el.disabled) continue; var t=(el.type||'').toLowerCase(); if(t==='file') continue; if((t==='checkbox'||t==='radio')&&!el.checked) continue; if(t==='submit'||t==='button'){ if(submitter && el===submitter){ p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(el.value)); } continue; } if(t==='select-multiple'){ for(var j=0;j<el.options.length;j++){ var opt=el.options[j]; if(opt.selected){ p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(opt.value)); } } continue; } p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(el.value)); } if(submitter && submitter.name){ var found=false; for(var k=0;k<form.elements.length;k++){ if(form.elements[k]===submitter){ found=true; break; } } if(!found){ p.push(encodeURIComponent(submitter.name)+'='+encodeURIComponent(submitter.value||'')); } } return p.join('&'); }catch(e){ return ''; } }
  var root = document.getElementById('waterfall') || document;
  root.addEventListener('click', function(ev){ var tgt=ev.target; var btn=tgt && tgt.closest ? tgt.closest('button, input[type=submit]') : null; if(btn && (String(btn.type||'').toLowerCase()==='submit')){ __qhtl_lastSubmitter=btn; } var a=tgt && tgt.closest ? tgt.closest('a') : null; if(!a) return; var href=a.getAttribute('href')||''; if(!href || href==='javascript:void(0)') return; if(!sameOrigin(href) || !isQhtlAction(href, null)) return; ev.preventDefault(); var u = href + (href.indexOf('?')>-1?'&':'?') + 'ajax=1'; loadInto(u, 'GET'); }, true);
  root.addEventListener('submit', function(ev){ var f=ev.target; if(!f || f.tagName!=='FORM') return; var action=f.getAttribute('action')||location.pathname; if(!sameOrigin(action) || !isQhtlAction(action, f)) return; var enc=(f.enctype||''); if (enc && String(enc).toLowerCase().indexOf('multipart/form-data')!==-1) return; ev.preventDefault(); var submitter = (ev.submitter ? ev.submitter : __qhtl_lastSubmitter); var data=serialize(f, submitter); loadInto(action + (action.indexOf('?')>-1?'&':'?') + 'ajax=1', (f.method||'GET').toUpperCase(), data); }, true);
})();</script>
JSLOADER
		# Replace only if we find the legacy loader signature with exact areaId marker
		$templatehtml =~ s{<script[^>]*>\s*\(function\(\)\{\s*var\s+areaId\s*=\s*['"]qhtl-inline-area['"];.*?\}\)\(\);\s*</script>}{$new_loader}is;
		# Also replace any script block that declares the legacy isQhtlAction(u) implementation
		$templatehtml =~ s{<script[^>]*>[^<]*function\s+isQhtlAction\s*\(\s*u\s*\)\s*\{[^<]*?/\\\?action=/.+?</script>}{$new_loader}is;
	}

	# Ensure cache-busting is present on status and widget loaders in captured HTML
	# Add &v=$myv to wstatus_js if missing
	if ($myv && $myv ne 'unknown') {
		$templatehtml =~ s{(src=\s*['"][^'"\?]+\?action=wstatus_js)(['"]) }{$1&v=$myv$2 }ig;
		# For widget_js, append &v only if not already present
		$templatehtml =~ s{(src=\s*['"][^'"\?]+\?action=widget_js&name=[^'"&]+)(?![^'"\>]*?&v=)(['"]) }{$1&v=$myv$2 }ig;
	}
	# If a script tag references our CGI with a query but without action=, force action=banner_js to return JavaScript instead of HTML
	$templatehtml =~ s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)\?(?![^'"\>]*?action=)([^'"\>]*)(['"]) }{$1$2?action=banner_js&$3$4 }ig;
	$templatehtml =~ s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)\?(?![^'"\>]*?action=)([^'"\>]*)(['"]) }{$1$2?action=banner_js&$3$4}ig;
}

# If AJAX request, always return raw inner content without WHM template/header/footer regardless of action
if ($is_ajax) {
	print $templatehtml if defined $templatehtml;
	exit 0;
}

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd" or $FORM{action} eq "viewlist" or $FORM{action} eq "editlist" or $FORM{action} eq "savelist") {
	my $rendered;
	eval {
		$rendered = Cpanel::Template::process_template(
			'whostmgr',
			{
				"template_file"   => "${thisapp}.tmpl",
				"${thisapp}_output" => $templatehtml,
				"print"           => 0,
			}
		);
		1;
	} or do {
		my $err = $@ || 'unknown error';
		print "<pre>Template render error: $err</pre>";
	};
	if (defined $rendered) {
		if (ref($rendered) eq 'SCALAR') {
			print ${$rendered};
		} elsif (ref($rendered) eq 'ARRAY') {
			print join('', @{$rendered});
		} else {
			print $rendered;
		}
	} elsif (defined $templatehtml && length $templatehtml) {
		# Fallback: print the raw captured HTML to avoid a blank page
		print $templatehtml;
	}
}
# end main
###############################################################################
## start printcmd
sub printcmd {
	my @command = @_;
	my ($childin, $childout);
	my $pid = open3($childin, $childout, $childout, @command);
	while (<$childout>) {print $_}
	waitpid ($pid, 0);
	return;
}
## end printcmd
###############################################################################

1;
