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
	my $plugin_css = "<link href='$images/qhtlfirewall.css' rel='stylesheet' type='text/css'>";
	my $plugin_js  = "<script src='$images/qhtlfirewall.js'></script>";
		print "You do not have access to this feature\n";
		exit();
		print $plugin_css;
		print "\n";
		# Inject dynamic theme CSS variables and flags before header
		my $primary = $config{STYLE_BRAND_PRIMARY} // '';
		my $accent  = $config{STYLE_BRAND_ACCENT} // '';
		if ($primary ne '' or $accent ne '') {
			$primary =~ s/[^#a-fA-F0-9]//g;
			$accent  =~ s/[^#a-fA-F0-9]//g;
			my $cssvars = ":root {";
			if ($primary ne '') { $cssvars .= " --qhtlf-color-primary: $primary;" }
			if ($accent  ne '') { $cssvars .= " --qhtlf-color-accent: $accent;" }
			$cssvars .= " }";
			print "<style>".$cssvars."</style>\n";
		}
		my $sparkles = ($config{STYLE_SPARKLES} && $config{STYLE_SPARKLES} =~ /^1$/) ? 1 : 0;
		print "<script>window.QHTLF_THEME = { sparkles: $sparkles };</script>\n";
		print @header;
	$htmltag = "";
}

my $thisapp = "qhtlfirewall";
my $reregister;
	    print $plugin_js;
	    print "\n";
	    print @footer;
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
\$('#tabAll').click(function(){
	\$('#tabAll').addClass('active');  
	\$('.tab-pane').each(function(i,t){
		\$('#myTabs li').removeClass('active'); 
		\$(this).addClass('active');  
	});
});
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
	Cpanel::Template::process_template(
		'whostmgr',
		{
			"template_file" => "${thisapp}.tmpl",
			"${thisapp}_output" => $templatehtml,
			"print"         => 1,
		}
	);
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
