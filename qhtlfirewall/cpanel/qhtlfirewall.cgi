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
use QhtLink::DisplayUI;
use QhtLink::DisplayResellerUI;
use QhtLink::Config;
use QhtLink::Slurp qw(slurp);

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

my $config = QhtLink::Config->loadconfig();
my %config = $config->config;
my $slurpreg = QhtLink::Slurp->slurpreg;
my $cleanreg = QhtLink::Slurp->cleanreg;

Cpanel::Rlimit::set_rlimit_to_infinity();

if (-e "/usr/local/cpanel/bin/register_appconfig") {
	$script = "qhtlfirewall.cgi";
	$images = "qhtlfirewall";
} else {
	$script = "addon_qhtlfirewall.cgi";
	$images = "qhtlfirewall";
}

foreach my $line (slurp("/etc/qhtlfirewall/qhtlfirewall.resellers")) {
	$line =~ s/$cleanreg//g;
	my ($user,$alert,$privs) = split(/\:/,$line);
	$privs =~ s/\s//g;
	foreach my $priv (split(/\,/,$privs)) {
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

open (my $IN, "<", "/etc/qhtlfirewall/version.txt") or die $!;
$myv = <$IN>;
close ($IN);
chomp $myv;

# Lightweight JSON status endpoint for sanctioned WHM includes
# Usage: /cgi/qhtlink/qhtlfirewall.cgi?action=status_json
if (defined $FORM{action} && $FORM{action} eq 'status_json') {
	my $is_disabled = -e "/etc/qhtlfirewall/qhtlfirewall.disable" ? 1 : 0;
	my $is_test     = $config{TESTING} ? 1 : 0;
	my $ipt_ok      = 0;
	eval {
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, "$config{IPTABLES} $config{IPTABLESWAIT} -L LOCALINPUT -n");
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
	print "Content-type: application/json\r\n\r\n";
	print $json;
	exit 0;
}

# Lightweight JavaScript endpoint to render a header badge without relying on inline JS in templates.
# Usage: /cgi/qhtlink/qhtlfirewall.cgi?action=banner_js (use relative path so cpsess is preserved)
if (defined $FORM{action} && $FORM{action} eq 'banner_js') {
		print "Content-type: application/javascript\r\n\r\n";
		print <<'JS';
(function(){
	function onReady(fn){ if(document.readyState!=='loading'){ fn(); } else { document.addEventListener('DOMContentLoaded', fn, { once:true }); } }
	onReady(function(){
		try {
			if (document.getElementById('qhtlfw-badge')) { return; }
			var url = 'cgi/qhtlink/qhtlfirewall.cgi?action=status_json';
			var controller = (typeof AbortController!=='undefined') ? new AbortController() : null;
			var to = controller ? setTimeout(function(){ try{controller.abort();}catch(e){} }, 1800) : null;
			var fetchOpts = { credentials: 'same-origin' };
			if (controller) fetchOpts.signal = controller.signal;
			(window.fetch ? fetch(url, fetchOpts) : Promise.reject('no-fetch'))
				.then(function(r){ return (r && r.ok) ? r.json() : null; })
				.then(function(data){
					if (to) clearTimeout(to);
					if(!data) return;
					var cls = data.class || 'default';
					var txt = data.text || 'Firewall';
					var overlay = document.createElement('div');
					overlay.id = 'qhtlfw-badge';
					overlay.style.position = 'fixed';
					overlay.style.top = '10px';
					overlay.style.right = '16px';
					overlay.style.zIndex = '2147483647';
					overlay.style.pointerEvents = 'none';
					overlay.style.fontFamily = 'system-ui, -apple-system, Segoe UI, Roboto, sans-serif';
					var badge = document.createElement('span');
					badge.className = 'label label-' + cls;
					badge.style.pointerEvents = 'auto';
					badge.style.padding = '4px 8px';
					badge.style.display = 'inline-block';
					badge.style.margin = '0';
					badge.textContent = 'Firewall: ' + txt;
					overlay.appendChild(badge);
					document.body.appendChild(overlay);

					var attempt = function(){
						try {
							var stats = document.querySelector('cp-whm-header-stats-control');
							if (!stats) return false;
							if (stats.shadowRoot) {
								var host = stats.shadowRoot.querySelector('.header-stats, header, div');
								if (host) {
									var span = document.createElement('span');
									span.className = 'label label-' + cls;
									span.style.marginLeft = '8px';
									span.textContent = 'Firewall: ' + txt;
									host.appendChild(span);
									return true;
								}
							}
						} catch(e) {}
						return false;
					};
					var tries = 0;
					var iv = setInterval(function(){
						tries++;
						if (attempt()) {
							overlay.style.display = 'none';
							clearInterval(iv);
						}
						if (tries > 20) { clearInterval(iv); }
					}, 100);
				})
				.catch(function(e){ /* ignore */ });
		} catch(e) {}
	});
})();
JS
		;
		exit 0;
}

	# Minimal HTML banner for iframe embedding (no JS required in parent)
	if (defined $FORM{action} && $FORM{action} eq 'banner_frame') {
		my $is_disabled = -e "/etc/qhtlfirewall/qhtlfirewall.disable" ? 1 : 0;
		my $is_test     = $config{TESTING} ? 1 : 0;
		my $ipt_ok      = 0;
		eval {
			my ($childin, $childout);
			my $pid = open3($childin, $childout, $childout, "$config{IPTABLES} $config{IPTABLESWAIT} -L LOCALINPUT -n");
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
		print "X-Frame-Options: SAMEORIGIN\r\n";
		print "Content-Security-Policy: frame-ancestors 'self';\r\n\r\n";
		print "<!doctype html><html><head><meta charset=\"utf-8\">\n";
		print "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'none'\">\n";
		print "<style>html,body{margin:0;padding:0;background:transparent} .label{display:inline-block;font:12px/1.2 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:#fff;border-radius:3px;padding:4px 8px} .label-success{background:#5cb85c} .label-warning{background:#f0ad4e} .label-danger{background:#d9534f}</style>\n";
		print "</head><body><span class=\"label label-$cls\">Firewall: $txt</span></body></html>";
		exit 0;
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
<div id="loader"></div><br />
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

#eval {
if ($reseller) {
	QhtLink::DisplayResellerUI::main(\%FORM, $script, 0, $images, $myv, 'cpanel');
} else {
	QhtLink::DisplayUI::main(\%FORM, $script, 0, $images, $myv, 'cpanel');
}
#};
#if ($@) {
#	print "Error during UI output generation: [$@]\n";
#	warn "Error during UI output generation: [$@]\n";
#}

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd") {
	print <<EOF;
<script>
function getCookie(cname) {
	var name = cname + "=";
	var ca = document.cookie.split(';');
	for(var i = 0; i <ca.length; i++) {
		var c = ca[i];
		while (c.charAt(0)==' ') {
			c = c.substring(1);
		}
		if (c.indexOf(name) == 0) {
			return c.substring(name.length,c.length);
		}
	}
	return "";
} 
\$("#loader").hide();
\$("#docs-link").hide();
\$.fn.scrollBottom = function() { 
  return \$(document).height() - this.scrollTop() - this.height(); 
};
\$('#botlink').on("click",function(){
	\$('html,body').animate({ scrollTop: 0 }, 'slow', function () {});
});
\$('#toplink').on("click",function() {
	var window_height = \$(window).height();
	var document_height = \$(document).height();
	\$('html,body').animate({ scrollTop: window_height + document_height }, 'slow', function () {});
});
/* Removed All-tab handler: tabAll no longer present */
\$(document).ready(function(){
	\$('[data-tooltip="tooltip"]').tooltip();
	\$(window).scroll(function () {
		if (\$(this).scrollTop() > 500) {
			\$('#botlink').fadeIn();
		} else {
			\$('#botlink').fadeOut();
		}
		if (\$(this).scrollBottom() > 500) {
			\$('#toplink').fadeIn();
		} else {
			\$('#toplink').fadeOut();
		}
	});
EOF
	if ($config{STYLE_MOBILE} or $reseller) {
		print <<EOF;
	var qhtlfirewallview = getCookie('qhtlfirewallview');
	if (qhtlfirewallview == 'mobile') {
		\$(".mobilecontainer").css('display','block');
		\$(".normalcontainer").css('display','none');
		\$("#qhtlfirewallreturn").addClass('btn-primary btn-lg btn-block').removeClass('btn-default');
	} else if (qhtlfirewallview == 'desktop') {
		\$(".mobilecontainer").css('display','none');
		\$(".normalcontainer").css('display','block');
		\$("#qhtlfirewallreturn").removeClass('btn-primary btn-lg btn-block').addClass('btn-default');
	}
	if (top.location == location) {
		\$("#cpframetr2").show();
	} else {
		\$("#cpframetr2").hide();
	}
	if (\$(".mobilecontainer").css('display') == 'block' ) {
		document.cookie = "qhtlfirewallview=mobile; path=/";
		if (top.location != location) {
			top.location.href = document.location.href ;
		}
	}
	\$(window).resize(function() {
		if (\$(".mobilecontainer").css('display') == 'block' ) {
			document.cookie = "qhtlfirewallview=mobile; path=/";
			if (top.location != location) {
				top.location.href = document.location.href ;
			}
		}
	});
EOF
	}
	print "});\n";
	if ($config{STYLE_MOBILE} or $reseller) {
		print <<EOF;
\$("#NormalView").click(function(){
	document.cookie = "qhtlfirewallview=desktop; path=/";
	\$(".mobilecontainer").css('display','none');
	\$(".normalcontainer").css('display','block');
});
\$("#MobileView").click(function(){
	document.cookie = "qhtlfirewallview=mobile; path=/";
	if (top.location == location) {
		\$(".normalcontainer").css('display','none');
		\$(".mobilecontainer").css('display','block');
	} else {
		top.location.href = document.location.href;
	}
});
EOF
	}
	print "</script>\n";
	print @footer;
}
unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd") {
	close ($SCRIPTOUT);
	select STDOUT;
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
