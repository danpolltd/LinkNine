###############################################################################
# QhtLink::qhtlwatcher - integration for QhtLink Watcher
###############################################################################
package QhtLink::qhtlwatcher;

use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(Rports Rreport);

# Return a hash of relevant ports; default empty unless implemented
sub Rports {
    return ();
}

# Report hook (trigger, ip, message, context)
sub Rreport {
    my ($trigger, $ip, $message, $context) = @_;
    # No-op placeholder; integrate with QhtLink reporting if needed
    return 1;
}

1;
