package Cpanel::Config::ConfigObj::Driver::ConfigServerqhtlfirewall::META;

use strict;

our $VERSION = 1.1;

#use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);
sub spec_version {
	return 1;
}

sub meta_version {
    return 1;
}

sub get_driver_name {
    return 'ConfigServerqhtlfirewall_driver';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'Jonathan Michaelson',
        'url'    => 'www.configserver.com',
        'name'   => {
            'short'  => 'ConfigServerqhtlfirewall Driver',
            'long'   => 'ConfigServerqhtlfirewall Driver',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel 11.38.1',
        'abstract' => "A ConfigServerqhtlfirewall driver",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext("ConfigServer qhtlfirewall driver");
    }

    return $content;
}

sub showcase {
    return;
}
1;
