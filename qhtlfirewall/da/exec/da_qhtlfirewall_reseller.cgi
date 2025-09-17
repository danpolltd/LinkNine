#!/usr/bin/perl
#WHMADDON:addonupdates:QhtLink Firewall
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################
## no critic (RequireUseWarnings, ProhibitExplicitReturnUndef, ProhibitMixedBooleanOperators, RequireBriefOpen)
# start main
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

our ($reseller, $script, $script_da, $images, %rprivs, $myv, %FORM, %daconfig);

my $config = QhtLink::Config->loadconfig();
my %config = $config->config;
my $slurpreg = QhtLink::Slurp->slurpreg;
my $cleanreg = QhtLink::Slurp->cleanreg;

foreach my $line (slurp("/etc/qhtlfirewall/qhtlfirewall.resellers")) {
	$line =~ s/$cleanreg//g;
	my ($user,$alert,$privs) = split(/\:/,$line);
	$privs =~ s/\s//g;
	foreach my $priv (split(/\,/,$privs)) {
		$rprivs{$user}{$priv} = 1;
	}
	$rprivs{$user}{ALERT} = $alert;
}

my %session;
if ($ENV{SESSION_ID} =~ /^\w+$/) {
	open (my $SESSION, "<", "/usr/local/directadmin/data/sessions/da_sess_".$ENV{SESSION_ID}) or die "Security Error: No valid session ID for [$ENV{SESSION_ID}]";
	flock ($SESSION, LOCK_SH);
	my @data = <$SESSION>;
	close ($SESSION);
	chomp @data;
	foreach my $line (@data) {
		my ($name, $value) = split(/\=/,$line);
		$session{$name} = $value;
	}
}
if (($session{key} eq "") or ($session{ip} eq "") or ($session{key} ne $ENV{SESSION_KEY})) {
	print "Security Error: No valid session key";
	exit;
}

my ($ppid, $pexe) = &getexe(getppid());
if ($pexe ne "/usr/local/directadmin/directadmin") {
	print "Security Error: Invalid parent";
	exit;
}

delete $ENV{REMOTE_USER};

#print "content-type: text/html\n\n";
#foreach my $key (keys %ENV) {
#	print "ENV $key = [$ENV{$key}]<br>\n";
#}
#foreach my $key (keys %session) {
#	print "session $key = [$session{$key}]<br>\n";
#}

if (($session{key} ne "" and ($ENV{SESSION_KEY} eq $session{key})) and
	($session{ip} ne "" and ($ENV{REMOTE_ADDR} eq $session{ip}))) {
	my @usernames = split(/\|/,$session{username});
	$ENV{REMOTE_USER} = $usernames[-1];
}

$reseller = 0;
if ($ENV{REMOTE_USER} ne "" and $ENV{REMOTE_USER} eq $ENV{QHTLFIREWALL_RESELLER} and $rprivs{$ENV{REMOTE_USER}}{USE}) {
	$reseller = 1;
} else {
	print "You do not have access to this feature\n";
	exit();
}

open (my $IN, "<", "/etc/qhtlfirewall/version.txt") or die $!;
$myv = <$IN>;
close ($IN);
chomp $myv;

$script = "/CMD_PLUGINS_RESELLER/qhtlfirewall/index.raw";
$script_da = "/CMD_PLUGINS_RESELLER/qhtlfirewall/index.raw";
$images = "/CMD_PLUGINS_RESELLER/qhtlfirewall/images";

my $buffer = $ENV{'QUERY_STRING'};
if ($buffer eq "") {$buffer = $ENV{POST}}
my @pairs = split(/&/, $buffer);
foreach my $pair (@pairs) {
	my ($name, $value) = split(/=/, $pair);
	$value =~ tr/+/ /;
	$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
	$FORM{$name} = $value;
}

open (my $DIRECTADMIN, "<", "/usr/local/directadmin/conf/directadmin.conf");
my @data = <$DIRECTADMIN>;
close ($DIRECTADMIN);
chomp @data;
foreach my $line (@data) {
	my ($name,$value) = split(/\=/,$line);
	$daconfig{$name} = $value;
}

my $bootstrapcss = "<link rel='stylesheet' href='$images/bootstrap/css/bootstrap.min.css'>";
my $jqueryjs = "<script src='$images/jquery.min.js'></script>";
my $bootstrapjs = "<script src='$images/bootstrap/js/bootstrap.min.js'></script>";

my @header;
my @footer;
my $bodytag;
my $htmltag = " data-post='$FORM{action}' ";
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
if (-e "/etc/qhtlfirewall/qhtlfirewall.htmltag") {
	open (my $HTMLTAG, "<", "/etc/qhtlfirewall/qhtlfirewall.htmltag");
	flock ($HTMLTAG, LOCK_SH);
	$htmltag .= <$HTMLTAG>;
	chomp $htmltag;
	close ($HTMLTAG);
}
if (-e "/etc/qhtlfirewall/qhtlfirewall.bodytag") {
	open (my $BODYTAG, "<", "/etc/qhtlfirewall/qhtlfirewall.bodytag");
	flock ($BODYTAG, LOCK_SH);
	$bodytag = <$BODYTAG>;
	chomp $bodytag;
	close ($BODYTAG);
}
unless ($config{STYLE_CUSTOM}) {
	undef @header;
	undef @footer;
	$htmltag = "";
	$bodytag = "";
}

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd") {
	print <<EOF;
<!doctype html>
<html lang='en' $htmltag>
<head>
	<title>QhtLink Firewall</title>
	<meta charset='utf-8'>
	<meta name='viewport' content='width=device-width, initial-scale=1'>
	$bootstrapcss
	<link href='$images/qhtlfirewall.css' rel='stylesheet' type='text/css'>
	$jqueryjs
	$bootstrapjs

<style>
.mobilecontainer {
	display:none;
}
.normalcontainer {
	display:block;
}
EOF
	if ($config{STYLE_MOBILE}) {
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
	print <<EOF;
</head>
<body $bodytag>
<div id="loader"></div>
<a id='toplink' class='toplink' title='Go to bottom'><span class='glyphicon glyphicon-hand-down'></span></a>
<div class='container-fluid'>
<br>
<div class='panel panel-default'>
<h4><img src='$images/qhtlfirewall_small.png' style='padding-left: 10px'> QhtLink Firewall - qhtlfirewall v$myv</h4>
</div>
EOF
}

QhtLink::DisplayResellerUI::main(\%FORM, $script, 0, $images, $myv);

unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd") {
	print <<EOF;
<a class='botlink' id='botlink' title='Go to top'><span class='glyphicon glyphicon-hand-up'></span></a>
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
	if ($config{STYLE_MOBILE}) {
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
EOF
	}
	print "});\n";
	if ($config{STYLE_MOBILE}) {
		print <<EOF;
	\$("#NormalView").click(function(){
		document.cookie = "qhtlfirewallview=desktop; path=/";
		\$(".mobilecontainer").css('display','none');
		\$(".normalcontainer").css('display','block');
	});
	\$("#MobileView").click(function(){
		document.cookie = "qhtlfirewallview=mobile; path=/";
		\$(".mobilecontainer").css('display','block');
		\$(".normalcontainer").css('display','none');
	});
EOF
	}
	print "</script>\n";
	print @footer;
	print "</body>\n";
	print "</html>\n";
}
sub getexe {
	my $thispid = shift;
	open (my $STAT, "<", "/proc/".$thispid."/stat");
	my $stat = <$STAT>;
	close ($STAT);
	chomp $stat;
	$stat =~ /\w\s+(\d+)\s+[^\)]*$/;
	my $ppid = $1;
	my $exe = readlink("/proc/".$ppid."/exe");
	return ($ppid, $exe);
}
1;
