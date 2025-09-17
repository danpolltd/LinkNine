###############################################################################
# QhtLink::qhtlwatcherUI - UI integration for QhtLink Watcher
###############################################################################
package QhtLink::qhtlwatcherUI;

use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(displayUI);

sub displayUI {
    # Arguments: (\%FORM, \%ajaxsubs, $script, $unused, $images, $myv, $session)
    print "<div class='panel panel-default panel-body'><h4>QhtLink Watcher UI not available</h4></div>\n";
    return 1;
}

1;
