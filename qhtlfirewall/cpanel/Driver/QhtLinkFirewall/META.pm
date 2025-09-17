package Cpanel::Config::ConfigObj::Driver::QhtLinkFirewall::META;

use strict;

our $VERSION = 1.2;

sub spec_version { return 1; }
sub meta_version { return 1; }

sub get_driver_name { return 'QhtLinkFirewall_driver'; }

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'Danpol Limited',
        'url'    => 'https://qhtlf.danpol.co.uk',
        'name'   => {
            'short'  => 'QhtLink Firewall Driver',
            'long'   => 'QhtLink Firewall Driver',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel 11.38.1',
        'abstract' => 'A QhtLink Firewall driver',
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext('QhtLink Firewall driver');
    }

    return $content;
}

sub showcase { return; }
1;
