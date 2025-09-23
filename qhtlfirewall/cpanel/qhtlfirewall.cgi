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
					var cls = (data && data['class']) || 'default';
					var txt = (data && data['text']) || 'Firewall';
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
							wrap.style.marginTop = '7px';
							wrap.style.marginBottom = '7px';
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
					a.style.marginTop = '7px';
					a.style.marginBottom = '7px';
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

	# Provide a smart wrapper so clicking Watcher waits briefly for modal init before falling back
	print <<EOF;
<script>
(function(){
	function fallback(){ try{ window.location='$script?action=logtail'; }catch(e){ window.location='$script?action=logtail'; } }
	window.__qhtlOpenWatcherSmart = function(){
		// Prefer calling the real opener if present; avoid calling the smart wrapper via window.openWatcher to prevent recursion
		if (window.__qhtlQuickViewShim && typeof window.__qhtlRealOpenWatcher==='function') { try{ window.__qhtlRealOpenWatcher(); } catch(e){ fallback(); } return false; }
		var attempts = 0, iv = setInterval(function(){
			attempts++;
			if (window.__qhtlQuickViewShim && typeof window.__qhtlRealOpenWatcher==='function'){
				clearInterval(iv);
				try{ window.__qhtlRealOpenWatcher(); } catch(e){ fallback(); }
			} else if (attempts >= 30) { // ~3s total
				clearInterval(iv);
				fallback();
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
			modal.style.position='fixed'; modal.style.inset='0'; modal.style.background='rgba(0,0,0,0.5)'; modal.style.display='none'; modal.style.zIndex='9999';
			var dialog = document.createElement('div');
			dialog.style.width='660px'; dialog.style.maxWidth='95vw'; dialog.style.height='500px'; dialog.style.background='#fff'; dialog.style.borderRadius='6px'; dialog.style.display='flex'; dialog.style.flexDirection='column'; dialog.style.overflow='hidden'; dialog.style.boxSizing='border-box'; dialog.style.position='fixed'; dialog.style.top='50%'; dialog.style.left='50%'; dialog.style.transform='translate(-50%, -50%)'; dialog.style.margin='0';
			var body = document.createElement('div'); body.id='quickViewBodyShim'; body.style.flex='1 1 auto'; body.style.overflowX='hidden'; body.style.overflowY='auto'; body.style.padding='10px'; body.style.minHeight='0';
			var title = document.createElement('h4'); title.id='quickViewTitleShim'; title.style.margin='10px'; title.textContent='Quick View';
			var footer = document.createElement('div'); footer.style.display='flex'; footer.style.justifyContent='space-between'; footer.style.alignItems='center'; footer.style.padding='10px'; footer.style.marginTop='auto';
			var left = document.createElement('div'); left.id='quickViewFooterLeft'; var mid = document.createElement('div'); mid.id='quickViewFooterMid'; var right = document.createElement('div'); right.id='quickViewFooterRight';
			// Watcher controls
			var logSelect = document.createElement('select'); logSelect.id='watcherLogSelect'; logSelect.className='form-control'; logSelect.style.display='inline-block'; logSelect.style.width='auto'; logSelect.style.marginRight='8px';
			var linesInput = document.createElement('input'); linesInput.id='watcherLines'; linesInput.type='text'; linesInput.value='100'; linesInput.size='4'; linesInput.className='form-control'; linesInput.style.display='inline-block'; linesInput.style.width='70px'; linesInput.style.marginRight='8px';
			var refreshBtn = document.createElement('button'); refreshBtn.id='watcherRefresh'; refreshBtn.className='btn btn-default'; refreshBtn.textContent='Autocheck'; refreshBtn.style.marginRight='8px';
			var refreshLabel = document.createElement('span'); refreshLabel.id='watcherRefreshLabel'; refreshLabel.textContent=' Refresh in ';
			var timerSpan = document.createElement('span'); timerSpan.id='watcherTimer'; timerSpan.textContent='0'; timerSpan.style.marginRight='8px';
			var pauseBtn = document.createElement('button'); pauseBtn.id='watcherPause'; pauseBtn.className='btn btn-default'; pauseBtn.textContent='Pause'; pauseBtn.style.width='80px';
			left.appendChild(logSelect); left.appendChild(document.createTextNode(' Lines: ')); left.appendChild(linesInput); left.appendChild(refreshBtn); left.appendChild(refreshLabel); left.appendChild(timerSpan); left.appendChild(pauseBtn);
			// No edit/save/cancel in watcher mode
			mid.style.display='none';
			var closeBtn = document.createElement('button'); closeBtn.id='quickViewCloseShim'; closeBtn.className='btn btn-default'; closeBtn.textContent='Close'; closeBtn.style.background='linear-gradient(180deg, #f8d7da 0%, #f5c6cb 100%)'; closeBtn.style.color='#721c24'; closeBtn.style.borderColor='#f1b0b7';
			right.appendChild(closeBtn);
			// Populate log options
			function populateLogs(){ try{ var xhr=new XMLHttpRequest(); xhr.open('GET', '$script?action=logtailcmd&meta=1', true); xhr.onreadystatechange=function(){ if(xhr.readyState===4 && xhr.status>=200 && xhr.status<300){ var opts = JSON.parse(xhr.responseText||'[]'); logSelect.innerHTML=''; for(var i=0;i<opts.length;i++){ var o=document.createElement('option'); o.value=opts[i].value; o.textContent=opts[i].label; if(opts[i].selected){ o.selected=true; } logSelect.appendChild(o);} } }; xhr.send(); }catch(e){} }
			// Refresh logic: 5s autocheck or 1s real-time mode; in-flight guard
			var watcherPaused=false, watcherTick=5, watcherTimerId=null, watcherMode='auto'; window.__qhtlWatcherLoading = false;
			function scheduleTick(){ if(watcherTimerId){ clearInterval(watcherTimerId);} watcherTick=5; if(watcherMode==='auto'){ refreshLabel.textContent=' Refresh in '; timerSpan.textContent=String(watcherTick); } else { refreshLabel.textContent=' '; timerSpan.textContent='live mode'; }
				watcherTimerId=setInterval(function(){ if(watcherPaused){ return; } if(window.__qhtlWatcherLoading){ return; }
					if(watcherMode==='auto'){
						watcherTick--; timerSpan.textContent=String(watcherTick);
						if(watcherTick<=0){ doRefresh(); watcherTick=5; timerSpan.textContent=String(watcherTick); }
					} else {
						// Real-time: refresh every second
						timerSpan.textContent='live mode'; doRefresh();
					}
				},1000);
			}
			window.__qhtlScheduleTick = scheduleTick;
			function setWatcherMode(mode){ watcherMode = (mode==='live') ? 'live' : 'auto'; window.__qhtlWatcherState = { lines: [] }; if(watcherMode==='live'){ refreshBtn.textContent='Real Time'; refreshLabel.textContent=' '; timerSpan.textContent='live mode'; } else { refreshBtn.textContent='Autocheck'; refreshLabel.textContent=' Refresh in '; timerSpan.textContent=String(watcherTick); } scheduleTick(); }
			function doRefresh(){ if(window.__qhtlWatcherLoading){ return; } var url='$script?action=logtailcmd&lines='+encodeURIComponent(linesInput.value||'100')+'&lognum='+encodeURIComponent(logSelect.value||'0'); quickViewLoad(url); }
			// Mode toggle: Autocheck (5s) <-> Real Time (1s)
			refreshBtn.addEventListener('click', function(e){ e.preventDefault(); setWatcherMode(watcherMode==='auto' ? 'live' : 'auto'); });
			pauseBtn.addEventListener('click', function(e){ e.preventDefault(); watcherPaused=!watcherPaused; pauseBtn.textContent=watcherPaused?'Start':'Pause'; });
			logSelect.addEventListener('change', function(){ window.__qhtlWatcherState = { lines: [] }; doRefresh(); scheduleTick(); });
			linesInput.addEventListener('change', function(){ window.__qhtlWatcherState = { lines: [] }; doRefresh(); scheduleTick(); });
			closeBtn.addEventListener('click', function(){ if(watcherTimerId){ clearInterval(watcherTimerId); watcherTimerId=null; } if(typeof dialog!=='undefined' && dialog){ dialog.classList.remove('fire-blue'); } modal.style.display='none'; });
			populateLogs();
			var inner = document.createElement('div'); inner.style.padding='10px'; inner.style.display='flex'; inner.style.flexDirection='column'; inner.style.flex='1 1 auto'; inner.style.minHeight='0'; inner.appendChild(title); inner.appendChild(body);
			footer.appendChild(left); footer.appendChild(mid); footer.appendChild(right);
			dialog.appendChild(inner); dialog.appendChild(footer); modal.appendChild(dialog); document.body.appendChild(modal);
			modal.addEventListener('click', function(e){ if(e.target===modal){ if(typeof dialog!=='undefined' && dialog){ dialog.classList.remove('fire-blue'); } modal.style.display='none'; } });
			return modal;
		}

		function quickViewLoad(url, done){ var m=document.getElementById('quickViewModalShim') || ensureQuickViewModal(); var b=document.getElementById('quickViewBodyShim'); if(!b){ return; } b.innerHTML='Loading...'; var x=new XMLHttpRequest(); window.__qhtlWatcherLoading=true; x.open('GET', url, true); x.onreadystatechange=function(){ if(x.readyState===4){ try{ if(x.status>=200&&x.status<300){ var html=x.responseText || ''; // safely remove any <script> tags without embedding a literal closing tag marker in this inline script
				try {
					// Preserve HTML line breaks before stripping markup. Avoid lookahead to prevent line terminators in regex literal.
					html = String(html).replace(/<br\\s*\\\/?>(?:)/gi, '\\n');
					var tmp = document.createElement('div');
					tmp.innerHTML = html;
					var scripts = tmp.getElementsByTagName('script');
					while (scripts.length) { scripts[0].parentNode.removeChild(scripts[0]); }
					// Use text content to treat payload as plain text, then render one line per row
					html = tmp.textContent || '';
				} catch(e){}
				// Render each line separately with truncation (no wrapping)
				var text = (html||'').replace(/\\r\\n/g,'\\n').replace(/\\r/g,'\\n');
				var parsed = text.split(String.fromCharCode(10));
				// Normalize: drop a single trailing blank line
				if (parsed.length && parsed[parsed.length-1] === '') { parsed.pop(); }
				var lines = parsed;
				b.style.fontFamily='SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace';
				// Tail-like append in real-time mode when prior state exists and new content is an extension
				var state = window.__qhtlWatcherState || { lines: [] };
				var appended = false;
				if (typeof watcherMode!=='undefined' && watcherMode==='live' && state.lines && state.lines.length && lines.length >= state.lines.length) {
					var isExtension = true;
					for (var pi=0; pi<state.lines.length; pi++){
						if (state.lines[pi] !== lines[pi]) { isExtension = false; break; }
					}
					if (isExtension) {
						// Append only new lines
						var frag = document.createDocumentFragment();
						for (var ai=state.lines.length; ai<lines.length; ai++){
							var l = lines[ai];
							var divA = document.createElement('div');
							divA.textContent = l;
							divA.title = l;
							divA.style.whiteSpace='nowrap'; divA.style.overflow='hidden'; divA.style.textOverflow='ellipsis'; divA.style.width='100%'; divA.style.boxSizing='border-box';
							frag.appendChild(divA);
						}
						b.appendChild(frag);
						appended = true;
					}
				}
				if (!appended){
					var frag = document.createDocumentFragment();
					for (var i=0;i<lines.length;i++){
						var line = lines[i];
						var div = document.createElement('div');
						div.textContent = line;
						div.title = line; // full text on hover
						div.style.whiteSpace = 'nowrap';
						div.style.overflow = 'hidden';
						div.style.textOverflow = 'ellipsis';
						div.style.width = '100%';
						div.style.boxSizing = 'border-box';
						frag.appendChild(div);
					}
					b.innerHTML='';
					b.appendChild(frag);
				}
				// Update state
				window.__qhtlWatcherState = { lines: lines };
				// Scroll to bottom so the newest lines are visible
				try { (window.requestAnimationFrame||function(f){setTimeout(f,0)})(function(){ b.scrollTop = b.scrollHeight; }); } catch(e){ b.scrollTop = b.scrollHeight; }
				if (typeof done==='function') done();
				} else { b.innerHTML = "<div class='alert alert-danger'>Failed to load content</div>"; } } finally { window.__qhtlWatcherLoading=false; } } }; x.send(); m.style.display='block'; }

		// Global watcher opener that sets size and starts auto-refresh
		window.__qhtlRealOpenWatcher = function(){ var m=ensureQuickViewModal(); var t=document.getElementById('quickViewTitleShim'); var d=m.querySelector('div'); t.textContent='Watcher'; if(d){ d.style.width='800px'; d.style.height='450px'; d.style.maxWidth='95vw'; d.style.position='fixed'; d.style.top='50%'; d.style.left='50%'; d.style.transform='translate(-50%, -50%)'; d.style.margin='0'; }
				// Ensure blue pulsating glow CSS exists and apply class
				(function(){ var css=document.getElementById('qhtl-blue-style'); if(!css){ css=document.createElement('style'); css.id='qhtl-blue-style'; css.textContent=String.fromCharCode(64)+'keyframes qhtl-blue {0%,100%{box-shadow: 0 0 14px 6px rgba(0,123,255,0.55), 0 0 24px 10px rgba(0,123,255,0.3);}50%{box-shadow: 0 0 28px 14px rgba(0,123,255,0.95), 0 0 46px 20px rgba(0,123,255,0.6);}} .fire-blue{ animation: qhtl-blue 2.2s infinite ease-in-out; }'; document.head.appendChild(css);} if(d){ d.classList.add('fire-blue'); } var bodyEl=document.getElementById('quickViewBodyShim'); if(bodyEl){ /* 50% brighter than glow base (#007bff) by mixing with white */ bodyEl.style.background='linear-gradient(180deg, rgb(127,189,255) 0%, rgb(159,205,255) 100%)'; bodyEl.style.borderRadius='4px'; bodyEl.style.padding='10px'; } })();
			// initial load and start timer (no synthetic change event to avoid loops)
			(function(){ var ls=document.getElementById('watcherLines'), sel=document.getElementById('watcherLogSelect'); var url='$script?action=logtailcmd&lines='+(ls?encodeURIComponent(ls.value||'100'):'100')+'&lognum='+(sel?encodeURIComponent(sel.value||'0'):'0'); quickViewLoad(url, function(){ var timer=document.getElementById('watcherTimer'); if(timer){ timer.textContent='5'; } if(typeof setWatcherMode==='function'){ setWatcherMode('auto'); } else if(window.__qhtlScheduleTick){ window.__qhtlScheduleTick(); } }); })();
				m.style.display='block'; return false; };
		// Also expose the real opener on the original name for direct callers
		window.openWatcher = window.__qhtlRealOpenWatcher;
	}
})();
</script>
EOF

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



my $ui_error = '';
eval {
	require QhtLink::DisplayUI;
	require QhtLink::DisplayResellerUI;
	1;
} or do { $ui_error = $@ || 'Failed to load UI modules'; };


# After UI module is loaded and modal JS is injected, render header and Watcher button
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
			<button type='button' class='btn btn-xs btn-default' style='margin-right:8px'
				onclick="return (window.__qhtlOpenWatcherSmart ? window.__qhtlOpenWatcherSmart() : (typeof window.openWatcher==='function' ? (openWatcher(), false) : (window.location='$script?action=logtail', false)));">
				Watcher
			</button>
			<img src='$images/qhtlfirewall_small.gif' onerror="this.onerror=null;this.src='$images/qhtlfirewall_small.png';" style='width:48px;height:48px;vertical-align:middle;margin-right:8px' alt='Logo'>
			$status_badge $status_buttons
		</div>
	</div>
</div>
EOF
		if ($reregister ne "") {print $reregister}
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
