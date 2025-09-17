package Cpanel::Config::ConfigObj::Driver::QhtLinkFirewall;

use strict;
use Cpanel::Config::ConfigObj::Driver::QhtLinkFirewall::META ();
*VERSION = $Cpanel::Config::ConfigObj::Driver::QhtLinkFirewall::META::VERSION;

our @ISA = qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

sub init {
    my ( $class, $software_obj ) = @_;

    my $QhtLinkFirewall_defaults = {
        'thirdparty_ns' => 'QhtLinkFirewall',
        'meta'          => {},
    };
    my $self = $class->SUPER::base( $QhtLinkFirewall_defaults, $software_obj );

    return $self;
}

sub enable { my ( $self, $input ) = @_; return 1; }
sub disable { my ( $self, $input ) = @_; return 1; }

sub info {
    my ($self)   = @_;
    my $meta_obj = $self->meta();
    my $abstract = $meta_obj->abstract();
    return $abstract;
}

sub acl_desc {
    return [
        {
            'acl'              => 'software-qhtlfirewall',
            'default_value'    => 0,
            'default_ui_value' => 0,
            'name'             => 'QhtLink Firewall (Reseller UI)',
            'acl_subcat'       => 'Third Party Services',
        },
    ];
}

1;
