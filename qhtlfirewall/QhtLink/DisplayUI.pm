package QhtLink::DisplayUI;
BEGIN {
	# Try to load optional/required modules; ignore failures where safe
	eval { require QhtLink::ServerStats; QhtLink::ServerStats->import(); 1 } or do { };
	eval { require QhtLink::URLGet;      QhtLink::URLGet->import();      1 } or do { };
	eval { require QhtLink::Config;      QhtLink::Config->import();      1 } or do { };
	eval { require QhtLink::Slurp;       QhtLink::Slurp->import();       1 } or do { };
	eval { require QhtLink::GetEthDev;   QhtLink::GetEthDev->import();   1 } or do { };
	eval { require IPC::Open3;           IPC::Open3->import(qw(open3));  1 } or do { };
	eval { require QhtLink::CheckIP;     QhtLink::CheckIP->import(qw(checkip)); 1 } or do { };
	eval { require QhtLink::Sanity;      QhtLink::Sanity->import(qw(sanity)); 1 } or do { };
	# Also try to load feature modules used in sections below; keep optional
	eval { require QhtLink::ServerCheck;  QhtLink::ServerCheck->import(); 1 } or do { };
	eval { require QhtLink::RBLCheck;     QhtLink::RBLCheck->import();     1 } or do { };
	eval { require QhtLink::Ports;        QhtLink::Ports->import();        1 } or do { };
	# Needed for fileparse() usages around profiles/backups
	eval { require File::Basename;        File::Basename->import(qw(fileparse)); 1 } or do { };
}

# Local wrappers to avoid undefined subroutines when called without fully qualified names
sub slurp { return QhtLink::Slurp::slurp(@_); }

sub resize {
	my ($pos, $auto_scroll) = @_;
	# Historically this adjusts the output container size; keep as no-op in this UI
	return;
}
## Version comparison helper (returns 1 if a > b, -1 if a < b, 0 if equal)
sub ver_cmp {
	my ($a, $b) = @_;
	my @a = split /\./, $a;
	my @b = split /\./, $b;
	for (my $i = 0; $i < @a || $i < @b; $i++) {
		my $ai = $i < @a ? $a[$i] : 0;
		my $bi = $i < @b ? $b[$i] : 0;
		return 1 if $ai > $bi;
		return -1 if $ai < $bi;
	}
	return 0;
}


# Lightweight version retrieval helpers (placed before main for early use)
sub manualversion {
	my ($curv) = @_;
	my ($upgrade, $actv, $src, $err) = (0, '', '', '');

	# Local helper: load mirror list from /etc/qhtlfirewall/downloadservers
	my $load_mirrors = sub {
		my %seen; my @servers;
		my $list = '/etc/qhtlfirewall/downloadservers';
		if (-r $list) {
			foreach my $line (slurp($list)) {
				$line =~ s/$cleanreg//g if defined $cleanreg;
				$line =~ s/#.*$//; $line =~ s/^\s+|\s+$//g;
				next unless length $line;
				# accept bare hostnames or scheme+host (strip any path portion)
				$line =~ s{^https?://}{}i;   # strip any scheme
				$line =~ s{/.*$}{};          # drop any path after host[:port]
				$line =~ s{/+\z}{};         # trim stray trailing slash
				next if $seen{lc $line}++;
				push @servers, $line;
			}
		}
		# Prefer the chosen server (if available in config) at the front
		if (defined $config{DOWNLOADSERVER} && $config{DOWNLOADSERVER} ne '') {
			my $c = $config{DOWNLOADSERVER};
			$c =~ s{^https?://}{}i; $c =~ s{/.*$}{}; $c =~ s{/+\z}{};
			if (!$seen{lc $c}++) { unshift @servers, $c; }
		}
		# Shuffle for resilience
		for (my $x = @servers; --$x;) {
			my $y = int(rand($x+1));
			next if $x == $y;
			@servers[$x,$y] = @servers[$y,$x];
		}
		return @servers;
	};

	# Ensure HTTP client is available; provide a clear error if not
	if (!defined $urlget) {
		$err = 'HTTP client not initialized';
		return ($upgrade, $actv, $src, $err);
	}

	eval {

		my @mirrors = $load_mirrors->();
		my $html = '';
		$html .= <<'QHTL_TABS_CSS';
<style>
/* qhtl tabs: tightly scoped, high-specificity to avoid collisions */
.qhtl-tabs { margin: 8px 0; }
	.qhtl-tabs .qhtl-tabs-radio { position: absolute; left: -9999px; width: 1px; height: 1px; overflow: hidden; }
	.qhtl-tabs .qhtl-tabs-nav { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 10px 0; padding: 0; list-style: none; }
	.qhtl-tabs .qhtl-tabs-nav label { cursor: pointer; border: 1px solid #ccc; background: #f7f7f7; padding: 6px 10px; border-radius: 4px; font-weight: 600; display: inline-block; }
	.qhtl-tabs .qhtl-tabpanel { display: none !important; }
/* Ensure our panels don’t get hidden by external CSS */
.qhtl-tabs .qhtl-tabpanel * { box-sizing: border-box; }
</style>
QHTL_TABS_CSS
		push @mirrors, 'update.qhtl.link' if !@mirrors;

		my $last_err = '';
		MIRROR: for my $host (@mirrors) {
			for my $scheme ('https','http') {
				my $url = "$scheme://$host/qhtlfirewall/version.txt";
				my ($rc, $data) = $urlget->urlget($url);
				if (!$rc && defined $data) {
					# Be tolerant: strip BOM, then scan lines for a clean version token
					$data =~ s/^\xEF\xBB\xBF//;   # UTF-8 BOM (at very start)
					my $found = '';
					for my $line (split /\r?\n/, $data){
						$line =~ s/^\s+|\s+$//g; next unless length $line;
						# Accept: v1.2[.3[.4]][-suffix]
						if ($line =~ /^v?(\d+(?:\.\d+){1,3})\b/i) { $found = $1; last; }
					}
					# As a last resort, try a multi-line anchored search for a single-token version line
					if (!$found && $data =~ /^\s*v?(\d+(?:\.\d+){1,3})\s*$/m) { $found = $1; }
					if ($found) { $actv = $found; $src = $host; }
				}
				if ($actv) {
					$upgrade = 1 if ver_cmp($actv, $curv) == 1;
					$err = '';
					last MIRROR;
				} else {
					my $why = defined $data ? $data : '';
					$why =~ s/[\r\n]+/ /g; $why =~ s/\s{2,}/ /g; $why = substr($why,0,180);
					$last_err = ($why ne '' ? $why : 'Unknown error');
				}
			}
		}
		if (!$actv) {
			my $count = scalar @mirrors;
			$err = 'Version check failed' . ($count ? ": tried $count mirror(s); last error: $last_err" : '');
		}
	};
	if ($@) { $err = 'Version check failed'; }
	return ($upgrade, $actv, $src, $err);
}

sub qhtlfirewallgetversion {
	my ($product, $curv) = @_;
	my ($upgrade, $actv) = (0,'');
	my ($u,$a) = (0,'');
	my ($flag, $act, $src, $err) = manualversion($curv);
	$upgrade = $flag; $actv = $act;
	return ($upgrade, $actv);
}

# Build non-destructive tabs for ServerCheck output. The first tab "General"
# shows non-section content (intro note + scorecard) and the action forms. Each
# subsequent tab contains exactly one original section (title block + lines).
sub _qhtl_render_servercheck_tabs {
		my ($full_html, $forms_html) = @_;

		# Defensive defaults
		$full_html  = '' unless defined $full_html;
		$forms_html = '' unless defined $forms_html;

		# Identify the start of the scorecard (Server Score) – use a tolerant marker
		my $score_idx = index($full_html, 'Server Score:');
		my $pre       = $full_html;   # content before first section (intro note)
		my $scorecard = '';
		if ($score_idx > -1) {
				# Include a small buffer before the heading to preserve layout breaks
				my $prefix_cut = rindex($full_html, '<br>', $score_idx);
				$prefix_cut = ($prefix_cut > -1) ? $prefix_cut : $score_idx;
				$scorecard = substr($full_html, $prefix_cut);
				$pre       = substr($full_html, 0, $prefix_cut);
		}

		# Extract sections: each begins with the addtitle() header block which is a
		# <div> containing a <strong>Title</strong> and a distinctive background.
		# We don’t rely on the exact inline styles – match a <div><strong>..</strong></div>.
		my @sections;
		my $work   = $pre; # re-scan pre+score separation correctly; we want sections within $pre
		$work      = $full_html; # sections live in the body (excluding scorecard at end)
		if ($score_idx > -1) { $work = substr($full_html, 0, $score_idx); }

		my $pos = 0;
		while ($work =~ m{<div[^>]*>\s*<strong>([^<]+)<\/strong>\s*<\/div>}g) {
				my $title   = $1;
				my $start   = $-[0];
				my $end     = pos($work);
				# Find the start of the next title to bound this section
				my $next_at = ($work =~ m{<div[^>]*>\s*<strong>([^<]+)<\/strong>\s*<\/div>}g) ? $-[0] : length($work);
				# Reset pos to after the current end for next loop step
				pos($work) = $end;
				# Compute slice: from this title start up to the next title (or end)
				my $slice_end = $next_at;
				my $html = substr($work, $start, $slice_end - $start);
				push @sections, { title => $title, html => $html };
		}

		# General tab content: everything not a section that’s still meaningful.
		# We keep only the top note (anything before the first section title) and
		# the scorecard; then append forms.
		my $first_title_pos = -1;
		if ($work =~ m{<div[^>]*>\s*<strong>([^<]+)<\/strong>\s*<\/div>}s) {
				$first_title_pos = $-[0];
		}
		my $intro = '';
		if ($first_title_pos > 0) { $intro = substr($work, 0, $first_title_pos); }
		elsif ($first_title_pos == -1) { $intro = $work; }

		# Build the tab UI. Keep CSS/JS strongly namespaced to avoid host theme clashes.
		my $html = '';
		$html .= <<'QHTL_TABS_CSS';
<style>
/* qhtl tabs: tightly scoped, high-specificity to avoid collisions */
.qhtl-tabs { margin: 8px 0; }
	.qhtl-tabs .qhtl-tabs-radio { position: absolute; left: -9999px; width: 1px; height: 1px; overflow: hidden; }
	.qhtl-tabs .qhtl-tabs-nav { display: flex; flex-wrap: wrap; gap: 6px; margin: 0 0 10px 0; padding: 0; list-style: none; }
	.qhtl-tabs .qhtl-tabs-nav label { cursor: pointer; border: 1px solid #ccc; background: #f7f7f7; padding: 6px 10px; border-radius: 4px; font-weight: 600; display: inline-block; }
	.qhtl-tabs .qhtl-tabpanel { display: none !important; }
/* Ensure our panels don’t get hidden by external CSS */
.qhtl-tabs .qhtl-tabpanel * { box-sizing: border-box; }
</style>
QHTL_TABS_CSS

			# Build tabs list: General + sections
			my @labels = ('General');
			push @labels, map { $_->{title} } @sections;
			my @ids;
			for my $i (0..$#labels) {
					my $id = $labels[$i];
					$id =~ s/[^A-Za-z0-9]+/-/g;
					$id =~ s/^-|-$/-/g; $id =~ s/-{2,}/-/g; $id =~ s/-$//; $id =~ s/^-//;
					$id = lc($id);
					$id = "gen" if $i == 0;
					# Ensure uniqueness
					my $base = $id; my $n = 2;
					while (grep { $_ eq $id } @ids) { $id = $base."-".$n++; }
					push @ids, $id;
			}

			# Render container
			$html .= "<div class='qhtl-tabs' id='qhtl-tabs-servercheck'>\n";
			# Add JS that allows re-clicking the currently active tab label to reset (return to General)
			$html .= "<script>(function(){try{var wrap=document.getElementById('qhtl-tabs-servercheck');if(!wrap)return;var radios=[].slice.call(wrap.querySelectorAll('.qhtl-tabs-radio'));var first=radios[0];wrap.addEventListener('click',function(e){var lab=e.target.closest('label');if(!lab)return;var forId=lab.getAttribute('for');if(!forId)return;var r=document.getElementById(forId);if(!r)return; if(r.checked && first && first!==r){ first.checked=true; } });}catch(_){}})();</script>";

			# Hidden radio inputs for pure-CSS tab switching (must be siblings of nav and panels)
			for my $i (0..$#ids) {
				my $rid = 'qhtl-r-'.$ids[$i];
				my $checked = ($i==0) ? " checked" : "";
				$html .= "  <input class='qhtl-tabs-radio' type='radio' name='qhtl-sc-tabs' id='$rid' value='$rid'$checked>\n";
			}

			# Tab labels/nav
			$html .= "  <ul class='qhtl-tabs-nav'>\n";
			for my $i (0..$#ids) {
					my $rid = 'qhtl-r-'.$ids[$i];
					my $lab = $labels[$i];
					$lab =~ s/&/&amp;/g; $lab =~ s/</&lt;/g; $lab =~ s/>/&gt;/g;
					$html .= "    <li><label for='$rid'>$lab</label></li>\n";
			}
			$html .= "  </ul>\n";

			# Panels wrapper
			$html .= "  <div class='qhtl-panels'>\n";
			for my $i (0..$#labels) {
					my $id = $ids[$i];
					$html .= "    <div id='qhtl-tab-$id' class='qhtl-tabpanel' role='tabpanel'>\n";
					if ($i == 0) {
							$html .= $intro if length $intro;
							$html .= $scorecard if length $scorecard;
							$html .= $forms_html if length $forms_html;
					} else {
							my $sec = $sections[$i-1];
							$html .= $sec->{html} if $sec && $sec->{html};
					}
					$html .= "    </div>\n";
			}
			$html .= "  </div>\n"; # .qhtl-panels

			# Generate CSS rules to show the panel for the checked radio and style its label
			$html .= "<style>\n";
			for my $i (0..$#ids) {
					my $rid = 'qhtl-r-'.$ids[$i];
					my $pid = 'qhtl-tab-'.$ids[$i];
					# Show panel
					$html .= "#qhtl-tabs-servercheck #$rid:checked ~ .qhtl-panels #$pid { display:block !important; }\n";
					# Style active label
					$html .= "#qhtl-tabs-servercheck #$rid:checked ~ .qhtl-tabs-nav label[for='$rid'] { background:#e7f0ff; border-color:#8fb3ff; }\n";
			}
			$html .= "</style>\n";

			$html .= "</div>\n"; # .qhtl-tabs

		return $html;
}
###############################################################################
# start main
sub main {
	my $form_ref = shift; %FORM = %{$form_ref} if $form_ref;
	$script      = shift; # cgi script path/name
	$script_da   = shift; # directadmin script path (or 0)
	$images      = shift; # images base path
	$myv         = shift; # version string
	$panel       = shift; # optional panel name

	# Load config for this module's scope (guard against undef)
	my $cfg;
	eval { $cfg = QhtLink::Config->loadconfig(); 1 } or do { $cfg = undef };
	if (defined $cfg && eval { $cfg->can('config') }) {
		%config = $cfg->config();
	} else {
		%config = ();
	}

	# Honor explicit panel context (e.g., 'cpanel') passed from caller
	if (defined $panel && $panel ne '') {
		$config{THIS_UI} = $panel;
	}

	$cleanreg   = QhtLink::Slurp->cleanreg;

	# Optional charts: initialize stats backend when enabled
	my $chart = 1;
	if ($config{ST_ENABLE}) {
		my $init_ok = eval { QhtLink::ServerStats::init() };
		if (!defined $init_ok) { $chart = 0 }
	}

	# HTTP client used for version/changelog fetches
	$urlget = QhtLink::URLGet->new($config{URLGET}, "qhtlfirewall/$myv", $config{URLPROXY});
	unless (defined $urlget) {
		$config{URLGET} = 1;
		$urlget = QhtLink::URLGet->new($config{URLGET}, "qhtlfirewall/$myv", $config{URLPROXY});
		print "<p>*WARNING* URLGET set to use LWP but perl module is not installed, reverting to HTTP::Tiny<p>\n";
	}

	if ($config{RESTRICT_UI} == 2) {
		print "<table class='table table-bordered table-striped' style='background:transparent!important'>\n";
		print "<tr><td><font color='red'>qhtlfirewall UI Disabled via the RESTRICT_UI option in /etc/qhtlfirewall/qhtlfirewall.conf</font></td></tr>\n";
		print "</tr></table>\n";
		return;
	}

	if ($FORM{ip} ne "") { $FORM{ip} =~ s/(^\s+)|(\s+$)//g }

	if (($FORM{ip} ne "") and ($FORM{ip} ne "all") and (!checkip(\$FORM{ip}))) {
		print "[$FORM{ip}] is not a valid IP/CIDR";
	}
	elsif (($FORM{ignorefile} ne "") and ($FORM{ignorefile} =~ /[^\w\.]/)) {
		print "[$FORM{ignorefile}] is not a valid file";
	}
	elsif (($FORM{template} ne "") and ($FORM{template} =~ /[^\w\.]/)) {
		print "[$FORM{template}] is not a valid file";
	}
	elsif ($FORM{action} eq "manualcheck") {
		print "<div><p>Checking version...</p>\n\n";
		my ($upgrade, $actv) = &qhtlfirewallgetversion("qhtlfirewall",$myv);
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&resize("bot",1);
		&printreturn;
	}
	elsif ($FORM{action} eq "disable") {
		print "<div><p>Disabling qhtlfirewall...</p>\n";
		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-x");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&resize("bot",1);
		&printreturn;
	}
	elsif ($FORM{action} eq "enable") {
		# Allow embedded/alternate UI contexts to enable when override flag is explicitly provided
		if ($config{THIS_UI} && !$FORM{override}) {
			print "<div><p>You must login to the root shell to enable qhtlfirewall using:\n<p><b>qhtlfirewall -e</b></p>\n";
		} else {
			print "<div><p>Enabling qhtlfirewall...</p>\n";
			&resize("top");
			print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
			&printcmd("/usr/sbin/qhtlfirewall","-e");
			print "</pre>";
			&resize("bot",1);
		}
		print "<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "chart") {
		# QhtL Stats: render charts inline (AJAX-safe)
		&chart();
		return;
	}
	elsif ($FORM{action} eq "systemstats") {
		# System Stats: render graphs inline; ignore posted graph selection (temporarily disabled)
		if (defined $FORM{graph} && $FORM{graph} ne '') {
			print "<div class='alert alert-info'>Graph selection is temporarily unavailable.</div>\n";
		}
		my $type = '';
		&systemstats($type);
		return;
	}
	elsif ($FORM{action} eq "logtail") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum' onchange='QHTLFIREWALLrefreshtimer()'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		# Ensure global function is available in this page scope and expose a collision-proof wrapper
		print "\nif (typeof window.QHTLFIREWALLgrep !== 'function' && typeof QHTLFIREWALLgrep === 'function') { window.QHTLFIREWALLgrep = QHTLFIREWALLgrep; }\n";
		print "window.QHTL_GREP = function(){ try{ if (typeof QHTLFIREWALLgrep === 'function') return QHTLFIREWALLgrep(); }catch(__){} try{ var fn = window['QHTLFIREWALLgrep']; if (typeof fn === 'function') return fn(); }catch(__){} return false; };\n";
		print "\nif (typeof window.QHTLFIREWALLgrep !== 'function' && typeof QHTLFIREWALLgrep === 'function') { window.QHTLFIREWALLgrep = QHTLFIREWALLgrep; }\n";
		print "window.QHTL_GREP = function(){ try{ if (typeof QHTLFIREWALLgrep === 'function') return QHTLFIREWALLgrep(); }catch(__){} try{ var fn = window['QHTLFIREWALLgrep']; if (typeof fn === 'function') return fn(); }catch(__){} return false; };\n";
	# Ensure wrapper helper exists to avoid form submission and call grep safely
	print "if (typeof window.QHTLFIREWALLgrep !== 'function' && typeof QHTLFIREWALLgrep === 'function') { window.QHTLFIREWALLgrep = QHTLFIREWALLgrep; }\n";
	print "window.QHTL_GREP = function(){ try{ if (typeof QHTLFIREWALLgrep === 'function') return QHTLFIREWALLgrep(); }catch(__){} try{ var fn = window['QHTLFIREWALLgrep']; if (typeof fn === 'function') return fn(); }catch(__){} return false; };\n";
	print "</script>\n";
		print <<EOF;
<div>$options Lines:<input type='text' id="QHTLFIREWALLlines" value="100" size='4'>&nbsp;&nbsp;<button class='btn btn-default' onclick="QHTLFIREWALLrefreshtimer()">Refresh Now</button></div>
<div>Refresh in <span id="QHTLFIREWALLtimer">0</span> <button class='btn btn-default' id="QHTLFIREWALLpauseID" onclick="QHTLFIREWALLpausetimer()" style="width:80px;">Pause</button> <img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both"> &nbsp; </pre>

		<script>
			QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
			QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
			QHTLFIREWALLscript = '$script?action=logtailcmd&ajax=1';
			QHTLFIREWALLtimer();
		</script>
EOF
	# Triangle buttons under logtail UI
	print "  <button id='qhtl-upgrade-manual' type='button' title='Check Manually' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span class='tri-status' id='qhtl-upgrade-status-inline'></span><span>Check Manually</span></span></button>";
	print "  <button id='qhtl-upgrade-changelog' type='button' title='View ChangeLog' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>View ChangeLog</span></span></button>";
	print "  <button id='qhtl-upgrade-rex' type='button' title='eXploit Scanner' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>eXploit Scanner</span></span></button>";
	print "  <button id='qhtl-upgrade-mpass' type='button' title='Mail Moderator' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>Mail Moderator</span></span></button>";
	print "  <button id='qhtl-upgrade-mshield' type='button' title='Mail Shiled' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>Mail Shiled</span></span></button>";
    
	# JS to control logtail font sizing
	print <<'QHTL_JQ_TAIL';
<script>
var myFont = 14;
(function(){
	function apply(){ try{ var el=document.getElementById('QHTLFIREWALLajax'); if(el){ el.style.fontSize = myFont + 'px'; } }catch(_){ }
	}
	apply();
	if (window.jQuery) {
		jQuery('#fontminus-btn').on('click', function(){ myFont--; if(myFont<12) myFont=12; apply(); });
		jQuery('#fontplus-btn').on('click', function(){ myFont++; if(myFont>40) myFont=40; apply(); });
	} else {
		try{ var m=document.getElementById('fontminus-btn'); if(m){ m.addEventListener('click', function(){ myFont--; if(myFont<12) myFont=12; apply(); }); } }catch(_){ }
		try{ var p=document.getElementById('fontplus-btn'); if(p){ p.addEventListener('click', function(){ myFont++; if(myFont>40) myFont=40; apply(); }); } }catch(_){ }
	}
})();
</script>
<!-- Quick View modal handlers are defined once in the main UI script below -->
QHTL_JQ_TAIL
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "logtailcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		my $wrap_pre = ($FORM{ajax} ? 1 : 0);
		if (-z $logfile) {
			if ($wrap_pre) { print "<pre class='comment' style=\"overflow:auto; max-height:500px; white-space: pre-wrap; line-height: 1.5;\">"; }
			print "<---- $logfile is currently empty ---->";
			if ($wrap_pre) { print "</pre>"; }
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					if ($wrap_pre) { print "<pre class='comment' style=\"overflow:auto; max-height:500px; white-space: pre-wrap; line-height: 1.5;\">"; }
					# Read all lines, then optionally reverse for AJAX watcher (newest-first)
					my @buf = <$childout>;
					if ($wrap_pre) { @buf = reverse @buf; }
					foreach my $raw (@buf) {
						my $line = $raw;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
					if ($wrap_pre) { print "</pre>"; }
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		# Ensure global grep function is accessible and provide a safe wrapper callable from HTML
		print "\nif (typeof window.QHTLFIREWALLgrep !== 'function' && typeof QHTLFIREWALLgrep === 'function') { window.QHTLFIREWALLgrep = QHTLFIREWALLgrep; }\n";
		print "window.QHTL_GREP = function(){ try{ if (typeof QHTLFIREWALLgrep === 'function') return QHTLFIREWALLgrep(); }catch(__){} try{ var fn = window['QHTLFIREWALLgrep']; if (typeof fn === 'function') return fn(); }catch(__){} return false; };\n";
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="return (typeof QHTLFIREWALLgrep==='function') ? QHTLFIREWALLgrep() : (window.QHTL_GREP ? QHTL_GREP() : false);">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Font-size controls for grep view with jQuery and vanilla fallbacks
var myFont = 14;
(function(){
	function apply(){ try{ var el=document.getElementById('QHTLFIREWALLajax'); if(el){ el.style.fontSize = myFont + 'px'; } }catch(_){ } }
	apply();
		if (window.jQuery) {
			jQuery('#fontplus-btn').on('click', function(e){ try{e.preventDefault();e.stopPropagation();}catch(_){ } myFont++; if(myFont>40) myFont=40; apply(); return false; });
			jQuery('#fontminus-btn').on('click', function(e){ try{e.preventDefault();e.stopPropagation();}catch(_){ } myFont--; if(myFont<12) myFont=12; apply(); return false; });
		} else {
			try{ var plus=document.getElementById('fontplus-btn'); if(plus){ plus.addEventListener('click', function(ev){ try{ev.preventDefault();ev.stopPropagation();}catch(_){ } myFont++; if(myFont>40) myFont=40; apply(); return false; }); } }catch(_){ }
			try{ var minus=document.getElementById('fontminus-btn'); if(minus){ minus.addEventListener('click', function(ev){ try{ev.preventDefault();ev.stopPropagation();}catch(_){ } myFont--; if(myFont<12) myFont=12; apply(); return false; }); } }catch(_){ }
	}
})();
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		my $wrap_pre = ($FORM{ajax} ? 1 : 0);
		if (-z $logfile) {
			if ($wrap_pre) { print "<pre class='comment' style=\"overflow:auto; max-height:500px; white-space: pre-wrap; line-height: 1.5;\">"; }
			print "<---- $logfile is currently empty ---->";
			if ($wrap_pre) { print "</pre>"; }
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					if ($wrap_pre) { print "<pre class='comment' style=\"overflow:auto; max-height:500px; white-space: pre-wrap; line-height: 1.5;\">"; }
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
					if ($wrap_pre) { print "</pre>"; }
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		# Provide safe grep wrapper even if jQuery or globals differ
		print "if (typeof window.QHTLFIREWALLgrep !== 'function' && typeof QHTLFIREWALLgrep === 'function') { window.QHTLFIREWALLgrep = QHTLFIREWALLgrep; }\n";
		print "window.QHTL_GREP = function(){ try{ if (typeof QHTLFIREWALLgrep === 'function') return QHTLFIREWALLgrep(); }catch(__){} try{ var fn = window['QHTLFIREWALLgrep']; if (typeof fn === 'function') return fn(); }catch(__){} return false; };\n";
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="return (typeof QHTLFIREWALLgrep==='function') ? QHTLFIREWALLgrep() : (window.QHTL_GREP ? QHTL_GREP() : false);">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Font-size controls for grep view with jQuery and vanilla fallbacks
var myFont = 14;
(function(){
	function apply(){ try{ var el=document.getElementById('QHTLFIREWALLajax'); if(el){ el.style.fontSize = myFont + 'px'; } }catch(_){ }
	}
	apply();
	if (window.jQuery) {
		jQuery('#fontplus-btn').on('click', function(){ myFont++; if(myFont>40) myFont=40; apply(); });
		jQuery('#fontminus-btn').on('click', function(){ myFont--; if(myFont<12) myFont=12; apply(); });
	} else {
		try{ var plus=document.getElementById('fontplus-btn'); if(plus){ plus.addEventListener('click', function(){ myFont++; if(myFont>40) myFont=40; apply(); }); } }catch(_){ }
		try{ var minus=document.getElementById('fontminus-btn'); if(minus){ minus.addEventListener('click', function(){ myFont--; if(myFont<12) myFont=12; apply(); }); } }catch(_){ }
	}
})();
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		if (-z $logfile) {
			print "<---- $logfile is currently empty ---->";
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		# Ensure grep function exists and provide a safe, collision-proof wrapper
		print "if (typeof window.QHTLFIREWALLgrep !== 'function' && typeof QHTLFIREWALLgrep === 'function') { window.QHTLFIREWALLgrep = QHTLFIREWALLgrep; }\n";
		print "window.QHTL_GREP = function(){ try{ if (typeof QHTLFIREWALLgrep === 'function') return QHTLFIREWALLgrep(); }catch(__){} try{ var fn = window['QHTLFIREWALLgrep']; if (typeof fn === 'function') return fn(); }catch(__){} return false; };\n";
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="return (typeof QHTLFIREWALLgrep==='function') ? QHTLFIREWALLgrep() : (window.QHTL_GREP ? QHTL_GREP() : false);">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Font-size controls for grep view with jQuery and vanilla fallbacks
var myFont = 14;
(function(){
	function apply(){ try{ var el=document.getElementById('QHTLFIREWALLajax'); if(el){ el.style.fontSize = myFont + 'px'; } }catch(_){ }
	}
	apply();
	if (window.jQuery) {
		jQuery('#fontplus-btn').on('click', function(){ myFont++; if(myFont>40) myFont=40; apply(); });
		jQuery('#fontminus-btn').on('click', function(){ myFont--; if(myFont<12) myFont=12; apply(); });
	} else {
		try{ var plus=document.getElementById('fontplus-btn'); if(plus){ plus.addEventListener('click', function(){ myFont++; if(myFont>40) myFont=40; apply(); }); } }catch(_){ }
		try{ var minus=document.getElementById('fontminus-btn'); if(minus){ minus.addEventListener('click', function(){ myFont--; if(myFont<12) myFont=12; apply(); }); } }catch(_){ }
	}
})();
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		if (-z $logfile) {
			print "<---- $logfile is currently empty ---->";
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="return window.QHTL_GREP && QHTL_GREP();">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Clean jQuery handlers for grep view
var myFont = 14;
$("#fontplus-btn").on('click', function () {
	myFont++;
	if (myFont > 20) { myFont = 20 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
$("#fontminus-btn").on('click', function () {
	myFont--;
	if (myFont < 12) { myFont = 12 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		if (-z $logfile) {
			print "<---- $logfile is currently empty ---->";
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="return window.QHTL_GREP && QHTL_GREP();">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Clean jQuery handlers for grep view
var myFont = 14;
$("#fontplus-btn").on('click', function () {
	myFont++;
	if (myFont > 20) { myFont = 20 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
$("#fontminus-btn").on('click', function () {
	myFont--;
	if (myFont < 12) { myFont = 12 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		if (-z $logfile) {
			print "<---- $logfile is currently empty ---->";
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="return window.QHTL_GREP && QHTL_GREP();">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Clean jQuery handlers for grep view
var myFont = 14;
$("#fontplus-btn").on('click', function () {
	myFont++;
	if (myFont > 20) { myFont = 20 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
$("#fontminus-btn").on('click', function () {
	myFont--;
	if (myFont < 12) { myFont = 12 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		if (-z $logfile) {
			print "<---- $logfile is currently empty ---->";
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "loggrep") {
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}
		my $script_safe = $script;
		my $QHTLFIREWALLfrombot = 120;
		my $QHTLFIREWALLfromright = 10;
		if ($config{DIRECTADMIN}) {
			$script = $script_da;
			$QHTLFIREWALLfrombot = 400;
			$QHTLFIREWALLfromright = 150;
		}
		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $options = "<select id='QHTLFIREWALLlognum'>\n";
		my $cnt = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					my $size = int((stat($globfile))[7]/1024);
					$options .= "<option value='$cnt'";
					if ($globfile eq "/var/log/qhtlwaterfall.log") {$options .= " selected"}
					$options .= ">$globfile ($size kb)</option>\n";
					$cnt++;
				}
			}
		}
		$options .= "</select>\n";
		
		open (my $AJAX, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewallajaxtail.js");
		flock ($AJAX, LOCK_SH);
		my @jsdata = <$AJAX>;
		close ($AJAX);
		print "<script>\n";
		print @jsdata;
		print "</script>\n";
		print <<EOF;
<div>Log: $options</div>
<div style='white-space: nowrap;'>Text: <input type='text' size="30" id="QHTLFIREWALLgrep" onClick="this.select()">&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_i" value="1">-i&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_E" value="1">-E&nbsp;
<input type="checkbox" id="QHTLFIREWALLgrep_Z" value="1"> wildcard&nbsp;
<button type='button' class='btn btn-default' onClick="QHTLFIREWALLgrep()">Search</button>&nbsp;
<img src="$images/loader.gif" id="QHTLFIREWALLrefreshing" style="display:none" /></div>
<div class='pull-right btn-group'><button class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>
<button class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>
<pre class='comment' id="QHTLFIREWALLajax" style="overflow:auto;height:500px;resize:none; white-space: pre-wrap; line-height: 1.5; clear:both">
Please Note:

 1. Searches use $config{GREP}/$config{ZGREP} if wildcard is used), so the search text/regex must be syntactically correct
 2. Use the "-i" option to ignore case
 3. Use the "-E" option to perform an extended regular expression search
 4. Searching large log files can take a long time. This feature has a 30 second timeout
 5. The searched for text will usually be <mark>highlighted</mark> but may not always be successful
 6. Only log files listed in /etc/qhtlfirewall/qhtlfirewall.syslogs can be searched. You can add to this file
 7. The wildcard option will use $config{ZGREP} and search logs with a wildcard suffix, e.g. /var/log/qhtlwaterfall.log*
</pre>

<script>
	QHTLFIREWALLfrombot = $QHTLFIREWALLfrombot;
	QHTLFIREWALLfromright = $QHTLFIREWALLfromright;
	QHTLFIREWALLscript = '$script?action=loggrepcmd&ajax=1';
</script>
EOF
		print <<'QHTL_JQ_GREP';
<script>
// Clean jQuery handlers for grep view
var myFont = 14;
$("#fontplus-btn").on('click', function () {
	myFont++;
	if (myFont > 20) { myFont = 20 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
$("#fontminus-btn").on('click', function () {
	myFont--;
	if (myFont < 12) { myFont = 12 }
	$('#QHTLFIREWALLajax').css('font-size', myFont + 'px');
});
</script>
QHTL_JQ_GREP
		if ($config{DIRECTADMIN}) {$script = $script_safe}
		&printreturn;
	}
	elsif ($FORM{action} eq "loggrepcmd") {
		# meta mode: return JSON list of logs for watcher selector
		if ($FORM{meta}) {
			my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
			foreach my $line (@data) {
				if ($line =~ /^Include\s*(.*)$/) {
					my @incfile = slurp($1);
					push @data,@incfile;
				}
			}
			@data = sort @data;
			my $cnt = 0;
			my @opts = ();
			foreach my $file (@data) {
				$file =~ s/$cleanreg//g;
				if ($file eq "") {next}
				if ($file =~ /^\s*\#|Include/) {next}
				my @globfiles;
				if ($file =~ /\*|\?|\[/) {
					foreach my $log (glob $file) {push @globfiles, $log}
				} else {push @globfiles, $file}

				foreach my $globfile (@globfiles) {
					if (-f $globfile) {
						my $size = int((stat($globfile))[7]/1024);
						my $sel = ($globfile eq "/var/log/qhtlwaterfall.log") ? 1 : 0;
						push @opts, { value => $cnt, label => "$globfile ($size kb)", selected => $sel };
						$cnt++;
					}
				}
			}
			# Manual JSON: [{"value":N,"label":"...","selected":0/1},...]
			my @parts;
			foreach my $o (@opts) {
				my $v = $o->{value};
				my $l = $o->{label};
				$l =~ s/"/\\"/g; # escape quotes
				my $s = $o->{selected} ? 1 : 0;
				push @parts, '{"value":'.$v.',"label":"'.$l.'","selected":'.$s.'}';
			}
			print '[' . join(',', @parts) . ']';
			return;
		}
		$FORM{lines} =~ s/\D//g;
		if ($FORM{lines} eq "" or $FORM{lines} == 0) {$FORM{lines} = 30}

		my @data = slurp("/etc/qhtlfirewall/qhtlfirewall.syslogs");
		foreach my $line (@data) {
			if ($line =~ /^Include\s*(.*)$/) {
				my @incfile = slurp($1);
				push @data,@incfile;
			}
		}
		@data = sort @data;
		my $cnt = 0;
		my $logfile = "/var/log/qhtlwaterfall.log";
		my $hit = 0;
		foreach my $file (@data) {
			$file =~ s/$cleanreg//g;
			if ($file eq "") {next}
			if ($file =~ /^\s*\#|Include/) {next}
			my @globfiles;
			if ($file =~ /\*|\?|\[/) {
				foreach my $log (glob $file) {push @globfiles, $log}
			} else {push @globfiles, $file}

			foreach my $globfile (@globfiles) {
				if (-f $globfile) {
					if ($FORM{lognum} == $cnt) {
						$logfile = $globfile;
						$hit = 1;
						last;
					}
					$cnt++;
				}
			}
			if ($hit) {last}
		}
		if (-z $logfile) {
			print "<---- $logfile is currently empty ---->";
		} else {
			if (-x $config{TAIL}) {
				my $timeout = 30;
				eval {
					local $SIG{__DIE__} = undef;
					local $SIG{'ALRM'} = sub {die};
					alarm($timeout);
					my ($childin, $childout);
					my $pid = open3($childin, $childout, $childout,$config{TAIL},"-$FORM{lines}",$logfile);
					while (<$childout>) {
						my $line = $_;
						$line =~ s/&/&amp;/g;
						$line =~ s/</&lt;/g;
						$line =~ s/>/&gt;/g;
						print $line;
					}
					waitpid ($pid, 0);
					alarm(0);
				};
				alarm(0);
			} else {
				print "Executable [$config{TAIL}] invalid";
			}
		}
	}
	elsif ($FORM{action} eq "readme") {
		&resize("top");
		print "<pre id='output' class='comment' style='white-space: pre-wrap;height: 500px; overflow: auto; resize:none; clear:both'>\n";
		open (my $IN, "<", "/etc/qhtlfirewall/readme.txt") or die $!;
		flock ($IN, LOCK_SH);
		my @readme = <$IN>;
		close ($IN);
		chomp @readme;

		foreach my $line (@readme) {
			$line =~ s/\</\&lt\;/g;
			$line =~ s/\>/\&gt\;/g;
			print $line."\n";
		}
		print "</pre>\n";
		&resize("bot",0);
		&printreturn;
	}
	elsif ($FORM{action} eq "changelog") {
		# Render the installed changelog file the same way as readme
		&resize("top");
		print "<pre id='output' class='comment' style='white-space: pre-wrap;height: 500px; overflow: auto; resize:none; clear:both'>\n";
		my $cl = "/etc/qhtlfirewall/changelog.txt";
		if (-e $cl) {
			open (my $CL, "<", $cl) or die $!;
			flock ($CL, LOCK_SH);
			while (my $line = <$CL>) {
				$line =~ s/\</\&lt\;/g;
				$line =~ s/\>/\&gt\;/g;
				print $line;
			}
			close ($CL);
		} else {
			# Fallback: try to fetch remotely if local file is missing
			my $url = "https://$config{DOWNLOADSERVER}/qhtlfirewall/changelog.txt";
			my ($status, $body) = $urlget->urlget($url);
			# QhtLink::URLGet returns status 0 on success
			if (!$status && defined $body && length $body) {
				$body =~ s/</&lt;/g; $body =~ s/>/&gt;/g;
				print $body;
			} else {
				print "Changelog file not found at $cl and unable to fetch from $url\n";
			}
		}
		print "</pre>\n";
		&resize("bot",0);
		&printreturn;
	}
	elsif ($FORM{action} eq "servercheck") {
		my $out = '';
		my $ok  = 0;
		eval {
			if (defined &QhtLink::ServerCheck::report) {
				$out = QhtLink::ServerCheck::report($FORM{verbose});
				$ok = 1;
			}
			1;
		} or do { $ok = 0; };
		unless ($ok) {
			print "<div class='alert alert-warning'>ServerCheck module not available in this environment. Skipping report.</div>\n";
			&printreturn; return;
		}

		# Build the action forms HTML (Schedule / Run Again / Verbose)
		open (my $IN, "<", "/etc/cron.d/qhtlfirewall-cron");
		flock ($IN, LOCK_SH);
		my @data = <$IN>;
		close ($IN);
		chomp @data;
		my $optionselected = "never";
		my $email;
		if (my @ls = grep {$_ =~ /qhtlfirewall \-m/} @data) {
			if ($ls[0] =~ /\@(\w+)\s+root\s+\/usr\/sbin\/qhtlfirewall \-m (.*)/) {$optionselected = $1; $email = $2}
		}
		my $forms = "";
		$forms .= "<br><div><form action='$script' method='post'><input type='hidden' name='action' value='serverchecksave'>\n";
		$forms .= "Generate and email this report <select name='freq'>\n";
		foreach my $option ("never","hourly","daily","weekly","monthly") {
			if ($option eq $optionselected) { $forms .= "<option selected>$option</option>\n" } else { $forms .= "<option>$option</option>\n" }
		}
		$forms .= "</select> to the email address <input type='text' name='email' value='$email'> <input type='submit' class='btn btn-default' value='Schedule'></form></div>\n";
		$forms .= "<br><div><form action='$script' method='post'><input type='hidden' name='action' value='servercheck'><input type='submit' class='btn btn-default' value='Run Again'></form></div>\n";
		$forms .= "<br><div><form action='$script' method='post'><input type='hidden' name='action' value='servercheck'><input type='hidden' name='verbose' value='1'><input type='submit' class='btn btn-default' value='Run Again and Display All Checks'></form></div>\n";

		# Render tabs view (General + one tab per report section)
		my $tabs_html = _qhtl_render_servercheck_tabs($out, $forms);
		print $tabs_html;
		&printreturn;
	}
	elsif ($FORM{action} eq "serverchecksave") {
		my $extra = "";
		my $freq = "daily";
		my $email;
		if ($FORM{email} ne "") {$email = "root"}
		if ($FORM{email} =~ /^[a-zA-Z0-9\-\_\.\@\+]+$/) {$email = $FORM{email}}
		foreach my $option ("never","hourly","daily","weekly","monthly") {if ($FORM{freq} eq $option) {$freq = $option}}
		unless ($email) {$freq = "never"; $extra = "(no valid email address supplied)";}
		sysopen (my $CRON, "/etc/cron.d/qhtlfirewall-cron", O_RDWR | O_CREAT) or die "Unable to open file: $!";
		flock ($CRON, LOCK_EX);
		my @data = <$CRON>;
		chomp @data;
		seek ($CRON, 0, 0);
		truncate ($CRON, 0);
		my $done = 0;
		foreach my $line (@data) {
			if ($line =~ /qhtlfirewall \-m/) {
				if ($freq and ($freq ne "never") and !$done) {
					print $CRON "\@$freq root /usr/sbin/qhtlfirewall -m $email\n";
					$done = 1;
				}
			} else {
				print $CRON "$line\n";
			}
		}
		if (!$done and ($freq ne "never")) {
				print $CRON "\@$freq root /usr/sbin/qhtlfirewall -m $email\n";
		}
		close ($CRON);

		if ($freq and $freq ne "never") {
			print "<div>Report scheduled to be emailed to $email $freq</div>\n";
		} else {
			print "<div>Report schedule cancelled $extra</div>\n";
		}
		# Return button removed (legacy); users can navigate via tabs or browser back
	}
	elsif ($FORM{action} eq "rblcheck") {
		my $status = 0;
		my $ok = 0;
		# Guard: temporarily disable 'standard' run (verbose=1) even if posted from a stale UI
		if (defined $FORM{verbose} && $FORM{verbose} eq '1') {
			print "<div class='alert alert-info'>The standard RBL update is temporarily unavailable.</div>\n";
			$ok = 1; # suppress module-missing warning below
		} else {
			eval {
				if (defined &QhtLink::RBLCheck::report) {
					($status, undef) = QhtLink::RBLCheck::report($FORM{verbose},$images,1);
					$ok = 1;
				}
				1;
			} or do { $ok = 0; };
		}
		unless ($ok) {
			print "<div class='alert alert-warning'>RBLCheck module not available in this environment. Skipping report.</div>\n";
		}

	print "<div><b>These options can take a long time to run</b> (several minutes) depending on the number of IP addresses to check and the response speed of the DNS requests:</div>\n";
	# Removed: 'Update All Checks (standard)' button (temporarily unavailable)
	print "<br><div><form action='${script}' method='post' data-noajax='1'><input type='hidden' name='action' value='rblcheck'><input type='hidden' name='verbose' value='2'><input type='submit' class='btn btn-default' value='Update All Checks (verbose)'> Generates the normal report but shows successes and failures</form></div>\n";
	print "<br><div><form action='${script}' method='post' data-noajax='1'><input type='hidden' name='action' value='rblcheckedit'><input type='submit' class='btn btn-default' value='Edit RBL Options'> Edit qhtlfirewall.rblconf to enable and disable IPs and RBLs</form></div>\n";

		open (my $IN, "<", "/etc/cron.d/qhtlfirewall-cron");
		flock ($IN, LOCK_SH);
		my @data = <$IN>;
		close ($IN);
		chomp @data;
		my $optionselected = "never";
		my $email;
		if (my @ls = grep {$_ =~ /qhtlfirewall \-\-rbl/} @data) {
			if ($ls[0] =~ /\@(\w+)\s+root\s+\/usr\/sbin\/qhtlfirewall \-\-rbl (.*)/) {$optionselected = $1; $email = $2}
		}
	print "<br><div><form action='${script}' method='post' data-noajax='1'><input type='hidden' name='action' value='rblchecksave'>\n";
	print "Generate and email this report <select name='freq'>\n";
		foreach my $option ("never","hourly","daily","weekly","monthly") {
			if ($option eq $optionselected) {print "<option selected>$option</option>\n"} else {print "<option>$option</option>\n"}
		}
		print "</select> to the email address <input type='text' name='email' value='$email'> <input type='submit' class='btn btn-default' value='Schedule'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "rblchecksave") {
		my $extra = "";
		my $freq = "daily";
		my $email;
		if ($FORM{email} ne "") {$email = "root"}
		if ($FORM{email} =~ /^[a-zA-Z0-9\-\_\.\@\+]+$/) {$email = $FORM{email}}
		foreach my $option ("never","hourly","daily","weekly","monthly") {if ($FORM{freq} eq $option) {$freq = $option}}
		unless ($email) {$freq = "never"; $extra = "(no valid email address supplied)";}
		sysopen (my $CRON, "/etc/cron.d/qhtlfirewall-cron", O_RDWR | O_CREAT) or die "Unable to open file: $!";
		flock ($CRON, LOCK_EX);
		my @data = <$CRON>;
		chomp @data;
		seek ($CRON, 0, 0);
		truncate ($CRON, 0);
		my $done = 0;
		foreach my $line (@data) {
			if ($line =~ /qhtlfirewall \-\-rbl/) {
				if ($freq and ($freq ne "never") and !$done) {
					print $CRON "\@$freq root /usr/sbin/qhtlfirewall --rbl $email\n";
					$done = 1;
				}
			} else {
				print $CRON "$line\n";
			}
		}
		if (!$done and ($freq ne "never")) {
				print $CRON "\@$freq root /usr/sbin/qhtlfirewall --rbl $email\n";
		}
		close ($CRON);

		if ($freq and $freq ne "never") {
			print "<div>Report scheduled to be emailed to $email $freq</div>\n";
		} else {
			print "<div>Report schedule cancelled $extra</div>\n";
		}
		# Return button removed (legacy); users can navigate via tabs or browser back
	}
	elsif ($FORM{action} eq "rblcheckedit") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.rblconf","saverblcheckedit");
		# Return button removed (legacy); users can navigate via tabs or browser back
	}
	elsif ($FORM{action} eq "saverblcheckedit") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.rblconf","");
		# Return button removed (legacy); users can navigate via tabs or browser back
	}
	elsif ($FORM{action} eq "cloudflareedit") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.cloudflare","savecloudflareedit");
		&printreturn;
	}
	elsif ($FORM{action} eq "savecloudflareedit") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.cloudflare","");
		&printreturn;
	}
	elsif ($FORM{action} eq "restartboth") {
		print "<div><p>Restarting qhtlfirewall...</p>\n";
		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-sf");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		if ($config{THIS_UI}) {
			print "<div><p>Signal qhtlwaterfall to <i>restart</i>...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
			open (my $OUT, ">", "/var/lib/qhtlfirewall/qhtlwaterfall.restart") or die "Unable to open file: $!";
			close ($OUT);
		} else {
			print "<div><p>Restarting qhtlwaterfall...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
			QhtLink::Service::restartqhtlwaterfall();
		}
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&resize("bot",1);
		&printreturn;
	}
	elsif ($FORM{action} eq "remapf") {
		print "<div><p>Removing APF/BFD...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("sh","/usr/local/qhtlfirewall/bin/remove_apf_bfd.sh");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		print "<div><p><b>Note: You should check the root cron and /etc/crontab to ensure that there are no apf or bfd related cron jobs remaining</b></p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "qallow") {
		print "<div><p>Allowing $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-a",$FORM{ip},$FORM{comment});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "applytemp") {
		# Apply Temporary Allow/Deny based on UI form (primary path)
		my $do = ($FORM{do} && $FORM{do} eq 'allow') ? 'allow' : 'block';
		$FORM{timeout} =~ s/\D//g;
		if ($FORM{dur} eq "minutes") {$FORM{timeout} = $FORM{timeout} * 60}
		elsif ($FORM{dur} eq "hours") {$FORM{timeout} = $FORM{timeout} * 60 * 60}
		elsif ($FORM{dur} eq "days") {$FORM{timeout} = $FORM{timeout} * 60 * 60 * 24}
		my @cmd = ($do eq 'block') ? ("-td", $FORM{ip}, $FORM{timeout}) : ("-ta", $FORM{ip}, $FORM{timeout});
		if (defined $FORM{ports} && $FORM{ports} ne '' && $FORM{ports} ne '*') { push @cmd, ("-p", $FORM{ports}); }
		if (defined $FORM{comment} && $FORM{comment} ne '') { push @cmd, $FORM{comment}; }
		my $verb = ($do eq 'block') ? 'Blocking' : 'Allowing';
		print "<div><p>Temporarily $verb $FORM{ip} for $FORM{timeout} seconds...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall", @cmd);
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "viewlist") {
		my $which = $FORM{which} || '';
		my %map = (
			allow  => { path => "/etc/qhtlfirewall/qhtlfirewall.allow",  title => "qhtlfirewall.allow" },
			deny   => { path => "/etc/qhtlfirewall/qhtlfirewall.deny",   title => "qhtlfirewall.deny" },
			ignore => { path => "/etc/qhtlfirewall/qhtlfirewall.ignore", title => "qhtlfirewall.ignore" },
		);
		if (!$map{$which}) {
			print "<div class='bs-callout bs-callout-danger'><h4>Unknown list requested</h4></div>";
			&printreturn;
		} else {
			my $path = $map{$which}{path};
			my $title = $map{$which}{title};
			my $bgstyle = '';
			if ($which eq 'allow') {
				$bgstyle = 'background: linear-gradient(180deg, #d4edda 0%, #c3e6cb 100%);';
			} elsif ($which eq 'ignore') {
				$bgstyle = 'background: linear-gradient(180deg, #ffe0b2 0%, #ffcc80 100%);';
			} elsif ($which eq 'deny') {
				$bgstyle = 'background: linear-gradient(180deg, #f8d7da 0%, #f5c6cb 100%);';
			}
			print "<div class='panel panel-default'><div class='panel-heading'><b>Quick View:</b> $title (comments omitted)</div><div class='panel-body'>";
			print "<pre class='comment' style='white-space: pre; overflow-x: hidden; overflow-y: auto; $bgstyle'>\n";
			foreach my $line (slurp($path)) {
				$line =~ s/$cleanreg//g;        # strip comments/blank
				$line =~ s/^\s+|\s+$//g;        # trim
				next if $line eq '';
				$line =~ s/&/&amp;/g; $line =~ s/</&lt;/g; $line =~ s/>/&gt;/g;  # escape
				print "$line\n";
			}
			print "</pre>";
			print "</div></div>";
		}
	}
	elsif ($FORM{action} eq "editlist") {
		my $which = $FORM{which} || '';
		my %map = (
			allow  => { path => "/etc/qhtlfirewall/qhtlfirewall.allow",  title => "qhtlfirewall.allow" },
			deny   => { path => "/etc/qhtlfirewall/qhtlfirewall.deny",   title => "qhtlfirewall.deny" },
			ignore => { path => "/etc/qhtlfirewall/qhtlfirewall.ignore", title => "qhtlfirewall.ignore" },
		);
		if (!$map{$which}) {
			print "<div class='bs-callout bs-callout-danger'><h4>Unknown list requested</h4></div>";
		} else {
			my $path = $map{$which}{path};
			my @lines = slurp($path);
			my $bgstyle = '';
			if ($which eq 'allow') {
				$bgstyle = 'background: linear-gradient(180deg, rgba(212,237,218,0.5) 0%, rgba(195,230,203,0.5) 100%);';
			} elsif ($which eq 'ignore') {
				$bgstyle = 'background: linear-gradient(180deg, rgba(255,224,178,0.5) 0%, rgba(255,204,128,0.5) 100%);';
			} elsif ($which eq 'deny') {
				$bgstyle = 'background: linear-gradient(180deg, rgba(248,215,218,0.5) 0%, rgba(245,198,203,0.5) 100%);';
			}
			print "<div style='display:flex; flex-direction:column; flex:1 1 auto; min-height:0'>";
			print "<div class='small text-muted' style='margin-bottom:6px; flex:0 0 auto'>Editing: $path</div>";
			print "<textarea id='quickEditArea' style='width:100%; flex:1 1 auto; border:1px solid #000; font-family: \"Courier New\", Courier; font-size: 13px; line-height: 1.15; box-sizing:border-box; overflow:auto; resize:none; $bgstyle' wrap='off'>";
			foreach my $line (@lines) {
				$line =~ s/&/&amp;/g; $line =~ s/</&lt;/g; $line =~ s/>/&gt;/g;
				print $line."\n"; # ensure newline between lines in textarea
			}
			print "</textarea></div>";
		}
	}
	elsif ($FORM{action} eq "savelist") {
		my $which = $FORM{which} || '';
		my %map = (
			allow  => { path => "/etc/qhtlfirewall/qhtlfirewall.allow" },
			deny   => { path => "/etc/qhtlfirewall/qhtlfirewall.deny" },
			ignore => { path => "/etc/qhtlfirewall/qhtlfirewall.ignore" },
		);
		if (!$map{$which}) {
			print "<div class='bs-callout bs-callout-danger'><h4>Unknown list requested</h4></div>";
		} else {
			my $path = $map{$which}{path};
			&savefile($path, "");
		}
	}
	elsif ($FORM{action} eq "qdeny") {
		print "<div><p>Blocking $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-d",$FORM{ip},$FORM{comment});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "qignore") {
		print "<div><p>Ignoring $FORM{ip}...\n";
		open (my $OUT, ">>", "/etc/qhtlfirewall/qhtlfirewall.ignore");
		flock ($OUT, LOCK_EX);
		print $OUT "$FORM{ip}\n";
		close ($OUT);
		print "<b>Done</b>.</p></div>\n";
		if ($config{THIS_UI}) {
			print "<div><p>Signal qhtlwaterfall to <i>restart</i>...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
			open (my $OUT, ">", "/var/lib/qhtlfirewall/qhtlwaterfall.restart") or die "Unable to open file: $!";
			close ($OUT);
		} else {
			print "<div><p>Restarting qhtlwaterfall...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
			QhtLink::Service::restartqhtlwaterfall();
		}
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "kill") {
		print "<div><p>Unblock $FORM{ip}, trying permanent blocks...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-dr",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		print "<div><p>Unblock $FORM{ip}, trying temporary blocks...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-trd",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "killallow") {
		print "<div><p>Unblock $FORM{ip}, trying permanent blocks...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-ar",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		print "<div><p>Unblock $FORM{ip}, trying temporary blocks...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-tra",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "grep") {
		print "<div><p>Searching for $FORM{ip}...</p>\n";
		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, "/usr/sbin/qhtlfirewall","-g",$FORM{ip});
		my $unblock;
		my $unallow;
		while (<$childout>) {
			my $line = $_;
			if ($line =~ /^qhtlfirewall.deny:\s(\S+)\s*/) {$unblock = 1}
			if ($line =~ /^Temporary Blocks: IP:(\S+)\s*/) {$unblock = 1}
			if ($line =~ /^qhtlfirewall.allow:\s(\S+)\s*/) {$unallow = 1}
			if ($line =~ /^Temporary Allows: IP:(\S+)\s*/) {$unallow = 1}
			print $_;
		}
		waitpid ($pid, 0);
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&resize("bot",1);
		if ($unblock) {print "<div><a class='btn btn-success' href='$script?action=kill&ip=$FORM{ip}'>Remove $FORM{ip} block</a></div>\n"}
		if ($unallow) {print "<div><a class='btn btn-success' href='$script?action=killallow&ip=$FORM{ip}'>Remove $FORM{ip} allow</a></div>\n"}
		&printreturn;
	}
	elsif ($FORM{action} eq "callow") {
		print "<div><p>Cluster Allow $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-ca",$FORM{ip},$FORM{comment});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "cignore") {
		print "<div><p>Cluster Ignore $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-ci",$FORM{ip},$FORM{comment});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "cirm") {
		print "<div><p>Cluster Remove ignore $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-cir",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "cloudflare") {
		&cloudflare;
	}
	elsif ($FORM{action} eq "cflist") {
		print "<div class='panel panel-info'><div class='panel-heading'>CloudFlare list $FORM{type} rules for user(s) $FORM{domains}:</div>\n";
		print "<div class='panel-body'><pre class='comment' style='white-space: pre-wrap;'>";
		&printcmd("/usr/sbin/qhtlfirewall","--cloudflare","list",$FORM{type},$FORM{domains});
		print "</pre>\n</div></div>\n";
	}
	elsif ($FORM{action} eq "cftempdeny") {
		print "<div class='panel panel-info'><div class='panel-heading'>CloudFlare $FORM{do} $FORM{target} for user(s) $FORM{domains}:</div>\n";
		print "<div class='panel-body'><pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","--cloudflare","tempadd",$FORM{do},$FORM{target},$FORM{domains});
		print "</pre>\n</div></div>\n";
	}
	elsif ($FORM{action} eq "cfadd") {
		print "<div class='panel panel-info'><div class='panel-heading'>CloudFlare Add $FORM{type} $FORM{target} for user(s) $FORM{domains}:</div>\n";
		print "<div class='panel-body'><pre class='comment' style='white-space: pre-wrap;'>";
		&printcmd("/usr/sbin/qhtlfirewall","--cloudflare","add",$FORM{type},$FORM{target},$FORM{domains});
		print "</pre>\n</div></div>\n";
	}
	elsif ($FORM{action} eq "cfremove") {
		print "<div class='panel panel-info'><div class='panel-heading'>CloudFlare Delete $FORM{type} $FORM{target} for user(s) $FORM{domains}:</div>\n";
		print "<div class='panel-body'><pre class='comment' style='white-space: pre-wrap;'>";
		&printcmd("/usr/sbin/qhtlfirewall","--cloudflare","del", $FORM{target},$FORM{domains});
		print "</pre>\n</div></div>\n";
	}
	elsif ($FORM{action} eq "cdeny") {
		print "<div><p>Cluster Deny $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-cd",$FORM{ip},$FORM{comment});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "ctempdeny") {
		$FORM{timeout} =~ s/\D//g;
		if ($FORM{dur} eq "minutes") {$FORM{timeout} = $FORM{timeout} * 60}
		if ($FORM{dur} eq "hours") {$FORM{timeout} = $FORM{timeout} * 60 * 60}
		if ($FORM{dur} eq "days") {$FORM{timeout} = $FORM{timeout} * 60 * 60 * 24}
		if ($FORM{ports} eq "") {$FORM{ports} = "*"}
		print "<div><p>cluster Temporarily $FORM{do}ing $FORM{ip} for $FORM{timeout} seconds:</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		if ($FORM{do} eq "block") {
			&printcmd("/usr/sbin/qhtlfirewall","-ctd",$FORM{ip},$FORM{timeout},"-p",$FORM{ports},$FORM{comment});
		} else {
			&printcmd("/usr/sbin/qhtlfirewall","-cta",$FORM{ip},$FORM{timeout},"-p",$FORM{ports},$FORM{comment});
		}
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "crm") {
		print "<div><p>Cluster Remove Deny $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-cr",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "carm") {
		print "<div><p>Cluster Remove Allow $FORM{ip}...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-car",$FORM{ip});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "cping") {
		print "<div><p>Cluster PING...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-cp");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "cgrep") {
		print "<div><p>Cluster GREP for $FORM{ip}...</p>\n";
		print "<pre class='comment' style='white-space: pre-wrap;'>\n";
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, "/usr/sbin/qhtlfirewall","-cg",$FORM{ip});
		my $unblock;
		my $start = 0;
		while (<$childout>) {
			my $line = $_;
			if ($line =~ /^====/) {
				if ($start) {
					print "$line</pre><pre class='comment' style='white-space: pre-wrap;'>";
					$start = 0;
				} else {
					print "</pre><pre class='comment' style='white-space: pre-wrap;background:#F4F4EA'>$line";
					$start = 1;
				}
			}
		}
		waitpid ($pid, 0);
		print "...Done\n</pre></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "cconfig") {
		$FORM{option} =~ s/\s*//g;
		my %restricted;
		if ($config{RESTRICT_UI}) {
			sysopen (my $IN, "/usr/local/qhtlfirewall/lib/restricted.txt", O_RDWR | O_CREAT) or die "Unable to open file: $!";
			flock ($IN, LOCK_SH);
			while (my $entry = <$IN>) {
				chomp $entry;
				$restricted{$entry} = 1;
			}
			close ($IN);
		}
		if ($restricted{$FORM{option}}) {
			print "<div>Option $FORM{option} cannot be set with RESTRICT_UI enabled</div>\n";
			exit;
		}
		print "<div><p>Cluster configuration option...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-cc",$FORM{option},$FORM{value});
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "crestart") {
		print "<div><p>Cluster restart qhtlfirewall and qhtlwaterfall...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall --crestart");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "allow") {
		my $is_ajax_req = ($FORM{ajax} && $FORM{ajax} eq '1') ? 1 : 0;
		if($is_ajax_req){ print "<div class='qhtl-inline-fragment'>"; }
		&editfile("/etc/qhtlfirewall/qhtlfirewall.allow","saveallow");
		&printreturn;
		if($is_ajax_req){ print "</div>"; }
	}
	elsif ($FORM{action} eq "saveallow") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.allow","both");
		&printreturn;
	}
	# Reintroduced redirect editing (now triggered from plus button fwb7 instead of legacy table row)
	elsif ($FORM{action} eq "redirect") {
		my $is_ajax_req = ($FORM{ajax} && $FORM{ajax} eq '1') ? 1 : 0;
		if($is_ajax_req){ print "<div class='qhtl-inline-fragment'>"; }
		&editfile("/etc/qhtlfirewall/qhtlfirewall.redirect","saveredirect");
		&printreturn;
		if($is_ajax_req){ print "</div>"; }
	}
	elsif ($FORM{action} eq "saveredirect") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.redirect","both");
		&printreturn;
	}
	elsif ($FORM{action} eq "smtpauth") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.smtpauth","savesmtpauth");
		&printreturn;
	}
	elsif ($FORM{action} eq "savesmtpauth") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.smtpauth","both");
		&printreturn;
	}
	elsif ($FORM{action} eq "reseller") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.resellers","savereseller");
		&printreturn;
	}
	elsif ($FORM{action} eq "savereseller") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.resellers","");
		&printreturn;
	}
	elsif ($FORM{action} eq "dirwatch") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.dirwatch","savedirwatch");
		&printreturn;
	}
	elsif ($FORM{action} eq "savedirwatch") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.dirwatch","qhtlwaterfall");
		&printreturn;
	}
	elsif ($FORM{action} eq "dyndns") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.dyndns","savedyndns");
		&printreturn;
	}
	elsif ($FORM{action} eq "savedyndns") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.dyndns","qhtlwaterfall");
		&printreturn;
	}
	elsif ($FORM{action} eq "blocklists") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.blocklists","saveblocklists");
		&printreturn;
	}
	elsif ($FORM{action} eq "saveblocklists") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.blocklists","both");
		&printreturn;
	}
	elsif ($FORM{action} eq "syslogusers") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.syslogusers","savesyslogusers");
		&printreturn;
	}
	elsif ($FORM{action} eq "savesyslogusers") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.syslogusers","qhtlwaterfall");
		&printreturn;
	}
	elsif ($FORM{action} eq "logfiles") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.logfiles","savelogfiles");
		&printreturn;
	}
	elsif ($FORM{action} eq "savelogfiles") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.logfiles","qhtlwaterfall");
		&printreturn;
	}
	elsif ($FORM{action} eq "deny") {
		&editfile("/etc/qhtlfirewall/qhtlfirewall.deny","savedeny");
		&printreturn;
	}
	elsif ($FORM{action} eq "savedeny") {
		&savefile("/etc/qhtlfirewall/qhtlfirewall.deny","both");
		&printreturn;
	}
	elsif ($FORM{action} eq "templates") {
		&editfile("/usr/local/qhtlfirewall/tpl/$FORM{template}","savetemplates","template");
		&printreturn;
	}
	elsif ($FORM{action} eq "savetemplates") {
		&savefile("/usr/local/qhtlfirewall/tpl/$FORM{template}","",1);
		&printreturn;
	}
	elsif ($FORM{action} eq "ignorefiles") {
		&editfile("/etc/qhtlfirewall/$FORM{ignorefile}","saveignorefiles","ignorefile");
		&printreturn;
	}
	elsif ($FORM{action} eq "saveignorefiles") {
		&savefile("/etc/qhtlfirewall/$FORM{ignorefile}","qhtlwaterfall");
		&printreturn;
	}
	elsif ($FORM{action} eq "conf") {
		my $is_ajax_req = ($FORM{ajax} && $FORM{ajax} eq '1') ? 1 : 0;
		if($is_ajax_req){ print "<div class='qhtl-inline-fragment'>"; }
		sysopen (my $IN, "/etc/qhtlfirewall/qhtlfirewall.conf", O_RDWR | O_CREAT) or die "Unable to open file: $!";
		flock ($IN, LOCK_SH);
		my @confdata = <$IN>;
		close ($IN);
		chomp @confdata;

		my %restricted;
		if ($config{RESTRICT_UI}) {
			sysopen (my $IN, "/usr/local/qhtlfirewall/lib/restricted.txt", O_RDWR | O_CREAT) or die "Unable to open file: $!";
			flock ($IN, LOCK_SH);
			while (my $entry = <$IN>) {
				chomp $entry;
				$restricted{$entry} = 1;
			}
			close ($IN);
		}

		print <<EOF;
<script type="text/javascript">
function QHTLFIREWALLexpand(obj){
	if (!obj.savesize) {obj.savesize=obj.size;}
	var newsize = Math.max(obj.savesize,obj.value.length);
	if (newsize > 120) {newsize = 120;}
	obj.size = newsize;
}

</script>
EOF
		print "<style>.hidepiece\{display:none\}</style>\n";
		open (my $DIV, "<", "/usr/local/qhtlfirewall/lib/qhtlfirewall.div");
		flock ($DIV, LOCK_SH);
		my @divdata = <$DIV>;
		close ($DIV);
		print @divdata;
		print "<div id='paginatediv2' class='text-center'></div>\n";
		print "<form action='$script' method='post' id='qhtl-options-form'>\n";
		print "<input type='hidden' name='action' value='saveconf'>\n";
		my $first = 1;
		my @divnames;
		my $comment = 0;
		foreach my $line (@confdata) {
			if (($line !~ /^\#/) and ($line =~ /=/)) {
				if ($comment) {print "</div>\n"}
				$comment = 0;
				my ($start,$end) = split (/=/,$line,2);
							my $name = $start;
				my $cleanname = $start;
				$cleanname =~ s/\s//g;
				$name =~ s/\s/\_/g;
				if ($end =~ /\"(.*)\"/) {$end = $1}
				my $size = length($end) + 4;
				my $class = "value-default";
				my ($status,$range,$default) = sanity($start,$end);
				my $showrange = "";
				my $showfrom;
				my $showto;
				if ($range =~ /^(\d+)-(\d+)$/) {
					$showfrom = $1;
					$showto = $2;
				}
				if ($default ne "") {
					$showrange = " Default: $default [$range]";
					if ($end ne $default) {$class = "value-other"}
				}
				if ($status) {$class = "value-warning"; $showrange = " Recommended range: $range (Default: $default)"}
				if ($config{RESTRICT_UI} and ($cleanname eq "CLUSTER_KEY" or $cleanname eq "UI_PASS" or $cleanname eq "UI_USER")) {
					print "<div class='$class'><b>$start</b> = <input type='text' value='********' size='14' disabled> (hidden restricted UI item)</div>\n";
				}
				elsif ($restricted{$cleanname}) {
					print "<div class='$class'><b>$start</b> = <input type='text' onFocus='QHTLFIREWALLexpand(this);' onkeyup='QHTLFIREWALLexpand(this);' value='$end' size='$size' disabled> (restricted UI item)</div>\n";
				} else {
					if ($range eq "0-1") {
						my $switch_checked_0 = "";
						my $switch_checked_1 = "";
						my $switch_active_0 = "";
						my $switch_active_1 = "";
						if ($end == 0) {$switch_checked_0 = "checked"; $switch_active_0 = "active"}
						if ($end == 1) {$switch_checked_1 = "checked"; $switch_active_1 = "active"}
						print "<div class='$class'><b>$start</b> = ";
						print "<div class='btn-group' data-toggle='buttons'>\n";
						print "<label class='btn btn-default btn-qhtlfirewall-config $switch_active_0'>\n";
						print "<input type='radio' name='${name}' value='0' $switch_checked_0> Off\n";
						print "</label>\n";
						print "<label class='btn btn-default btn-qhtlfirewall-config $switch_active_1'>\n";
						print "<input type='radio' name='${name}' value='1' $switch_checked_1> On\n";
						print "</label>\n";
						print "</div></div>\n";
					}
					elsif ($range =~ /^(\d+)-(\d+)$/ and !(-e "/etc/csuibuttondisable") and ($showto - $showfrom <= 20) and $end >= $showfrom and $end <= $showto) {
						my $selected = "";
						print "<div class='$class'><b>$start</b> = <select name='$name'>\n";
						for ($showfrom..$showto) {
							if ($_ == $end) {$selected = "selected"} else {$selected = ""}
							print "<option $selected>$_</option>\n";
						}
						print "</select></div>\n";
					} else {
						print "<div class='$class'><b>$start</b> = <input type='text' onFocus='QHTLFIREWALLexpand(this);' onkeyup='QHTLFIREWALLexpand(this);' name='$name' value='$end' size='$size'>$showrange</div>\n";
					}
				}
			} else {
				if ($line =~ /^\# SECTION:(.*)/) {
					push @divnames, $1;
					unless ($first) {print "</div>\n"}
					print "<div class='virtualpage hidepiece'>\n<div class='section'>";
					print "$1</div>\n";
					$first = 0;
					next;
				}
				if ($line =~ /^\# / and $comment == 0) {
					$comment = 1;
					print "<div class='comment'>\n";
				}
				$line =~ s/\#//g;
				$line =~ s/&/&amp;/g;
				$line =~ s/</&lt;/g;
				$line =~ s/>/&gt;/g;
				$line =~ s/\n/<br \/>\n/g;
				print "$line<br />\n";
			}
		}
	    my $is_ajax = ($FORM{ajax} && $FORM{ajax} eq '1');
		print "</div><br />\n";
		unless ($is_ajax){
			print "<div id='paginatediv' class='text-center'>\n<a class='btn btn-default' href='javascript:pagecontent.showall()'>Show All</a> <a class='btn btn-default' href='#' rel='previous'>Prev</a> <select style='width: 250px'></select> <a class='btn btn-default' href='#' rel='next' >Next</a>\n</div>\n";
			print <<'EOD';
<script type="text/javascript">
var pagecontent=new virtualpaginate({
 piececlass: "virtualpage", //class of container for each piece of content
 piececontainer: "div", //container element type (ie: "div", "p" etc)
 pieces_per_page: 1, //Pieces of content to show per page (1=1 piece, 2=2 pieces etc)
 defaultpage: 0, //Default page selected (0=1st page, 1=2nd page etc). Persistence if enabled overrides this setting.
 wraparound: false,
 persist: false //Remember last viewed page and recall it when user returns within a browser session?
});
EOD
		print "pagecontent.buildpagination(['paginatediv','paginatediv2'],[";
		foreach my $line (@divnames) {print "'$line',"}
		print "''])\npagecontent.showall();\n</script>\n";
		print "<br /><div class='text-center'><input type='submit' class='btn btn-default' value='Change'></div>\n";
		}
		print "</form>\n";
		&printreturn unless $is_ajax;
	}
	elsif ($FORM{action} eq "saveconf") {
		sysopen (my $IN, "/etc/qhtlfirewall/qhtlfirewall.conf", O_RDWR | O_CREAT) or die "Unable to open file: $!";
		flock ($IN, LOCK_SH);
		my @confdata = <$IN>;
		close ($IN);
		chomp @confdata;

		my %restricted;
		if ($config{RESTRICT_UI}) {
			sysopen (my $IN, "/usr/local/qhtlfirewall/lib/restricted.txt", O_RDWR | O_CREAT) or die "Unable to open file: $!";
			flock ($IN, LOCK_SH);
			while (my $entry = <$IN>) {
				chomp $entry;
				$restricted{$entry} = 1;
			}
			close ($IN);
		}

		sysopen (my $OUT, "/etc/qhtlfirewall/qhtlfirewall.conf", O_WRONLY | O_CREAT) or die "Unable to open file: $!";
		flock ($OUT, LOCK_EX);
		seek ($OUT, 0, 0);
		truncate ($OUT, 0);
		for (my $x = 0; $x < @confdata;$x++) {
			if (($confdata[$x] !~ /^\#/) and ($confdata[$x] =~ /=/)) {
				my ($start,$end) = split (/=/,$confdata[$x],2);
				if ($end =~ /\"(.*)\"/) {$end = $1}
				my $name = $start;
				my $sanity_name = $start;
				$name =~ s/\s/\_/g;
				$sanity_name =~ s/\s//g;
				if ($restricted{$sanity_name}) {
					print $OUT "$confdata[$x]\n";
				} else {
					print $OUT "$start= \"$FORM{$name}\"\n";
					$end = $FORM{$name};
				}
			} else {
				print $OUT "$confdata[$x]\n";
			}
		}
		close ($OUT);
		QhtLink::Config::resetconfig();
		my $newconfig = QhtLink::Config->loadconfig();
		my %newconfig = ();
		if (defined $newconfig && eval { $newconfig->can('config') }) {
			%newconfig = $newconfig->config();
		}
		foreach my $key (keys %newconfig) {
			my ($insane,$range,$default) = sanity($key,$newconfig{$key});
			if ($insane) {print "<br>WARNING: $key sanity check. $key = \"$newconfig{$key}\". Recommended range: $range (Default: $default)\n"}
		}

		print "<div>Changes saved. You should restart both qhtlfirewall and qhtlwaterfall.</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
		if($is_ajax_req){ print "</div>"; }
	}
	elsif ($FORM{action} eq "viewlogs") {
		if (-e "/var/lib/qhtlfirewall/stats/iptables_log") {
			open (my $IN, "<", "/var/lib/qhtlfirewall/stats/iptables_log") or die "Unable to open file: $!";
			flock ($IN, LOCK_SH);
			my @iptables = <$IN>;
			close ($IN);
			chomp @iptables;
			@iptables = reverse @iptables;
			my $from;
			my $to;
			my $divcnt = 0;
			my $expcnt = @iptables;

			if ($iptables[0] =~ /\|(\S+\s+\d+\s+\S+)/) {$from = $1}
			if ($iptables[-1] =~ /\|(\S+\s+\d+\s+\S+)/) {$to = $1}

			print "<div class='pull-right'><button type='button' class='btn btn-primary glyphicon glyphicon-arrow-down' data-tooltip='tooltip' title='Expand All' onClick='\$(\".submenu\").show();'></button>\n";
			print "<button type='button' class='btn btn-primary glyphicon glyphicon-arrow-up' data-tooltip='tooltip' title='Collapse All' onClick='\$(\".submenu\").hide();'></button></div>\n";
			print "<h4>Last $config{ST_IPTABLES} iptables logs*, latest:<code>$from</code> oldest:<code>$to</code></h4><br />\n";
			print "<table class='table table-bordered table-striped'>\n";
			print "<thead><tr><th>Time</th><th width='50%'>From</th><th>Port</th><th>I/O</th><th width='50%'>To</th><th>Port</th><th>Proto</th></tr></thead>\n";
			my $size = scalar @iptables;
			if ($size > $config{ST_IPTABLES}) {$size = $config{ST_IPTABLES}}
			for (my $x = 0 ;$x < $size ;$x++) {
				my $line = $iptables[$x];
				$divcnt++;
				my ($text,$log) = split(/\|/,$line);
				my ($time,$desc,$in,$out,$src,$dst,$spt,$dpt,$proto,$inout);
				if ($log =~ /IN=(\S+)/) {$in = $1}
				if ($log =~ /OUT=(\S+)/) {$out = $1}
				if ($log =~ /SRC=(\S+)/) {$src = $1}
				if ($log =~ /DST=(\S+)/) {$dst = $1}
				if ($log =~ /SPT=(\d+)/) {$spt = $1}
				if ($log =~ /DPT=(\d+)/) {$dpt = $1}
				if ($log =~ /PROTO=(\S+)/) {$proto = $1}

				if ($text ne "") {
					$text =~ s/\(/\<br\>\(/g;
					if ($in and $src) {$src = $text ; $dst .= " <br>(server)"}
					elsif ($out and $dst) {$dst = $text ; $src .= " <br>(server)"}
				}
				if ($log =~ /^(\S+\s+\d+\s+\S+)/) {$time = $1}

				$inout = "n/a";
				if ($in) {$inout = "in"}
				elsif ($out) {$inout = "out"}

				print "<tr><td style='white-space: nowrap;'><button type='button' class='btn btn-primary glyphicon glyphicon-resize-vertical' data-tooltip='tooltip' title='Toggle Info' onClick='\$(\"#s$divcnt\").toggle()'></button> $time</td><td>$src</td><td>$spt</td><td>$inout</td><td>$dst</td><td>$dpt</td><td>$proto</td></tr>\n";

				$log =~ s/\&/\&amp\;/g;
				$log =~ s/>/\&gt\;/g;
				$log =~ s/</\&lt\;/g;
				print "<tr style='display:none' class='submenu' id='s$divcnt'><td colspan='7'><span>$log</span></td></tr>\n";
			}
			print "</table>\n";
			print "<div class='bs-callout bs-callout-warning'>* These iptables logs taken from $config{IPTABLES_LOG} will not necessarily show all packets blocked by iptables. For example, ports listed in DROP_NOLOG or the settings for DROP_LOGGING/DROP_IP_LOGGING/DROP_ONLYRES/DROP_PF_LOGGING will affect what is logged. Additionally, there is rate limiting on all iptables log rules to prevent log file flooding</div>\n";
		} else {
			print "<div class='bs-callout bs-callout-info'> No logs entries found</div>\n";
		}
		&printreturn;
	}
	elsif ($FORM{action} eq "sips") {
		sysopen (my $IN, "/etc/qhtlfirewall/qhtlfirewall.sips", O_RDWR | O_CREAT) or die "Unable to open file: $!";
		flock ($IN, LOCK_SH);
		my @confdata = <$IN>;
		close ($IN);
		chomp @confdata;

		print "<form action='$script' method='post'><input type='hidden' name='action' value='sipsave'><br>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<tr><td><b>IP Address</b></td><td><b>Deny All Access to IP</b></td></tr>\n";

		my %sips;
		open (my $SIPS, "<","/etc/qhtlfirewall/qhtlfirewall.sips");
		flock ($SIPS, LOCK_SH);
		my @data = <$SIPS>;
		close ($SIPS);
		chomp @data;
		foreach my $line (@data) {
			if ($line =~ /^(\s|\#|$)/) {next}
			$sips{$line} = 1;
		}

		my $ethdev = QhtLink::GetEthDev->new();
		my %g_ipv4 = $ethdev->ipv4;
		my %g_ipv6 = $ethdev->ipv6;

		foreach my $key (sort keys %g_ipv4) {
			my $ip = $key;
			if ($ip =~ /^127\.0\.0/) {next}
			my $chk = "ip_$ip";
			$chk =~ s/\./\_/g;
			my $checked = "";
			if ($sips{$ip}) {$checked = "checked"}
			print "<tr><td>$ip</td><td><input type='checkbox' name='$chk' $checked></td></tr>\n";
		}

		foreach my $key (sort keys %g_ipv6) {
			my $ip = $key;
			my $chk = "ip_$ip";
			$chk =~ s/\./\_/g;
			my $checked = "";
			if ($sips{$ip}) {$checked = "checked"}
			print "<tr><td>$ip</td><td><input type='checkbox' name='$chk' $checked></td></tr>\n";
		}

		print "<tr><td colspan='2'><input type='submit' class='btn btn-default' value='Change'></td></tr>\n";
		print "</table></form>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "sipsave") {
		open (my $IN,"<","/etc/qhtlfirewall/qhtlfirewall.sips");
		flock ($IN, LOCK_SH);
		my @data = <$IN>;
		close ($IN);
		chomp @data;

		open (my $OUT,">","/etc/qhtlfirewall/qhtlfirewall.sips");
		flock ($OUT, LOCK_EX);
		foreach my $line (@data) {
			if ($line =~ /^\#/) {print $OUT "$line\n"} else {last}
		}
		foreach my $key (keys %FORM) {
			if ($key =~ /^ip_(.*)/) {
				my $ip = $1;
				$ip =~ s/\_/\./g;
				print $OUT "$ip\n";
			}
		}
		close($OUT);

		print "<div>Changes saved. You should restart qhtlfirewall.</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restart'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "upgrade") {
		if ($config{THIS_UI}) {
			# Run upgrade in the background to avoid blocking/tearing down the current HTTP session immediately.
			# The UI daemon will restart during the upgrade; inform the user and provide a log snapshot if available.
			my $ulog = "/var/log/qhtlfirewall-ui-upgrade.log";
			# Pre-create the log file with a header so the UI shows immediate content
			eval {
				if (open(my $LF, '>', $ulog)) {
					my $now = scalar localtime();
					print $LF "=== QhtLink Firewall upgrade started at $now ===\n";
					close $LF;
				}
				1;
			};
			# Use nohup if available to ensure the background process survives the CGI/session ending
			my $nohup = (-x '/usr/bin/nohup') ? '/usr/bin/nohup' : ((-x '/bin/nohup') ? '/bin/nohup' : '');
			my $shell = (-x '/bin/sh') ? '/bin/sh' : '/usr/bin/sh';
			my $cmd;
			if ($nohup ne '') {
				$cmd = "$nohup $shell -c '/usr/sbin/qhtlfirewall -uf' >> $ulog 2>&1 &";
			} else {
				$cmd = "(/usr/sbin/qhtlfirewall -uf) >> $ulog 2>&1 &";
			}
			system($cmd);
			print "<div><p>Upgrade started in the background. This UI may restart during the process and disconnect your session.</p>";
			print "<p>The log below will update automatically for a short time. If it remains empty, try refreshing after 30–60 seconds.</p>";
			print "<p>Current upgrade log snapshot:</p>\n";
			print "<pre id='qhtl-upgrade-log' class='comment' style='white-space: pre-wrap; height: 400px; overflow: auto; resize:none; clear:both'><span class=\"text-muted\">(no output yet)</span></pre>\n";
			# Client-side poller to fetch the log content periodically
			print <<'QHTL_UPGRADE_POLL';
<script>
(function(){
	try {
		var box = document.getElementById('qhtl-upgrade-log');
		if (!box) return;
		var attempts = 0, maxAttempts = 30; // ~60s @ 2s interval
		function fetchLog(){
			attempts++;
			var base = (window.QHTL_SCRIPT || '') || '$script';
			var url = base + '?action=upgrade_log&_=' + String(Date.now());
			try {
				var xhr = new XMLHttpRequest();
				xhr.open('GET', url, true);
				try{ xhr.setRequestHeader('X-Requested-With','XMLHttpRequest'); }catch(_){ }
				xhr.onreadystatechange = function(){
					if (xhr.readyState === 4) {
						if (xhr.status >= 200 && xhr.status < 300) {
							var ct = (xhr.getResponseHeader && xhr.getResponseHeader('Content-Type')) || '';
							var marker = (xhr.getResponseHeader && xhr.getResponseHeader('X-QHTL-ULOG')) || '';
							var text = xhr.responseText || '';
							// Only render when server indicates plain text log via header or content-type
							if ((marker === '1') || (/^text\/plain/i.test(ct))) {
								if (text) {
									text = text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
									box.innerHTML = text;
									try { box.scrollTop = box.scrollHeight; } catch(e){}
								} else if (attempts <= 1) {
									box.innerHTML = '<span class="text-muted">(no output yet)</span>';
								}
							} else {
								// Ignore unexpected HTML responses (e.g., full UI) to avoid dumping markup
								if (attempts <= 1) {
									box.innerHTML = '<span class="text-muted">(waiting for log output)</span>';
								}
							}
						}
					}
				};
				xhr.send(null);
			} catch(e){}
			if (attempts < maxAttempts) { setTimeout(fetchLog, 2000); }
		}
		setTimeout(fetchLog, 500);
	} catch(e){}
})();
</script>
QHTL_UPGRADE_POLL
			print "</div>\n";
			&printreturn;
		} else {
			print "<div><p>Upgrading qhtlfirewall...</p>\n";
			&resize("top");
			print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
			&printcmd("/usr/sbin/qhtlfirewall","-u");
			print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
			&resize("bot",1);

			open (my $IN, "<", "/etc/qhtlfirewall/version.txt") or die $!;
			flock ($IN, LOCK_SH);
			$myv = <$IN>;
			close ($IN);
			chomp $myv;
		}

		&printreturn;
	}
	elsif ($FORM{action} eq "denyf") {
		print "<div><p>Removing all entries from qhtlfirewall.deny...</p>\n";
		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","-df");
		&printcmd("/usr/sbin/qhtlfirewall","-tf");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&resize("bot",1);
		&printreturn;
	}
	elsif ($FORM{action} eq "qhtlfirewalltest") {
		print "<div><p>Testing iptables...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/local/qhtlfirewall/bin/qhtlfirewalltest.pl");
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		print "<div>You should restart qhtlfirewall after having run this test.</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restart'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "profiles") {
		my $is_ajax_req = ($FORM{ajax} && $FORM{ajax} eq '1') ? 1 : 0; if($is_ajax_req){ print "<div class='qhtl-inline-fragment'>"; }
		my @profiles = sort glob("/usr/local/qhtlfirewall/profiles/*");
		my @backups = reverse glob("/var/lib/qhtlfirewall/backup/*");

		print "<form action='$script' method='post'><input type='hidden' name='action' value='profileapply'>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th colspan='2'>Preconfigured Profiles</th><th style='border-left:1px solid #990000'>&nbsp;</th></tr></thead>\n";
		foreach my $profile (@profiles) {
			my ($file, undef) = fileparse($profile);
			$file =~ s/\.conf$//;
			my $text;
			open (my $IN, "<", $profile);
			flock ($IN, LOCK_SH);
			my @profiledata = <$IN>;
			close ($IN);
			chomp @profiledata;

			if ($file eq "reset_to_defaults") {
				$text = "This is the installation default profile and will reset all qhtlfirewall.conf settings, including enabling TESTING mode";
			}
			elsif ($profiledata[0] =~ /^\# Profile:/) {
				foreach my $line (@profiledata) {
					if ($line =~ /^\# (.*)$/) {$text .= "$1 "}
				}
			}

			print "<tr><td><b>$file</b><br>\n$text</td><td style='border-left:1px solid #990000'><input type='radio' name='profile' value='$file'></td></tr>\n";
		}
		print "<tr><td>You can apply one or more of these profiles to qhtlfirewall.conf. Apart from reset_to_defaults, most of these profiles contain only a subset of settings. You can find out what will be changed by comparing the profile to the current configuration below. A backup of qhtlfirewall.conf will be created before any profile is applied.</td><td style='border-left:1px solid #990000'><input type='submit' class='btn btn-default' value='Apply Profile'></td></tr>\n";
		print "</table>\n";
		print "</form>\n";

		print "<br><form action='$script' method='post'><input type='hidden' name='action' value='profilebackup'>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th>Backup qhtlfirewall.conf</th></tr></thead>\n";
		print "<tr><td>Create a backup of qhtlfirewall.conf. You can use an optional name for the backup that should only contain alphanumerics. Other characters (including spaces) will be replaced with an underscore ( _ )</td></tr>\n";
		print "<tr><td><input type='text' size='40' name='backup' placeholder='Optional name'> <input type='submit' class='btn btn-default' value='Create Backup'></td></tr>\n";
		print "</table>\n";
		print "</form>\n";

		print "<br><form action='$script' method='post'><input type='hidden' name='action' value='profilerestore'>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th>Restore Backup Of qhtlfirewall.conf</th></tr></thead>\n";
		print "<tr><td><select name='backup' size='10' style='min-width:400px'>\n";
		foreach my $backup (@backups) {
			my ($file, undef) = fileparse($backup);
			my ($stamp,undef) = split(/_/,$file);
			print "<optgroup label='".localtime($stamp).":'><option>$file</option></optgroup>\n";
		}
		print "</select></td></tr>\n";
		print "<tr><td><input type='submit' class='btn btn-default' value='Restore Backup'></td></tr>\n";
		print "</table>\n";
		print "</form>\n";

		print "<br><form action='$script' method='post'><input type='hidden' name='action' value='profilediff'>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th colspan='2'>Compare Configurations</th></tr></thead>";
		print "<tr><td>Select first configuration:<br>\n<select name='profile1' size='10' style='min-width:400px'>\n";
		print "<optgroup label='Profiles:'>\n";
		foreach my $profile (@profiles) {
			my ($file, undef) = fileparse($profile);
			$file =~ s/\.conf$//;
			print "<option>$file</option>\n";
		}
		print "</optgroup>\n";
		foreach my $backup (@backups) {
			my ($file, undef) = fileparse($backup);
			my ($stamp,undef) = split(/_/,$file);
			print "<optgroup label='".localtime($stamp).":'><option>$file</option></optgroup>\n";
		}
		print "</select></td></tr>\n";
		print "<tr><td style='border-top:1px dashed #990000'>Select second configuration:<br>\n<select name='profile2' size='10' style='min-width:400px'>\n";
		print "<optgroup label='Current Configuration:'><option value='current' selected>/etc/qhtlfirewall/qhtlfirewall.conf</option></optgroup>\n";
		print "<optgroup label='Profiles:'>\n";
		foreach my $profile (@profiles) {
			my ($file, undef) = fileparse($profile);
			$file =~ s/\.conf$//;
			print "<option>$file</option>\n";
		}
		print "</optgroup>\n";
		foreach my $backup (@backups) {
			my ($file, undef) = fileparse($backup);
			my ($stamp,undef) = split(/_/,$file);
			print "<optgroup label='".localtime($stamp).":'><option>$file</option></optgroup>\n";
		}
		print "</select></td></tr>\n";
		print "<tr><td><input type='submit' class='btn btn-default' value='Compare Config/Backup/Profile Settings'></td></tr>\n";
		print "</table>\n";
		print "</form>\n";

		&printreturn; if($is_ajax_req){ print "</div>"; }
	}
	elsif ($FORM{action} eq "profileapply") {
		my $profile = $FORM{profile};
		$profile =~ s/\W/_/g;
		print "<div><p>Applying profile ($profile)...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","--profile","apply",$profile);
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		print "<div>You should restart both qhtlfirewall and qhtlwaterfall.</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "profilebackup") {
		my $profile = $FORM{backup};
		$profile =~ s/\W/_/g;
		print "<div><p>Creating backup...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","--profile","backup",$profile);
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "profilerestore") {
		my $profile = $FORM{backup};
		$profile =~ s/\W/_/g;
		print "<div><p>Restoring backup ($profile)...</p>\n<pre class='comment' style='white-space: pre-wrap;'>\n";
		&printcmd("/usr/sbin/qhtlfirewall","--profile","restore",$profile);
		print "</pre>\n<p>...<b>Done</b>.</p></div>\n";
		print "<div>You should restart both qhtlfirewall and qhtlwaterfall.</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "profilediff") {
		my $profile1 = $FORM{profile1};
		my $profile2 = $FORM{profile2};
		$profile2 =~ s/\W/_/g;
		$profile2 =~ s/\W/_/g;

		print "<table class='table table-bordered table-striped'>\n";
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, "/usr/sbin/qhtlfirewall","--profile","diff",$profile1,$profile2);
		while (<$childout>) {
			$_ =~ s/\[|\]//g;
			my ($var,$p1,$p2) = split(/\s+/,$_);
			if ($var eq "") {
				next;
			}
			elsif ($var eq "SETTING") {
				print "<tr><td><b>$var</b></td><td><b>$p1</b></td><td><b>$p2</b></td></tr>\n";
			}
			else {
				print "<tr><td>$var</td><td>$p1</td><td>$p2</td></tr>\n";
			}
		}
		waitpid ($pid, 0);
		print "</table>\n";

		&printreturn;
	}
	elsif ($FORM{action} eq "viewports") {
		print "<div><h4>Ports listening for external connections and the executables running behind them:</h4></div>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th>Port</th><th>Proto</th><th>Open</th><th>Conns</th><th>PID</th><th>User</th><th>Command Line</th><th>Executable</th></tr></thead>\n";
		my (%listen, %ports);
		my $ports_ok = 0;
		eval {
			# Ensure methods exist before calling
			if (QhtLink::Ports->can('listening') && QhtLink::Ports->can('openports')) {
				%listen = QhtLink::Ports->listening;
				%ports  = QhtLink::Ports->openports;
				$ports_ok = 1;
			}
			1;
		} or do { $ports_ok = 0; };
		unless ($ports_ok) {
			print "<tr><td colspan='8'><div class='alert alert-warning' style='margin:0'>Ports module not available; unable to enumerate listening ports in this environment.</div></td></tr>\n";
		}
		foreach my $protocol (sort keys %listen) {
			foreach my $port (sort {$a <=> $b} keys %{$listen{$protocol}}) {
				foreach my $pid (sort {$a <=> $b} keys %{$listen{$protocol}{$port}}) {
					my $fopen;
					if ($ports{$protocol}{$port}) {$fopen = "4"} else {$fopen = "-"}
					if ($config{IPV6} and $ports{$protocol."6"}{$port}) {$fopen .= "/6"} else {$fopen .= "/-"}

					my $fcmd = ($listen{$protocol}{$port}{$pid}{cmd});
					$fcmd =~ s/\</\&lt;/g;
					$fcmd =~ s/\&/\&amp;/g;

					my $fexe = $listen{$protocol}{$port}{$pid}{exe};
					$fexe =~ s/\</\&lt;/g;
					$fexe =~ s/\&/\&amp;/g;

					my $fconn = $listen{$protocol}{$port}{$pid}{conn};
					print "<tr><td>$port</td><td>$protocol</td><td>$fopen</td><td>$fconn</td><td>$pid</td><td>$listen{$protocol}{$port}{$pid}{user}</td><td style='overflow: hidden;text-overflow: ellipsis; width:50%'>$fcmd</td><td style='overflow: hidden;text-overflow: ellipsis; width:50%'>$fexe</td></tr>\n";
				}
			}
		}
		print "</table>\n";

		&printreturn;
	}
	elsif ($mobile) {
		print "<table class='table table-bordered table-striped'>\n";
		print "<tr><td colspan='2'><form action='$script' method='post'><input type='hidden' name='mobi' value='$mobile'><input type='hidden' name='action' value='qallow'><input type='submit' class='btn btn-default' value='Quick Allow'><div style='margin-top:6px'><input type='text' name='ip' value='' size='18' style='background-color: #BDECB6'></div></form></td></tr>\n";
		print "<tr><td colspan='2'><form action='$script' method='post'><input type='hidden' name='mobi' value='$mobile'><input type='hidden' name='action' value='qdeny'><input type='submit' class='btn btn-default' value='Quick Deny'><div style='margin-top:6px'><input type='text' name='ip' value='' size='18' style='background-color: #FFD1DC'></div></form></td></tr>\n";
		print "<tr><td colspan='2'><form action='$script' method='post'><input type='hidden' name='mobi' value='$mobile'><input type='hidden' name='action' value='qignore'><input type='submit' class='btn btn-default' value='Quick Ignore'><div style='margin-top:6px'><input type='text' name='ip' value='' size='18' style='background-color: #D9EDF7'></div></form></td></tr>\n";
		print "<tr><td colspan='2'><form action='$script' method='post'><input type='hidden' name='mobi' value='$mobile'><input type='hidden' name='action' value='kill'><input type='submit' class='btn btn-default' value='Quick Unblock'><div style='margin-top:6px'><input type='text' name='ip' value='' size='18'></div></form></td></tr>\n";
		print "</table>\n";
	}
	elsif ($FORM{action} eq "fix") {
		print "<div class='bs-callout bs-callout-warning'>These options should only be used as a last resort as most of them will reduce the effectiveness of qhtlfirewall and qhtlwaterfall to protect the server</div>\n";

		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th colspan='2'>Fix Common Problems</th></tr></thead>";

		if ($config{LF_SPI} == 0) {
			print "<tr><td><button class='btn btn-default' disabled>Disable SPI</button>\n";
		} else {
			print "<tr><td><button type='button' class='btn btn-default confirmButton' data-query='Are you sure you want to disable LF_SPI?' data-href='$script?action=fixspi' data-toggle='modal' data-target='#confirmmodal'>Disable SPI</button>\n";
		}
		print "</td><td style='width:100%'>If you find that ports listed in TCP_IN/UDP_IN are being blocked by iptables (e.g. port 80) as seen in /var/log/messages and users can only connect to the server if entered in qhtlfirewall.allow, then it could be that the kernel (usually on virtual servers) is broken and cannot perform connection tracking. In this case, disabling the Stateful Packet Inspection functionality of qhtlfirewall (LF_SPI) may help\n";
		if ($config{LF_SPI} == 0) {
			print "<br><strong>Note: LF_SPI is already disabled</strong>";
		}
		print "</td></tr>\n";
		# Inline content area for Quick Actions (results from star button actions)
		print "<tr style='background:transparent!important'><td colspan='2' style='background:transparent!important'><div id='qhtl-quick-inline-area' style='padding-top:10px;min-height:160px;background:transparent'></div></td></tr>\n";
		# Intercept hidden form submits (qallow,qdeny,qignore,grep,qkill) to load into the Quick Actions inline area
		print "<script>(function(){try{ var area=document.getElementById('qhtl-quick-inline-area'); if(!area) return;\n".
			"  function setLoading(msg){ try{ if(area.qhtlCancelFade) area.qhtlCancelFade(); area.innerHTML = '<div class=\\'text-muted\\'>'+(msg||'Loading...')+'</div>'; }catch(_){ } }\n".
			"  function onLoaded(html){ try{ area.innerHTML = html; if(area.qhtlArmAuto) area.qhtlArmAuto(); }catch(_){ } }\n".
			"  function handleForm(f){ try{ var fd=new FormData(f); try{ fd.append('ajax','1'); }catch(__){} var u=f.getAttribute('action')||''; setLoading(); if(window.jQuery){ jQuery.ajax({ url:u, method:(f.method||'POST'), data:fd, processData:false, contentType:false }).done(function(d){ onLoaded(d); }).fail(function(){ onLoaded('<div class=\\'text-danger\\'>Failed to load content.</div>'); }); } else { var x=new XMLHttpRequest(); x.open((f.method||'POST'), u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200&&x.status<300){ onLoaded(x.responseText); } else { onLoaded('<div class=\\'text-danger\\'>Failed to load content.</div>'); } } }; x.send(fd); } }catch(e){} }\n".
			"  document.addEventListener('submit', function(ev){ try{ var f=ev.target; if(!f || f.tagName!=='FORM') return; var id=f.id||''; if(id==='qallow'||id==='qdeny'||id==='qignore'||id==='grep'||id==='qkill'){ ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation && ev.stopImmediatePropagation(); handleForm(f); } }catch(_){ } }, true);\n".
			"}catch(e){} })();</script>\n";

		if ($config{TCP_IN} =~ /30000:35000/) {
			print "<tr><td><button class='btn btn-default' disabled>Open PASV FTP Hole</button>\n";
		} else {
			print "<tr><td><button type='button' class='btn btn-default confirmButton' data-query='Are you sure you want to open PASV FTP hole?' data-href='$script?action=fixpasvftp' data-toggle='modal' data-target='#confirmmodal'>Open PASV FTP Hole</button>\n";
		}
		print "</td><td style='width:100%'>If the kernel (usually on virtual servers) is broken and cannot perform ftp connection tracking, or if you are trying to use FTP over SSL, this option will open a hole in the firewall to allow PASV connections through\n";
		if ($config{TCP_IN} =~ /30000:35000/) {
			print "<br><strong>Note: The port range 30000 to 35000 is already open in qhtlfirewall</strong>\n";
		}
		print "</td></tr>\n";

		if ($config{PT_USERKILL} == 0) {
			print "<tr><td><button class='btn btn-default' disabled>Disable PT_USERKILL</button>\n";
		} else {
			print "<tr><td><button type='button' class='btn btn-default confirmButton' data-query='Are you sure you want to disable PT_USERKILL?' data-href='$script?action=fixkill' data-toggle='modal' data-target='#confirmmodal'>Disable PT_USERKILL</button>\n";
		}
		print "</td><td style='width:100%'>If qhtlwaterfall is killing running processes and you have PT_USERKILL enabled, then we recommend that you disable this feature\n";
		if ($config{PT_USERKILL} == 0) {
			print "<br><strong>Note: PT_USERKILL is already disabled</strong>";
		}
		print "</td></tr>\n";

		if ($config{SMTP_BLOCK} == 0) {
			print "<tr><td><button class='btn btn-default' disabled>Disable SMTP_BLOCK</button>\n";
		} else {
			print "<tr><td><button type='button' class='btn btn-default confirmButton' data-query='Are you sure you want to disable SMTP_BLOCK?' data-href='$script?action=fixsmtp' data-toggle='modal' data-target='#confirmmodal'>Disable SMTP_BLOCK</button>\n";
		}
		print "</td><td style='width:100%'>If scripts on the server are unable to send out email via external SMTP connections and you have SMTP_BLOCK enabled then those scripts should be configured to send email either through /usr/sbin/sendmail or localhost on the server. If this is not possible then disabling SMTP_BLOCK can fix this\n";
		if ($config{SMTP_BLOCK} == 0) {
			print "<br><strong>Note: SMTP_BLOCK is already disabled</strong>";
		}
		print "</td></tr>\n";

		print "<tr><td><button type='button' class='btn btn-default confirmButton' data-query='Are you sure you want to disable all alerts?' data-href='$script?action=fixalerts' data-toggle='modal' data-target='#confirmmodal'>Disable All Alerts</button>\n";
		print "</td><td style='width:100%'>If you really want to disable all alerts in qhtlwaterfall you can do so here. This is <strong>not</strong> recommended in any situation - you should go through the qhtlfirewall configuration and only disable those you do not want. As new features are added to qhtlfirewall you may find that you have to go into the qhtlfirewall configuration and disable them manually as this procedure only disables the ones that it is aware of when applied\n";
		print "</td></tr>\n";

		print "<tr><td><button type='button' class='btn btn-danger confirmButton' data-query='Are you sure you want to reinstall qhtlfirewall and lose all modifications?' data-href='$script?action=fixnuclear' data-toggle='modal' data-target='#confirmmodal'>Reinstall qhtlfirewall</button>\n";
		print "</td><td style='width:100%'>If all else fails this option will <strong>completely</strong> uninstall qhtlfirewall and install it again with completely default options (including TESTING mode). The previous configuration will be lost including all modifications\n";
		print "</td></tr>\n";

		print "</table>\n";
		&printreturn;
		&confirmmodal;
	}
	elsif ($FORM{action} eq "fixpasvftp") {
		print "<div class='panel panel-default'>\n";
		print "<div class='panel-heading panel-heading'>Enabling pure-ftpd PASV hole:</div>\n";
		print "<div class='panel-body'>";
		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";

		my $ftpdone = 0;
		if (-e "/usr/local/cpanel/version") {
			require Cpanel::Config;
			import Cpanel::Config;
			my $cpconf = Cpanel::Config::loadcpconf();
			if ($cpconf->{ftpserver} eq "pure-ftpd") {
				copy("/etc/pure-ftpd.conf","/etc/pure-ftpd.conf-".time."_prefixpasvftp");
				sysopen (my $PUREFTP,"/etc/pure-ftpd.conf", O_RDWR | O_CREAT);
				flock ($PUREFTP, LOCK_EX);
				my @ftp = <$PUREFTP>;
				chomp @ftp;
				seek ($PUREFTP, 0, 0);
				truncate ($PUREFTP, 0);
				my $hit = 0;
				foreach my $line (@ftp) {
					if ($line =~ /^#?\s*PassivePortRange/i) {
						if ($hit) {next}
						$line = "PassivePortRange 30000 35000";
						$hit = 1;
					}
					print $PUREFTP "$line\n";
				}
				unless ($hit) {print $PUREFTP "PassivePortRange 30000 35000"}
				close ($PUREFTP);
				&printcmd("/scripts/restartsrv_pureftpd");
				$ftpdone = 1;
			}
		}

		if ($config{TCP_IN} =~ /30000:35000/) {
			print "PASV port range 30000:35000 already exists in TCP_IN/TCP6_IN\n";
		} else {
			$config{TCP_IN} .= ",30000:35000";
			$config{TCP6_IN} .= ",30000:35000";

			copy("/etc/qhtlfirewall/qhtlfirewall.conf","/var/lib/qhtlfirewall/backup/".time."_prefixpasvftp");
			sysopen (my $QHTLFIREWALLCONF,"/etc/qhtlfirewall/qhtlfirewall.conf", O_RDWR | O_CREAT);
			flock ($QHTLFIREWALLCONF, LOCK_EX);
			my @qhtlfirewall = <$QHTLFIREWALLCONF>;
			chomp @qhtlfirewall;
			seek ($QHTLFIREWALLCONF, 0, 0);
			truncate ($QHTLFIREWALLCONF, 0);
			foreach my $line (@qhtlfirewall) {
				if ($line =~ /^TCP6_IN/) {
					print $QHTLFIREWALLCONF "TCP6_IN = \"$config{TCP6_IN}\"\n";
					print "*** PASV port range 30000:35000 added to the TCP6_IN port list\n";
				}
				elsif ($line =~ /^TCP_IN/) {
					print $QHTLFIREWALLCONF "TCP_IN = \"$config{TCP_IN}\"\n";
					print "*** PASV port range 30000:35000 added to the TCP_IN port list\n";
				}
				else {
					print $QHTLFIREWALLCONF $line."\n";
				}
			}
			close ($QHTLFIREWALLCONF);
		}

		print "</pre></div>\n";
		&resize("bot",1);
		print "<div class='panel-footer panel-footer'>Completed<br>\n";
		unless ($ftpdone) {print "<p><strong>You MUST now open the same port range hole (30000 to 35000) in your FTP Server configuration</strong></p>\n"}
		print "</div>\n";
		print "</div>\n";
		print "<div>You MUST now restart both qhtlfirewall and qhtlwaterfall:</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "fixspi") {
		print "<div class='panel panel-default'>\n";
		print "<div class='panel-heading panel-heading'>Disabling LF_SPI:</div>\n";
		print "<div class='panel-body'>";

		copy("/etc/qhtlfirewall/qhtlfirewall.conf","/var/lib/qhtlfirewall/backup/".time."_prefixspi");
		sysopen (my $QHTLFIREWALLCONF,"/etc/qhtlfirewall/qhtlfirewall.conf", O_RDWR | O_CREAT);
		flock ($QHTLFIREWALLCONF, LOCK_EX);
		my @qhtlfirewall = <$QHTLFIREWALLCONF>;
		chomp @qhtlfirewall;
		seek ($QHTLFIREWALLCONF, 0, 0);
		truncate ($QHTLFIREWALLCONF, 0);
		foreach my $line (@qhtlfirewall) {
			if ($line =~ /^LF_SPI /) {
				print $QHTLFIREWALLCONF "LF_SPI = \"0\"\n";
				print "*** LF_SPI disabled ***\n";
			} else {
				print $QHTLFIREWALLCONF $line."\n";
			}
		}
		close ($QHTLFIREWALLCONF);

		print "</div>\n";
		print "<div class='panel-footer panel-footer'>Completed</div>\n";
		print "</div>\n";
		print "<div>You MUST now restart both qhtlfirewall and qhtlwaterfall:</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "fixkill") {
		print "<div class='panel panel-default'>\n";
		print "<div class='panel-heading panel-heading'>Disabling PT_USERKILL:</div>\n";
		print "<div class='panel-body'>";

		copy("/etc/qhtlfirewall/qhtlfirewall.conf","/var/lib/qhtlfirewall/backup/".time."_prefixkill");
		sysopen (my $QHTLFIREWALLCONF,"/etc/qhtlfirewall/qhtlfirewall.conf", O_RDWR | O_CREAT);
		flock ($QHTLFIREWALLCONF, LOCK_EX);
		my @qhtlfirewall = <$QHTLFIREWALLCONF>;
		chomp @qhtlfirewall;
		seek ($QHTLFIREWALLCONF, 0, 0);
		truncate ($QHTLFIREWALLCONF, 0);
		foreach my $line (@qhtlfirewall) {
			if ($line =~ /^PT_USERKILL /) {
				print $QHTLFIREWALLCONF "PT_USERKILL = \"0\"\n";
				print "*** PT_USERKILL disabled ***\n";
			} else {
				print $QHTLFIREWALLCONF $line."\n";
			}
		}
		close ($QHTLFIREWALLCONF);

		print "</div>\n";
		print "<div class='panel-footer panel-footer'>Completed</div>\n";
		print "</div>\n";
		print "<div>You MUST now restart both qhtlfirewall and qhtlwaterfall:</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "fixsmtp") {
		print "<div class='panel panel-default'>\n";
		print "<div class='panel-heading panel-heading'>Disabling SMTP_BLOCK:</div>\n";
		print "<div class='panel-body'>";

		copy("/etc/qhtlfirewall/qhtlfirewall.conf","/var/lib/qhtlfirewall/backup/".time."_prefixsmtp");
		sysopen (my $QHTLFIREWALLCONF,"/etc/qhtlfirewall/qhtlfirewall.conf", O_RDWR | O_CREAT);
		flock ($QHTLFIREWALLCONF, LOCK_EX);
		my @qhtlfirewall = <$QHTLFIREWALLCONF>;
		chomp @qhtlfirewall;
		seek ($QHTLFIREWALLCONF, 0, 0);
		truncate ($QHTLFIREWALLCONF, 0);
		foreach my $line (@qhtlfirewall) {
			if ($line =~ /^SMTP_BLOCK /) {
				print $QHTLFIREWALLCONF "SMTP_BLOCK = \"0\"\n";
				print "*** SMTP_BLOCK disabled ***\n";
			} else {
				print $QHTLFIREWALLCONF $line."\n";
			}
		}
		close ($QHTLFIREWALLCONF);

		print "</div>\n";
		print "<div class='panel-footer panel-footer'>Completed</div>\n";
		print "</div>\n";
		print "<div>You MUST now restart both qhtlfirewall and qhtlwaterfall:</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "fixalerts") {
		print "<div class='panel panel-default'>\n";
		print "<div class='panel-heading panel-heading'>Disabling All Alerts:</div>\n";
		print "<div class='panel-body'>";

		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
		copy("/etc/qhtlfirewall/qhtlfirewall.conf","/var/lib/qhtlfirewall/backup/".time."_prefixalerts");
		&printcmd("/usr/sbin/qhtlfirewall","--profile","apply","disable_alerts");
		print "</pre>\n";
		&resize("bot",1);
		print "</div>\n";
		print "<div class='panel-footer panel-footer'>Completed</div>\n";
		print "</div>\n";
		print "<div>You MUST now restart both qhtlfirewall and qhtlwaterfall:</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	elsif ($FORM{action} eq "fixnuclear") {
		print "<div class='panel panel-default'>\n";
		print "<div class='panel-heading panel-heading'>Nuclear Option:</div>\n";
		print "<div class='panel-body'>";

		my $time = time;
		sysopen (my $REINSTALL, "/usr/src/reinstall_$time.sh", O_WRONLY | O_CREAT | O_TRUNC);
		flock ($REINSTALL, LOCK_EX);
		print $REINSTALL <<EOF;
#!/usr/bin/bash
bash /etc/qhtlfirewall/uninstall.sh
cd /usr/src
mv -fv qhtlfirewall.tgz qhtlfirewall.tgz.$time
mv -fv qhtlfirewall qhtlfirewall.$time
wget "https://$config{DOWNLOADSERVER}/qhtlfirewall.tgz?_=$time"
tar -xzf qhtlfirewall.tgz
cd qhtlfirewall
sh install.sh
EOF
		close ($REINSTALL);
		&resize("top");
		print "<pre class='comment' style='white-space: pre-wrap; height: 500px; overflow: auto; resize:none; clear:both' id='output'>\n";
		&printcmd("bash","/usr/src/reinstall_$time.sh");
		unlink "/usr/src/reinstall_$time.sh";
		print "</pre>\n";
		&resize("bot",1);
		print "</div>\n";
		print "<div class='panel-footer panel-footer'>Completed</div>\n";
		print "</div>\n";
		print "<div>You MUST now restart both qhtlfirewall and qhtlwaterfall:</div>\n";
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restartboth'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall+qhtlwaterfall'></form></div>\n";
		&printreturn;
	}
	else {
		if (defined $ENV{WEBMIN_VAR} and defined $ENV{WEBMIN_CONFIG} and -e "module.info") {
			my @data = slurp("module.info");
			foreach my $line (@data) {
				if ($line =~ /^name=qhtlfirewall$/) {
					unless (-l "index.cgi") {
						unlink "index.cgi";
						my $status = symlink ("/usr/local/qhtlfirewall/lib/webmin/qhtlfirewall/index.cgi","index.cgi");
						if ($status and -l "index.cgi") {
							symlink ("/usr/local/qhtlfirewall/lib/webmin/qhtlfirewall/images","qhtlfirewallimages");
							print "<p><b>qhtlfirewall updated to symlink webmin module to /usr/local/qhtlfirewall/lib/webmin/qhtlfirewall/. Click <a href='index.cgi'>here</a> to continue<p></b>\n";
							exit;
						} else {
							print "<p>Failed to symlink to /usr/local/qhtlfirewall/lib/webmin/qhtlfirewall/<p>\n";
						}
					}
					last;
				}
			}
		}

		&getethdev;
		my ($childin, $childout);
		my $pid = open3($childin, $childout, $childout, "$config{IPTABLES} $config{IPTABLESWAIT} -L LOCALINPUT -n");
		my @iptstatus = <$childout>;
		waitpid ($pid, 0);
		chomp @iptstatus;
		if ($iptstatus[0] =~ /# Warning: iptables-legacy tables present/) {shift @iptstatus}
	my $status = "<div class='bs-callout bs-callout-success text-center'><h4>Firewall Status: Enabled and Running</h4></div>";

		if (-e "/etc/qhtlfirewall/qhtlfirewall.disable") {
			$status = "<div class='bs-callout bs-callout-danger text-center'><form action='$script' method='post'><h4>Firewall Status: Disabled and Stopped <input type='hidden' name='action' value='enable'><input type='submit' class='btn btn-default' value='Enable'></form></h4></div>\n"
		}
		elsif ($config{TESTING}) {
			$status = "<div class='bs-callout bs-callout-warning text-center'><form action='$script' method='post'><h4>Firewall Status: Enabled but in Test Mode - Don't forget to disable TESTING in the Firewall Configuration</h4></div>";
		}
		elsif ($iptstatus[0] !~ /^Chain LOCALINPUT/) {
			$status = "<div class='bs-callout bs-callout-danger text-center'><form action='$script' method='post'><h4>Firewall Status: Enabled but Stopped <input type='hidden' name='action' value='start'><input type='submit' class='btn btn-default' value='Start'></form></h4></div>"
		}
	my $status_extras = '';
	if (-e "/var/lib/qhtlfirewall/qhtlwaterfall.restart") { $status_extras .= "<div class='bs-callout bs-callout-info text-center'><h4>qhtlwaterfall restart request pending</h4></div>"; }
	unless ($config{RESTRICT_SYSLOG}) { $status_extras .= "<div class='bs-callout bs-callout-warning text-center'><h4>WARNING: RESTRICT_SYSLOG is disabled. See SECURITY WARNING in Firewall Configuration</h4></div>\n"; }

		my $tempcnt = 0;
		if (! -z "/var/lib/qhtlfirewall/qhtlfirewall.tempban") {
			sysopen (my $IN, "/var/lib/qhtlfirewall/qhtlfirewall.tempban", O_RDWR);
			flock ($IN, LOCK_EX);
			my @data = <$IN>;
			close ($IN);
			chomp @data;
			$tempcnt = scalar @data;
		}
		my $tempbans = "(Currently: <code>$tempcnt</code> temp IP bans, ";
		$tempcnt = 0;
		if (! -z "/var/lib/qhtlfirewall/qhtlfirewall.tempallow") {
			sysopen (my $IN, "/var/lib/qhtlfirewall/qhtlfirewall.tempallow", O_RDWR);
			flock ($IN, LOCK_EX);
			my @data = <$IN>;
			close ($IN);
			chomp @data;
			$tempcnt = scalar @data;
		}
		$tempbans .= "<code>$tempcnt</code> temp IP allows)";

		my $permcnt = 0;
		if (! -z "/etc/qhtlfirewall/qhtlfirewall.deny") {
			sysopen (my $IN, "/etc/qhtlfirewall/qhtlfirewall.deny", O_RDWR);
			flock ($IN, LOCK_SH);
			while (my $line = <$IN>) {
				chomp $line;
				if ($line =~ /^(\#|\n|\r)/) {next}
				if ($line =~ /$ipv4reg|$ipv6reg/) {$permcnt++}
			}
			close ($IN);
		}
		my $permbans = "(Currently: <code>$permcnt</code> permanent IP bans)";

		$permcnt = 0;
		if (! -z "/etc/qhtlfirewall/qhtlfirewall.allow") {
			sysopen (my $IN, "/etc/qhtlfirewall/qhtlfirewall.allow", O_RDWR);
			flock ($IN, LOCK_SH);
			while (my $line = <$IN>) {
				chomp $line;
				if ($line =~ /^(\#|\n|\r)/) {next}
				if ($line =~ /$ipv4reg|$ipv6reg/) {$permcnt++}
			}
			close ($IN);
		}
		my $permallows = "(Currently: <code>$permcnt</code> permanent IP allows)";

		# If invoked from cPanel/WHM UI, the header already shows status next to the Watcher button.
		# Suppress the inline ribbon entirely in that context to avoid duplication.
		# Decide concise firewall status for UI widgets (on/testing/off) regardless of cpanel context
		my $fw_state_js = 'off';
		if (-e "/etc/qhtlfirewall/qhtlfirewall.disable") {
			$fw_state_js = 'off';
		} elsif ($config{TESTING}) {
			$fw_state_js = 'testing';
		} elsif ($iptstatus[0] !~ /^Chain LOCALINPUT/) {
			$fw_state_js = 'off';
		} else {
			$fw_state_js = 'on';
		}
		# Print visual callouts only when not suppressed by cpanel UI embedding
		if (!($config{THIS_UI} && $config{THIS_UI} eq 'cpanel')) {
			print $status;
			print $status_extras;
		}
		# Provide both concise and detailed (running/testing/disabled/stopped) statuses
		my $fw_detail = 'running';
		if (-e "/etc/qhtlfirewall/qhtlfirewall.disable") { $fw_detail = 'disabled'; }
		elsif ($config{TESTING}) { $fw_detail = 'testing'; }
		elsif ($iptstatus[0] !~ /^Chain LOCALINPUT/) { $fw_detail = 'stopped'; }
		print "<script>window.QHTL_FW_STATUS='".$fw_state_js."';window.QHTL_FW_STATE_DETAIL='".$fw_detail."';</script>\n";

		print "<div class='normalcontainer'>\n";
		# Enforce tab-pane visibility regardless of host theme CSS and disable tab clicks while Quick View is open
		print "<style>.tab-content>.tab-pane{display:none!important}.tab-content>.tab-pane.active{display:block!important}.qhtl-tabs-locked #myTabs a[data-toggle='tab']{pointer-events:none;cursor:not-allowed;opacity:0.6;filter:grayscale(0.25)}</style>\n";
	# Removed upgrade-available ribbon above tabs per request

		print "<ul class='nav nav-tabs' id='myTabs' style='font-weight:bold'>\n";
		print "<li><a data-toggle='tab' href='#upgrade'>Upgrade</a></li>\n";
		print "<li><a data-toggle='tab' href='#quickactions'>Quick Actions</a></li>\n";
	print "<li><a data-toggle='tab' href='#home'>Options</a></li>\n";
    	print "<li><a data-toggle='tab' href='#firewall1'>Firewall</a></li>\n";
    	print "<li><a data-toggle='tab' href='#waterfall'>Waterfall</a></li>\n";
    	print "<li><a data-toggle='tab' href='#moreplus'>Advanced</a></li>\n";
		print "<li><a data-toggle='tab' href='#promotion' class='qhtl-promo-tab'>".
		      "<span class='glyphicon glyphicon-star' style='color:#ffbf00'></span>" x 5 .
		      " Promotion " .
		      "<span class='glyphicon glyphicon-star' style='color:#ffbf00'></span>" x 5 .
		      "</a></li>\n";
	# Removed the old 'Firewall' nav link; pane retained for global scripts
	# Old QhtLink Waterfall tab removed; replaced by new 'Waterfall'
		if ($config{CLUSTER_SENDTO}) {
			print "<li><a data-toggle='tab' href='#cluster'>Cluster</a></li>\n";
		}
		print "</ul><br>\n";

		# Ensure tabs switch even if Bootstrap JS isn't active (fallback minimal handler)
		print <<'QHTL_TAB_FALLBACK';
<script>
(function(){
	try {
		var nav = document.getElementById('myTabs');
		if (!nav) return;
		var links = nav.querySelectorAll('a[data-toggle="tab"]');
		function activate(hash){
			if(!hash) return; if(hash.charAt(0)!='#') return;
			var panes = document.querySelectorAll('.tab-content > .tab-pane');
			for (var i=0;i<panes.length;i++){ panes[i].classList.remove('active'); }
			var act = document.querySelector(hash); if (act) act.classList.add('active');
			for (var j=0;j<links.length;j++){ var li=links[j].parentNode; if(li) li.classList.remove('active'); }
			for (var k=0;k<links.length;k++){ if(links[k].getAttribute('href')===hash){ var pli=links[k].parentNode; if(pli) pli.classList.add('active'); break; } }
		}
        // Expose activation for other scripts (e.g., to keep current tab sticky)
        window.qhtlActivateTab = activate;
		for (var i=0;i<links.length;i++){
			links[i].addEventListener('click', function(e){ e.preventDefault(); activate(this.getAttribute('href')); });
		}
			// On load, if URL has a hash pointing to a tab pane, activate it
			try {
				if (window.location && window.location.hash) {
					var h = window.location.hash;
					for (var z=0; z<links.length; z++) {
						if (links[z].getAttribute('href') === h) { activate(h); break; }
					}
				}
			} catch(_e){}
	} catch(e) {}
})();
</script>
QHTL_TAB_FALLBACK

		# Removed legacy inline Quick View shim here; the modal/watch functions are provided by the main CGI now

		# Intercept Promotion tab clicks to open promo modal without switching tabs
		print <<'QHTL_PROMO_TAB_INTERCEPT';
<script>
(function(){
	try {
		document.addEventListener('click', function(e){
			var t = e.target;
			var a = (t && t.closest) ? t.closest('a.qhtl-promo-tab') : null;
			if (!a) return;
			if (e && e.preventDefault) e.preventDefault();
			if (e && e.stopPropagation) e.stopPropagation();
			if (e && e.stopImmediatePropagation) e.stopImmediatePropagation();
			try { if (window.openPromoModal) { openPromoModal(); } } catch(_){ }
			// Re-assert currently active tab to be safe
			try {
				var act = document.querySelector('#myTabs li.active > a[href^="#"]');
				var hash = act ? act.getAttribute('href') : '#upgrade';
				if (typeof window.qhtlActivateTab === 'function') { window.qhtlActivateTab(hash); }
			} catch(__){}
			return false;
		}, true);
	} catch(_){ }
})();
</script>
QHTL_PROMO_TAB_INTERCEPT

		# Guard tabs from changing while Quick View is open (capture-phase interceptor)
		print <<'QHTL_TAB_GUARD';
<script>
(function(){
	try {
		window.qhtlTabLock = window.qhtlTabLock || 0;
		// Capture-phase listener to block any tab link clicks when locked
		document.addEventListener('click', function(ev){
			if (!window.qhtlTabLock) return;
			var t = ev.target;
			if (t && t.closest) {
				var a = t.closest('a[data-toggle="tab"]');
				if (a) {
					if (ev && typeof ev.preventDefault === 'function') ev.preventDefault();
					if (ev && typeof ev.stopPropagation === 'function') ev.stopPropagation();
					if (ev && typeof ev.stopImmediatePropagation === 'function') ev.stopImmediatePropagation();
				}
			}
		}, true);
		// Block Bootstrap tab activations while locked
		if (window.jQuery) {
			try {
				jQuery(document).on('show.bs.tab', 'a[data-toggle="tab"]', function(e){
					if (window.qhtlTabLock) {
						if (e && e.preventDefault) e.preventDefault();
						return false;
					}
				});
			} catch(__){}
		}
		// Guard against hash changes toggling tabs while locked
		try {
			window.addEventListener('hashchange', function(e){
				if (!window.qhtlTabLock) return;
				try { if (e && e.preventDefault) e.preventDefault(); } catch(__){}
				try {
					var keep = (typeof window.qhtlSavedURLHash !== 'undefined') ? window.qhtlSavedURLHash : '';
					var base = window.location.pathname + window.location.search + (keep || '');
					history.replaceState(null, '', base);
					if (typeof window.qhtlActivateTab === 'function' && window.qhtlSavedTabHash) {
						setTimeout(function(){ try { window.qhtlActivateTab(window.qhtlSavedTabHash); } catch(_){} }, 0);
					}
				} catch(__){}
			}, false);
		} catch(__){}
	} catch(e) {}
})();
</script>
QHTL_TAB_GUARD

		print "<div class='tab-content'>\n";
		print "<div id='upgrade' class='tab-pane active'>\n";
		print "<form action='$script' method='post'>\n";
		print "<table class='table table-bordered table-striped' id='upgradetable'>\n";
		print "<thead><tr><th colspan='2'>Upgrade</th></tr></thead>";
	my ($upgrade, $actv) = &qhtlfirewallgetversion("qhtlfirewall",$myv);
		# Unified layout: always render the triangle row and flip via JS when upgrade is available
			print "<tr style='background:transparent!important'><td colspan='2' style='background:transparent!important'>";
		# Status box above the manual check button
		# Removed external status box (status shows inside triangle now)
		print "<link rel='stylesheet' href='$script?action=widget_js&name=triangle.css&_=" . time() . "' />";
	print "<div style='display:flex;gap:15px;flex-wrap:wrap;margin:4px 0 0 0;justify-content:center'>";
	# Force each word on its own line by inserting <br> between words
	print "  <button id='qhtl-upgrade-manual' type='button' title='Check Manually' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary' data-mode='check'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span class='tri-status' id='qhtl-upgrade-status-inline'></span><span>Check<br>Manually</span></span></button>";
	print "  <button id='qhtl-upgrade-changelog' type='button' title='View ChangeLog' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>View<br>ChangeLog</span></span></button>";
	# New independent triangles (placeholders)
		print "  <button id='qhtl-upgrade-rex' type='button' title='eXploit Scanner' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>eXploit<br>Scanner</span></span></button>";
		print "  <button id='qhtl-upgrade-mpass' type='button' title='Mail Moderator' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>Mail<br>Moderator</span></span></button>";
		print "  <button id='qhtl-upgrade-mshield' type='button' title='Mail Shiled' style='all:unset;margin:0' onclick='return false;'><span class='qhtl-tri-btn secondary'><svg class='tri-svg' viewBox='0 0 100 86.6' preserveAspectRatio='none' aria-hidden='true'><polygon points='50,3 96,83.6 4,83.6' fill='none' stroke='#a9d7ff' stroke-width='10' stroke-linejoin='round' stroke-linecap='round'/></svg><span class='tri'></span><span>Mail<br>Shiled</span></span></button>";
		print "</div>";
		# Upgrade tab inline area below triangles
			print "<div id='qhtl-upgrade-inline-area' style='min-height:180px;border-top:1px solid #ddd;margin-top:0;padding-top:0;background:transparent; transition: opacity 5s ease;'></div>";
		# Wire manual check/upgrade button behavior
				print <<'QHTL_UPGRADE_WIRE_JS';
<script>
(function(){
	try{
		var base = (window.QHTL_SCRIPT||'') || '$script';
		var manualBtn = document.getElementById('qhtl-upgrade-manual');
		if (!manualBtn) return;
		var tri = manualBtn.querySelector('.qhtl-tri-btn');
		var label = manualBtn.querySelector('.qhtl-tri-btn > span:last-child');
	var sbox = document.getElementById('qhtl-upgrade-status-box');
	var sTop = document.getElementById('qhtl-upgrade-status-inline'); // inline inside triangle
	var sVer = document.getElementById('qhtl-upgrade-version');
		function setBlueCheck(){ if(!tri||!label) return; tri.classList.remove('installing','upgrade'); tri.classList.add('secondary'); try{ var svg = tri.querySelector('svg polygon'); if(svg){ svg.setAttribute('stroke', '#a9d7ff'); } }catch(_){ } label.innerHTML = 'Check<br>Manually'; }
		function setOrangeUpgrade(){ if(!tri||!label) return; tri.classList.remove('secondary'); tri.classList.add('upgrade'); label.innerHTML = 'Upgrade'; try { var svg = tri.querySelector('svg polygon'); if(svg){ svg.setAttribute('stroke', '#f59e0b'); } } catch(_){ }
		}
		function startUpgrade(){
			try{ tri.classList.add('installing'); }catch(_){ }
			// visually start a minimal fill animation and pulse
			try{ var fill = tri.querySelector('.tri'); if (fill){ fill.style.transition = 'transform 0.6s ease'; fill.style.transform = fill.style.transform.replace(/scaleY\([^)]*\)/,'scaleY(0.05)'); } }catch(_){ }
			var xhr = new XMLHttpRequest();
			xhr.open('POST', base + '?action=api_start_upgrade&_=' + String(Date.now()), true);
			try{ xhr.setRequestHeader('X-Requested-With','XMLHttpRequest'); xhr.setRequestHeader('Content-Type','application/x-www-form-urlencoded'); }catch(_){ }
			xhr.onreadystatechange=function(){ if(xhr.readyState===4){
				// Start timed auto refreshes (every 10s for up to 60s) and stop when upgrade button disappears
				try { beginTimedAutoRefresh(); } catch(__){}
			} };
			try{ xhr.send('start=1'); } catch(e){ try { beginTimedAutoRefresh(); } catch(__){} }
		}

		// Persist a short-lived auto-refresh schedule in sessionStorage so it survives reloads
		function beginTimedAutoRefresh(){
			try{
				var until = Date.now() + 60000; // 1 minute
				sessionStorage.setItem('qhtlAutoRefreshUntil', String(until));
				sessionStorage.setItem('qhtlAutoRefreshEvery', '10000'); // 10 seconds
				scheduleAutoRefresh();
			}catch(_){ }
		}

		function scheduleAutoRefresh(){
			try{
				if (window.QHTL_AUTO_REFRESH_RUNNING) { return; }
				var untilS = sessionStorage.getItem('qhtlAutoRefreshUntil');
				if (!untilS) { return; }
				var until = parseInt(untilS, 10) || 0;
				if (!until || Date.now() > until) { try{ sessionStorage.removeItem('qhtlAutoRefreshUntil'); sessionStorage.removeItem('qhtlAutoRefreshEvery'); }catch(__){} return; }
				var every = parseInt(sessionStorage.getItem('qhtlAutoRefreshEvery')||'10000',10);
				if (!(every > 0)) { every = 10000; }
				window.QHTL_AUTO_REFRESH_RUNNING = setInterval(function(){
					try{
						var triBtn = document.querySelector('#qhtl-upgrade-manual .qhtl-tri-btn');
						var isUpgrade = !!(triBtn && triBtn.classList.contains('upgrade'));
						var expired = Date.now() > (parseInt(sessionStorage.getItem('qhtlAutoRefreshUntil')||'0',10) || 0);
						if (!isUpgrade || expired){
							clearInterval(window.QHTL_AUTO_REFRESH_RUNNING);
							window.QHTL_AUTO_REFRESH_RUNNING = null;
							try{ sessionStorage.removeItem('qhtlAutoRefreshUntil'); sessionStorage.removeItem('qhtlAutoRefreshEvery'); }catch(__){}
							return;
						}
						location.reload();
					}catch(__){}
				}, every);
			}catch(__){}
		}
		function applyResult(data, fromCountdown){
			try{
				if (!data || !data.ok) { if (fromCountdown && sTop){ sTop.textContent='Fail'; sTop.style.color='#dc2626'; sTop.style.fontWeight='800'; } if(sVer){ sVer.textContent=''; } return; }
				var avail = (data.available||'').trim();
				var cur = (data.current||'').trim();
				var up = !!data.upgrade;
				if (fromCountdown){
					if (!avail){ if(sTop){ sTop.textContent='Fail'; sTop.style.color='#dc2626'; sTop.style.fontWeight='800'; } if(sVer){ sVer.textContent=''; } }
					else {
						if (sVer){ sVer.textContent = avail; sVer.style.color='#16a34a'; sVer.style.fontWeight='700'; }
						if (avail===cur){ if(sTop){ sTop.textContent='OK'; sTop.style.color='#16a34a'; sTop.style.fontWeight='800'; setTimeout(function(){ try{ sTop.textContent=''; }catch(_){ } }, 5000); } }
						else { if(sTop){ sTop.textContent=''; } }
					}
				}
				if (up){ setOrangeUpgrade(); manualBtn.onclick=function(e){ e.preventDefault(); startUpgrade(); return false; }; }
				else { setBlueCheck(); }
			} catch(e){}
		}

		function doManualCheckAuto(){ // no countdown; used on load
			var xhr = new XMLHttpRequest();
			xhr.open('GET', base + '?action=api_manual_check&_=' + String(Date.now()), true);
			try{ xhr.setRequestHeader('X-Requested-With','XMLHttpRequest'); }catch(_){ }
			xhr.onreadystatechange=function(){ if(xhr.readyState===4){ var data=null; try{ data=JSON.parse(xhr.responseText||'{}'); }catch(__){} applyResult(data, false); } };
			try { xhr.send(null); } catch(e) { }
		}

		function doManualCheckWithCountdown(){
			if (sTop){ sTop.style.color='#16a34a'; sTop.style.fontWeight='800'; }
			var n = 5; if (sTop) { sTop.textContent = String(n); }
			if (sVer) { sVer.textContent = ''; }
			var dataResp = null, haveResp = false, finished = false;
			// fire request immediately
			try{
				var xhr = new XMLHttpRequest();
				xhr.open('GET', base + '?action=api_manual_check&_=' + String(Date.now()), true);
				try{ xhr.setRequestHeader('X-Requested-With','XMLHttpRequest'); }catch(_){ }
				xhr.onreadystatechange=function(){ if(xhr.readyState===4){ try{ dataResp = JSON.parse(xhr.responseText||'{}'); haveResp = true; if (finished) { applyResult(dataResp, true); } }catch(__){ haveResp = true; if (finished) { applyResult(null, true); } } } };
				xhr.send(null);
			} catch(_){ }
			// countdown
			var iv = setInterval(function(){
				try { n--; if (n<=1) { n=1; } if (sTop) { sTop.textContent = String(n); } } catch(_){ }
				if (n===1) { clearInterval(iv); finished = true; if (haveResp) { applyResult(dataResp, true); } }
			}, 1000);
		}
		// Wire click to countdown-based manual check
		manualBtn.onclick = function(e){ e.preventDefault(); doManualCheckWithCountdown(); return false; };
		setTimeout(doManualCheckAuto, 200);
	}catch(e){}
})();
</script>
QHTL_UPGRADE_WIRE_JS
		print "<script src='$script?action=widget_js&name=uupdate.js'></script>";
		print "<script src='$script?action=widget_js&name=uchange.js'></script>";
		print "<script src='$script?action=widget_js&name=qhtlrex.js'></script>";
		print "<script src='$script?action=widget_js&name=qhtlmpass.js'></script>";
		print "<script src='$script?action=widget_js&name=qhtlmshield.js'></script>";
		# Removed version status/info line to reduce height
		print "</td></tr>\n";
    
		print "</table>\n";
		print "</form>\n";
		if ($upgrade) {print "<script>\$('\#upgradebs').show();</script>\n"}

		# Remove informational callouts (buttons now cover these functions)

		# Removed legacy Mobile View panel/button; tabs are now mobile-friendly by default
		print "</div>\n";

		# New Quick Actions tab content (moved from QhtLink Firewall tab)
		print "<div id='quickactions' class='tab-pane'>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th colspan='2'>Quick Actions</th></tr></thead>";

		# First cell: six violet star buttons (120x70) with a precise 10px bright-violet halo via SVG stroke, 15px apart, centered, labeled left-to-right
		print "<tr style='background:transparent!important'><td colspan='2' style='background:transparent!important'>";
		print "<div style=\"width:100%; display:flex; justify-content:center;\">";
		# Scoped styles for star layout and shape
		print "<style>\n".
			".qhtl-star-item{width:140px;display:inline-flex;flex-direction:column;align-items:center;justify-content:flex-start;min-height:150px;}\n".
			".qhtl-star-wrap{position:relative;width:140px;height:90px;display:inline-flex;align-items:center;justify-content:center;}\n".
			".qhtl-star{position:relative;width:140px;height:90px;background:transparent;border:none;cursor:pointer;display:inline-block;padding:0;}\n".
			".qhtl-star svg{display:block;width:140px;height:90px;}\n".
			".qhtl-star:focus{outline:2px solid #fff;outline-offset:2px;}\n".
			".qhtl-star.counting text{visibility:hidden;}\n".
			".qhtl-star-label{margin-top:6px;font-size:13px;line-height:1.1;color:#eee;text-shadow:0 1px 0 rgba(0,0,0,0.35);}\n".
			".qhtl-star-field{margin-top:6px;width:120px;max-width:120px;}\n".
		"</style>";
		# Button group with 15px gap between halos (wrappers)
		print "<div style=\"display:flex;flex-wrap:wrap;justify-content:center;align-items:flex-start;gap:15px;\">";
		my @qstars = (
			{ label => 'Allow',   form => 'qallow',   btn => 'btn-qallow',   file => 'qAllow.js',   key => 'allow'   },
			{ label => 'Deny',    form => 'qdeny',    btn => 'btn-qdeny',    file => 'qDeny.js',    key => 'deny'    },
			{ label => 'Ignore',  form => 'qignore',  btn => 'btn-qignore',  file => 'qIgnore.js',  key => 'ignore'  },
			{ label => 'Search',  form => 'grep',     btn => 'btn-grep',     file => 'qSearch.js',  key => 'search'  },
			{ label => 'Unblock', form => 'qkill',    btn => 'btn-qkill',    file => 'qUnblock.js', key => 'unblock' },
			{ label => 'Temp',    form => 'tempdeny', btn => 'btn-tempdeny', file => 'qTemp.js',    key => 'temp'    },
		);
		foreach my $q (@qstars) {
			my $label = $q->{label};
			my $form  = $q->{form};
			my $btnid = $q->{btn};
			my $sid   = "starip-".$q->{key};
			my $onclick = '';
			if ($q->{key} eq 'temp') {
				$onclick = "try{ openTempRule({}); }catch(e){}";
			} else {
				$onclick = "try{var siv=document.getElementById('$sid'); var tf=document.querySelector('#$form input[name=ip]'); if(tf && siv){ tf.value=siv.value; } var f=document.getElementById('$form'); if(!f){ return false; } var ev; try{ ev=new Event('submit', {bubbles:true, cancelable:true}); }catch(__){ try{ ev=document.createEvent('Event'); ev.initEvent('submit', true, true); }catch(___){ ev=null; } } if(ev){ var notCancelled = f.dispatchEvent(ev); if(notCancelled){ try{ f.submit(); }catch(____){} } } else { try{ f.submit(); }catch(_____){} } }catch(e){}";
			}
			my $bg    = ($q->{key} eq 'allow') ? '#BDECB6' :
			           ($q->{key} eq 'deny') ? '#FFD1DC' :
			           ($q->{key} eq 'ignore') ? '#FFD27A' :
			           ($q->{key} eq 'search') ? '#D9EDF7' :
			           ($q->{key} eq 'unblock') ? '#E0E0E0' : '#FFFFFF';
			my $title = $label;
			print "<div class=\"qhtl-star-item\">".
				"<div class=\"qhtl-star-wrap\" aria-hidden=\"false\">".
					"<button type=\"button\" class=\"qhtl-star\" data-qaction=\"$q->{key}\" title=\"$title\" aria-label=\"$title\" onclick=\"$onclick\">".
						"<svg width=\"140\" height=\"90\" viewBox=\"-10 -10 140 90\" xmlns=\"http://www.w3.org/2000/svg\" aria-hidden=\"true\">".
							"<path d=\"M60,0 L73.2,24.5 L117.6,24.5 L81.6,39.9 L94.8,63.7 L60,49 L25.2,63.7 L38.4,39.9 L2.4,24.5 L46.8,24.5 Z\" fill=\"none\" stroke=\"#ee82ee\" stroke-width=\"20\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\"/>".
							"<path d=\"M60,0 L73.2,24.5 L117.6,24.5 L81.6,39.9 L94.8,63.7 L60,49 L25.2,63.7 L38.4,39.9 L2.4,24.5 L46.8,24.5 Z\" fill=\"#8a2be2\"/>".
							"<text x=\"60\" y=\"35\" fill=\"#ffffff\" stroke=\"rgba(0,0,0,0.45)\" stroke-width=\"2\" paint-order=\"stroke fill\" text-anchor=\"middle\" dominant-baseline=\"middle\" font-weight=\"700\" font-size=\"15\" style=\"font-family: Arial, Helvetica, sans-serif; letter-spacing:.2px;\">$label</text>".
						"</svg>".
					"</button>".
				"</div>".
				(($q->{key} ne 'temp') ? ("<input id=\"$sid\" class=\"qhtl-star-field form-control\" type=\"text\" placeholder=\"IP\" style=\"background:$bg;width:120px;\">") : ('')).
			"</div>";
		}
		print "</div>"; # end group
		print "</div>"; # end centering container
		# Load per-button JS files (qAllow.js, qDeny.js, qIgnore.js, qSearch.js, qUnblock.js, qTemp.js)
		foreach my $q (@qstars) { my $f = $q->{file}; print "<script src='$script?action=widget_js&name=$f&v=$myv'></script>"; }
		# Long-press (3s) for first three stars (Allow/Deny/Ignore) to open their Quick View popups with a visible countdown
		print "<script>(function(){try{\n".
			"  var map = { allow:'allow', deny:'deny', ignore:'ignore' }; var secs=3;\n".
			"  function attach(btn){ var key=btn.getAttribute('data-qaction'); if(!map[key]) return; var down=false, t=null, remain=secs, overlay=null;\n".
			"    function clearOv(){ try{ if(overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay); }catch(_){ } overlay=null; }\n".
			"    function cancel(){ down=false; if(t){ clearInterval(t); t=null; } clearOv(); btn.dataset.lpHandled='0'; btn.classList.remove('counting'); }\n".
			"    function done(){ if(t){ clearInterval(t); t=null; } btn.dataset.lpHandled='1'; clearOv(); btn.classList.remove('counting'); try{ var a=document.querySelector('a.quickview-link[data-which=\\''+map[key]+'\\']'); if(a){ a.click(); } }catch(_){ } }\n".
			"    function start(){ down=true; remain=secs; clearOv(); btn.classList.add('counting'); overlay=document.createElement('div'); overlay.className='qhtl-star-countdown'; overlay.style.cssText='position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:16px;color:#ffff00;text-shadow:0 1px 2px rgba(0,0,0,.6);pointer-events:none;'; overlay.textContent=remain; btn.appendChild(overlay); t=setInterval(function(){ if(!down){ cancel(); return; } remain--; if(remain>0){ overlay.textContent=remain; } else { done(); } }, 1000); }\n".
			"    btn.addEventListener('mousedown', start); btn.addEventListener('touchstart', start, {passive:true});\n".
			"    ['mouseup','mouseleave','touchend','touchcancel','blur'].forEach(function(ev){ btn.addEventListener(ev, cancel, {passive:true}); });\n".
			"    // Suppress normal click when long-press handled\n".
			"    btn.addEventListener('click', function(e){ if(btn.dataset.lpHandled==='1'){ e.preventDefault(); if(e.stopImmediatePropagation) e.stopImmediatePropagation(); btn.dataset.lpHandled='0'; } }, true);\n".
			"  }\n".
			"  document.querySelectorAll('.qhtl-star[data-qaction]').forEach(attach);\n".
			"}catch(e){} })();</script>";
		# New: Temporary Rule Popup modal (same sizing behaviour as Quick View), yellow glow, scrolls with page and closes on outside click
		print "<style>\n".
			  ".qhtl-temp-modal{ position:absolute !important; inset:0 !important; z-index:1100 !important; background: rgba(0,0,0,0.5); opacity:0; transition: opacity .2s ease; }\n".
			  ".qhtl-temp-modal.in, .qhtl-temp-modal.show{ opacity:1 !important; }\n".
			  ".qhtl-temp-modal .modal-dialog{ width: calc(100% - 40px) !important; max-width:none !important; position:absolute !important; top:20px !important; left:20px !important; right:20px !important; transform:none !important; margin:0 !important; }\n".
		      ".qhtl-temp-modal .modal-content{ height:auto !important; max-height:480px !important; display:flex !important; flex-direction:column !important; overflow:hidden !important; }\n".
		      ".qhtl-temp-modal .modal-body{ flex:1 1 auto !important; min-height:0 !important; overflow:auto !important; padding:10px !important; }\n".
		      ".qhtl-temp-modal .modal-footer{ flex:0 0 auto !important; padding:10px !important; display:flex !important; justify-content:flex-end !important; gap:8px !important; }\n".
		      ".qhtl-yellow-glow{ box-shadow: 0 0 14px 6px rgba(255,215,0,0.6), 0 0 26px 14px rgba(255,215,0,0.32); animation: qhtl-yellow 2.4s infinite ease-in-out; }\n".
		      "@keyframes qhtl-yellow { 0%,100%{ box-shadow: 0 0 14px 6px rgba(255,215,0,0.55), 0 0 26px 12px rgba(255,215,0,0.28);} 50%{ box-shadow: 0 0 28px 14px rgba(255,215,0,0.95), 0 0 46px 20px rgba(255,215,0,0.55);} }\n".
			  "/* Constrain input fields inside the Temp modal to 150px */\n".
			  ".qhtl-temp-modal input.form-control, .qhtl-temp-modal input[type=text]{ max-width:150px !important; width:150px !important; }\n".
		      "</style>\n";
		print "<div class='modal fade qhtl-temp-modal' id='qhtlTempRuleModal' tabindex='-1' role='dialog' aria-hidden='true' data-backdrop='false' style='display:none'>\n".
		      "  <div class='modal-dialog'>\n".
		      "    <div class='modal-content qhtl-yellow-glow'>\n".
		      "      <div class='modal-body'>\n".
		      "        <h4 id='qhtlTempRuleTitle' style='margin:0 0 8px 0;'>Temporary Allow/Deny</h4>\n".
		      "        <div id='qhtlTempRuleBody'>\n".
		      "          <form action='$script' method='post' id='qhtlTempRuleForm'>\n".
		      "            <input type='hidden' name='action' value='applytemp'>\n".
		      "            <div style='display:flex; align-items:center; gap:12px; width:100%; margin-bottom:8px'>\n".
		      "              <div style='flex:0 0 20%; max-width:20%'>Action</div>\n".
		      "              <div style='flex:1 1 auto'><select name='do' class='form-control' style='width:auto; display:inline-block; min-width:140px'><option>block</option><option>allow</option></select></div>\n".
		      "            </div>\n".
		      "            <div style='display:flex; align-items:center; gap:12px; width:100%; margin-bottom:8px'>\n".
		      "              <div style='flex:0 0 20%; max-width:20%'>IP address</div>\n".
		      "              <div style='flex:1 1 auto'><input type='text' name='ip' value='' size='18' class='form-control' style='max-width:340px'></div>\n".
		      "            </div>\n".
		      "            <div style='display:flex; align-items:center; gap:12px; width:100%; margin-bottom:8px'>\n".
		      "              <div style='flex:0 0 20%; max-width:20%'>Ports</div>\n".
		      "              <div style='flex:1 1 auto'><input type='text' name='ports' value='*' size='5' class='form-control' style='max-width:200px'></div>\n".
		      "            </div>\n".
		      "            <div style='display:flex; align-items:center; gap:12px; width:100%; margin-bottom:8px'>\n".
		      "              <div style='flex:0 0 20%; max-width:20%'>Duration for</div>\n".
		      "              <div style='flex:1 1 auto'><input type='text' name='timeout' value='' size='4' class='form-control' style='display:inline-block; width:90px; margin-right:8px;'> <select name='dur' class='form-control' style='display:inline-block; width:auto; min-width:120px'><option>seconds</option><option>minutes</option><option>hours</option><option>days</option></select></div>\n".
		      "            </div>\n".
		      "            <div style='display:flex; align-items:center; gap:12px; width:100%; margin-bottom:8px'>\n".
		      "              <div style='flex:0 0 20%; max-width:20%'>Comment</div>\n".
		      "              <div style='flex:1 1 auto'><input type='text' name='comment' value='' size='30' class='form-control' style='max-width:520px'></div>\n".
		      "            </div>\n".
		      "            <div class='text-muted' style='font-size:12px; margin-bottom:8px'>(ports can be either * for all ports, a single port, or a comma separated list of ports)</div>\n".
		      "            <div style='display:flex; justify-content:center; margin:6px 0;'><button id='qhtlTempRuleApplyBtn' type='submit' class='btn btn-default' data-bubble-color='purple'>Apply Temporary Rule</button></div>\n".
		      "          </form>\n".
		      "        </div>\n".
		      "      </div>\n".
		      "      <div class='modal-footer'>\n".
		      "        <button type='button' class='btn btn-default' id='qhtlTempRuleCloseBtn' data-dismiss='modal'>Close</button>\n".
		      "      </div>\n".
		      "    </div>\n".
		      "  </div>\n".
		      "</div>\n";
	  # Script to wire the Temporary Rule modal: use single-quoted heredoc to prevent Perl from interpolating $ in jQuery
	  print <<'QHTL_TEMP_MODAL_JS_A';
<script>(function(){ try{
  function getJQ(){ try{ return window.jQuery || window.$ || null; }catch(_){ return null; } }
  var $modal = $('#qhtlTempRuleModal');
  function appendToScope(){ try{ var $w=$('.qhtl-bubble-bg').first(); if($w.length){ $modal.appendTo($w); $modal.css({position:'absolute'}); try{ var el=$w.get(0); var cs=window.getComputedStyle(el); if(cs && cs.position==='static'){ el.style.position='relative'; } }catch(__){} } else { $modal.appendTo('body'); $modal.css({position:'fixed'}); } }catch(_){ } }
  window.openTempRule = function(prefill){ try{ appendToScope(); var jq=getJQ(); var $m=$modal; var mEl=document.getElementById('qhtlTempRuleModal'); try{ if(prefill && prefill.ip){ var ipI=document.querySelector('#qhtlTempRuleForm input[name=ip]'); if(ipI) ipI.value=prefill.ip; } }catch(__){} var canJQ = !!(jq && $m && typeof $m.modal==='function'); if (canJQ) { $m.css({ left:0, top:0, right:0, bottom:0, width:'auto', height:'auto', margin:0, background:'rgba(0,0,0,0.5)' }); $m.modal({ show:true, backdrop:false, keyboard:true }); try{ jq('body').removeClass('modal-open').css({ overflow: '' }); }catch(__){} } else if (mEl) { mEl.style.left='0'; mEl.style.top='0'; mEl.style.right='0'; mEl.style.bottom='0'; mEl.style.width='auto'; mEl.style.height='auto'; mEl.style.margin='0'; mEl.style.background='rgba(0,0,0,0.5)'; mEl.style.display='block'; mEl.style.opacity='1'; try{ mEl.classList.add('in'); mEl.classList.add('show'); }catch(_c){} mEl.setAttribute('aria-hidden','false'); } } catch(e){} };
  // Close modal when clicking outside dialog (works with or without jQuery)
	(function(){ try{
		var jq=getJQ(); var $m=$modal; var mEl=document.getElementById('qhtlTempRuleModal');
		// jQuery/Bootstrap path: bind on mousedown/touchstart/pointerdown
		if(jq && $m){
			try{ $m.off('mousedown.qhtlOutside touchstart.qhtlOutside pointerdown.qhtlOutside'); }catch(_){ }
			$m.on('mousedown.qhtlOutside touchstart.qhtlOutside pointerdown.qhtlOutside', function(ev){ try{
				var dlg = $(this).find('.modal-dialog')[0]; if(!dlg) return; var t = ev.target;
				if (t === this || (dlg && !dlg.contains(t))){ $(this).modal('hide'); }
			}catch(_){ } });
		}
		// Vanilla path: bind on mousedown/touchstart/pointerdown
		if(mEl){
			function hideVanilla(){ try{ if(jq && $m && typeof $m.modal==='function'){ $m.modal('hide'); } }catch(__){} mEl.style.display='none'; mEl.style.opacity=''; try{ mEl.classList.remove('in'); mEl.classList.remove('show'); }catch(_r){} mEl.setAttribute('aria-hidden','true'); }
			function outsideHandler(ev){ try{ var dlg=mEl.querySelector('.modal-dialog'); var t=ev.target; if (t===mEl || (dlg && !dlg.contains(t))){ hideVanilla(); } }catch(__){} }
			try{
				mEl.addEventListener('mousedown', outsideHandler, {passive:true});
				mEl.addEventListener('touchstart', outsideHandler, {passive:true});
				mEl.addEventListener('pointerdown', outsideHandler, {passive:true});
			}catch(_){ }
			var cb=document.getElementById('qhtlTempRuleCloseBtn'); if(cb){ cb.addEventListener('click', function(){ hideVanilla(); }); }
		}
	}catch(_){ } })();
  // AJAX-submit the form and render results inside body, keep header/button visible
  $(document).on('submit', '#qhtlTempRuleForm', function(ev){ try{ ev.preventDefault(); var f=this; var area = document.getElementById('qhtlTempRuleBody'); if(!area) return; if(area.qhtlCancelFade) area.qhtlCancelFade(); area.innerHTML = '<div class=\'text-muted\'>Applying…</div>'; var fd=new FormData(f); try{ fd.append('ajax','1'); }catch(__){} var u=f.getAttribute('action')||''; if(window.jQuery){ jQuery.ajax({ url:u, method:(f.method||'POST'), data:fd, processData:false, contentType:false }).done(function(d){ try{ area.innerHTML=d; if(area.qhtlArmAuto) area.qhtlArmAuto(); }catch(__){} }).fail(function(){ try{ area.innerHTML='<div class=\'text-danger\'>Failed to apply temporary rule.</div>'; }catch(__){} }); } else { var x=new XMLHttpRequest(); x.open((f.method||'POST'), u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ try{ if(x.status>=200 && x.status<300){ area.innerHTML=x.responseText; if(area.qhtlArmAuto) area.qhtlArmAuto(); } else { area.innerHTML='<div class=\'text-danger\'>Failed to apply temporary rule.</div>'; } }catch(__){} } }; x.send(fd); } }catch(_){ } });
  // Wire the Temp star long-press to open this modal too (3s), similar overlay/countdown as others
  (function(){ try{ var btn = document.querySelector('.qhtl-star[data-qaction=\'temp\']'); if(!btn) return; var secs=3, down=false, t=null, remain=secs, overlay=null; function clearOv(){ try{ if(overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay); }catch(_){ } overlay=null; } function cancel(){ down=false; if(t){ clearInterval(t); t=null; } clearOv(); btn.dataset.lpHandled='0'; btn.classList.remove('counting'); } function done(){ if(t){ clearInterval(t); t=null; } btn.dataset.lpHandled='1'; clearOv(); btn.classList.remove('counting'); try{ openTempRule({}); }catch(__){} } function start(){ down=true; remain=secs; clearOv(); btn.classList.add('counting'); overlay=document.createElement('div'); overlay.className='qhtl-star-countdown'; overlay.style.cssText='position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:16px;color:#ffff00;text-shadow:0 1px 2px rgba(0,0,0,.6);pointer-events:none;'; overlay.textContent=remain; btn.appendChild(overlay); t=setInterval(function(){ if(!down){ cancel(); return; } remain--; if(remain>0){ overlay.textContent=remain; } else { done(); } }, 1000); } btn.addEventListener('mousedown', start); btn.addEventListener('touchstart', start, {passive:true}); ['mouseup','mouseleave','touchend','touchcancel','blur'].forEach(function(ev){ btn.addEventListener(ev, cancel, {passive:true}); }); btn.addEventListener('click', function(e){ if(btn.dataset.lpHandled==='1'){ e.preventDefault(); if(e.stopImmediatePropagation) e.stopImmediatePropagation(); btn.dataset.lpHandled='0'; } }, true); }catch(_){ } })();
  // Capture-phase click to ensure Temp star always opens the popup (robust vs inline handlers)
  document.addEventListener('click', function(ev){ try{ var el = ev.target && ev.target.closest ? ev.target.closest('.qhtl-star[data-qaction=\'temp\']') : null; if(!el) return; ev.preventDefault(); if(ev.stopPropagation) ev.stopPropagation(); if(ev.stopImmediatePropagation) ev.stopImmediatePropagation(); openTempRule({}); }catch(_){ } }, true);
  // Load optional external behavior file for the Temp Rule modal
  var s=document.createElement('script'); s.async=true;
QHTL_TEMP_MODAL_JS_A
	  print "  s.src='$script?action=widget_js&name=qTempRule.js&v=$myv';\n";
	  print <<'QHTL_TEMP_MODAL_JS_B';
  try{ document.body.appendChild(s); }catch(__){}
}catch(e){} })();</script>
QHTL_TEMP_MODAL_JS_B
		# Fallback: define openTempRule and handlers without jQuery if previous script failed (ensures popup opens)
		print "<script>(function(){ try{\n".
		      "  if (typeof window.openTempRule !== 'function') {\n".
		      "    window.openTempRule = function(prefill){ try{ var modal=document.getElementById('qhtlTempRuleModal'); if(!modal) return; var wrap=document.querySelector('.qhtl-bubble-bg'); if(wrap){ try{ wrap.appendChild(modal); modal.style.position='absolute'; }catch(_){} } else { try{ document.body.appendChild(modal); modal.style.position='fixed'; }catch(_){} } try{ if(prefill && prefill.ip){ var ipI = document.querySelector('#qhtlTempRuleForm input[name=ip]'); if(ipI) ipI.value = prefill.ip; } }catch(__){} modal.style.left='0'; modal.style.top='0'; modal.style.right='0'; modal.style.bottom='0'; modal.style.width='auto'; modal.style.height='auto'; modal.style.margin='0'; modal.style.background='rgba(0,0,0,0.5)'; modal.style.display='block'; modal.setAttribute('aria-hidden','false'); } catch(e){} };\n".
			  "    // Outside-click to close (vanilla)\n".
			  "    (function(){ try{ var modal=document.getElementById('qhtlTempRuleModal'); if(!modal) return; function hide(){ try{ modal.style.display='none'; modal.setAttribute('aria-hidden','true'); }catch(__){} } function outside(ev){ try{ var dlg=modal.querySelector('.modal-dialog'); var t=ev.target; if (t===modal || (dlg && !dlg.contains(t))){ hide(); } }catch(__){} } modal.addEventListener('mousedown', outside, {passive:true}); modal.addEventListener('touchstart', outside, {passive:true}); modal.addEventListener('pointerdown', outside, {passive:true}); var cb=document.getElementById('qhtlTempRuleCloseBtn'); if(cb){ cb.addEventListener('click', function(){ hide(); }); } }catch(_){ } })();\n".
		      "    // AJAX-submit (vanilla)\n".
		      "    document.addEventListener('submit', function(ev){ try{ var f=ev.target; if(!f || f.id!=='qhtlTempRuleForm') return; ev.preventDefault(); var area=document.getElementById('qhtlTempRuleBody'); if(!area) return; if(area.qhtlCancelFade) area.qhtlCancelFade(); area.innerHTML='<div class=\\'text-muted\\'>Applying…</div>'; var fd=new FormData(f); try{ fd.append('ajax','1'); }catch(__){} var u=f.getAttribute('action')||''; var x=new XMLHttpRequest(); x.open((f.method||'POST'), u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ try{ if(x.status>=200 && x.status<300){ area.innerHTML=x.responseText; if(area.qhtlArmAuto) area.qhtlArmAuto(); } else { area.innerHTML='<div class=\\'text-danger\\'>Failed to apply temporary rule.</div>'; } }catch(__){} } }; x.send(fd); }catch(_){ } }, true);\n".
		      "  }\n".
		      "}catch(e){} })();</script>";
		# Hidden helpers: quickview links and minimal forms for star submissions
		print "<div id='qhtl-quick-hidden' style='display:none'>";
		print "<a class='quickview-link' data-which='allow' data-url='$script?action=viewlist&which=allow' href='javascript:void(0)'></a>";
		print "<a class='quickview-link' data-which='deny' data-url='$script?action=viewlist&which=deny' href='javascript:void(0)'></a>";
		print "<a class='quickview-link' data-which='ignore' data-url='$script?action=viewlist&which=ignore' href='javascript:void(0)'></a>";
		print "<form id='qallow' action='$script' method='post'><input type='hidden' name='action' value='qallow'><input type='text' name='ip' value=''></form>";
		print "<form id='qdeny' action='$script' method='post'><input type='hidden' name='action' value='qdeny'><input type='text' name='ip' value=''></form>";
		print "<form id='qignore' action='$script' method='post'><input type='hidden' name='action' value='qignore'><input type='text' name='ip' value=''></form>";
		print "<form id='grep' action='$script' method='post'><input type='hidden' name='action' value='grep'><input type='text' name='ip' value=''></form>";
		print "<form id='qkill' action='$script' method='post'><input type='hidden' name='action' value='kill'><input type='text' name='ip' value=''></form>";
		print "</div>";
		print "</td></tr>\n";

		# Inline content area for Quick Actions (results from star button actions)
		print "<tr style='background:transparent!important'><td colspan='2' style='background:transparent!important'><div id='qhtl-quick-inline-area' style='padding-top:10px;min-height:160px;background:transparent'></div></td></tr>\n";
		# Intercept hidden form submits (qallow,qdeny,qignore,grep,qkill) to load into the Quick Actions inline area
		print "<script>(function(){try{ var area=document.getElementById('qhtl-quick-inline-area'); if(!area) return;\n".
			"  function setLoading(msg){ try{ if(area.qhtlCancelFade) area.qhtlCancelFade(); area.innerHTML = '<div class=\\'text-muted\\'>'+(msg||'Loading...')+'</div>'; }catch(_){ } }\n".
			"  function onLoaded(html){ try{ area.innerHTML = html; if(area.qhtlArmAuto) area.qhtlArmAuto(); }catch(_){ } }\n".
			"  function handleForm(f){ try{ var fd=new FormData(f); try{ fd.append('ajax','1'); }catch(__){} var u=f.getAttribute('action')||''; setLoading(); if(window.jQuery){ jQuery.ajax({ url:u, method:(f.method||'POST'), data:fd, processData:false, contentType:false }).done(function(d){ onLoaded(d); }).fail(function(){ onLoaded('<div class=\\'text-danger\\'>Failed to load content.</div>'); }); } else { var x=new XMLHttpRequest(); x.open((f.method||'POST'), u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200&&x.status<300){ onLoaded(x.responseText); } else { onLoaded('<div class=\\'text-danger\\'>Failed to load content.</div>'); } } }; x.send(fd); } }catch(e){} }\n".
			"  document.addEventListener('submit', function(ev){ try{ var f=ev.target; if(!f || f.tagName!=='FORM') return; var id=f.id||''; if(id==='qallow'||id==='qdeny'||id==='qignore'||id==='grep'||id==='qkill'){ ev.preventDefault(); ev.stopPropagation(); ev.stopImmediatePropagation && ev.stopImmediatePropagation(); handleForm(f); } }catch(_){ } }, true);\n".
			"}catch(e){} })();</script>\n";


		print "</table>\n";
		print "</div>\n";

		print "<div id='home' class='tab-pane'>\n";
		print "<form id='qhtl-options-form' action='$script' method='post'>\n";
		# Ensure Options table and all cells are transparent so the gradient shows through
		print "<style>#qhtl-options-table, #qhtl-options-table thead th, #qhtl-options-table tbody td, #qhtl-options-table tbody tr { background: transparent !important; } #qhtl-options-table.table-striped > tbody > tr:nth-of-type(odd){ background: transparent !important; } #qhtl-options-table td, #qhtl-options-table th{ background-color: transparent !important; }</style>\n";
		print "<table id='qhtl-options-table' class='table table-bordered table-striped' style='background:transparent!important'>\n";
		print "<thead style='background:transparent!important'><tr><th colspan='2' style='background:transparent!important'>Server Information</th></tr></thead>";
		# Eight orange square buttons (80x80) with a 10px bright-orange halo, centered, each word on its own line
		print "<tr style='background:transparent!important'><td colspan='2' style='background:transparent!important'>";
		print "<div style='display:flex; justify-content:center; margin:10px 0;'>";
		print "  <div style='display:flex; flex-wrap:wrap; justify-content:center; align-items:center; gap:30px;'>";
		my @orangeBtns = (
			{ label => 'Test Security',   action => 'servercheck' },
			{ label => 'QhtLink Info',    action => 'readme'      },
			{ label => 'Search Logs',     action => 'loggrep'     },
			{ label => 'Active Ports',    action => 'viewports'   },
			{ label => 'Check RBLs',      action => 'rblcheck'    },
			{ label => 'View ipt-Log',    action => 'viewlogs'    },
			{ label => 'QhtL Stats',      action => 'chart'       },
			{ label => 'System Stats',    action => 'systemstats' },
		);
		foreach my $b (@orangeBtns) {
			my $label  = $b->{label};
			my $action = $b->{action};
			my $aria   = $label;
			my $label_html = join('<br>', map { "<span style=\"display:block; line-height:1.02;\">$_</span>" } split(/\s+/, $label));
			print "<button name='action' value='$action' type='button' aria-label='$aria' title='$label' onmouseover=\"this.style.transform='scale(1.05)'\" onmouseout=\"this.style.transform='scale(1)'\" style=\"all:unset; cursor:pointer; width:70px; height:70px; display:flex; align-items:center; justify-content:center; text-align:center; padding:6px; background: linear-gradient(180deg, #ffd27a 0%, #ffad33 50%, #ff9800 70%, #e67e00 100%); border:2px solid #e68900; box-shadow: 0 0 0 10px rgba(255,165,0,0.65), 0 10px 18px rgba(255,140,0,0.35); transition: transform .15s ease; transform: translateZ(0);\"><span style=\"display:block; color:#fff; font-weight:800; font-size:15px; line-height:1.02; text-shadow:0 1px 0 rgba(0,0,0,0.25); width:100%; text-align:center;\">$label_html</span></button>";
		}
        # Load an optional, per-button JS file named as 'o' + label without non-alphanumerics + '.js' (e.g., Active Ports => oActivePorts.js)
        foreach my $b (@orangeBtns) {
            my $label = $b->{label};
            my $norm = $label; $norm =~ s/[^A-Za-z0-9]+//g; # strip spaces, hyphens, punctuation
            my $ofile = "o${norm}.js";
            print "<script src='$script?action=widget_js&name=$ofile&v=$myv'></script>";
        }
		print "  </div>";
		print "</div>";
		print "</td></tr>\n";
		# Inline content area for Options actions (load results below squares)
		print "<tr style='background:transparent!important'><td style='background:transparent!important'><div id='qhtl-options-inline-area' style='padding-top:10px;min-height:180px;background:transparent'></div></td></tr>\n";
		print "</table>\n";
		print "</form>\n";

		# Delegate the Options form submit/click to load into inline area instead of navigating
		print "<script>(function(){\n";
		print "  try{ var of=document.getElementById('qhtl-options-form'); if(!of) return; var area=document.getElementById('qhtl-options-inline-area'); if(!area) return;\n";
		print "    function setLoading(){ try{ if(area.qhtlCancelFade) area.qhtlCancelFade(); if(window.jQuery){ jQuery(area).html('<div class=\\\'text-muted\\\'>Loading...</div>'); } else { area.innerHTML='<div class=\\\'text-muted\\\'>Loading...</div>'; } }catch(_){ } }\n";
		print "    function onLoaded(html){ try{ area.innerHTML = html; if(area.qhtlArmAuto) area.qhtlArmAuto(); }catch(_){ } }\n";
		print "    function sendAjax(submitter){ try{ setLoading(); var u = of.getAttribute('action') || ''; var fd = new FormData(of); try{ fd.append('ajax','1'); }catch(__){} try{ if(submitter && submitter.name){ fd.append(submitter.name, submitter.value); } }catch(__){}\n";
		print "      if (window.jQuery) { jQuery.ajax({ url: u, method: 'POST', data: fd, processData: false, contentType: false }).done(function(d){ onLoaded(d); }).fail(function(){ onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); }); }\n";
		print "      else { var x=new XMLHttpRequest(); x.open('POST', u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ onLoaded(x.responseText); } else { onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); } } }; x.send(fd); } }catch(e){} }\n";
		print "    of.addEventListener('submit', function(ev){ try{ ev.preventDefault(); sendAjax(ev.submitter || null); }catch(_){ } }, true);\n";
		print "    // Also intercept direct clicks/keys on square buttons to send AJAX and include their name/value\n";
		print "    of.addEventListener('click', function(ev){ try{ var btn = ev.target && ev.target.closest ? ev.target.closest('button[name=action]') : null; if(!btn) return; ev.preventDefault(); sendAjax(btn); }catch(_){ } }, true);\n";
		print "    of.addEventListener('keydown', function(ev){ try{ var key=ev.key||''; if(key!=='Enter' && key!==' ') return; var btn = ev.target && ev.target.closest ? ev.target.closest('button[name=action]') : null; if(!btn) return; ev.preventDefault(); sendAjax(btn); }catch(_){ } }, true);\n";
		print "    // Intercept submits from forms inside the Options inline area (e.g., System Stats), and load inline here\n";
	print "    document.addEventListener('submit', function(ev){ try{ var f=ev.target; if(!f || f.tagName!=='FORM') return; if(!area.contains(f)) return; if(f.getAttribute('data-noajax')==='1') return; ev.preventDefault(); if(ev.stopPropagation) ev.stopPropagation(); if(ev.stopImmediatePropagation) ev.stopImmediatePropagation(); var msg='Loading...'; try{ if(f.querySelector('[name=action][value=rblcheck]')){ msg='Running RBL checks — this can take several minutes…'; } }catch(__){} try{ if(window.jQuery){ jQuery(area).html('<div class=\\\'text-muted\\\'>'+msg+'</div>'); } else { area.innerHTML='<div class=\\\'text-muted\\\'>'+msg+'</div>'; } }catch(__){} var fd=new FormData(f); try{ fd.append('ajax','1'); }catch(__){} var u=f.getAttribute('action')||''; if(window.jQuery){ jQuery.ajax({ url:u, method:'POST', data:fd, processData:false, contentType:false }).done(function(d){ onLoaded(d); }).fail(function(){ onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); }); } else { var x=new XMLHttpRequest(); x.open('POST', u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ onLoaded(x.responseText); } else { onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); } } }; x.send(fd); } }catch(_){ } }, true);\n";
		print "    // Document-level click capture to catch submit button clicks inside Options inline area\n";
	print "    document.addEventListener('click', function(ev){ try{ var btn = ev.target && ev.target.closest ? ev.target.closest('input[type=submit],button[type=submit]') : null; if(!btn) return; var f = btn.form; if(!f) return; if(!area.contains(f)) return; if(f.getAttribute('data-noajax')==='1') return; ev.preventDefault(); if(ev.stopPropagation) ev.stopPropagation(); if(ev.stopImmediatePropagation) ev.stopImmediatePropagation(); var msg='Loading...'; try{ if(f.querySelector('[name=action][value=rblcheck]')){ msg='Running RBL checks — this can take several minutes…'; } }catch(__){} try{ if(window.jQuery){ jQuery(area).html('<div class=\\\'text-muted\\\'>'+msg+'</div>'); } else { area.innerHTML='<div class=\\\'text-muted\\\'>'+msg+'</div>'; } }catch(__){} var fd = new FormData(f); try{ fd.append('ajax','1'); }catch(__){} try{ if(btn.name){ fd.append(btn.name, btn.value); } }catch(__){} var u = f.getAttribute('action')||''; if(window.jQuery){ jQuery.ajax({ url:u, method:'POST', data:fd, processData:false, contentType:false }).done(function(d){ onLoaded(d); }).fail(function(){ onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); }); } else { var x=new XMLHttpRequest(); x.open('POST', u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ onLoaded(x.responseText); } else { onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); } } }; x.send(fd); } }catch(_){ } }, true);\n";
		print "    // Global helper to force-submit any Options-area form via AJAX (used as onsubmit handler)\n";
	print "    window.__QHTL_OPTIONS_AJAX = function(f){ try{ if(!f) return true; var area=document.getElementById('qhtl-options-inline-area'); if(!area) return true; if(!area.contains(f)) return true; if(f.getAttribute('data-noajax')==='1') return true; var msg='Loading...'; try{ if(f.querySelector('[name=action][value=rblcheck]')){ msg='Running RBL checks — this can take several minutes…'; } }catch(__){} try{ if(window.jQuery){ jQuery(area).html('<div class=\\\'text-muted\\\'>'+msg+'</div>'); } else { area.innerHTML='<div class=\\\'text-muted\\\'>'+msg+'</div>'; } }catch(__){} var fd=new FormData(f); try{ fd.append('ajax','1'); }catch(__){} var u=f.getAttribute('action')||''; if(u && u.indexOf('ajax=1')===-1){ u += (u.indexOf('?')>-1?'&':'?')+'ajax=1'; } if(window.jQuery){ jQuery.ajax({ url:u, method:(f.method||'POST'), data:fd, processData:false, contentType:false }).done(function(d){ try{ area.innerHTML=d; if(area.qhtlArmAuto) area.qhtlArmAuto(); }catch(__){} }).fail(function(){ try{ area.innerHTML='<div class=\\\'text-danger\\\'>Failed to load content.</div>'; }catch(__){} }); } else { var x=new XMLHttpRequest(); x.open((f.method||'POST'), u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ try{ if(x.status>=200 && x.status<300){ area.innerHTML=x.responseText; if(area.qhtlArmAuto) area.qhtlArmAuto(); } else { area.innerHTML='<div class=\\\'text-danger\\\'>Failed to load content.</div>'; } }catch(__){} } }; x.send(fd); } return false; } catch(e){ return true; } };\n";
		print "    // Also catch clicks on submit buttons inside the Options inline area to prevent navigation and submit via AJAX\n";
		print "    area.addEventListener('click', function(ev){ try{ var btn = ev.target && ev.target.closest ? ev.target.closest('input[type=submit],button[type=submit]') : null; if(!btn) return; var f = btn.form; if(!f || !area.contains(f)) return; ev.preventDefault(); if(ev.stopPropagation) ev.stopPropagation(); if(ev.stopImmediatePropagation) ev.stopImmediatePropagation(); setLoading(); var fd = new FormData(f); try{ fd.append('ajax','1'); }catch(__){} try{ if(btn.name){ fd.append(btn.name, btn.value); } }catch(__){} var u = f.getAttribute('action')||''; if(window.jQuery){ jQuery.ajax({ url:u, method:'POST', data:fd, processData:false, contentType:false }).done(function(d){ onLoaded(d); }).fail(function(){ onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); }); } else { var x=new XMLHttpRequest(); x.open('POST', u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ onLoaded(x.responseText); } else { onLoaded('<div class=\\\'text-danger\\\'>Failed to load content.</div>'); } } }; x.send(fd); } }catch(_){ } }, true);\n";
		print "  }catch(e){}\n";
		print "})();</script>\n";
		if (!$config{INTERWORX} and (-e "/etc/apf" or -e "/usr/local/bfd")) {
			print "<table class='table table-bordered table-striped' style='background:transparent!important'>\n";
			print "<thead style='background:transparent!important'><tr><th style='background:transparent!important'>Legacy Firewalls</th></tr></thead>";
			print "<tr><td><form action='$script' method='post'><button name='action' value='remapf' type='submit' class='btn btn-default'>Remove APF/BFD</button></form><div class='text-muted small' style='margin-top:6px'>Remove APF/BFD from the server. You must not run both APF or BFD with qhtlfirewall on the same server</div></td></tr>\n";
			print "</table>\n";
		}
		print "</div>\n";

		# New Firewall1 tab (placeholder) placed between Options and Waterfall
		print "<div id='firewall1' class='tab-pane'>\n";
		print "<table class='table table-bordered table-striped'>\n";
	print "<thead><tr><th colspan='2'>QHTL \"Firewall\"</th></tr></thead>";
		# Replace single + with 8-button red plus cluster
		print "<tr class='fw-plus-row'><td colspan='2' class='fw-plus-cell'>";
		print <<'QHTL_FIREWALL_CLUSTER';
<style>
#firewall1 .fw-plus-wrapper { position:relative; width:100%; display:flex; justify-content:center; padding:7px 0 7px; }
/* Glossy circular buttons forming a plus. Increase gap so halos don't merge */
/* Horizontal row of plus buttons */
#firewall1 .fw-plus-grid { display:flex; flex-wrap:nowrap; gap:26px; position:relative; justify-content:center; align-items:center; }
/* Row plus buttons refined: remove white square feel, softer halo like waterfall */
#firewall1 .fw-plus-btn { position:relative; width:120px; height:120px; border:none; background:transparent; cursor:pointer; padding:0; outline:none; 
	filter:drop-shadow(0 4px 10px rgba(0,0,0,0.25));
	transition:transform .25s ease; }
#firewall1 .fw-plus-item { position:relative; display:flex; flex-direction:column; align-items:center; gap:8px; min-width:120px; }
#firewall1 .fw-plus-label { font-size:14px; font-weight:600; color:#8b0000; text-shadow:0 1px 1px rgba(255,255,255,0.55); line-height:1; white-space:nowrap; }
#firewall1 .fw-plus-item .fw-plus-btn:focus + .fw-plus-label, #firewall1 .fw-plus-item:hover .fw-plus-label { color:#b80000; }
/* Build glossy plus using two layered pseudo elements so each button is an independent plus shape */
#firewall1 .fw-plus-btn::before, #firewall1 .fw-plus-btn::after { content:""; position:absolute; left:50%; top:50%; transform:translate(-50%,-50%); border-radius:18px; background: linear-gradient(180deg,#ffe6e6 0%,#ffb5b5 8%,#ff2a2a 38%,#d40000 78%,#a70000 100%); }
/* Horizontal bar (on top) */
#firewall1 .fw-plus-btn::before { width:120px; height:48px; box-shadow: inset 0 2px 4px rgba(255,255,255,0.6), inset 0 -4px 10px rgba(120,0,0,0.55); z-index:2; }
/* Vertical bar (under) */
#firewall1 .fw-plus-btn::after { height:120px; width:48px; box-shadow: inset 0 2px 4px rgba(255,255,255,0.6), inset 0 -4px 10px rgba(120,0,0,0.55); z-index:1; }
/* Remove highlight bubble for cleaner look */
/* (fw-hi span will be ignored; will remove from markup) */
/* Hover/active effects */
#firewall1 .fw-plus-btn:hover { transform:translateY(-4px) scale(1.05); }
#firewall1 .fw-plus-btn:active { transform:scale(.94); }
/* Placement (7 true plus buttons + optional center for 8th if needed) */
/* No special positioning needed in row */
#fwb6 { display:none; }
/* Flush/Reboot countdown animation */
@keyframes fwFlushToOrange { 0% { filter:brightness(1); } 40% { filter:brightness(1.05); } 70% { filter:brightness(1.08); } 100% { filter:brightness(1.12); } }
#firewall1 .fw-flush-btn.fw-flush-counting::before, #firewall1 .fw-flush-btn.fw-flush-counting::after { background: linear-gradient(180deg,#ffe6e6 0%,#ffb5b5 10%,#ff6a2a 45%,#ff9c1a 78%,#ff8c00 100%) !important; animation: fwFlushToOrange 3s linear forwards; }
#firewall1 .fw-flush-btn.fw-flush-counting .fw-plus-label { text-shadow:0 0 4px #000,0 0 10px rgba(255,150,0,0.9),0 0 18px rgba(255,120,0,0.85); }
@media (max-width: 1200px) { #firewall1 .fw-plus-grid { flex-wrap:wrap; } }
@media (max-width: 860px) { #firewall1 .fw-plus-grid { transform:scale(.85); transform-origin:top center; } }
@media (max-width: 620px) { #firewall1 .fw-plus-grid { transform:scale(.72); } }
</style>
<style>#firewall1 .fw-plus-row td.fw-plus-cell { background:transparent!important; box-shadow:none!important; }</style>
<div class='fw-plus-wrapper'>
	<div class='fw-plus-grid' aria-label='Firewall Plus Buttons'>
		<div class='fw-plus-item'><button id='fwb1' class='fw-plus-btn fw-status-btn' aria-label='Firewall Status' title='Firewall Status'><span class='fw-plus-label' id='fw-status-text'>Status</span></button></div>
		<div class='fw-plus-item'><button id='fwb2' class='fw-plus-btn' aria-label='Config' title='Config'><span class='fw-plus-label'>Config</span></button></div>
		<div class='fw-plus-item'><button id='fwb3' class='fw-plus-btn' aria-label='Profiles' title='Profiles'><span class='fw-plus-label'>Profiles</span></button></div>
		<div class='fw-plus-item'><button id='fwb4' class='fw-plus-btn fw-allow-btn' aria-label='Allow IPs' title='Allow IPs'><span class='fw-plus-label'>Allow</span><span class='fw-plus-count' id='fw-allow-count'></span></button></div>
		<div class='fw-plus-item'><button id='fwb5' class='fw-plus-btn' aria-label='Rules' title='Firewall Rules'><span class='fw-plus-label'>Rules</span></button></div>
		<div class='fw-plus-item' style='display:none'><button id='fwb6' class='fw-plus-btn' aria-label='Inner Right Firewall Control' title='Inner Right Firewall Control'><span class='fw-plus-label'>Hidden</span></button></div>
	<div class='fw-plus-item'><button id='fwb7' class='fw-plus-btn' aria-label='Redirect' title='Redirect'><span class='fw-plus-label'>Redirect</span></button></div>
	<div class='fw-plus-item'><button id='fwb8' class='fw-plus-btn fw-flush-btn' aria-label='Flush / Restart Firewall' title='Flush / Restart Firewall (Hold 3s to Restart)'><span class='fw-plus-label' id='fw-flush-label'>Flush</span></button></div>
	</div>
</div>
<script>(function(){ try { var base=(window.QHTL_SCRIPT||'$script');
 // Allow count extraction (unchanged)
 // Allow count extraction with robust fallbacks
 var allowCount=(function(){
	 try {
		 var raw = "$permallows";
		 // Primary pattern: (Currently: <code>123</code> permanent IP allows)
		 var m = raw.match(/<code>(\d+)<\/code>/);
		 if(m) return m[1];
		 // Fallback: any standalone digits
		 var m2 = raw.match(/(\d+)/);
		 if(m2) return m2[1];
	 } catch(e) { }
	 return "0"; // default
 })();
 var c=document.getElementById('fw-allow-count'); if(c){ c.textContent = (allowCount===""?"0":allowCount); }
 // Late re-check in case markup injected asynchronously later updates $permallows equivalent
 setTimeout(function(){ try{ if(!c) c=document.getElementById('fw-allow-count'); if(c && (!c.textContent || /^(?:0|)$/.test(c.textContent))){ var raw="$permallows"; var mm=raw.match(/<code>(\d+)<\/code>/)||raw.match(/(\d+)/); if(mm){ c.textContent=mm[1]; } } }catch(_){ } }, 800);
 // Improved firewall status detection: prefer authoritative global set by server, fallback to callout or heuristic
 var statusState = (typeof window.QHTL_FW_STATUS==='string') ? window.QHTL_FW_STATUS : 'off';
 if(statusState!=='on' && statusState!=='off' && statusState!=='testing'){ statusState='off'; }
 if(statusState==='off' || statusState==='testing') { // only bother parsing DOM if not already definitively 'on'
	 try {
		 if(typeof window.QHTL_FW_STATUS==='undefined') { // only scrape if global absent
			 var header=document.querySelector('.bs-callout-success h4, .bs-callout-warning h4, .bs-callout-danger h4');
			 if(header){
				 var t=header.textContent||'';
				 if(/Test Mode|Testing/i.test(t)){ statusState='testing'; }
				 else if(/Enabled/i.test(t) && /Running/i.test(t)){ statusState='on'; }
				 else { statusState='off'; }
			 } else {
				 var hasDisable=document.querySelector("button[name='action'][value='disable']");
				 if(hasDisable){ statusState='on'; }
				 if(window.QHTL_FW_TESTING){ statusState='testing'; }
			 }
		 }
	 } catch(e){}
 }
 var statusBtn=document.getElementById('fwb1'); var statusLabel=document.getElementById('fw-status-text');
 if(statusBtn && statusLabel){
 	 statusBtn.classList.remove('fw-status-on','fw-status-testing','fw-status-off');
 	 if(statusState==='on'){ statusBtn.classList.add('fw-status-on'); statusLabel.textContent='On'; }
 	 else if(statusState==='testing'){ statusBtn.classList.add('fw-status-testing'); statusLabel.textContent='Testing'; }
 	 else { statusBtn.classList.add('fw-status-off'); statusLabel.textContent='Off'; }
     // Sync global so later logic trusts it
     try { window.QHTL_FW_STATUS = statusState; } catch(_){ }
 }
 // Delayed re-check once DOM likely settled (handles late header injection)
 setTimeout(function(){
	 try {
		 var s = (typeof window.QHTL_FW_STATUS==='string') ? window.QHTL_FW_STATUS : statusState;
		 if(s!==statusState){ statusState=s; }
		 var btn=document.getElementById('fwb1'); var lab=document.getElementById('fw-status-text');
		 if(btn && lab){
			 btn.classList.remove('fw-status-on','fw-status-testing','fw-status-off');
			 if(s==='on'){ btn.classList.add('fw-status-on'); lab.textContent='On'; }
			 else if(s==='testing'){ btn.classList.add('fw-status-testing'); lab.textContent='Testing'; }
			 else { btn.classList.add('fw-status-off'); lab.textContent='Off'; }
		 }
	 } catch(e){}
 }, 600);
 // Expose submitAction globally (refactored external per-button modules will call this)
window.submitAction = window.submitAction || function(act, extra){ try{
	// Inline-capable actions (include enable so starting firewall doesn't navigate away)
	var inlineActs=/^(conf|profiles|allow|status|redirect|denyf|restart|enable)$/; var tgt;
	if(inlineActs.test(act)){
		tgt=document.getElementById('fw-spacer-inline-area');
		if(tgt){
			// Cancel any pending fades
			if(tgt._fadeTimer){ clearTimeout(tgt._fadeTimer); tgt._fadeTimer=null; }
			if(tgt._fadeHideTimer){ clearTimeout(tgt._fadeHideTimer); tgt._fadeHideTimer=null; }
			tgt.classList.remove('fw-faded','fw-fade-hidden');
			tgt.classList.remove('fw-spacer-empty');
			tgt.classList.add('fw-loading');
		}
		var fd=new FormData(); fd.append('action',act); fd.append('ajax','1'); if(act==='enable'){ fd.append('override','1'); }
		if(extra){ Object.keys(extra).forEach(function(k){ fd.append(k,extra[k]); }); }
		fetch(base,{method:'POST',body:fd,credentials:'same-origin'}).then(r=>r.text()).then(function(txt){ try{
			try{ if(window.console && console.debug){ console.debug('[QHTL submitAction raw]', act, txt.slice(0,400)); } }catch(_){ }
			var fragment='';
			(function(){
				try {
					var div=document.createElement('div');
					div.innerHTML=txt;
					// Remove only script/noscript nodes (preserve forms so editors render inline)
					Array.from(div.querySelectorAll('script,noscript')).forEach(function(n){ n.parentNode.removeChild(n); });
					var inlineFrag=div.querySelector('.qhtl-inline-fragment');
					if(inlineFrag){ fragment=inlineFrag.innerHTML; return; }
					if(act==='status'){
						var preEl=div.querySelector('pre');
						if(preEl){ fragment='<pre>'+preEl.innerHTML+'</pre>'; return; }
						// If no pre, take entire body to at least show something
					}
					// Fallback: take first meaningful block-level element inside body
					var body=div.querySelector('body')||div;
					var firstBlock = body.querySelector('pre,table,div,section,article');
					if(firstBlock){ fragment=firstBlock.outerHTML; return; }
					// If body contains forms (config/profiles editors) but no block matched, keep the forms
					var forms=body.querySelectorAll('form');
					if(forms.length){ var wrap=document.createElement('div'); forms.forEach(function(fm){ wrap.appendChild(fm.cloneNode(true)); }); fragment=wrap.innerHTML; return; }
					fragment=body.innerHTML || txt;
				} catch(_){ fragment=txt; }
			})();
			if(act==='denyf'){ fragment='<div class="text-success">Temporary bans flushed.</div>'; }
			if(act==='restart'){ fragment='<div class="text-info">Firewall restart requested.</div>'; }
			if(act==='enable'){
				fragment='<div class="text-success">Firewall enable requested.</div>';
				try{ setTimeout(function(){ try{ window.submitAction('status'); }catch(_){ } }, 1600); }catch(_){ }
				// Hard reload fallback if status fails to populate anything meaningful after ~4s
				try { setTimeout(function(){ try{
					var t=document.getElementById('fw-spacer-inline-area');
					if(t){
						var tc=(t.textContent||'').trim();
						if(/Firewall enable requested/i.test(tc) || tc==='' || /No rules output|output unavailable/.test(tc)){
							if(window.console && console.warn){ console.warn('[QHTL enable fallback] Forcing full reload to get status.'); }
							window.location.reload();
						}
					}
				} catch(_){ } }, 4000); }catch(_){ }
			}
			var clean=fragment.trim();
			if(!clean && txt){ clean=txt.trim(); }
			if(!clean){
				if(act==='status'){ clean='<div class="text-muted">(No rules output)</div>'; }
				else if(act==='conf'){ clean='<div class="text-muted">(Config output unavailable)</div>'; }
				else if(act==='profiles'){ clean='<div class="text-muted">(Profiles output unavailable)</div>'; }
				else { clean='<div class="text-muted">(No output returned)</div>'; }
			}
			if(tgt){
				tgt.innerHTML=clean;
				// Secondary retry: if conf/status returned an empty placeholder, perform a non-AJAX fetch of full page and re-extract.
				(function retryFallback(){
					if(act!=='conf' && act!=='status') return;
					var placeholderRe=/(?:Config output unavailable|No rules output|No output returned|\(No rules output\)|\(Config output unavailable\))/i;
					if(!placeholderRe.test(clean)) return;
					try { if(window.console && console.debug){ console.debug('[QHTL retry] Attempting non-AJAX fallback for', act); } } catch(e){}
					try {
						var fd2=new FormData(); fd2.append('action',act); // intentionally omit ajax flag
						fetch(base,{method:'POST',body:fd2,credentials:'same-origin'})
							.then(function(r){ return r.text(); })
							.then(function(txt2){
								try {
									var div2=document.createElement('div'); div2.innerHTML=txt2;
									Array.from(div2.querySelectorAll('script,noscript')).forEach(function(n){ if(n.parentNode){ n.parentNode.removeChild(n); }});
									var newFrag='';
									var inline2=div2.querySelector('.qhtl-inline-fragment'); if(inline2){ newFrag=inline2.innerHTML; }
									if(!newFrag && act==='status'){
										var pre2=div2.querySelector('pre'); if(pre2){ newFrag='<pre>'+pre2.innerHTML+'</pre>'; }
									}
									if(!newFrag){
										var body2=div2.querySelector('body')||div2;
										var first2=body2.querySelector('pre,table,div,section,article');
										if(first2){ newFrag=first2.outerHTML; }
										if(!newFrag){
											var forms2=body2.querySelectorAll('form');
											if(forms2.length){ var wrap2=document.createElement('div'); forms2.forEach(function(fm){ wrap2.appendChild(fm.cloneNode(true)); }); newFrag=wrap2.innerHTML; }
										}
										if(!newFrag){ newFrag=body2.innerHTML||txt2; }
									}
									newFrag=(newFrag||'').trim();
									if(newFrag && !placeholderRe.test(newFrag) && newFrag.length>20){
										try { if(window.console && console.debug){ console.debug('[QHTL retry] Non-AJAX fetch produced content, replacing placeholder.'); } } catch(e){}
										tgt.innerHTML=newFrag;
									}
								} catch(e) { /* swallow parse issues */ }
							})
							.catch(function(){ /* ignore network errors */ });
					} catch(e) { /* swallow outer retry errors */ }
				})();
				tgt.classList.remove('fw-loading');
				try{ tgt.style.backgroundImage='none'; }catch(_){}
				// Schedule staged fade (20s then hide at 30s). Cancelled by new activity or user interaction.
				var schedule=function(){
					if(tgt._fadeTimer){ clearTimeout(tgt._fadeTimer); }
					if(tgt._fadeHideTimer){ clearTimeout(tgt._fadeHideTimer); }
					tgt._fadeTimer=setTimeout(function(){ try{ tgt.classList.add('fw-faded'); }catch(_){} },20000);
					tgt._fadeHideTimer=setTimeout(function(){ try{ tgt.classList.add('fw-fade-hidden'); }catch(_){} },30000);
				};
				// Interaction cancels fade & re-schedules
				var cancel=function(){
					if(tgt._fadeTimer){ clearTimeout(tgt._fadeTimer); tgt._fadeTimer=null; }
					if(tgt._fadeHideTimer){ clearTimeout(tgt._fadeHideTimer); tgt._fadeHideTimer=null; }
					tgt.classList.remove('fw-faded','fw-fade-hidden');
				};
				['mouseenter','mousedown','focusin','keydown','touchstart'].forEach(function(ev){
					if(!tgt._fadeBound){ tgt.addEventListener(ev,function(){ cancel(); schedule(); },{passive:true}); }
				});
				tgt._fadeBound=1;
				schedule();
			}
		}catch(e){ if(tgt){ tgt.innerHTML='<pre>'+String(e)+'</pre>'; tgt.classList.remove('fw-loading'); } }}).catch(function(e){ if(tgt){ tgt.innerHTML='<div class="text-danger">Request failed: '+e+'</div>'; tgt.classList.remove('fw-loading'); } });
		return; }
	// Non-inline acts fallback to full submit (rare now)
	var f=document.createElement('form'); f.method='post'; f.action=base; var i=document.createElement('input'); i.type='hidden'; i.name='action'; i.value=act; f.appendChild(i); if(extra){ Object.keys(extra).forEach(function(k){ var h=document.createElement('input'); h.type='hidden'; h.name=k; h.value=extra[k]; f.appendChild(h); }); } document.body.appendChild(f); f.submit();
}catch(e){} };
// Direct inline bindings (removed external module loader due to MIME issues in some environments)
setTimeout(function(){
	var statusBtn2=document.getElementById('fwb1'); if(statusBtn2 && !statusBtn2._fwBound){
		statusBtn2.addEventListener('click',function(ev){ try{
			if(statusBtn2.classList.contains('fw-status-off')){ window.submitAction('enable'); return; }
			window.submitAction('status');
		}catch(_){ } });
		statusBtn2._fwBound=1;
	}
	var map={fwb2:'conf',fwb3:'profiles',fwb4:'allow',fwb5:'status',fwb7:'redirect'};
	Object.keys(map).forEach(function(id){ var el=document.getElementById(id); if(!el) return; if(!el._fwBound){ el.addEventListener('click',function(){ if(window.submitAction) window.submitAction(map[id]); }); el._fwBound=1; } });
	var flush=document.getElementById('fwb8'); if(flush && !flush._fwBound){ flush.addEventListener('click',function(){ if(window.submitAction) window.submitAction('denyf'); }); flush._fwBound=1; }
},400);
 } catch(e){} })();</script>
QHTL_FIREWALL_CLUSTER
        # Interpolated heredoc (needs $script expansion for loader image URL)
		print <<"QHTL_FW_SPACER_CSS";
<style>
	#fw-spacer-inline-area { position:relative; z-index:20; background:transparent !important; min-height:220px; padding:8px 10px; box-sizing:border-box; }
	#fw-spacer-inline-area.fw-loading { background:transparent url('$script?action=fallback_asset&name=idle_fallback.gif&v=$myv') center 60px / 240px 68px no-repeat !important; }
	#fw-spacer-inline-area.fw-spacer-empty::before { content:none !important; }
	#fw-spacer-inline-area.fw-faded { opacity:.55; transition:opacity .6s ease; }
	#fw-spacer-inline-area.fw-fade-hidden { opacity:0; pointer-events:none; }
</style>
QHTL_FW_SPACER_CSS
		# Added/Updated: Firewall plus button label styling (labels above buttons, white text)
		# Find the existing fw-plus CSS block and append overrides.
		print <<'QHTL_FW_PLUS_LABELS_CSS';
<style>
/* Reposition labels inside horizontal bar of plus button */
#firewall1 .fw-plus-item {position:relative; display:inline-flex; flex-direction:column; align-items:center; justify-content:flex-start;}
#firewall1 .fw-plus-btn {position:relative;}
#firewall1 .fw-plus-btn .fw-plus-label {position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); font-size:16px; font-weight:700; color:#fff !important; text-shadow:0 0 3px #000,0 0 6px #d40000,0 0 12px #ff2020; letter-spacing:.6px; pointer-events:none; z-index:3; line-height:1; white-space:nowrap;}
#firewall1 .fw-plus-btn .fw-plus-count {position:absolute; bottom:-18px; left:50%; transform:translate(-50%,0); background:transparent !important; color:#00454d; font-weight:800; font-size:22px; line-height:1; padding:0; border:none !important; border-radius:0; box-shadow:none !important; min-width:0; text-align:center; z-index:40; letter-spacing:.5px; white-space:nowrap; filter:drop-shadow(0 2px 2px rgba(0,0,0,0.35)); pointer-events:none; }
#firewall1 .fw-plus-btn.fw-allow-btn .fw-plus-count { bottom:-22px; transform:translate(-50%,0); font-size:24px; color:#007b89; text-shadow:0 0 3px rgba(255,255,255,0.85),0 0 6px rgba(255,255,255,0.55); }
#firewall1 .fw-plus-btn .fw-plus-count:empty { display:inline; }
#firewall1 .fw-status-btn::before, #firewall1 .fw-status-btn::after { transition:background .4s ease; }
#firewall1 .fw-status-on::before, #firewall1 .fw-status-on::after { background: linear-gradient(180deg,#e8ffe9 0%,#b9f5c2 8%,#2ecc4f 42%,#1f9939 78%,#16722a 100%) !important; }
#firewall1 .fw-status-testing::before, #firewall1 .fw-status-testing::after { background: linear-gradient(180deg,#fff6e6 0%,#ffe2b3 8%,#ffb347 45%,#ff8c00 78%,#d46a00 100%) !important; }
#firewall1 .fw-status-off::before, #firewall1 .fw-status-off::after { background: linear-gradient(180deg,#ffe6e6 0%,#ffb5b5 8%,#ff2a2a 38%,#d40000 78%,#a70000 100%) !important; }
#firewall1 .fw-status-btn.fw-status-off .fw-plus-label { text-shadow:0 0 3px #000,0 0 6px #700,0 0 10px #900; }
#firewall1 .fw-status-btn.fw-status-on .fw-plus-label { text-shadow:0 0 3px #000,0 0 6px #0c5,0 0 12px #1fae55; }
#firewall1 .fw-status-btn.fw-status-testing .fw-plus-label { text-shadow:0 0 3px #000,0 0 6px #c96,0 0 12px #e87; }
#firewall1 .fw-plus-grid {margin-top:0 !important;}
#firewall1 .fw-plus-btn, #firewall1 .fw-plus-btn * {color:#fff !important;}
/* Allow button (fwb4) green theme */
#firewall1 .fw-plus-btn.fw-allow-btn::before, #firewall1 .fw-plus-btn.fw-allow-btn::after { background: linear-gradient(180deg,#e3fcff 0%,#b8f1f7 10%,#6ddbe8 38%,#27b9cc 70%,#138da0 100%) !important; }
#firewall1 .fw-plus-btn.fw-allow-btn .fw-plus-label { text-shadow:0 0 3px #000,0 0 6px #12b0c7,0 0 14px #3dd0e5 !important; }
/* Provide some extra space beneath plus buttons to show count if translated */
#firewall1 .fw-plus-grid { padding-bottom:26px; }
/* Advanced tab hex halo restoration */
#moreplus .qhtl-hex-btn { box-shadow:0 0 0 10px rgba(192,192,192,0.55), 0 6px 14px rgba(0,0,0,0.35); }
#moreplus .qhtl-hex-btn::after { content:""; position:absolute; inset:0; border-radius:6px; background:radial-gradient(circle at 30% 30%,rgba(255,255,255,0.9),rgba(255,255,255,0) 60%); pointer-events:none; mix-blend-mode:screen; }
/* Hold-to-disable status button states */
#firewall1 .fw-status-btn.hold-counting::before, #firewall1 .fw-status-btn.hold-counting::after { background: linear-gradient(180deg,#f2ffe6 0%,#d6f5b0 8%,#9ccc3a 40%,#7aa52c 78%,#5c7a20 100%) !important; }
#firewall1 .fw-status-btn.hold-warning::before, #firewall1 .fw-status-btn.hold-warning::after { background: linear-gradient(180deg,#fff4e0 0%,#ffd9a3 12%,#ffb347 45%,#ff8c00 78%,#d46a00 100%) !important; animation: fwWarnFlash 0.9s ease-in-out infinite; }
#firewall1 .fw-status-btn.hold-dimming::before, #firewall1 .fw-status-btn.hold-dimming::after { background: linear-gradient(180deg,#fff4e0 0%,#ffd0a0 10%,#ff7a30 38%,#ff2a2a 78%,#a70000 100%) !important; animation: fwDimToRed 3s linear forwards; }
#firewall1 .fw-status-btn.hold-counting .fw-plus-label, #firewall1 .fw-status-btn.hold-warning .fw-plus-label, #firewall1 .fw-status-btn.hold-dimming .fw-plus-label { text-shadow:0 0 4px #000,0 0 10px rgba(255,180,0,0.9),0 0 16px rgba(255,90,0,0.9); }
@keyframes fwWarnFlash { 0%,55% { filter:brightness(1); box-shadow:0 0 0 0 rgba(255,140,0,0.6),0 0 14px 4px rgba(255,120,0,0.4); } 70% { filter:brightness(1.25); box-shadow:0 0 0 4px rgba(255,140,0,0.5),0 0 18px 8px rgba(255,120,0,0.55); } 100% { filter:brightness(1); box-shadow:0 0 0 0 rgba(255,140,0,0.6),0 0 14px 4px rgba(255,120,0,0.4);} }
@keyframes fwDimToRed { 0% { filter:brightness(1); } 30% { filter:brightness(.9); } 60% { filter:brightness(.8); } 100% { filter:brightness(.65); } }
</style>
QHTL_FW_PLUS_LABELS_CSS
		print "</td></tr>\n";
		# Config row removed; action now mapped to second firewall plus button (fwb2)
		#print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='conf' type='submit' class='btn btn-default'>Config</button></form><div class='text-muted small' style='margin-top:6px'>Edit the configuration file for the qhtlfirewall firewall and qhtlwaterfall</div></td></tr>\n";
	# Profiles row removed; action now mapped to third firewall plus button (fwb3)
	#print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='profiles' type='submit' class='btn btn-default'>Profiles</button></form><div class='text-muted small' style='margin-top:6px'>Apply pre-configured qhtlfirewall.conf profiles and backup/restore qhtlfirewall.conf</div></td></tr>\n";
    # View Rules row removed; functionality moved to fifth plus button (fwb5 -> action=status)
	#print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='allow' type='submit' class='btn btn-default'>Allow IPs</button></form><div class='text-muted small' style='margin-top:6px'>Edit qhtlfirewall.allow, the IP address allow file $permallows</div></td></tr>\n";
	# Spacer/inline row enhanced: acts as a secondary inline output target for the plus buttons (conf/profiles/allow/status/redirect)
	# Includes loader background animation similar to main inline output cell; fades/disappears once populated
	print "<tr style='background:transparent!important'><td colspan='2' style='background:transparent!important'>".
		      "<div id='fw-spacer-inline-area' class='fw-spacer-empty fw-loading'></div>".
		      "</td></tr>\n";
	print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='deny' type='submit' class='btn btn-default'>Deny IPs</button></form><div class='text-muted small' style='margin-top:6px'>Edit qhtlfirewall.deny, the IP address deny file $permbans</div></td></tr>\n";
	# Unified inline output/content area (reusing gradient background motif)
	my $loader = "$script?image=qhtlfirewall-loader.gif"; # isolate interpolation to a single variable
print <<"QHTL_FW_INLINE_OUT";
<tr id='fw-inline-row'>
  <td id='fw-inline-output' colspan='2' style="min-height:280px;position:relative;margin:8px 6px;padding:12px;border:2px solid rgba(255,255,255,0.35);border-radius:6px;overflow:auto;box-shadow:inset 0 0 8px rgba(0,0,0,0.25);background:linear-gradient(180deg,#d7f0ff 0%,#b5d6ff 50%,#c9b5ff 100%);"></td>
</tr>
<style>
	/* Simplified single-layer inline output cell; loader via background image on loading (now the TD itself) */
	#fw-inline-output.loading { filter:brightness(.92); background-image:linear-gradient(180deg,#d7f0ff 0%,#b5d6ff 50%,#c9b5ff 100%), url('$loader'); background-position:0 0, center center; background-repeat:repeat, no-repeat; background-size:auto,96px 96px; }
	#fw-inline-output .fw-inline-result pre { background:rgba(0,0,0,0.55); color:#eee; padding:10px; border-radius:4px; }
</style>
QHTL_FW_INLINE_OUT
	# Redundant control rows removed (Enable/Disable/Restart now handled by status plus button hold logic)
	# print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='enable' type='submit' class='btn btn-default'>Enable</button></form><div class='text-muted small' style='margin-top:6px'>Enables qhtlfirewall and qhtlwaterfall if previously Disabled</div></td></tr>\n";
	# print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='disable' type='submit' class='btn btn-default'>Disable</button></form><div class='text-muted small' style='margin-top:6px'>Completely disables qhtlfirewall and qhtlwaterfall</div></td></tr>\n";
	# print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='restart' type='submit' class='btn btn-default'>Restart</button></form><div class='text-muted small' style='margin-top:6px'>Restart the qhtlfirewall iptables firewall</div></td></tr>\n";
	print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='temp' type='submit' class='btn btn-default'>Temp IPs</button></form><div class='text-muted small' style='margin-top:6px'>View/Remove the <i>temporary</i> IP entries $tempbans</div></td></tr>\n";
	print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='sips' type='submit' class='btn btn-default'>Deny IPs</button></form><div class='text-muted small' style='margin-top:6px'>Deny access to and from specific IP addresses configured on the server (qhtlfirewall.sips)</div></td></tr>\n";
	#print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='denyf' type='submit' class='btn btn-default'>Flush All</button></form><div class='text-muted small' style='margin-top:6px'>Removes and unblocks all entries in qhtlfirewall.deny (excluding those marked \"do not delete\") and all temporary IP entries (blocks <i>and</i> allows)</div></td></tr>\n"; # Mapped to fwb8 plus button (Flush)
	# Fix Tool moved into Advanced (hex buttons) as 3rd hex; original row removed
		print "</table>\n";
		print "</div>\n";
		# Inject JS helpers for inline output + options tab reset + promo modal centering
		print <<'QHTL_INLINE_HELPER_JS';
	<script>(function(){try{
	// Inline output hijack: capture postbacks triggered by plus buttons & table buttons
	var out=document.getElementById('fw-inline-output');
	if(out){
		function hijackForms(){
			document.querySelectorAll("form[action][method='post'] button[name='action']").forEach(function(btn){
				var form=btn.closest('form'); if(!form) return; if(form.dataset.qhtlHijacked) return; form.dataset.qhtlHijacked='1';
				form.addEventListener('submit', function(ev){
					var act=btn.value; if(!/^(allow|deny|conf|profiles|status|redirect|temp|sips|denyf)$/.test(act)) return; ev.preventDefault();
					try{out.classList.add('loading');}catch(_){ }
					var fd=new FormData(form); fd.append('ajax','1');
					fetch(form.action||location.href,{method:'POST',body:fd,credentials:'same-origin'}).then(r=>r.text()).then(function(txt){
						try{ out.classList.remove('loading'); out.innerHTML = (txt.replace(/<form[\s\S]*?<\/form>/gi,'').trim() || '<div class="text-muted">(No output returned)</div>'); }catch(e){ out.innerHTML='<pre>'+String(e)+'</pre>'; }
					}).catch(function(e){ out.innerHTML='<div class="text-danger">Request failed: '+e+'</div>'; });
				});
			});
		}
		setTimeout(hijackForms,400); setTimeout(hijackForms,1200); document.addEventListener('click', function(){ setTimeout(hijackForms,200); }, true);
	}
	// Options tab re-click reset (clears any inline outputs in that tab area)
	var tabs=document.querySelectorAll('.nav-tabs li a');
	tabs.forEach(function(a){ a.addEventListener('click', function(){ a.dataset.lastClick=Date.now(); }); });
	// Find the Options tab link without using non-standard :contains
	var optTab=(function(){
		var c=document.querySelectorAll('.nav-tabs li a');
		for(var i=0;i<c.length;i++){ var t=c[i].textContent.trim().toLowerCase(); if(t==='options'){ return c[i]; } }
		return null;
	})();
	if(optTab){ optTab.addEventListener('click', function(){
		var last=optTab.dataset._last?parseInt(optTab.dataset._last,10):0; var now=Date.now();
		if(last && (now-last)<800){
			var optPane=document.getElementById('Options')||document.querySelector('#options,#OptionsTab');
			if(optPane){ var area=document.getElementById('fw-inline-output'); if(area){ area.innerHTML='<div class="text-muted">(Reset)</div>'; } }
		}
		optTab.dataset._last=now;
	}); }
	// Promo modal centering tweak
	function recenterPromo(){ var m=document.querySelector('.qhtl-promo-modal'); if(!m) return; m.style.position='fixed'; m.style.left='50%'; m.style.top='90px'; m.style.transform='translateX(-50%)'; }
	setInterval(recenterPromo,800);
	}catch(e){ console.error('inline helper init failed', e); }})();</script>
QHTL_INLINE_HELPER_JS

		# New Waterfall tab (duplicate of QhtLink Waterfall content) placed before QhtLink Firewall
					print "<div id='waterfall' class='tab-pane'>\n";
		print "<table class='table table-bordered table-striped' style='background:transparent!important'>\n";
		print "<thead style='background:transparent!important'><tr><th style='background:transparent!important'>qhtlwaterfall - Login Failure Daemon</th></tr></thead>";
					print "<tr style='background:transparent!important'><td style='background:transparent!important'>".
				  "<div style='display:flex;flex-wrap:wrap;gap:14px;align-items:flex-start;justify-content:center'>".
						"<div id='wstatus-anchor' style='position:relative;display:inline-block;width:100px;height:100px'>".
							"<div id='wstatus-fallback' class='wcircle' style='position:relative;width:100px;height:100px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;vertical-align:top;'>".
								"<div class='wcircle-outer' style='position:absolute;inset:0;border-radius:50%;background: radial-gradient(circle at 30% 30%, #e3f9e7 0%, #b4f2c1 50%, #7fdc95 85%);box-shadow: 0 6px 18px rgba(0,0,0,0.25), inset 0 2px 6px rgba(255,255,255,0.6);'></div>".
								"<div class='wcircle-inner' role='button' tabindex='0' title='Waterfall Status' style='position:relative;width:80px;height:80px;border-radius:50%;border:2px solid #2f8f49;background: linear-gradient(180deg, #66e08a 0%, #34a853 100%);color:#fff;font-weight:700;display:flex;align-items:center;justify-content:center;user-select:none;box-shadow: inset 0 2px 6px rgba(255,255,255,0.35), 0 8px 16px rgba(52,168,83,0.35);cursor:pointer;'>On</div>".
								"<div class='wcircle-msg' style='position:absolute;bottom:-22px;width:140px;left:50%;transform:translateX(-50%);text-align:center;font-size:12px;color:#333;text-shadow:0 1px 0 rgba(255,255,255,0.25);'></div>".
							"</div>".
						"</div>".
					"<div id='wignore-anchor' style='width:100px;height:100px'></div>".
					"<div id='wdirwatch-anchor' style='width:100px;height:100px'></div>".
					"<div id='wddns-anchor' style='width:100px;height:100px'></div>".
					"<div id='walerts-anchor' style='width:100px;height:100px'></div>".
					"<div id='wscanner-anchor' style='width:100px;height:100px'></div>".
					"<div id='wblocklist-anchor' style='width:100px;height:100px'></div>".
					"<div id='wusers-anchor' style='width:100px;height:100px'></div>".
						"</div>".
					"</td></tr>\n";
		# Seasonal decorations loader (Oct 1–31)
		print "<script>(function(){ try { var d=new Date(); var m=d.getUTCMonth()+1, day=d.getUTCDate(); if (m===10 && day>=1 && day<=31) { var base=(window.QHTL_SCRIPT||'$script'); var css=document.createElement('link'); css.rel='stylesheet'; css.href=base+'?action=holiday_asset&name=style.css&v=$myv'; (document.head||document.documentElement).appendChild(css); var layer=document.createElement('div'); layer.id='qhtl-holiday-layer'; var a=document.getElementById('wstatus-anchor'); if(a){ a.style.position='relative'; a.appendChild(layer); var p=new Image(); p.src=base+'?action=holiday_asset&name=pumpkin.svg&v=$myv'; p.className='qhtl-pumpkin'; layer.appendChild(p); var b=new Image(); b.src=base+'?action=holiday_asset&name=bat.svg&v=$myv'; b.className='qhtl-bat'; b.style.top='-4px'; layer.appendChild(b); var outer=document.getElementById('wstatus-outer'); if(outer){ outer.classList.add('qhtl-halloween'); } } } } catch(e){} })();</script>\n";
			print "<script src='$script?action=widget_js&name=wignore.js&v=$myv'></script>\n";
			print "<script src='$script?action=widget_js&name=wdirwatch.js&v=$myv'></script>\n";
			print "<script src='$script?action=widget_js&name=wddns.js&v=$myv'></script>\n";
			print "<script src='$script?action=widget_js&name=walerts.js&v=$myv'></script>\n";
			print "<script src='$script?action=widget_js&name=wscanner.js&v=$myv'></script>\n";
			print "<script src='$script?action=widget_js&name=wblocklist.js&v=$myv'></script>\n";
			print "<script src='$script?action=widget_js&name=wusers.js&v=$myv'></script>\n";
			print "<script>(function(){\n"
				."  // Ensure wstatus.js is loaded; if not, inject it now\n"
				."  if (!window.WStatus) {\n"
				."    try {\n"
				."      var s=document.createElement('script');\n"
				."      var base = (typeof QHTL_SCRIPT!=='undefined' && QHTL_SCRIPT) ? QHTL_SCRIPT : '$script';\n"
				."      s.src = base + '?action=wstatus_js&v=$myv';\n"
				."      s.defer = true;\n"
				."      (document.head||document.documentElement).appendChild(s);\n"
				."    } catch(e){}\n"
				."  }\n"
				."  var attempts=0, maxAttempts=40; // ~10s at 250ms\n"
				."  function mounted(sel){ var el=document.querySelector(sel); if(!el) return false; return !!el.querySelector('#wstatus-popup') || el.getAttribute('data-mounted')==='1'; }\n"
				."  function markMounted(sel){ var el=document.querySelector(sel); if(el) el.setAttribute('data-mounted','1'); }\n"
				."  // Remove fallback once mounted, or after a grace period even if not\n"
				."  function removeFallback(){ /* keep fallback visible as a control in case WStatus fails to mount */ }\n"
				."  // Fallback click: try to open/refresh status\n"
				."  (function(){ var f=document.getElementById('wstatus-fallback'); if(!f) return; try{ var inner=f.querySelector('.wcircle-inner'); if(inner){ inner.addEventListener('click', function(e){ e.preventDefault(); if (window.WStatus && typeof WStatus.open==='function'){ try{ WStatus.open(); return; }catch(_){ } } try{ var base=(window.QHTL_SCRIPT||'$script'); var u=base+'?action=qhtlwaterfallstatus&ajax=1'; var area=document.getElementById('qhtl-inline-area'); if(area){ if(window.jQuery){ jQuery(area).html('<div class=\"text-muted\">Loading...</div>').load(u); } else { var x=new XMLHttpRequest(); x.open('GET', u, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} x.onreadystatechange=function(){ if(x.readyState===4 && x.status>=200 && x.status<300){ area.innerHTML=x.responseText; } }; x.send(); } } else { /* as last resort navigate */ window.location=base+'?action=qhtlwaterfallstatus'; } }catch(__){} }); } }catch(_){} })();\n"
				."  function tryMount(){\n"
				."    attempts++;\n"
				."    try{ if(!mounted('#wstatus-anchor') && window.WStatus){ if(WStatus.mountInline('#wstatus-anchor')) markMounted('#wstatus-anchor'); } }catch(e){}\n"
				."    if (mounted('#wstatus-anchor')) { removeFallback(); }\n"
				."    try{ if(!mounted('#wignore-anchor') && window.WIgnore){ if(WIgnore.mountInline('#wignore-anchor')) markMounted('#wignore-anchor'); } }catch(e){}\n"
				."    try{ if(!mounted('#wdirwatch-anchor') && window.WDirWatch){ if(WDirWatch.mountInline('#wdirwatch-anchor')) markMounted('#wdirwatch-anchor'); } }catch(e){}\n"
				."    try{ if(!mounted('#wddns-anchor') && window.WDDNS){ if(WDDNS.mountInline('#wddns-anchor')) markMounted('#wddns-anchor'); } }catch(e){}\n"
				."    try{ if(!mounted('#walerts-anchor') && window.WAlerts){ if(WAlerts.mountInline('#walerts-anchor')) markMounted('#walerts-anchor'); } }catch(e){}\n"
				."    try{ if(!mounted('#wscanner-anchor') && window.WScanner){ if(WScanner.mountInline('#wscanner-anchor')) markMounted('#wscanner-anchor'); } }catch(e){}\n"
				."    try{ if(!mounted('#wblocklist-anchor') && window.WBlocklist){ if(WBlocklist.mountInline('#wblocklist-anchor')) markMounted('#wblocklist-anchor'); } }catch(e){}\n"
				."    try{ if(!mounted('#wusers-anchor') && window.WUsers){ if(WUsers.mountInline('#wusers-anchor')) markMounted('#wusers-anchor'); } }catch(e){}\n"
				."    if (attempts>=maxAttempts || (mounted('#wstatus-anchor')&&mounted('#wignore-anchor')&&mounted('#wdirwatch-anchor')&&mounted('#wddns-anchor')&&mounted('#walerts-anchor')&&mounted('#wscanner-anchor')&&mounted('#wblocklist-anchor')&&mounted('#wusers-anchor'))) { clearInterval(iv); }\n"
				."  }\n"
				."  // Start shortly after parse, and also run once immediately if DOM is already ready\n"
				."  var iv=setInterval(tryMount,250); if (document.readyState!=='loading') tryMount(); else document.addEventListener('DOMContentLoaded', tryMount);\n"
				."  // Do not auto-remove fallback; leave it as a persistent control if WStatus fails\n"
				."})();</script>\n";
		# Inline content area for widget actions (load results below bubbles)
	print "<tr style='background:transparent!important'><td style='background:transparent!important'><div id='qhtl-inline-area' style='padding-top:10px;min-height:180px;background:transparent'></div></td></tr>\n";
	print "<script>\n";
	print "(function(){\n";
	print "  function makeAutoClear(id){ var el=document.getElementById(id); if(!el) return; el.style.transition = el.style.transition || 'opacity 5s ease'; var t=null, fading=false, fadeTimer=null;\n";
	print "    function clearNow(){ try{ el.innerHTML=''; el.style.opacity=''; el.style.pointerEvents=''; fading=false; if(fadeTimer){ clearTimeout(fadeTimer); fadeTimer=null; } showFallback(true); }catch(_){ } }\n";
	print "    function beginFade(){ if(fading) return; try{ var onlyFallback = (el.children && el.children.length===1 && el.querySelector('.qhtl-fallback-holder')); if(onlyFallback){ return; } }catch(__){} fading=true; el.style.opacity='0'; el.style.pointerEvents='none'; fadeTimer=setTimeout(clearNow, 5000); }\n";
	print "    function cancelFade(){ if(!fading) return; try{ el.style.opacity=''; el.style.pointerEvents=''; }catch(_){ } fading=false; if(fadeTimer){ clearTimeout(fadeTimer); fadeTimer=null; } }\n";
	print "    function showFallback(force){ try{ if(!el) return; if (!force && el.children.length>0) return; var url=(window.QHTL_SCRIPT||'$script')+'?action=fallback_asset&name=idle_fallback.gif&v=$myv'; el.innerHTML = \"<div class=\\\"qhtl-fallback-holder\\\" style=\\\"min-height:160px;display:flex;align-items:center;justify-content:center;\\\"><img alt=\\\"\\\" src=\\\"\"+url+\"\\\" style=\\\"max-width:100%;height:auto;opacity:0.9\\\"></div>\"; el.style.opacity=''; el.style.pointerEvents=''; }catch(_){ } }\n";
	print "    function arm(){ if(t){ clearTimeout(t); } cancelFade(); t=setTimeout(beginFade, 10000); }\n";
	print "    // Arm on interactions and when content changes; also cancel any active dimming to keep content visible\n";
	print "    ['click','input','mousemove','wheel','keydown','touchstart','pointermove','pointerdown'].forEach(function(evt){ el.addEventListener(evt, arm, {passive:true}); });\n";
	print "    // Also listen globally so activity outside the area cancels dimming and resets the timer\n";
	print "    try { if (!el.qhtlDocArmBound) { el.qhtlDocArmBound = true; ['click','input','mousemove','wheel','keydown','touchstart','pointermove','pointerdown','scroll'].forEach(function(evt){ document.addEventListener(evt, arm, {passive:true, capture:true}); }); } } catch(_) { }\n";
	print "    var mo = new MutationObserver(function(){ arm(); try{ var fh=el.querySelector('.qhtl-fallback-holder'); if (el.children.length===0){ showFallback(); } else if (fh && el.children.length>1){ if(fh.parentNode) fh.parentNode.removeChild(fh); } }catch(_){ } }); mo.observe(el, { childList:true, subtree:true }); arm(); if (el.children.length===0) showFallback();\n";
	print "    // Expose small helpers for external use (e.g., tab re-click toggles)\n";
	print "    el.qhtlClearNow = clearNow; el.qhtlCancelFade = cancelFade; el.qhtlArmAuto = arm; el.qhtlShowFallback = showFallback;\n";
	print "  }\n";
	print "  makeAutoClear('qhtl-inline-area');\n";
	print "  makeAutoClear('qhtl-upgrade-inline-area');\n";
	print "  makeAutoClear('qhtl-options-inline-area');\n";
	print "  makeAutoClear('qhtl-quick-inline-area');\n";
	print "  makeAutoClear('qhtl-advanced-inline');\n";
	print "  try{ var adv=document.getElementById('qhtl-advanced-inline'); if(adv && (!adv.children || adv.children.length===0) && adv.qhtlShowFallback){ adv.qhtlShowFallback(true); } }catch(e){}\n";
	print "})();\n";
	print "</script>\n";
	# Re-click active tab name to clear its own inline area and cancel dimming
	print <<'QHTL_ADV_RESET_JS';
<script>
(function(){
	try{
		var tabs = document.getElementById('myTabs'); if(!tabs) return; var lastClick = 0;
		tabs.addEventListener('click', function(ev){
			var a = ev.target && ev.target.closest ? ev.target.closest('a[data-toggle="tab"]') : null; if(!a) return;
			var href = a.getAttribute('href')||''; if(!href) return;
			var li = a.parentNode; var isActive = li && li.classList && li.classList.contains('active');
			if (isActive) {
				ev.preventDefault();
				var now = Date.now(); if (now - lastClick < 350) { return; } lastClick = now;
				var isAdv = (href === '#moreplus');
				var areaId = (href === '#upgrade') ? 'qhtl-upgrade-inline-area' : (href === '#waterfall' ? 'qhtl-inline-area' : (isAdv ? 'qhtl-advanced-inline' : null));
				if (!areaId) return; var area = document.getElementById(areaId); if (!area) return;
				try {
					if (area.qhtlCancelFade) area.qhtlCancelFade();
					area.innerHTML = '';
					if (area.qhtlShowFallback) area.qhtlShowFallback(true); // force re-show fallback GIF after manual clear
					// Safety: if still empty shortly after, re-attempt fallback
					setTimeout(function(){ try{ if(area && area.children.length===0 && area.qhtlShowFallback){ area.qhtlShowFallback(true); } }catch(_){ } },250);
					if (area.qhtlArmAuto) area.qhtlArmAuto();
				} catch(_){ }
			}
		}, true);
	} catch(e){}
})();
</script>
QHTL_ADV_RESET_JS
		# Delegate clicks and form submits inside the Waterfall tab to load into inline area
		print "<script>(function(){\n";
	print "  if (window.__QHTL_INLINE_LOADER_ACTIVE) { return; } window.__QHTL_INLINE_LOADER_ACTIVE = true;\n";
	print "  var areaId = 'qhtl-inline-area';\n";
		print "  function sameOrigin(u){ try{ var a=document.createElement('a'); a.href=u; return (!a.host || a.host===location.host); }catch(e){ return false; } }\n";
		print "  function isQhtlAction(u, form){ try{ if (String(u).indexOf('?action=')!==-1) return true; if (form && form.querySelector && form.querySelector('[name=\\x61ction]')) return true; return false; }catch(e){ return false; } }\n";
	print "  function loadInto(url, method, data){ try{ var area=document.getElementById(areaId); if(!area){ location.href=url; return; } if (window.jQuery){ if(method==='POST'){ jQuery(area).html('<div class=\"text-muted\">Loading...</div>').load(url, data); } else { jQuery(area).html('<div class=\"text-muted\">Loading...</div>').load(url); } } else { var x=new XMLHttpRequest(); x.open(method||'GET', url, true); x.setRequestHeader('X-Requested-With','XMLHttpRequest'); if(method==='POST'){ x.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=UTF-8'); } x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ area.innerHTML = x.responseText; } else { location.href=url; } } }; x.send(data||null); } } catch(e){ try{ location.href=url; }catch(_){} } }\n";
		print "  var __qhtl_lastSubmitter=null;\n";
		print "  function serialize(form, submitter){ try{ var p=[]; for(var i=0;i<form.elements.length;i++){ var el=form.elements[i]; if(!el || !el.name || el.disabled) continue; var t=(el.type||'').toLowerCase(); if(t==='file') continue; if((t==='checkbox'||t==='radio')&&!el.checked) continue; if(t==='submit'||t==='button'){ if(submitter && el===submitter){ p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(el.value)); } continue; } if(t==='select-multiple'){ for(var j=0;j<el.options.length;j++){ var opt=el.options[j]; if(opt.selected){ p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(opt.value)); } } continue; } p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(el.value)); } if(submitter && submitter.name){ /* ensure submitter included even if not part of elements */ var found=false; for(var k=0;k<form.elements.length;k++){ if(form.elements[k]===submitter){ found=true; break; } } if(!found){ p.push(encodeURIComponent(submitter.name)+'='+encodeURIComponent(submitter.value||'')); } } return p.join('&'); }catch(e){ return ''; } }\n";
	print "  var root = document.getElementById('waterfall'); if(!root){ return; }\n";
	print "  root.addEventListener('click', function(ev){ var tgt=ev.target; var btn=tgt && tgt.closest ? tgt.closest('button, input[type=submit]') : null; if(btn && (String(btn.type||'').toLowerCase()==='submit')){ __qhtl_lastSubmitter=btn; } var a=tgt && tgt.closest ? tgt.closest('a') : null; if(!a) return; var href=a.getAttribute('href')||''; if(!href || href==='javascript:void(0)') return; if(!sameOrigin(href) || !isQhtlAction(href, null)) return; ev.preventDefault(); var u = href + (href.indexOf('?')>-1?'&':'?') + 'ajax=1'; loadInto(u, 'GET'); }, true);\n";
		print "  root.addEventListener('submit', function(ev){ var f=ev.target; if(!f || f.tagName!=='FORM') return; var action=f.getAttribute('action')||location.pathname; if(!sameOrigin(action) || !isQhtlAction(action, f)) return; var enc=(f.enctype||''); if (enc && String(enc).toLowerCase().indexOf('multipart/form-data')!==-1) return; ev.preventDefault(); var submitter = (ev.submitter ? ev.submitter : __qhtl_lastSubmitter); var data=serialize(f, submitter); loadInto(action + (action.indexOf('?')>-1?'&':'?') + 'ajax=1', (f.method||'GET').toUpperCase(), data); }, true);\n";
		print "})();</script>\n";
		print "</table>\n";
		print "</div>\n";

		# New More... tab (duplicate of 'More' content) placed between Waterfall and QhtLink Firewall
		print "<div id='moreplus' class='tab-pane'>\n";
		my $moreplus_has_content = 0;
		if ($config{CF_ENABLE}) {
			$moreplus_has_content = 1;
			print "<table class='table table-bordered table-striped'>\n";
			print "<thead><tr><th colspan='2'>CloudFlare Firewall</th></tr></thead>";
			print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='cloudflare' type='submit' class='btn btn-default'>CloudFlare</button></form><div class='text-muted small' style='margin-top:6px'>Access CloudFlare firewall functionality</div></td></tr>\n";
			print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='cloudflareedit' type='submit' class='btn btn-default'>CloudFlare Config</button></form><div class='text-muted small' style='margin-top:6px'>Edit the CloudFlare Configuration file (qhtlfirewall.cloudflare)</div></td></tr>\n";
			print "</table>\n";
		}
		if ($config{SMTPAUTH_RESTRICT}) {
			$moreplus_has_content = 1;
			print "<table class='table table-bordered table-striped'>\n";
			print "<thead><tr><th colspan='2'>cPanel SMTP AUTH Restrictions</th></tr></thead>";
			print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='smtpauth' type='submit' class='btn btn-default'>Edit SMTP AUTH</button></form><div class='text-muted small' style='margin-top:6px'>Edit the file that allows SMTP AUTH to be advertised to listed IP addresses (qhtlfirewall.smtpauth)</div></td></tr>\n";
			print "</table>\n";
		}

		# Resellers section removed (handled by Advanced hex buttons)

		# True move: include the former 'Extra' tab content inside 'More...'
		$moreplus_has_content = 1;
		print "<table class='table table-bordered table-striped'>\n";
		# Removed heading row label 'Extra' (no longer needed now that hex buttons replace that section)
		# (Previously: <thead><tr><th colspan='2'>Extra</th></tr></thead>)
		# Hex button grid (Advanced): 8 golden hex buttons with 10px silver glitter halo, above 'Test iptables'
		print "<tr><td colspan='2' class='qhtl-advanced-hex-cell'>\n";
		print "<style>\n";
		print "  /* Scoped to Advanced tab only */\n";
		print "  #moreplus .qhtl-advanced-hex-cell{background:transparent !important; border:0 !important;}\n";
	print "  #moreplus .qhtl-advanced-hexes{display:flex;flex-wrap:wrap;justify-content:center;gap:30px;align-items:flex-start;margin:8px 0 14px 0}\n";
	print "  #moreplus .qhtl-hex-wrap{padding:0;display:flex;align-items:center;justify-content:center;text-align:center}\n";
	print "  #moreplus .qhtl-hex-btn{position:relative;width:70px;height:70px;cursor:pointer;border:none;padding:4px 4px;background:linear-gradient(135deg,#b8860b,#ffd700,#d4af37);\n";
		print "    display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center; font-size:11px; font-weight:700; line-height:1.05; color:#ffffff; text-shadow:0 1px 2px rgba(0,0,0,0.65); outline:none; clip-path:polygon(25% 6.7%,75% 6.7%,100% 50%,75% 93.3%,25% 93.3%,0% 50%);\n";
		print "    box-shadow:0 0 4px 2px rgba(255,215,0,0.9),0 0 10px 4px rgba(255,215,0,0.75),0 0 18px 8px rgba(255,215,0,0.55),0 0 34px 14px rgba(255,223,100,0.45),0 0 48px 22px rgba(255,240,160,0.35);\n";
		print "    border:1px solid rgba(255,255,255,0.5);\n";
		print "    transition:transform .15s ease, box-shadow .25s ease;\n";
	print "  }\n";
	print "  #moreplus .qhtl-hex-btn:after{content:'';position:absolute;inset:-6px;pointer-events:none;clip-path:inherit;border-radius:12px;\n";
	print "    background:radial-gradient(circle at 50% 50%, rgba(255,255,255,0.55) 0%, rgba(255,215,0,0.25) 55%, rgba(255,215,0,0) 70%); mix-blend-mode:screen; opacity:0.9; filter:blur(2px);\n";
	print "  }\n";
	print "  #moreplus .qhtl-hex-btn:hover{transform:translateY(-3px) scale(1.04); box-shadow:0 0 6px 3px rgba(255,230,120,0.95),0 0 14px 6px rgba(255,230,120,0.85),0 0 26px 12px rgba(255,220,90,0.75),0 0 50px 22px rgba(255,235,140,0.6);}\n";
	print "  #moreplus .qhtl-hex-btn:active{transform:translateY(0) scale(.97); box-shadow:0 0 3px 1px rgba(255,215,0,0.9),0 0 10px 4px rgba(255,200,0,0.65),0 0 18px 10px rgba(255,200,0,0.5);}\n";
		print "    transition:transform .12s ease, box-shadow .12s ease;\n";
		print "  }\n";
	print "  /* Restored luminous halo via :before pseudo-element */\n";
	print "  #moreplus .qhtl-hex-btn:before{content:'';position:absolute;inset:-10px;clip-path:inherit;border-radius:18px;pointer-events:none;\n";
	print "    background:radial-gradient(circle at 50% 50%, rgba(255,255,255,0.95) 0%, rgba(255,235,120,0.65) 40%, rgba(255,200,0,0.25) 68%, rgba(255,200,0,0) 78%);\n";
	print "    box-shadow:0 0 6px 3px rgba(255,255,200,0.95),0 0 14px 8px rgba(255,235,140,0.75),0 0 30px 18px rgba(255,215,60,0.55),0 0 60px 32px rgba(255,210,40,0.35);\n";
	print "    animation:qhtlHexPulse 3.6s ease-in-out infinite; transform-origin:center center;\n";
	print "  }\n";
	print "  @keyframes qhtlHexPulse { 0%,100%{opacity:1; filter:brightness(1);} 50%{opacity:.86; filter:brightness(1.08);} }\n";
	print "  #moreplus a.qhtl-hex-btn{color:#ffffff !important; text-shadow:0 1px 2px rgba(0,0,0,0.65);}\n";
	print "  #moreplus a.qhtl-hex-btn:visited{color:#ffffff !important;}\n";
	print "  #moreplus a.qhtl-hex-btn:hover{color:#ffffff !important;}\n";
	print "  #moreplus .qhtl-hex-btn:hover{transform:translateY(-2px);}\n";
	print "  #moreplus .qhtl-hex-btn:active{transform:translateY(0);}\n";
	print "  /* halo: plain ring; spacing via container gap only */\n";
		print "  /* Provide minimal fallback if clip-path unsupported */\n";
		print "  @supports not (clip-path: polygon(0 0)){ #moreplus .qhtl-hex-btn{border-radius:10px;} #moreplus .qhtl-hex-btn:before{clip-path:none;} }\n";
		print "</style>\n";
		print "<div class='qhtl-advanced-hexes' aria-label='Advanced actions'>\n";
		for my $i (1..8) {
			if ($i == 1) {
				my $lbl = "Test iptables";
				print "  <div class='qhtl-hex-wrap'>\n";
				print "    <form action='$script' method='post' style='margin:0'>\n";
				print "      <button name='action' value='qhtlfirewalltest' type='submit' class='qhtl-hex-btn' aria-label='$lbl' title='$lbl'>$lbl</button>\n";
				print "    </form>\n";
				print "  </div>\n";
			} elsif ($i == 2) {
				my $lbl = "Edit Reseller Privs";
				print "  <div class='qhtl-hex-wrap'>\n";
				print "    <form action='$script' method='post' style='margin:0'>\n";
				print "      <button name='action' value='reseller' type='submit' class='qhtl-hex-btn' aria-label='$lbl' title='$lbl'>$lbl</button>\n";
				print "    </form>\n";
				print "  </div>\n";
			} elsif ($i == 3) {
				# Third hex now hosts the Fix Tool action (migrated from Firewall tab)
				my $lbl = "Fix Tool";
				print "  <div class='qhtl-hex-wrap'>\n";
				print "    <form action='$script' method='post' style='margin:0'>\n";
				print "      <button name='action' value='fix' type='submit' class='qhtl-hex-btn' aria-label='$lbl' title='$lbl'>$lbl</button>\n";
				print "    </form>\n";
				print "  </div>\n";
			} elsif ($i == 8) {
				my $lbl = "About";
				print "  <div class='qhtl-hex-wrap'>\n";
				print "    <a href='https://forum.danpol.co.uk/' target='_blank' rel='noopener' class='qhtl-hex-btn' aria-label='$lbl' title='$lbl' style='text-decoration:none;display:flex;align-items:center;justify-content:center'>$lbl</a>\n";
				print "  </div>\n";
			} else {
				# All remaining (non-special) hex buttons are promotion triggers
				my $aria = 'Buy Promotions Now!';
				my $lbl_html = "Buy<br>Promotions<br>Now!";
				print "  <div class='qhtl-hex-wrap'>\n";
				print "    <button type='button' class='qhtl-hex-btn' aria-label='$aria' title='$aria' onclick=\"try{ if(window.openPromoModal){ openPromoModal(); } }catch(e){}\">$lbl_html</button>\n";
				print "  </div>\n";
			}
		}
		print "</div>\n";
	print "</td></tr>\n";
	# Inline results area for Advanced actions (clean area; fallback animation will show when empty)
	print "<tr style='background:transparent!important'><td style='background:transparent!important'>".
	      "<div id='qhtl-advanced-inline' style='padding-top:10px;min-height:180px;background:transparent'></div>".
	      "</td></tr>\n";
	print "  <script>(function(){\n";
	print "    if(window.__QHTL_ADV_INLINE_LOADER_ACTIVE){return;} window.__QHTL_ADV_INLINE_LOADER_ACTIVE=true;\n";
	print "    var areaId='qhtl-advanced-inline';\n";
	print "    function sameOrigin(u){ try{ var a=document.createElement('a'); a.href=u; return (!a.host || a.host===location.host); }catch(e){ return false; } }\n";
	print "    function isQhtlAction(u, form){ try{ if(String(u).indexOf('?action=')!==-1) return true; if(form && form.querySelector && form.querySelector('[name=\\x61ction]')) return true; return false; }catch(e){ return false; } }\n";
	print "    function loadInto(url, method, data){ try{ var area=document.getElementById(areaId); if(!area){ location.href=url; return; } if(window.jQuery){ if(method==='POST'){ jQuery(area).html(\"<div class='text-muted'>Loading...</div>\").load(url, data); } else { jQuery(area).html(\"<div class='text-muted'>Loading...</div>\").load(url); } } else { var x=new XMLHttpRequest(); x.open(method||'GET', url, true); try{x.setRequestHeader('X-Requested-With','XMLHttpRequest');}catch(__){} if(method==='POST'){ try{x.setRequestHeader('Content-Type','application/x-www-form-urlencoded; charset=UTF-8');}catch(__){} } x.onreadystatechange=function(){ if(x.readyState===4){ if(x.status>=200 && x.status<300){ area.innerHTML=x.responseText; } else { location.href=url; } } }; x.send(data||null); } } catch(e){ try{ location.href=url; }catch(_){} } }\n";
	print "    var __qhtl_adv_lastSubmitter=null;\n";
	print "    function serialize(form, submitter){ try{ var p=[]; for(var i=0;i<form.elements.length;i++){ var el=form.elements[i]; if(!el||!el.name||el.disabled) continue; var t=(el.type||'').toLowerCase(); if(t==='file') continue; if((t==='checkbox'||t==='radio')&&!el.checked) continue; if(t==='submit'||t==='button'){ if(submitter && el===submitter){ p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(el.value)); } continue; } if(t==='select-multiple'){ for(var j=0;j<el.options.length;j++){ var opt=form.elements[i].options[j]; if(opt.selected){ p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(opt.value)); } } continue; } p.push(encodeURIComponent(el.name)+'='+encodeURIComponent(el.value)); } if(submitter && submitter.name){ var found=false; for(var k=0;k<form.elements.length;k++){ if(form.elements[k]===submitter){ found=true; break; } } if(!found){ p.push(encodeURIComponent(submitter.name)+'='+encodeURIComponent(submitter.value||'')); } } return p.join('&'); }catch(e){ return ''; } }\n";
	print "    var root=document.getElementById('moreplus'); if(!root) return;\n";
	print "    root.addEventListener('click', function(ev){ var t=ev.target; if(!t) return; var btn=t.closest?t.closest('button, input[type=submit]'):null; if(btn && (String(btn.type||'').toLowerCase()==='submit')){ __qhtl_adv_lastSubmitter=btn; } var a=t.closest?t.closest('a'):null; if(!a) return; var href=a.getAttribute('href')||''; if(!href || href==='javascript:void(0)') return; if(!sameOrigin(href) || !isQhtlAction(href,null)) return; ev.preventDefault(); var u=href+(href.indexOf('?')>-1?'&':'?')+'ajax=1'; loadInto(u,'GET'); }, true);\n";
	print "    root.addEventListener('submit', function(ev){ var f=ev.target; if(!f||f.tagName!=='FORM') return; var action=f.getAttribute('action')||location.pathname; if(!sameOrigin(action) || !isQhtlAction(action,f)) return; var enc=(f.enctype||''); if(enc && String(enc).toLowerCase().indexOf('multipart/form-data')!==-1) return; ev.preventDefault(); var submitter=(ev.submitter?ev.submitter:__qhtl_adv_lastSubmitter); var data=serialize(f, submitter); loadInto(action+(action.indexOf('?')>-1?'&':'?')+'ajax=1', (f.method||'GET').toUpperCase(), data); }, true);\n";
	print "  })();</script>\n";
	# Extra explicit fallback injection immediately after advanced area markup
print <<'QHTL_ADV_FALLBACK_INJECT';
	<script>(function(){
		try {
			var adv=document.getElementById('qhtl-advanced-inline');
			if(adv && adv.children.length===0){
				var u=(window.QHTL_SCRIPT||'$script')+'?action=fallback_asset&name=idle_fallback.gif&v=$myv';
				adv.innerHTML="<div class=\"qhtl-fallback-holder\" style=\"min-height:160px;display:flex;align-items:center;justify-content:center;\"><img alt=\"\" src=\""+u+"\" style=\"max-width:100%;height:auto;opacity:.9\"></div>";
			}
		} catch(e){}
	})();</script>
QHTL_ADV_FALLBACK_INJECT
print <<'QHTL_ADV_FALLBACK_DOMREADY';
<script>(function(){
	function ensureBlade(){
		try{
			var adv=document.getElementById('qhtl-advanced-inline');
			if(!adv) return; if(adv.children && adv.children.length>0) return;
			var url=(window.QHTL_SCRIPT||'$script')+'?action=fallback_asset&name=idle_fallback.gif&v=$myv';
			adv.innerHTML="<div class=\"qhtl-fallback-holder\" style=\"min-height:160px;display:flex;align-items:center;justify-content:center;\"><img alt=\"\" src=\""+url+"\" style=\"max-width:100%;height:auto;opacity:.9\"></div>";
		}catch(e){}
	}
	if(document.readyState==='loading'){ document.addEventListener('DOMContentLoaded', ensureBlade); }
	else { ensureBlade(); }
})();</script>
QHTL_ADV_FALLBACK_DOMREADY
	print "</td></tr>\n";
	print "</table>\n";

	# About section replaced by hex button; no fallback table

		print "</div>\n";

		# (Removed unused legacy #firewall tab; navigation points to #firewall1)
	# Enforce Quick View modal sizing (500x400) with scrollable body
	print "<style>\n";
	print "#quickViewModal { position: absolute !important; inset: 0 !important; z-index: 1000 !important; touch-action: auto !important; }\n";
	# Quick View modal dialog spans nearly full width with 20px gutters; no max-width cap
	print "#quickViewModal .modal-dialog { width: calc(100% - 40px) !important; max-width: none !important; position: absolute !important; top: 20px !important; left: 20px !important; right: 20px !important; transform: none !important; margin: 0 !important; }\n";
	print "#quickViewModal .modal-content { height: 400px !important; display: flex !important; flex-direction: column !important; overflow: hidden !important; box-sizing: border-box !important; }\n";
	print "#quickViewModal .modal-body { flex: 1 1 auto !important; display:flex !important; flex-direction:column !important; overflow:auto !important; min-height:0 !important; padding:10px !important; }\n";
		print "#quickViewModal .modal-footer { flex: 0 0 auto !important; margin-top: auto !important; padding:10px !important; display:flex !important; justify-content: space-between !important; align-items: center !important; gap:8px !important; }\n";
	print "#quickViewModal #quickViewTitle { margin:0 0 8px 0 !important; }\n";
	# Make Quick View body a flex column that can grow and scroll, without forcing 100% height
	print "#quickViewBody { flex:1 1 auto !important; min-height:0 !important; display:flex !important; flex-direction:column !important; overflow:auto !important; }\n";
	print "#quickViewModal #quickViewBody { display:flex !important; flex-direction:column !important; width:100% !important; height:auto !important; max-height:none !important; overflow:auto !important; }\n";
	# Ensure <pre> in view mode expands within the modal and scrolls if needed
	print "#quickViewModal #quickViewBody pre { flex:1 1 auto !important; min-height:0 !important; height:auto !important; max-height:none !important; white-space: pre; overflow: auto; overflow-wrap: normal; word-break: normal; }\n";
	# Textarea in edit mode should fill available space via flex, not absolute 100% height
	print "#quickEditArea { flex: 1 1 auto !important; min-height: 220px !important; height: auto !important; max-height: none !important; }\n";
	print "#quickViewModal #quickEditArea { resize: none !important; }\n";
	print ".btn-close-red { background: linear-gradient(180deg, #f8d7da 0%, #f5c6cb 100%); color: #721c24 !important; border-color: #f1b0b7 !important; }\n";
	print ".btn-close-red:hover { background: #dc3545 !important; color: #fff !important; border-color: #dc3545 !important; }\n";
	# Ensure confirm modal is anchored within the UI container and not the whole window
	print "#confirmmodal { position: absolute !important; inset: 0 !important; z-index: 1000 !important; }\n";
	print "#confirmmodal .modal-dialog { width: 320px !important; max-width: 95% !important; position: absolute !important; top: 12px !important; left: 50% !important; transform: translateX(-50%) !important; margin: 0 !important; }\n";
	print "#confirmmodal .modal-content { display: flex !important; flex-direction: column !important; overflow: hidden !important; max-height:480px !important; }\n";
	print "#confirmmodal .modal-body { flex: 1 1 auto !important; min-height: 0 !important; overflow:auto !important; }\n";
	print "#confirmmodal .modal-footer { flex: 0 0 auto !important; display:flex !important; justify-content: space-between !important; align-items: center !important; gap:8px !important; }\n";
		# Tabs wrap improvements: ensure full-width usage on wrap with even spacing
		print "#myTabs { display:flex; flex-wrap: wrap; gap: 6px; }\n";
		print "#myTabs > li { float:none !important; }\n";
		print "#myTabs > li > a { display:block; }\n";
		print "#myTabs > li { flex: 1 1 auto; }\n";
		print "#myTabs > li > a { width: 100%; text-align: center; }\n";
	# Fire border effect radiating OUTSIDE the edges for Edit mode
	print ".fire-border { position: relative; }\n";
	print ".fire-allow { box-shadow: 0 0 20px 10px rgba(40,167,69,0.75), 0 0 40px 18px rgba(40,167,69,0.45); animation: flicker-allow 1.4s infinite ease-in-out; }\n";
	print ".fire-ignore { box-shadow: 0 0 20px 10px rgba(255,152,0,0.78), 0 0 40px 18px rgba(255,152,0,0.48); animation: flicker-ignore 1.4s infinite ease-in-out; }\n";
	print ".fire-deny { box-shadow: 0 0 20px 10px rgba(220,53,69,0.78), 0 0 40px 18px rgba(220,53,69,0.5); animation: flicker-deny 1.4s infinite ease-in-out; }\n";
	# View-mode: half intensity, 50% slower animation
	print ".fire-allow-view { box-shadow: 0 0 20px 10px rgba(40,167,69,0.38), 0 0 40px 18px rgba(40,167,69,0.225); animation: flicker-allow 2.8s infinite ease-in-out; }\n";
	print ".fire-ignore-view { box-shadow: 0 0 20px 10px rgba(255,152,0,0.39), 0 0 40px 18px rgba(255,152,0,0.24); animation: flicker-ignore 2.8s infinite ease-in-out; }\n";
	print ".fire-deny-view { box-shadow: 0 0 20px 10px rgba(220,53,69,0.39), 0 0 40px 18px rgba(220,53,69,0.25); animation: flicker-deny 2.8s infinite ease-in-out; }\n";
	print "\@keyframes flicker-allow { 0%,100% { box-shadow: 0 0 14px 6px rgba(40,167,69,0.6), 0 0 24px 10px rgba(40,167,69,0.35); } 50% { box-shadow: 0 0 28px 14px rgba(40,167,69,0.9), 0 0 46px 20px rgba(40,167,69,0.65); } }\n";
	print "\@keyframes flicker-ignore { 0%,100% { box-shadow: 0 0 14px 6px rgba(255,152,0,0.62), 0 0 24px 10px rgba(255,152,0,0.35); } 50% { box-shadow: 0 0 28px 14px rgba(255,152,0,0.98), 0 0 46px 20px rgba(255,152,0,0.6); } }\n";
	print "\@keyframes flicker-deny { 0%,100% { box-shadow: 0 0 14px 6px rgba(220,53,69,0.62), 0 0 24px 10px rgba(220,53,69,0.35); } 50% { box-shadow: 0 0 28px 14px rgba(220,53,69,0.98), 0 0 46px 20px rgba(220,53,69,0.62); } }\n";
	print "</style>\n";
	# Add a Bootstrap modal for inline quick-view (no address bar)
	print "<div class='modal fade' id='quickViewModal' tabindex='-1' role='dialog' aria-labelledby='myModalLabel' aria-hidden='true' data-backdrop='false' style='background-color: rgba(0, 0, 0, 0.5)'>\n";
	print "<div class='modal-dialog'>\n";
	print "<div class='modal-content'>\n";
	print "<div class='modal-body'>\n";
	print "<h4 id='quickViewTitle'>Quick View</h4>\n";
	print "<div id='quickViewBody'>Loading...</div>\n";
	print "</div>\n";

	print "<div class='modal-footer' style='display:flex; justify-content:space-between; align-items:center;'>\n";
	print "  <div>\n";
	print "    <button type='button' class='btn btn-primary' id='quickViewEditBtn'>Edit</button>\n";
	print "    <button type='button' class='btn btn-success' id='quickViewSaveBtn' style='display:none; margin-left: 4px;'>Save</button>\n";
	print "  </div>\n";
	print "  <div>\n";
	print "    <button type='button' class='btn btn-warning' id='quickViewCancelBtn' style='display:none;'>Cancel</button>\n";
	print "  </div>\n";
	print "  <div>\n";
	print "    <button type='button' class='btn btn-default btn-close-red' data-dismiss='modal'>Close</button>\n";
	print "  </div>\n";
	print "</div>\n";

	# Promo modal opener as a standalone compact Bootstrap modal (no Quick View reuse)
	print "<script>\n";
	print <<'QHTL_PROMO_JS';
(function(){
  function ensureOrangeCSS(){
    if (document.getElementById('qhtl-orange-style')) return;
    var s=document.createElement('style'); s.id='qhtl-orange-style';
	s.textContent = String.fromCharCode(64)+"keyframes qhtl-orange {0%,100%{box-shadow: 0 0 12px 5px rgba(255,140,0,0.55), 0 0 20px 9px rgba(255,140,0,0.28);}50%{box-shadow: 0 0 22px 12px rgba(255,140,0,0.95), 0 0 36px 16px rgba(255,140,0,0.5);}}\n"+
                   ".fire-orange{ animation: qhtl-orange 2s infinite ease-in-out; }\n"+
                   ".btn-golden{ background: linear-gradient(180deg, #ffd766 0%, #ffbf00 100%); color: #c0c0c0 !important; font-weight: 800; border: 1px solid #e6c200; }\n"+
                   ".btn-golden:hover{ background: linear-gradient(180deg, #ffe387 0%, #ffc41a 100%); color: #f0f0f0 !important; }\n"+
                   ".btn-bright-red{ background: #ff2d2d !important; color:#fff !important; border:1px solid #d61e1e; }\n"+
                   ".btn-bright-red:hover{ background:#e61e1e !important; color:#fff !important; }\n"+
			   ".qhtl-promo-modal{ position:absolute !important; inset:0 !important; background: rgba(0,0,0,0.5); z-index:1000; }\n"+
			   ".qhtl-promo-modal .modal-dialog{ width:320px; max-width:95vw; margin:0 !important; position:absolute; top:12px; left:50%; transform:translateX(-50%);}\n"+
				   ".qhtl-promo-modal .modal-content{ display:flex; flex-direction:column; overflow:hidden; max-height:480px;}\n"+
				   ".qhtl-promo-modal .modal-body{ padding:6px !important; overflow:auto !important;}\n"+
                   "#qhtlPromoTitle{ margin:0 0 4px 0; }\n";
    document.head.appendChild(s);
  }
  function buildPromoModal(){
    var modal = document.createElement('div');
    modal.id = 'qhtlPromoModal';
    modal.className = 'modal fade qhtl-promo-modal';
    modal.setAttribute('tabindex','-1');
    modal.setAttribute('role','dialog');
    modal.setAttribute('aria-hidden','true');
	modal.innerHTML = "\n<div class='modal-dialog'>\n  <div class='modal-content'>\n    <div class='modal-body'>\n      <h4 id='qhtlPromoTitle'>Information</h4>\n      <div id='qhtlPromoBody' style='display:flex;align-items:center;justify-content:center;text-align:center;font-size:13px;line-height:1.35;padding:4px;'>\n        <div style='padding:2px 4px;'>"+
					"<b>You need promotion active to access !</b><br>"+
					"Yeah, well i wish this is the case<br>"+
					"but not yet, for now you can donate ;)<br>"+
					"Coding soft and hardware cost a loot.<br>"+
					"If you want me keep going pls donate.<br>"+
					"Use button below or contact me via email<br>"+
					"You can change donated amount here:<br>"+
					"<input type='text' id='qhtlPromoAmount' inputmode='numeric' pattern='[0-9]*' maxlength='10' style='width:140px;text-align:center;' placeholder='10'>"+
				"</div>\n"+
			"</div>\n"+
		"</div>\n"+
		"<div class='modal-footer' style='display:flex;justify-content:space-between;align-items:center;'>\n"+
			"<div><button type='button' class='btn btn-success' id='qhtlPromoBuyBtn' style='font-weight:800'>\n"+
			"<span class='glyphicon glyphicon-usd' aria-hidden='true'></span> "+
			"<span>Buy Promotions</span> "+
			"<span class='glyphicon glyphicon-usd' aria-hidden='true'></span>\n"+
			"</button></div>\n"+
			"<div><button type='button' class='btn btn-bright-red' id='qhtlPromoCloseBtn' data-dismiss='modal'>Close</button></div>\n"+
		"</div>\n"+
	"</div>\n"+
"</div>\n";
    return modal;
  }
	window.openPromoModal = function(){
		try {
			ensureOrangeCSS();
			var existing = document.getElementById('qhtlPromoModal');
			if (existing) {
				try { if (window.jQuery) jQuery(existing).modal('hide'); } catch(_h){}
				try { existing.remove(); } catch(_r){}
			}
			var modal = buildPromoModal();
			var parent = document.querySelector('.qhtl-bubble-bg') || document.body;
			parent.appendChild(modal);
			var hasJQ = !!window.jQuery;
			if (hasJQ) {
				var $modal = jQuery('#qhtlPromoModal');
				// wire inputs
				$modal.on('input', '#qhtlPromoAmount', function(){ try { this.value=(this.value||'').replace(/\D+/g,'').slice(0,10); }catch(e){} });
				$modal.on('click', '#qhtlPromoBuyBtn', function(){ try{ var amt=(document.getElementById('qhtlPromoAmount')||{}).value||''; amt=(amt+'').replace(/\D+/g,'').slice(0,10); if(!amt) amt='10'; window.open('https://www.paypal.com/paypalme/danpollimited/'+amt,'_blank'); }catch(e){} });
				$modal.on('click', '#qhtlPromoCloseBtn', function(){ try{ $modal.modal('hide'); }catch(e){} });
				$modal.on('hidden.bs.modal', function(){ try{ $modal.off(); }catch(_1){} try{ $modal.remove(); }catch(_2){} try{ jQuery('body').removeClass('modal-open').css({overflow:''}); }catch(_3){} });
				$modal.modal({ show:true, backdrop:false, keyboard:true });
			} else {
				// Vanilla fallback: basic close + handlers
				var buyBtn = modal.querySelector('#qhtlPromoBuyBtn');
				if (buyBtn) buyBtn.addEventListener('click', function(){ try{ var amt=(document.getElementById('qhtlPromoAmount')||{}).value||''; amt=(amt+'').replace(/\D+/g,'').slice(0,10); if(!amt) amt='10'; window.open('https://www.paypal.com/paypalme/danpollimited/'+amt,'_blank'); }catch(e){} });
				var closeBtn = modal.querySelector('#qhtlPromoCloseBtn');
				if (closeBtn) closeBtn.addEventListener('click', function(){ try{ modal.remove(); }catch(e){} });
				// Simple escape key handler
				document.addEventListener('keydown', function esc(e){ if(e.key==='Escape'){ try{ modal.remove(); }catch(_){} document.removeEventListener('keydown', esc, true);} }, true);
			}
		} catch(e){ try{ console.error('openPromoModal failed', e); }catch(_){} }
		return false;
	};
})();
QHTL_PROMO_JS
	print "</script>\n";

		# Inline script to wire up Quick View modal behavior
		print "<script>\n";
		print "var QHTL_SCRIPT = '$script';\n";
		print <<'JS';
var currentQuickWhich = null;
// Helpers to disable/enable tab links while Quick View is open
function qhtlLockTabs(){
	try {
		var links = document.querySelectorAll('#myTabs a');
		for (var i=0;i<links.length;i++){
			var a = links[i];
			if (!a.getAttribute('data-qhtl-disabled')){
				var href = a.getAttribute('href');
				if (href) a.setAttribute('data-qhtl-href', href);
				var dt = a.getAttribute('data-toggle');
				if (dt) a.setAttribute('data-qhtl-toggle', dt);
				a.setAttribute('data-qhtl-disabled', '1');
				try { a.setAttribute('aria-disabled','true'); } catch(_e){}
				try { a.removeAttribute('data-toggle'); } catch(_e){}
				try { a.setAttribute('href','javascript:void(0)'); } catch(_e){}
			}
		}
	} catch(e){}
}
function qhtlUnlockTabs(){
	try {
		var links = document.querySelectorAll('#myTabs a[data-qhtl-disabled="1"]');
		for (var i=0;i<links.length;i++){
			var a = links[i];
			try {
				var href = a.getAttribute('data-qhtl-href');
				if (href) a.setAttribute('href', href);
				else a.removeAttribute('href');
				a.removeAttribute('data-qhtl-href');
			} catch(_1){}
			try {
				var dt = a.getAttribute('data-qhtl-toggle');
				if (dt) a.setAttribute('data-toggle', dt);
				else a.removeAttribute('data-toggle');
				a.removeAttribute('data-qhtl-toggle');
			} catch(_2){}
			try { a.removeAttribute('aria-disabled'); } catch(_3){}
			try { a.removeAttribute('data-qhtl-disabled'); } catch(_4){}
		}
	} catch(e){}
}
function openQuickView(url, which) {
	try {
		// Increase lock and mark document BEFORE any DOM work so stray handlers can't flip tabs
		window.qhtlTabLock = (window.qhtlTabLock||0) + 1;
		try { document.documentElement.classList.add('qhtl-tabs-locked'); } catch(__){}
		// Snapshot current tab/hash as the canonical target while modal is open
		try {
			var actA0 = document.querySelector('#myTabs li.active > a[href^="#"]');
			window.qhtlSavedTabHash = actA0 ? actA0.getAttribute('href') : (window.qhtlSavedTabHash||'#home');
			if (!window.qhtlSavedTabHash) { window.qhtlSavedTabHash = '#home'; }
			try { window.qhtlSavedURLHash = window.location.hash; } catch(___){}
		} catch(__){}
		// Note: Removed MutationObserver-based tab reversion to avoid mutation feedback loops
		// that could cause heavy CPU usage and UI freezes. We still rely on:
		// - capture-phase click guard for tabs
		// - Bootstrap show.bs.tab suppression while locked
		// - hashchange guard + explicit re-activation timers
	} catch(_){ }
	var titleMap = {allow:'qhtlfirewall.allow', deny:'qhtlfirewall.deny', ignore:'qhtlfirewall.ignore'};
	$('#quickViewTitle').text('Quick View: ' + (titleMap[which]||which));
	$('#quickViewBody').html('Loading...');
	currentQuickWhich = which;
	var $modal = $('#quickViewModal');
	var $wrapper = $('.qhtl-bubble-bg').first();
	// Append into the wrapper if present so it scrolls with the page area; fallback to body
	if ($wrapper.length) { $modal.appendTo($wrapper); } else { $modal.appendTo('body'); }
	// Position overlay relative to the wrapper so it stays aligned and scrolls with content
	try {
		var scoped = $wrapper.length > 0;
	var w = scoped ? ($wrapper[0].clientWidth || window.innerWidth) : window.innerWidth;
	var h = scoped ? ($wrapper[0].clientHeight || window.innerHeight) : window.innerHeight;
		var $dlg = $modal.find('.modal-dialog');
		var $mc = $modal.find('.modal-content');
		if (scoped) {
			$modal.css({ position:'absolute', left: 0, top: 0, right: 0, bottom: 0, width:'auto', height:'auto', margin:0, background:'rgba(0,0,0,0.5)' });
		} else {
			$modal.css({ position:'fixed', left: 0, top: 0, right: 0, bottom: 0, width:'auto', height:'auto', margin:0, background:'rgba(0,0,0,0.5)' });
		}
	// Use 20px gutters and full available width; no max-width cap
	$dlg.css({ position:'absolute', left:'20px', right:'20px', top:'12px', transform:'none', margin:0, width:'auto', maxWidth:'none' });
	var maxH = 480; // enforce global cap
	$mc.css({ height:'auto', maxHeight: maxH+'px', display:'flex', flexDirection:'column', overflow:'hidden' });
		$modal.find('.modal-body').css({ flex:'1 1 auto', minHeight:0, overflow:'auto' });
	} catch(_) {}
	// Show without Bootstrap backdrop so it doesn't cover the full window
	$modal.modal({ show: true, backdrop: false, keyboard: true });
	// Keep page scroll enabled (defensive against Bootstrap's modal-open)
	try { $('body').removeClass('modal-open').css({ overflow: '' }); } catch(_ignore) {}
	// Close when clicking outside the dialog (overlay area)
	try {
		$modal.off('mousedown.qhtlOutside');
		$modal.on('mousedown.qhtlOutside', function(ev){
			try {
				var dlg = $(this).find('.modal-dialog')[0];
				if (!dlg) { return; }
				var t = ev.target;
				if (t === this || (dlg && !dlg.contains(t))) {
					$(this).modal('hide');
				}
			} catch(__){}
		});
	} catch(__){}
	$('#quickViewEditBtn').show();
	$('#quickViewSaveBtn').hide();
	$('#quickViewCancelBtn').hide();
	// Apply view-mode glow (half intensity, slower)
	var $mc = $('#quickViewModal .modal-content');
	$mc.removeClass('fire-border fire-allow fire-ignore fire-deny fire-allow-view fire-ignore-view fire-deny-view');
	$mc.addClass('fire-border');
	if (currentQuickWhich==='allow') { $mc.addClass('fire-allow-view'); } else if (currentQuickWhich==='ignore') { $mc.addClass('fire-ignore-view'); } else if (currentQuickWhich==='deny') { $mc.addClass('fire-deny-view'); }
	// Gentle hint if the load takes longer (large lists)
	try { window.clearTimeout(window.__qhtlLoadHintTimer); } catch(__h){}
	window.__qhtlLoadHintTimer = setTimeout(function(){
		try {
			var bodyEl = document.getElementById('quickViewBody');
			if (bodyEl && /Loading\.\.\./.test(bodyEl.textContent||'')) {
				bodyEl.innerHTML = "<div>Still loading… If the list is large, this can take a moment.</div>";
			}
		} catch(__){ }

		// Pre-lock on mousedown specifically for Quick View gear anchors to prevent any
		// background tab activation (e.g., Waterfall) before our click handler runs.
		// Includes a short safety auto-unlock if the modal doesn't open.
		try {
			document.addEventListener('mousedown', function(e){
				var t = e.target;
				var a = (t && t.closest) ? t.closest('a.quickview-link') : null;
				if (!a) return;
				if (e && typeof e.preventDefault === 'function') e.preventDefault();
				if (e && typeof e.stopPropagation === 'function') e.stopPropagation();
				if (e && typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
				try {
					var currentTab = (function(gear){
						try {
							if (gear && gear.closest) {
								var pane = gear.closest('.tab-pane');
								if (pane && pane.id) return '#'+pane.id;
							}
							var paneActive = document.querySelector('.tab-content .tab-pane.active');
							if (paneActive && paneActive.id) return '#'+paneActive.id;
							var actA = document.querySelector('#myTabs li.active > a[href^="#"]') ||
												 document.querySelector('#myTabs .active > a[href^="#"]') ||
												 document.querySelector('#myTabs a[aria-selected="true"][href^="#"]');
							if (actA) return actA.getAttribute('href');
						} catch(__){}
						return '#home';
					})(a);
					window.qhtlSavedTabHash = currentTab;
					try { window.qhtlSavedURLHash = window.location.hash; } catch(__){}
					window.qhtlTabLock = 1;
					document.documentElement.classList.add('qhtl-tabs-locked');
					try { qhtlLockTabs(); } catch(__){}
					if (typeof window.qhtlActivateTab === 'function' && currentTab) { window.qhtlActivateTab(currentTab); }
					try { window.clearTimeout(window.__qhtlGearPreLockTimer); } catch(__){}
					window.__qhtlGearPreLockTimer = setTimeout(function(){
						try {
							if (!$('#quickViewModal').is(':visible')) {
								window.qhtlTabLock = 0;
								document.documentElement.classList.remove('qhtl-tabs-locked');
								qhtlUnlockTabs();
							}
						} catch(__s){}
					}, 600);
				} catch(__e){}
			}, true);
		} catch(__){ }

	}, 1200);

    try { if (window.__qhtlCurrentXHR && window.__qhtlCurrentXHR.abort) { window.__qhtlCurrentXHR.abort(); } } catch(__ax){}
    if (window.console && console.info) { try { console.info('[QHTL] QuickView GET', url); } catch(__c){} }
	window.__qhtlCurrentXHR = jQuery.ajax({ url: url, method: 'GET', dataType: 'html', timeout: 15000, cache: false, headers: { 'X-Requested-With': 'XMLHttpRequest' } })
		.done(function(data){
			try { window.clearTimeout(window.__qhtlLoadHintTimer); } catch(__h){}
			var body = data;
			try { var m = data.match(/<pre[\s\S]*?<\/pre>/i); if (m) { body = m[0]; } } catch(e) {}
			$('#quickViewBody').html(body);
		})
		.fail(function(xhr, textStatus, errorThrown){
			if (window.console && console.warn) { try { console.warn('[QHTL] QuickView GET failed', url, textStatus, errorThrown, xhr && xhr.status); } catch(__c){} }
			try { window.clearTimeout(window.__qhtlLoadHintTimer); } catch(__h){}
			var code = (xhr && typeof xhr.status !== 'undefined') ? xhr.status : 'n/a';
			var msg = (textStatus || 'error') + (errorThrown ? (': '+errorThrown) : '');
			$('#quickViewBody').html('<div class=\'alert alert-danger\'>Failed to load content ('+code+'): '+msg+'<br><span class="small text-muted">Try again or use the full editor button if available.</span></div>');
		});
}
function showQuickView(which) {
	var url = QHTL_SCRIPT + '?action=viewlist&which=' + encodeURIComponent(which);
	openQuickView(url, which);
}
// Capture-phase guard to intercept Quick View gear clicks before any other handlers
try {
	// Determine the best current tab hash. Prefer the origin pane of the clicked gear.
	function __qhtlGetPreferredTabHash(gearAnchor){
		try {
			if (gearAnchor && gearAnchor.closest) {
				var pane = gearAnchor.closest('.tab-pane');
				if (pane && pane.id) { return '#'+pane.id; }
			}
			var paneActive = document.querySelector('.tab-content .tab-pane.active');
			if (paneActive && paneActive.id) { return '#'+paneActive.id; }
			var actA = document.querySelector('#myTabs li.active > a[href^="#"]') ||
					   document.querySelector('#myTabs .active > a[href^="#"]') ||
					   document.querySelector('#myTabs a[aria-selected="true"][href^="#"]');
			if (actA) { return actA.getAttribute('href'); }
			if (window.location && window.location.hash && document.querySelector(window.location.hash)) {
				return window.location.hash;
			}
		} catch(__){}
		return '#home';
	}
	document.addEventListener('click', function(e){
		var t = e.target;
		var a = (t && t.closest) ? t.closest('a.quickview-link') : null;
		if (!a) return;
		// Halt default navigation and any bubbling that might toggle tabs FIRST
		if (e && typeof e.preventDefault === 'function') e.preventDefault();
		if (e && typeof e.stopPropagation === 'function') e.stopPropagation();
		if (e && typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();
		// Compute origin tab and lock tabs during modal
		var currentTab = __qhtlGetPreferredTabHash(a);
		try { window.qhtlSavedTabHash = currentTab; } catch(__){}
		try { window.qhtlSavedURLHash = window.location.hash; } catch(__){}
		try { window.qhtlTabLock = 1; } catch(__){}
		try { document.documentElement.classList.add('qhtl-tabs-locked'); } catch(__){}
		try { qhtlLockTabs(); } catch(__){}
		// Hard re-assert the current tab immediately to prevent any background switch
		try { if (typeof window.qhtlActivateTab === 'function') { window.qhtlActivateTab(currentTab); } } catch(__){}
		// Open the modal directly
		var url = a.getAttribute('data-url') || a.getAttribute('href');
		var which = a.getAttribute('data-which');
		try {
			// cancel the pre-lock safety timer since we are opening now
			try { window.clearTimeout(window.__qhtlGearPreLockTimer); } catch(__){}
			openQuickView(url, which);
		} catch(_){ }
		// Re-activate the current tab after the modal opens (multiple ticks)
		try {
			if (currentTab && typeof window.qhtlActivateTab === 'function') {
				var times=[0,50,150,300,600];
				for (var i=0;i<times.length;i++){ (function(ms){ setTimeout(function(){ try { window.qhtlActivateTab(currentTab); } catch(__e){} }, ms); })(times[i]); }
			}
		} catch(__e){}
		// Safety: auto-unlock if modal didn't become visible
		setTimeout(function(){
			try {
				var visible = $('#quickViewModal').is(':visible');
				if (!visible) {
					window.qhtlTabLock = 0;
					document.documentElement.classList.remove('qhtl-tabs-locked');
					qhtlUnlockTabs();
				}
			} catch(__s){}
		}, 400);
		return false;
	}, true);
} catch(_){ }
$(document).on('click', '#quickViewEditBtn', function(){
	if (!currentQuickWhich) { return; }
    var url = QHTL_SCRIPT + '?action=editlist&which=' + encodeURIComponent(currentQuickWhich);
	$('#quickViewBody').html('Loading...');
    try { if (window.__qhtlEditXHR && window.__qhtlEditXHR.abort) { window.__qhtlEditXHR.abort(); } } catch(__ax){}
    if (window.console && console.info) { try { console.info('[QHTL] QuickView EDIT GET', url); } catch(__c){} }
	window.__qhtlEditXHR = jQuery.ajax({ url: url, method: 'GET', dataType: 'html', timeout: 15000, cache: false, headers: { 'X-Requested-With': 'XMLHttpRequest' } })
		.done(function(data){
			$('#quickViewBody').html(data);
			$('#quickViewEditBtn').hide();
			$('#quickViewSaveBtn').show();
			$('#quickViewCancelBtn').show();
			// add fire effect according to which list is being edited
			var cls = (currentQuickWhich==='allow') ? 'fire-allow' : (currentQuickWhich==='ignore' ? 'fire-ignore' : 'fire-deny');
			var $mc = $('#quickViewModal .modal-content'); $mc.removeClass('fire-allow fire-ignore fire-deny').addClass('fire-border').addClass(cls);
		})
		.fail(function(xhr, textStatus, errorThrown){
			if (window.console && console.warn) { try { console.warn('[QHTL] QuickView EDIT failed', url, textStatus, errorThrown, xhr && xhr.status); } catch(__c){} }
			var code = (xhr && typeof xhr.status !== 'undefined') ? xhr.status : 'n/a';
			var msg = (textStatus || 'error') + (errorThrown ? (': '+errorThrown) : '');
			$('#quickViewBody').html('<div class=\'alert alert-danger\'>Failed to load editor ('+code+'): '+msg+'</div>');
		});
});
$(document).on('click', '#quickViewCancelBtn', function(){
	if (!currentQuickWhich) { return; }
	$('#quickViewEditBtn').show();
	$('#quickViewSaveBtn').hide();
	$('#quickViewCancelBtn').hide();
	var $mc2 = $('#quickViewModal .modal-content'); $mc2.removeClass('fire-allow fire-ignore fire-deny'); $mc2.addClass('fire-border'); $mc2.removeClass('fire-allow-view fire-ignore-view fire-deny-view'); if (currentQuickWhich==='allow') { $mc2.addClass('fire-allow-view'); } else if (currentQuickWhich==='ignore') { $mc2.addClass('fire-ignore-view'); } else if (currentQuickWhich==='deny') { $mc2.addClass('fire-deny-view'); }
	showQuickView(currentQuickWhich);
});
$(document).on('click', '#quickViewSaveBtn', function(){
	if (!currentQuickWhich) { return; }
	var content = '';
	var ta = document.getElementById('quickEditArea');
	if (ta) { content = ta.value; }
	$('#quickViewBody').html('Saving...');
    try { if (window.__qhtlSaveXHR && window.__qhtlSaveXHR.abort) { window.__qhtlSaveXHR.abort(); } } catch(__ax){}
    if (window.console && console.info) { try { console.info('[QHTL] QuickView SAVE POST', currentQuickWhich); } catch(__c){} }
	window.__qhtlSaveXHR = jQuery.ajax({ url: QHTL_SCRIPT + '?action=savelist&which=' + encodeURIComponent(currentQuickWhich), method: 'POST', data: { formdata: content }, timeout: 15000, cache: false, headers: { 'X-Requested-With': 'XMLHttpRequest' } })
		.done(function(){
			showQuickView(currentQuickWhich);
			$('#quickViewEditBtn').show();
			$('#quickViewSaveBtn').hide();
			$('#quickViewCancelBtn').hide();
			var $mc3 = $('#quickViewModal .modal-content'); $mc3.removeClass('fire-allow fire-ignore fire-deny'); $mc3.addClass('fire-border'); $mc3.removeClass('fire-allow-view fire-ignore-view fire-deny-view'); $mc3.addClass((currentQuickWhich==='allow')?'fire-allow-view':(currentQuickWhich==='ignore')?'fire-ignore-view':'fire-deny-view');
		})
		.fail(function(xhr, textStatus, errorThrown){
			if (window.console && console.warn) { try { console.warn('[QHTL] QuickView SAVE failed', textStatus, errorThrown, xhr && xhr.status); } catch(__c){} }
			var code = (xhr && typeof xhr.status !== 'undefined') ? xhr.status : 'n/a';
			var msg = (textStatus || 'error') + (errorThrown ? (': '+errorThrown) : '');
			$('#quickViewBody').html('<div class=\'alert alert-danger\'>Failed to save changes ('+code+'): '+msg+'</div>');
		});
});
$('#quickViewModal').on('hidden.bs.modal', function(){
	// Force-unlock to ensure tabs are usable even if lock was incremented multiple times
	try { window.qhtlTabLock = 0; } catch(_){ }
	try { document.documentElement.classList.remove('qhtl-tabs-locked'); } catch(_){ }
	try { qhtlUnlockTabs(); } catch(_){ }
	// Abort any in-flight XHRs and clear timers
	try { if (window.__qhtlCurrentXHR && window.__qhtlCurrentXHR.abort) { window.__qhtlCurrentXHR.abort(); } } catch(_ax){}
	try { if (window.__qhtlEditXHR && window.__qhtlEditXHR.abort) { window.__qhtlEditXHR.abort(); } } catch(_ax){}
	try { if (window.__qhtlSaveXHR && window.__qhtlSaveXHR.abort) { window.__qhtlSaveXHR.abort(); } } catch(_ax){}
	try { window.clearTimeout(window.__qhtlLoadHintTimer); } catch(_t){}
	// No observers to disconnect (MutationObserver approach removed to avoid freezes)
	$('#quickViewModal .modal-content').removeClass('fire-border fire-allow fire-ignore fire-deny fire-allow-view fire-ignore-view fire-deny-view');
});
JS
		print "</script>\n";
	print "</div>\n";
		print "</div>\n";

	# Old QhtLink Waterfall pane removed; content lives in '#waterfall'

		if ($config{CLUSTER_SENDTO}) {
			print "<div id='cluster' class='tab-pane'>\n";
			print "<table class='table table-bordered table-striped'>\n";
			print "<thead><tr><th colspan='2'>qhtlfirewall - qhtlwaterfall Cluster</th></tr></thead>";

			print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='cping' type='submit' class='btn btn-default'>Cluster PING</button></form><div class='text-muted small' style='margin-top:6px'>Ping each member of the cluster (logged in qhtlwaterfall.log)</div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#callow\").submit();' class='btn btn-default'>Cluster Allow</button><div style='margin-top:6px'><form action='$script' method='post' id='callow'><input type='submit' class='hide'><input type='hidden' name='action' value='callow'>Allow IP address <input type='text' name='ip' value='' size='18' style='background-color: lightgreen'> through the Cluster and add to the allow file (qhtlfirewall.allow)<br>Comment: <input type='text' name='comment' value='' size='30'></form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#cdeny\").submit();' class='btn btn-default'>Cluster Deny</button><div style='margin-top:6px'><form action='$script' method='post' id='cdeny'><input type='submit' class='hide'><input type='hidden' name='action' value='cdeny'>Block IP address <input type='text' name='ip' value='' size='18' style='background-color: pink'> in the Cluster and add to the deny file (qhtlfirewall.deny)<br>Comment: <input type='text' name='comment' value='' size='30'></form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#cignore\").submit();' class='btn btn-default'>Cluster Ignore</button><div style='margin-top:6px'><form action='$script' method='post' id='cignore'><input type='submit' class='hide'><input type='hidden' name='action' value='cignore'>Ignore IP address <input type='text' name='ip' value='' size='18'> in the Cluster and add to the ignore file (qhtlfirewall.ignore)<br>Comment: <input type='text' name='comment' value='' size='30'> Note: This will result in qhtlwaterfall being restarted</form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#cgrep\").submit();' class='btn btn-default'>Search the Cluster for IP</button><div style='margin-top:6px'><form action='$script' method='post' id='cgrep'><input type='submit' class='hide'><input type='hidden' name='action' value='cgrep'>Search iptables for IP address <input type='text' name='ip' value='' size='18'></form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#ctempdeny\").submit();' class='btn btn-default'>Cluster Temp Allow/Deny</button><div style='margin-top:6px'><form action='$script' method='post' id='ctempdeny'><input type='submit' class='hide'><input type='hidden' name='action' value='ctempdeny'>Temporarily <select name='do' id='do'><option>allow</option><option>deny</option></select> IP address <input type='text' name='target' value='' size='18' id='target'> for $config{CF_TEMP} secs in CloudFlare AND qhtlfirewall for the chosen accounts and those with to \"any\"</form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#crm\").submit();' class='btn btn-default'>Cluster Remove Deny</button><div style='margin-top:6px'><form action='$script' method='post' id='crm'><input type='submit' class='hide'><input type='hidden' name='action' value='crm'>Remove Deny IP address <input type='text' name='ip' value='' size='18' style=''> in the Cluster (temporary or permanent)</form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#carm\").submit();' class='btn btn-default'>Cluster Remove Allow</button><div style='margin-top:6px'><form action='$script' method='post' id='carm'><input type='submit' class='hide'><input type='hidden' name='action' value='carm'>Remove Allow IP address <input type='text' name='ip' value='' size='18' style=''> in the Cluster (temporary or permanent)</form></div></td></tr>\n";
			print "<tr><td colspan='2'><button onClick='\$(\"#cirm\").submit();' class='btn btn-default'>Cluster Remove Ignore</button><div style='margin-top:6px'><form action='$script' method='post' id='cirm'><input type='submit' class='hide'><input type='hidden' name='action' value='cirm'>Remove Ignore IP address <input type='text' name='ip' value='' size='18'> in the Cluster<br>Note: This will result in qhtlwaterfall being restarted</form></div></td></tr>\n";

			if ($config{CLUSTER_CONFIG}) {
				if ($ips{$config{CLUSTER_MASTER}} or $ipscidr6->find($config{CLUSTER_MASTER}) or ($config{CLUSTER_MASTER} eq $config{CLUSTER_NAT})) {
					my $options;
					my %restricted;
					if ($config{RESTRICT_UI}) {
						sysopen (my $IN, "/usr/local/qhtlfirewall/lib/restricted.txt", O_RDWR | O_CREAT) or die "Unable to open file: $!";
						flock ($IN, LOCK_SH);
						while (my $entry = <$IN>) {
							chomp $entry;
							$restricted{$entry} = 1;
						}
						close ($IN);
					}
					foreach my $key (sort keys %config) {
						unless ($restricted{$key}) {$options .= "<option>$key</option>"}
					}
					print "<tr><td colspan='2'><button onClick='\$(\"#cconfig\").submit();' class='btn btn-default'>Cluster Config</button><div style='margin-top:6px'><form action='$script' method='post' id='cconfig'><input type='submit' class='hide'><input type='hidden' name='action' value='cconfig'>Change configuration option <select name='option'>$options</select> to <input type='text' name='value' value='' size='18'> in the Cluster";
					if ($config{RESTRICT_UI}) {print "<br />\nSome items have been removed with RESTRICT_UI enabled"}
					print "</form></div></td></tr>\n";
					print "<tr><td colspan='2'><form action='$script' method='post'><button name='action' value='crestart' type='submit' class='btn btn-default'>Cluster Restart</button></form><div class='text-muted small' style='margin-top:6px'>Restart qhtlfirewall and qhtlwaterfall on Cluster members</div></td></tr>\n";
				}
			}
			print "</table>\n";
			print "</div>\n";
		}


		# New Promotion tab-pane between More... and QhtLink Firewall (placeholder)
		print "<div id='promotion' class='tab-pane'>\n";
		print "<table class='table table-bordered table-striped'>\n";
		print "<thead><tr><th colspan='2'>Promotion</th></tr></thead>";
		print "<tr><td colspan='2'>No promotions are currently available.</td></tr>\n";
		print "</table>\n";
		print "</div>\n";

	# New Extra tab-pane at the end
		# Close tab-content container
		print "</div>\n";

		# Extra section moved to its own tab above
#		if ($config{DIRECTADMIN} and !$config{THIS_UI}) {
#			print "<a href='/' class='btn btn-success' data-spy='affix' data-offset-bottom='0' style='bottom: 0; left:45%'><span class='glyphicon glyphicon-home'></span> DirectAdmin Main Page</a>\n";
#		}
		# Note: Mobile View panel moved to Upgrade tab above

	# About already moved under 'More' tab above

	}

		unless ($FORM{action} eq "tailcmd" or $FORM{action} =~ /^cf/ or $FORM{action} eq "logtailcmd" or $FORM{action} eq "loggrepcmd" or $FORM{action} eq "viewlist" or $FORM{action} eq "editlist" or $FORM{action} eq "savelist") {
				# Auto-hide single section headers within a tab (show only when a tab has 2+ sections)
				print <<'JS_HIDE_HEADERS';
<script>
function qhtlUpdateSectionHeaders(scope){
	try {
		var nodes = scope ? $(scope) : $('.tab-pane');
		nodes.each(function(){
			var $tp = $(this);
			var $tables = $tp.find('table.table');
			if ($tables.length === 1) {
				$tables.first().find('thead').hide();
			} else if ($tables.length > 1) {
				$tables.find('thead').show();
			}
		});
	} catch(e){}
}
$(function(){
	qhtlUpdateSectionHeaders();
	$(document).on('shown.bs.tab','a[data-toggle="tab"]',function(e){
		var target = $(e.target).attr('href');
		if (target) { qhtlUpdateSectionHeaders(target); }
	});
});
</script>
JS_HIDE_HEADERS
				# Close the normal container opened earlier
				print "</div>\n";
		}

		# Lightweight runtime helper: change a bubble button's color variant dynamically.
		# Usage example (browser console or future features):
		#   qhtlSetBubbleColor('#someButton','red');
		print "<script>window.qhtlSetBubbleColor=function(sel,color){try{var el=(typeof sel==='string')?document.querySelector(sel):sel;if(el){el.setAttribute('data-bubble-color',color);}}catch(e){}};</script>\n";

	return;
}
# end main
###############################################################################
# start printcmd
sub printcmd {
	my @command = @_;

	my ($childin, $childout);
	my $pid = open3($childin, $childout, $childout, @command);
	while (<$childout>) {print $_}
	waitpid ($pid, 0);

	return;
}
# end printcmd
###############################################################################
# start confirmmodal
sub confirmmodal {
		# Render a compact, scoped confirm modal and wire .confirmButton triggers
		print <<'CONFIRM_MODAL_HTML';
<div class='modal fade' id='confirmmodal' tabindex='-1' role='dialog' aria-labelledby='confirmtitle' aria-hidden='true' data-backdrop='false' style='background-color: rgba(0,0,0,0.5)'>
	<div class='modal-dialog'>
		<div class='modal-content'>
			<div class='modal-body'>
				<h4 id='confirmtitle' style='margin:0 0 8px 0;'>Please Confirm</h4>
				<div id='confirmtext'>Are you sure?</div>
			</div>
			<div class='modal-footer' style='display:flex;justify-content:space-between;align-items:center;'>
				<div></div>
				<div>
					<button type='button' class='btn btn-default' id='confirmcancel' data-dismiss='modal'>Cancel</button>
					<button type='button' class='btn btn-primary' id='confirmok'>OK</button>
				</div>
			</div>
		</div>
	</div>
</div>
<script>
(function(){
	var pendingHref = null;
	function ensureScoped(){
		try {
			var $modal = $('#confirmmodal');
			var parent = document.querySelector('.qhtl-bubble-bg') || document.body;
			if (parent && $modal.length) {
				$modal.appendTo(parent);
				var inScoped = (parent !== document.body);
				var w = inScoped ? (parent.clientWidth || window.innerWidth) : window.innerWidth;
				var $dlg = $modal.find('.modal-dialog');
				var $mc  = $modal.find('.modal-content');
				$modal.css({ position: inScoped ? 'absolute' : 'fixed', left:0, top:0, right:0, bottom:0, width:'auto', height:'auto', margin:0 });
				$dlg.css({ position:'absolute', left:'50%', top:'12px', transform:'translateX(-50%)', margin:0, width: Math.min(320, Math.floor(w*0.95)) + 'px', maxWidth: Math.min(320, Math.floor(w*0.95)) + 'px' });
				$mc.css({ display:'flex', flexDirection:'column', overflow:'hidden', maxHeight:'480px' });
				$modal.find('.modal-body').css({ flex:'1 1 auto', minHeight:0, overflow:'auto' });
			}
		} catch(_){ }
	}
	function lockTabs(){ try { window.qhtlTabLock = 1; document.documentElement.classList.add('qhtl-tabs-locked'); if(window.qhtlLockTabs) qhtlLockTabs(); } catch(_){ } }
	function unlockTabs(){ try { window.qhtlTabLock = 0; document.documentElement.classList.remove('qhtl-tabs-locked'); if(window.qhtlUnlockTabs) qhtlUnlockTabs(); } catch(_){ } }
	$(document).on('click', '.confirmButton', function(e){
		try {
			e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
			var $btn = $(this);
			var txt = $btn.data('query') || 'Are you sure?';
			pendingHref = $btn.data('href') || null;
			$('#confirmtext').text(txt);
			ensureScoped();
			lockTabs();
			$('#confirmmodal').modal({ show:true, backdrop:false, keyboard:true });
		} catch(__){}
		return false;
	});
	$(document).on('click', '#confirmok', function(){
		try {
			var href = pendingHref; pendingHref = null;
			$('#confirmmodal').modal('hide');
			unlockTabs();
			if (href) { window.location = href; }
		} catch(__){}
	});
	$('#confirmmodal').on('hidden.bs.modal', function(){ try { pendingHref = null; unlockTabs(); } catch(_){ } });
})();
</script>
CONFIRM_MODAL_HTML

		return;
}
# end confirmmodal
###############################################################################
# start getethdev
sub getethdev {
	my $ethdev = QhtLink::GetEthDev->new();
	my %g_ipv4 = $ethdev->ipv4;
	my %g_ipv6 = $ethdev->ipv6;
	foreach my $key (keys %g_ipv4) {
		$ips{$key} = 1;
	}
	if ($config{IPV6}) {
		foreach my $key (keys %g_ipv6) {
			eval {
				local $SIG{__DIE__} = undef;
				$ipscidr6->add($key);
			};
		}
	}

	return;
}
# end getethdev
###############################################################################
# start chart
sub chart {
	my $img;
	my $imgdir = "";
	my $imghddir = "";
	if (-e "/usr/local/cpanel/version") {
		# When installed via cPanel register_appconfig, serve images from WHM cgi docroot
		if (-e "/usr/local/cpanel/bin/register_appconfig") {
			my $token = $ENV{cp_security_token} // ""; # e.g. /cpsess1590026883
			if ($token ne "" && $token !~ m{^/}) { $token = "/".$token }
			# Point image src to CGI endpoint which serves generated files
			$imgdir = ($token ne "" ? $token : "")."/cgi/qhtlink/qhtlfirewall.cgi?action=serve_stat_image&f=";
			$imghddir = "/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/";
			umask(0133);
		} else {
			$imgdir = "/";
			$imghddir = "";
		}
	}
	elsif (-e "/usr/local/directadmin/conf/directadmin.conf") {
		$imgdir = "/CMD_PLUGINS_ADMIN/qhtlfirewall/images/";
		$imghddir = "plugins/qhtlfirewall/images/";
		umask(0133);
	}
	elsif (-e "/usr/local/interworx") {
		$imgdir = "/qhtlfirewall/";
		$imghddir = "/usr/local/interworx/html/qhtlfirewall/";
		umask(0133);
	}
	elsif (-e "/usr/local/CyberCP/") {
		$imgdir = "/static/qhtlfirewall/";
		$imghddir = "/usr/local/CyberCP/public/static/qhtlfirewall/";
		umask(0133);
	}
	if ($config{THIS_UI}) {
		# Do not override $imgdir for dynamic graphs on cPanel/WHM; keep CGI endpoint if already set
		if ($imgdir eq "") { $imgdir = "$images/"; }
		$imghddir = "/etc/qhtlfirewall/ui/images/";
	}

	my $STATS;
	if (-e "/var/lib/qhtlfirewall/stats/qhtlwaterfallstats") {
		sysopen ($STATS,"/var/lib/qhtlfirewall/stats/qhtlwaterfallstats", O_RDWR | O_CREAT);
	}
	elsif (-e "/var/lib/qhtlfirewall/stats/qhtlwaterfallmain") {
		sysopen (my $OLDSTATS,"/var/lib/qhtlfirewall/stats/qhtlwaterfallmain", O_RDWR | O_CREAT);
		flock ($OLDSTATS, LOCK_EX);
		my @stats = <$OLDSTATS>;
		chomp @stats;

		my @newstats;
		my $cnt = 0;
		foreach my $line (@stats) {
			if ($cnt == 55) {push @newstats,""}
			push @newstats,$line;
			$cnt++;
		}
		sysopen ($STATS,"/var/lib/qhtlfirewall/stats/qhtlwaterfallstats", O_RDWR | O_CREAT);
		flock ($STATS, LOCK_EX);
		seek ($STATS, 0, 0);
		truncate ($STATS, 0);
		foreach my $line (@newstats) {
			print $STATS "$line\n";
		}
		close ($STATS);

		rename "/var/lib/qhtlfirewall/stats/qhtlwaterfallmain", "/var/lib/qhtlfirewall/stats/qhtlwaterfallmain.".time;
		close ($OLDSTATS);
		sysopen ($STATS,"/var/lib/qhtlfirewall/stats/qhtlwaterfallstats", O_RDWR | O_CREAT);
	} else {
		sysopen ($STATS,"/var/lib/qhtlfirewall/stats/qhtlwaterfallstats", O_RDWR | O_CREAT);
	}
	flock ($STATS, LOCK_SH);
	my @stats = <$STATS>;
	chomp @stats;
	close ($STATS);

	if (@stats) {
		QhtLink::ServerStats::charts($config{CC_LOOKUPS},$imghddir);
		print QhtLink::ServerStats::charts_html($config{CC_LOOKUPS},$imgdir);
	} else {
		print "<table class='table table-bordered table-striped'>\n";
		print "<tr><td>No statistical data has been collected yet</td></tr></table>\n";
	}
	&printreturn;

	return;
}
# end chart
###############################################################################
# start systemstats
sub systemstats {
	my $type = shift;
	if ($type eq "") {$type = "load"}
	my $img;
	my $imgdir = "";
	my $imghddir = "";
	if (-e "/usr/local/cpanel/version") {
		if (-e "/usr/local/cpanel/bin/register_appconfig") {
			# Serve via WHM CGI endpoint and write to the same place
			my $token = $ENV{cp_security_token} // ""; # e.g. /cpsess1590026883
			if ($token ne "" && $token !~ m{^/}) { $token = "/".$token }
			$imgdir = ($token ne "" ? $token : "")."/cgi/qhtlink/qhtlfirewall.cgi?action=serve_stat_image&f=";
			$imghddir = "/usr/local/cpanel/whostmgr/docroot/cgi/qhtlink/qhtlfirewall/";
			umask(0133);
		} else {
			$imgdir = "/";
			$imghddir = "";
		}
	}
	elsif (-e "/usr/local/directadmin/conf/directadmin.conf") {
		$imgdir = "/CMD_PLUGINS_ADMIN/qhtlfirewall/images/";
		$imghddir = "plugins/qhtlfirewall/images/";
		umask(0133);
	}
	elsif (-e "/usr/local/interworx") {
		$imgdir = "/qhtlfirewall/";
		$imghddir = "/usr/local/interworx/html/qhtlfirewall/";
		umask(0133);
	}
	elsif (-e "/usr/local/CyberCP/") {
		$imgdir = "/static/qhtlfirewall/";
		$imghddir = "/usr/local/CyberCP/public/static/qhtlfirewall/";
		umask(0133);
	}
	if ($config{THIS_UI}) {
		# Do not override $imgdir for dynamic graphs on cPanel/WHM; keep CGI endpoint if already set
		if ($imgdir eq "") { $imgdir = "$images/"; }
		$imghddir = "/etc/qhtlfirewall/ui/images/";
	}
	if (defined $ENV{WEBMIN_VAR} and defined $ENV{WEBMIN_CONFIG}) {
		$imgdir = "/qhtlfirewall/";
		$imghddir = "";
	}

	sysopen (my $STATS,"/var/lib/qhtlfirewall/stats/system", O_RDWR | O_CREAT);
	flock ($STATS, LOCK_SH);
	my @stats = <$STATS>;
	chomp @stats;
	close ($STATS);

	if (@stats > 1) {
		QhtLink::ServerStats::graphs($type,$config{ST_SYSTEM_MAXDAYS},$imghddir);

	# Removed: System Stats graph selector and 'Select Graphs' button (temporarily unavailable)

		print QhtLink::ServerStats::graphs_html($imgdir);

		# Defensive: if any legacy static paths slipped through (e.g., cached HTML), rewrite them client-side to the CGI endpoint
		my $token = $ENV{cp_security_token} // '';
		if ($token ne '' && $token !~ m{^/}) { $token = '/'.$token }
		my $cgi_base = ($token ne '' ? $token : '')."/cgi/qhtlink/qhtlfirewall.cgi?action=serve_stat_image&f=";
		print "<script>(function(){try{var base='".$cgi_base."';var imgs=document.querySelectorAll('img');for(var i=0;i<imgs.length;i++){var s=imgs[i].getAttribute('src')||'';if(/\\/cgi\\/qhtlink\\/qhtlfirewall\\/qhtlwaterfall_system(?:hour|day|week|month)\\.gif/.test(s)){var fname=(s.split('/')||[]).pop().split('?')[0];var qs='';var qi=s.indexOf('?');if(qi>=0){qs=s.substring(qi+1)};imgs[i].setAttribute('src',base+fname+(qs?('&'+qs):''));}}}catch(_){}})();</script>\n";

		unless ($config{ST_MYSQL} and $config{ST_APACHE}) {
			print "<br>\n<table class='table table-bordered table-striped'>\n";
			print "<tr><td>You may be able to collect more statistics by enabling ST_MYSQL or ST_APACHE in the qhtlfirewall configuration</td></tr></table>\n";
		}
	} else {
		print "<table class='table table-bordered table-striped'>\n";
		print "<tr><td>No statistical data has been collected yet</td></tr></table>\n";
	}
	&printreturn;

	return;
}
# end systemstats
###############################################################################
# start editfile
sub editfile {
	my $file = shift;
	my $save = shift;
	my $extra = shift;
	my $ace = 0;
	my $is_ajax = ($FORM{ajax} && $FORM{ajax} eq '1');

	sysopen (my $IN, $file, O_RDWR | O_CREAT) or die "Unable to open file: $!";
	flock ($IN, LOCK_SH);
	my @confdata = <$IN>;
	close ($IN);
	chomp @confdata;

	if (-e "/usr/local/cpanel/3rdparty/share/ace-editor/optimized/src-min-noconflict/ace.js") {$ace = 1}

	if (-e "/usr/local/cpanel/version" and $ace and !$config{THIS_UI}) {
		print "<script src='/libraries/ace-editor/optimized/src-min-noconflict/ace.js'></script>\n";
		print "<div class='qhtl-inline-fragment'>" if $is_ajax;
		print "<h4>Edit <code>$file</code></h4>\n" unless $is_ajax;
		print "<button class='btn btn-default' id='toggletextarea-btn'>Toggle Editor/Textarea</button>\n";
	print " <div class='pull-right btn-group'><button type='button' class='btn btn-default' id='fontminus-btn'><strong>a</strong><span class='glyphicon glyphicon-arrow-down icon-qhtlfirewall'></span></button>\n";
	print "<button type='button' class='btn btn-default' id='fontplus-btn'><strong>A</strong><span class='glyphicon glyphicon-arrow-up icon-qhtlfirewall'></span></button></div>\n";
		print "<form action='$script' method='post'>\n";
		print "<input type='hidden' name='action' value='$save'>\n";
		print "<input type='hidden' name='ace' value='1'>\n";
		if ($extra) {print "<input type='hidden' name='$extra' value='$FORM{$extra}'>\n";}
		print "<div id='editor' style='width:100%;height:500px;border: 1px solid #000;display:none;'>";
		print "Loading...</div>\n";
		print "<div id='textarea'><textarea class='textarea' name='formdata' id='formdata' style='width:100%;height:500px;border: 1px solid #000;font-family:\"Courier New\", Courier;font-size:14px;line-height:1.1' wrap='off'>";
		print "# Do not remove or change this line as it is a safeguard for the UI editor\n";
		foreach my $line (@confdata) {
			$line =~ s/\</\&lt\;/g;
			$line =~ s/\>/\&gt\;/g;
			print $line."\n";
		}
		print "</textarea><br></div>\n";
		print "<br><div class='text-center'><input type='submit' class='btn btn-default' value='Change'></div>\n" unless $is_ajax;
		print "</form>\n";
		print "</div>" if $is_ajax;
		print <<EOF;
<script>
	var myFont = 14;
	var textarea = \$('#formdata');
	var editordiv = \$('#editor');
	var editor = ace.edit("editor");
	editor.setTheme("ace/theme/tomorrow");
	editor.setShowPrintMargin(false);
	editor.setOptions({
		fontFamily: "Courier New, Courier",
		fontSize: "14px"
	});
	editor.getSession().setMode("ace/mode/space");

	editor.getSession().on('change', function () {
		textarea.val(editor.getSession().getValue());
	});

	textarea.on('change', function () {
		editor.getSession().setValue(textarea.val());
	});

	editor.getSession().setValue(textarea.val());
	\$('#textarea').hide();
	editordiv.show();

	\$("#toggletextarea-btn").on('click', function () {
		\$('#textarea').toggle();
		editordiv.toggle();
	});
	\$("#fontplus-btn").on('click', function () {
		myFont++;
		if (myFont > 20) {myFont = 20}
		editor.setFontSize(myFont)
		textarea.css("font-size",myFont+"px");
	});
	\$("#fontminus-btn").on('click', function () {
		myFont--;
		if (myFont < 12) {myFont = 12}
		editor.setFontSize(myFont)
		textarea.css("font-size",myFont+"px");
	});
</script>
EOF
	} else {
		if ($config{DIRECTADMIN}) {
			print "<form action='$script?pipe_post=yes' method='post'>\n<div class='panel panel-default'>\n";
		} else {
			print "<div class='qhtl-inline-fragment'>" if $is_ajax;
			print "<form action='$script' method='post'>\n<div class='panel panel-default'>\n" unless $is_ajax;
		}
		print "<div class='panel-heading panel-heading-qhtlwatcher'>Edit <code>$file</code></div>\n" unless $is_ajax;
		print "<div class='panel-body'>\n";
		print "<input type='hidden' name='action' value='$save'>\n";
		if ($extra) {print "<input type='hidden' name='$extra' value='$FORM{$extra}'>\n";}
		print "<textarea class='textarea' name='formdata' style='width:100%;height:500px;border: 1px solid #000;' wrap='off'>";
		foreach my $line (@confdata) {
			$line =~ s/\</\&lt\;/g;
			$line =~ s/\>/\&gt\;/g;
			print $line."\n";
		}
		print "</textarea></div>\n";
		print "<div class='panel-footer text-center'><input type='submit' class='btn btn-default' value='Change'></div>\n" unless $is_ajax;
		print "</div></form>\n" unless $is_ajax;
		print "</div>" if $is_ajax;
	}

	return;
}
# end editfile
###############################################################################
# start savefile
sub savefile {
	my $file = shift;
	my $restart = shift;

	$FORM{formdata} =~ s/\r//g;
	if ($FORM{ace} == "1") {
		if ($FORM{formdata} !~ /^# Do not remove or change this line as it is a safeguard for the UI editor\n/) {
			print "<div>UI editor safeguard missing, changes have not been saved.</div>\n";
			return;
		}
		$FORM{formdata} =~ s/^# Do not remove or change this line as it is a safeguard for the UI editor\n//g;
	}

	sysopen (my $OUT, $file, O_WRONLY | O_CREAT) or die "Unable to open file: $!";
	flock ($OUT, LOCK_EX);
	seek ($OUT, 0, 0);
	truncate ($OUT, 0);
	if ($FORM{formdata} !~ /\n$/) {$FORM{formdata} .= "\n"}
	print $OUT $FORM{formdata};
	close ($OUT);

	if ($restart eq "qhtlfirewall") {
		print "<div>Changes saved. You should restart qhtlfirewall.</div>\n";
		# Keep legacy button for firewall only (not tied to On bubble)
		print "<div><form action='$script' method='post'><input type='hidden' name='action' value='restart'><input type='submit' class='btn btn-default' value='Restart qhtlfirewall'></form></div>\n";
	}
	elsif ($restart eq "qhtlwaterfall") {
		print "<div>Changes saved. Restarting qhtlwaterfall…</div>\n";
		# Auto-trigger the On bubble restart countdown; no manual button
		print "<script>(function(){ try { if (window.WStatus && typeof WStatus.restartCountdown==='function') { WStatus.restartCountdown(); } else { /* ensure loader present then trigger */ var s=document.createElement('script'); s.src=(window.QHTL_SCRIPT||'$script')+'?action=wstatus_js&v=$myv'; s.onload=function(){ try{ if(window.WStatus&&WStatus.restartCountdown) WStatus.restartCountdown(); }catch(e){} }; (document.head||document.documentElement).appendChild(s); } } catch(e){} })();</script>\n";
	}
	elsif ($restart eq "both") {
		print "<div>Changes saved. Restarting qhtlwaterfall now; qhtlfirewall may also need a restart depending on your change.</div>\n";
		# Trigger bubble restart for qhtlwaterfall; keep firewall combo button hidden to reduce clutter
		print "<script>(function(){ try { if (window.WStatus && typeof WStatus.restartCountdown==='function') { WStatus.restartCountdown(); } else { var s=document.createElement('script'); s.src=(window.QHTL_SCRIPT||'$script')+'?action=wstatus_js&v=$myv'; s.onload=function(){ try{ if(window.WStatus&&WStatus.restartCountdown) WStatus.restartCountdown(); }catch(e){} }; (document.head||document.documentElement).appendChild(s); } } catch(e){} })();</script>\n";
	}
	else {
		print "<div>Changes saved.</div>\n";
	}

	return;
}
	# end savefile
###############################################################################
# start cloudflare
sub cloudflare {
	my $scope = &QhtLink::CloudFlare::getscope();
	print "<link rel='stylesheet' href='$images/bootstrap-chosen.css'>\n";
	print "<script src='$images/chosen.min.js'></script>\n";
		print "<script>\n";
		print <<'JS';
$(function() {
	$('.chosen-select').chosen();
	$('.chosen-select-deselect').chosen({ allow_single_deselect: true });
});
JS
		print "</script>\n";

	print "<table class='table table-bordered table-striped'>\n";
	print "<thead><tr><th colspan='2'>qhtlfirewall - CloudFlare</th></tr></thead>";
	print "<tr><td>Select the user(s), then select the action below</td><td style='width:100%'><select data-placeholder='Select user(s)' class='chosen-select' id='domains' name='domains' multiple>\n";
	foreach my $user (keys %{$scope->{user}}) {print "<option>$user</option>\n"}
	print "</select></td></tr>\n";
	print "<tr><td><button type='button' id='cflistbtn' class='btn btn-default' disabled='true'>CF List Rules</button></td><td style='width:100%'><form action='#' id='cflist'>List <select name='type' id='type'><option>all</option><option>block</option><option>challenge</option><option>whitelist</option></select> rules in CloudFlare ONLY for the chosen accounts</form></td></tr>";
	print "<tr><td><button type='button' id='cfaddbtn' class='btn btn-default' disabled='true'>CloudFlare Add</button></td><td style='width:100%'><form action='#' id='cfadd'>Add <select name='type' id='type'><option>block</option><option>challenge</option><option>whitelist</option></select> rule for target <input type='text' name='target' value='' size='18' id='target'> in CloudFlare ONLY for the chosen accounts</form></td></tr>\n";
	print "<tr><td><button type='button' id='cfremovebtn' class='btn btn-default' disabled='true'>CloudFlare Delete</button></td><td style='width:100%'><form action='#' id='cfremove'>Delete rule for target <input type='text' name='target' value='' size='18' id='target'> in CloudFlare ONLY</form></td></tr>\n";
	print "<tr><td><button type='button' id='cftempdenybtn' class='btn btn-default' disabled='true'>CF Temp Allow/Deny</button></td><td style='width:100%'><form action='#' id='cftempdeny'>Temporarily <select name='do' id='do'><option>allow</option><option>deny</option></select> IP address <input type='text' name='target' value='' size='18' id='target'> for $config{CF_TEMP} secs in CloudFlare AND qhtlfirewall for the chosen accounts and those with to \"any\"</form></td></tr>";
	print "</table>\n";
	print "<div id='CFajax'><div class='panel panel-info'><div class='panel-heading'>Output will appear here</div></div></div>\n";
	print "<div class='bs-callout bs-callout-success'>Note:\n<ul>\n";
	print "<li><mark>target</mark> can be one of:<ul><li>An IP address</li>\n<li>2 letter Country Code</li>\n<li>IP range CIDR</li></ul>\n</li>\n";
	print "<li>Only Enterprise customers can <mark>block</mark> a Country Code, but all can <mark>allow</mark> and <mark>challenge</mark>\n";
	print "<li>\nIP range CIDR is limited to /16 and /24</blockquote></li></ul></div>\n";
	print "<script>\n";
	print "var QHTL_SCRIPT = '$script';\n";
	print <<'JS';
$(document).ready(function(){
  $('#cflist').submit(function(){ $('#cflistbtn').click(); return false; });
  $('#cftempdeny').submit(function(){ $('#cftempdenybtn').click(); return false; });
  $('#cfadd').submit(function(){ $('#cfaddbtn').click(); return false; });
  $('#cfremove').submit(function(){ $('#cfremovebtn').click(); return false; });
  $('button').click(function(){
    $('body').css('cursor', 'progress');
    var myurl;
    if (this.id == 'cflistbtn') { myurl = QHTL_SCRIPT + '?action=cflist&type=' + $("#cflist #type").val() + '&domains=' + $("#domains").val(); }
    if (this.id == 'cftempdenybtn') { myurl = QHTL_SCRIPT + '?action=cftempdeny&do=' + $("#cftempdeny #do").val() + '&target=' + $("#cftempdeny #target").val().replace(/\s/g,'') + '&domains=' + $("#domains").val(); }
    if (this.id == 'cfaddbtn') { myurl = QHTL_SCRIPT + '?action=cfadd&type=' + $("#cfadd #type").val() + '&target=' + $("#cfadd #target").val().replace(/\s/g,'') + '&domains=' + $("#domains").val(); }
    if (this.id == 'cfremovebtn') { myurl = QHTL_SCRIPT + '?action=cfremove&target=' + $("#cfremove #target").val().replace(/\s/g,'') + '&domains=' + $("#domains").val(); }
    $('#CFajax').html('<div id="loader"></div><div class="panel panel-info"><div class="panel-heading">Loading...</div></div>');
    $('#CFajax').load(myurl);
    $('body').css('cursor', 'default');
  });
  $('#domains').on('keyup change',function() {
    if ($('#domains').val() == null) {
      $('#cflistbtn,#cftempdenybtn,#cfaddbtn,#cfremovebtn').prop('disabled', true);
    } else {
      $('#cflistbtn,#cftempdenybtn,#cfaddbtn,#cfremovebtn').prop('disabled', false);
		}
	});
});
JS
	print "</script>\n";

}
# end cloudflare
1;
sub printreturn {
	# Return button deprecated; keeping function for compatibility but intentionally emits nothing

	return;
}
# end printreturn