#!/usr/bin/perl
#WHMADDON:qhtlfirewall:QhtLink Firewall
###############################################################################
# Copyright (C) 2025 Daniel Nowakowski
#
# https://qhtlf.danpol.co.uk
###############################################################################
## no critic (RequireUseWarnings, ProhibitExplicitReturnUndef, ProhibitMixedBooleanOperators, RequireBriefOpen)
use strict;
use Fcntl qw(:DEFAULT :flock);
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

my $config_obj = QhtLink::Config->loadconfig();
my %config = $config_obj->config;
my $cleanreg = QhtLink::Slurp->cleanreg;

Cpanel::Rlimit::set_rlimit_to_infinity();

# Determine script and asset path within WHM
if (-e "/usr/local/cpanel/bin/register_appconfig") {
    $script = "qhtlfirewall.cgi";
    $images = "qhtlfirewall";
} else {
    $script = "addon_qhtlfirewall.cgi";
    $images = "qhtlfirewall";
}

# Load version string
eval {
    open(my $IN, '<', '/etc/qhtlfirewall/version.txt') or die $!;
    $myv = <$IN> // '';
    close($IN);
    chomp $myv if defined $myv;
};
$myv ||= 'dev';

# Build reseller privileges map
foreach my $line (slurp('/etc/qhtlfirewall/qhtlfirewall.resellers')) {
    $line =~ s/$cleanreg//g;
    my ($user,$alert,$privs) = split(/\:/,$line);
    next unless defined $user;
    $privs //= '';
    $privs =~ s/\s//g;
    foreach my $priv (split(/\,/, $privs)) {
        next unless length $priv;
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
        exit 0;
    }
}

# Capture UI output from DisplayUI
my $templatehtml = '';
open (my $SCRIPTOUT, '>', \$templatehtml);
select $SCRIPTOUT;

# Optional: inject plugin CSS/JS and dynamic theme vars at the top of the content
my $plugin_css = "<link href='$images/qhtlfirewall.css' rel='stylesheet' type='text/css'>\n";
my $primary = $config{STYLE_BRAND_PRIMARY} // '';
my $accent  = $config{STYLE_BRAND_ACCENT}  // '';
if ($primary ne '' or $accent ne '') {
    $primary =~ s/[^#a-fA-F0-9]//g;
    $accent  =~ s/[^#a-fA-F0-9]//g;
    my $cssvars = ":root {";
    $cssvars .= " --qhtlf-color-primary: $primary;" if $primary ne '';
    $cssvars .= " --qhtlf-color-accent: $accent;"   if $accent  ne '';
    $cssvars .= " }";
    print "<style>".$cssvars."</style>\n";
}
my $sparkles = ($config{STYLE_SPARKLES} && $config{STYLE_SPARKLES} =~ /^1$/) ? 1 : 0;
print $plugin_css;
print "<script>window.QHTLF_THEME = { sparkles: $sparkles };</script>\n";

QhtLink::DisplayUI::main(\%FORM, $script, $script, $images, $myv);

# Footer JS include
print "<script src='$images/qhtlfirewall.js'></script>\n";

close ($SCRIPTOUT);
select STDOUT;

# Render within WHM master template
my $thisapp = 'qhtlfirewall';
Cpanel::Template::process_template(
    'whostmgr',
    {
        'template_file'       => "${thisapp}.tmpl",
        "${thisapp}_output"  => $templatehtml,
        'print'               => 1,
    }
);

###############################################################################
## start printcmd
sub printcmd {
    my @command = @_;
    my ($childin, $childout);
    my $pid = open3($childin, $childout, $childout, @command);
    while (<$childout>) { print $_ }
    waitpid ($pid, 0);
    return;
}
## end printcmd
###############################################################################

1;
