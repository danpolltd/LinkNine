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
require Cpanel::Form;
require Cpanel::Config;
require Whostmgr::ACLS;
require Cpanel::Rlimit;
require Cpanel::Template;
require Cpanel::Version::Tiny;
###############################################################################
# start main

our ($reseller, $script, $images, %rprivs, $myv, %FORM);

Whostmgr::ACLS::init_acls();

%FORM = Cpanel::Form::parseform();

## Postpone config and regex setup until after lightweight endpoints

Cpanel::Rlimit::set_rlimit_to_infinity();

# Defensive: if this CGI is requested in a script-like context without an action, return a JS no-op.
# Simple rule: only consider it script-like when Sec-Fetch-Dest=script or Accept indicates JavaScript.
my $sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
my $sec_mode = lc($ENV{HTTP_SEC_FETCH_MODE} // '');
my $sec_user = lc($ENV{HTTP_SEC_FETCH_USER} // ''); # '?1' for user navigations
my $accept   = lc($ENV{HTTP_ACCEPT} // '');
if (!defined $FORM{action} || $FORM{action} eq '') {
	my $is_script_dest= ($sec_dest eq 'script');
	my $accept_js     = ($accept =~ /\b(?:application|text)\/(?:javascript|ecmascript)\b/);
	# Treat script-like only when clearly a script destination or Accept looks like JS
	my $scriptish     = $is_script_dest || $accept_js;
	if ($scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
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
	my $sj_accept   = lc($ENV{HTTP_ACCEPT} // '');
	if ($sj_sec_dest eq 'script' || $sj_accept =~ /\b(?:application|text)\/(?:javascript|ecmascript)\b/) {
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

	my ($enabled, $running, $class, $text, $status_key);
	if ($is_disabled) {
		($enabled, $running, $class, $text, $status_key) = (0, 0, 'danger', 'Disabled and Stopped', 'disabled_stopped');
	} elsif (!$ipt_ok) {
		($enabled, $running, $class, $text, $status_key) = (1, 0, 'danger', 'Enabled but Stopped', 'enabled_stopped');
	} elsif ($is_test) {
		($enabled, $running, $class, $text, $status_key) = (1, 1, 'warning', 'Enabled (Test Mode)', 'enabled_test');
	} else {
		($enabled, $running, $class, $text, $status_key) = (1, 1, 'success', 'Enabled and Running', 'enabled_running');
	}

	# Simple JSON response, no external modules required here
	my $json = sprintf(
		'{"enabled":%d,"running":%d,"test_mode":%d,"status":"%s","text":"%s","class":"%s","version":"%s"}',
		$enabled, $running, $is_test, $status_key, $text, $class, $myv
	);
	print "Content-type: application/json\r\nX-Content-Type-Options: nosniff\r\n\r\n";
	print $json;
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

			function onReady(fn){ if(document.readyState!=='loading'){ fn(); } else { document.addEventListener('DOMContentLoaded', fn, { once:true }); } }

			onReady(function(){
			// Don't inject on our own firewall UI page to avoid doubling there
			var path = String(location.pathname || '');
			var href = path + String(location.search || '');
		if (/\/qhtlfirewall\.cgi(?:\?|$)/.test(href)) { return; }
			// Run only when a cpsess token is present (login pages won't have it)

		function cps(){ var m=(location.pathname||'').match(/\/cpsess[^\/]+/); return m?m[0]:''; }
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
					var cls = data && data.class || 'default';
					var txt = data && data.text || 'Firewall';
					var bg = (cls==='success') ? '#5cb85c' : (cls==='warning' ? '#f0ad4e' : (cls==='danger' ? '#d9534f' : '#777'));
					return {bg:bg, txt:txt};
				}

				function tryInject(){
					// Do not inject until we have real data to avoid gray placeholder
					if (!lastData) return false;
					var stats = document.querySelector('cp-whm-header-stats-control');
					if (!stats || !stats.shadowRoot) return false;
					var host = stats.shadowRoot.querySelector('.header-stats, header, div');
					if (!host) return false;
					var sty = computeStyle(lastData);
					var existing = stats.shadowRoot.getElementById('qhtlfw-header-badge');
					if (existing) {
						// existing is the inner span; update its style/text
						existing.style.background = sty.bg;
						existing.style.boxShadow = '0 0 0 5px '+sty.bg+'33';
						existing.textContent = 'Firewall: ' + sty.txt;
						// ensure wrapper provides space for glow on all sides
						var wrap = existing.parentElement;
						if (wrap && wrap.tagName && wrap.tagName.toUpperCase()==='A') {
							wrap.style.marginTop = '10px';
							wrap.style.marginBottom = '10px';
						}
						return true;
					}
					// Build clickable link to the Firewall UI (cpsess-aware)
					var a = document.createElement('a');
					a.href = origin()+token+'/cgi/qhtlink/qhtlfirewall.cgi';
					a.target = '_self';
					a.setAttribute('aria-label','Open QhtLink Firewall');
					a.style.textDecoration = 'none';
					a.style.marginLeft = '8px';
					// add vertical spacing so top/bottom glow is visible
					a.style.marginTop = '10px';
					a.style.marginBottom = '10px';
					// Inner badge span for color/status
					var span = document.createElement('span');
					span.id = 'qhtlfw-header-badge';
					span.style.padding = '4px 8px';
					span.style.borderRadius = '3px';
					span.style.color = '#fff';
					span.style.background = sty.bg;
					span.style.cursor = 'pointer';
					// 5px glow in same color (with slight transparency)
					span.style.boxShadow = '0 0 0 5px '+sty.bg+'33';
					span.textContent = 'Firewall: ' + sty.txt;
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
			($cls, $txt) = ('danger', 'Disabled and Stopped');
		} elsif (!$ipt_ok) {
			($cls, $txt) = ('danger', 'Enabled but Stopped');
		} elsif ($is_test) {
			($cls, $txt) = ('warning', 'Enabled (Test Mode)');
		} else {
			($cls, $txt) = ('success', 'Enabled and Running');
		}
		print "Content-type: text/html\r\n";
		print "X-Content-Type-Options: nosniff\r\n";
		print "X-Frame-Options: SAMEORIGIN\r\n";
		print "Content-Security-Policy: frame-ancestors 'self';\r\n\r\n";
		print "<!doctype html><html><head><meta charset=\"utf-8\">\n";
		print "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'\">\n";
		print "<style>html,body{margin:0;padding:0;background:transparent} .label{display:inline-block;font:12px/1.2 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#fff;border-radius:3px;padding:4px 8px} .label-success{background:#5cb85c} .label-warning{background:#f0ad4e} .label-danger{background:#d9534f}</style>\n";
		print "</head><body style=\"margin:0\"><span class=\"label label-$cls\" style=\"display:inline-block;white-space:nowrap\">Firewall: $txt</span></body></html>";
		exit 0;
	}

## From here onwards, load full config and regex helpers, then resolve reseller ACLs
require QhtLink::Config;
my $config = QhtLink::Config->loadconfig();
my %config = $config->config;
my $slurpreg = QhtLink::Slurp->slurpreg;
my $cleanreg = QhtLink::Slurp->cleanreg;

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
		s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(\?)(?!action=)}{$1$2$3}ig; # leave existing queries intact
    }
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

# If an action other than our lightweight endpoints is being requested in a script-like context,
# emit a JS no-op to prevent browsers from parsing full HTML as JavaScript.
if (defined $FORM{action} && $FORM{action} ne '' && $FORM{action} !~ /^(?:status_json|banner_js|banner_frame)$/) {
	my $g_sec_dest = lc($ENV{HTTP_SEC_FETCH_DEST} // '');
	my $g_sec_mode = lc($ENV{HTTP_SEC_FETCH_MODE} // '');
	my $g_sec_user = lc($ENV{HTTP_SEC_FETCH_USER} // '');
	my $g_accept   = lc($ENV{HTTP_ACCEPT} // '');
	my $g_is_script_dest= ($g_sec_dest eq 'script');
	my $g_accept_js     = ($g_accept =~ /\b(?:application|text)\/(?:javascript|ecmascript)\b/);
	my $g_scriptish     = $g_is_script_dest || $g_accept_js;
	if ($g_scriptish) {
		print "Content-type: application/javascript\r\nX-Content-Type-Options: nosniff\r\nCache-Control: no-cache, no-store, must-revalidate, private\r\nPragma: no-cache\r\nExpires: 0\r\n\r\n";
		print ";\n";
		exit 0;
	}
}

print "Content-type: text/html\r\n\r\n";
#if ($Cpanel::Version::Tiny::major_version < 65) {$modalstyle = "style='top:120px'"}

my $templatehtml;
my $SCRIPTOUT;
unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd" or $FORM{action} eq "viewlist" or $FORM{action} eq "editlist" or $FORM{action} eq "savelist") {
#	open(STDERR, ">&STDOUT");
	open ($SCRIPTOUT, '>', \$templatehtml);
	select $SCRIPTOUT;

	print <<EOF;
	<!-- $bootstrapcss -->
	<link href='$images/qhtlfirewall.css' rel='stylesheet' type='text/css'>
	$jqueryjs
	$bootstrapjs
<style>
.toplink {
top: 140px;
}
.mobilecontainer {
display:none;
}
.normalcontainer {
display:block;
}
EOF
	if ($config{STYLE_MOBILE} or $reseller) {
		print <<EOF;
\@media (max-width: 600px) {
.mobilecontainer {
	display:block;
}
.normalcontainer {
	display:none;
}
}
EOF
	}
	print "</style>\n";
	print @header;
}

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd" or $FORM{action} eq "viewlist" or $FORM{action} eq "editlist" or $FORM{action} eq "savelist") {
		# Build a compact status badge for the header's right column
		my $status_badge = "<span class='label label-success'>Enabled and Running</span>";
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
				$status_badge = "<span class='label label-danger'>Disabled and Stopped</span>";
				$status_buttons = "<form action='$script' method='post' style='display:inline;margin-left:8px'>".
													"<input type='hidden' name='action' value='enable'>".
													"<input type='submit' class='btn btn-xs btn-default' value='Enable'></form>";
		} elsif ($is_test) {
				$status_badge = "<span class='label label-warning'>Enabled (Test Mode)</span>";
		} elsif (!$ipt_ok) {
				$status_badge = "<span class='label label-danger'>Enabled but Stopped</span>";
				$status_buttons = "<form action='$script' method='post' style='display:inline;margin-left:8px'>".
													"<input type='hidden' name='action' value='start'>".
													"<input type='submit' class='btn btn-xs btn-default' value='Start'></form>";
		}

 		print <<EOF;
<div class='panel panel-default' style='padding: 10px'>
	<div class='row' style='display:flex;align-items:center;'>
		<div class='col-sm-8 col-xs-12'>
			<h4 style='margin:5px 0;'>QhtLink Firewall (qhtlfirewall) v$myv</h4>
		</div>
		<div class='col-sm-4 col-xs-12 text-right'>
			<img src='$images/qhtlfirewall_small.png' style='height:24px;vertical-align:middle;margin-right:8px' alt='Logo'>
			$status_badge $status_buttons
		</div>
	</div>
</div>
EOF
		if ($reregister ne "") {print $reregister}
}

my $ui_error = '';
eval {
	require QhtLink::DisplayUI;
	require QhtLink::DisplayResellerUI;
	1;
} or do { $ui_error = $@ || 'Failed to load UI modules'; };

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

if ($ui_error) {
	print qq{<div class="alert alert-danger" role="alert" style="margin:10px">QhtLink Firewall UI error: <code>} . ( $ui_error =~ s/</&lt;/gr ) . qq{</code></div>};
}

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd") {
	# No local fallback loader here; global WHM includes handle banner injection with a valid cpsess token.
	print @footer;
}
unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd") {
	close ($SCRIPTOUT);
	select STDOUT;
	# Defensive cleanup: rewrite any legacy includes in the captured template HTML
	if (defined $templatehtml && length $templatehtml) {
		# Do not strip inline scripts here; UI relies on them for tabs and interactions.
		$templatehtml =~ s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(['"]) }{$1$2?action=banner_js$3 }ig;
		$templatehtml =~ s{(src=\s*['"])((?:[^'"\s>]+/)?cgi/qhtlink/(?:qhtlfirewall|addon_qhtlfirewall)\.cgi)(\?)(?!action=)}{$1$2$3}ig;
	}
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
