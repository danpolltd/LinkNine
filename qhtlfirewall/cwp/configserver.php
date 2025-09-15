<script type="text/javascript">
	$(document).ready(function() {
		var newButtons = ''
		+' <li>'
		+' <a href="#" class="hasUl"><span aria-hidden="true" class="icon16 icomoon-icon-bug"></span>ConfigServer Scripts<span class="hasDrop icon16 icomoon-icon-arrow-down-2"></span></a>'
		+'	<ul class="sub">'
<?php 
// qhtlfirewall rebrand (removed legacy csfofficial module name)
if (file_exists("/usr/local/cwpsrv/htdocs/resources/admin/modules/qhtlfirewall.php")) {
	echo "+'\t\t<li><a href=\"index.php?module=qhtlfirewall\"><span class=\"icon16 icomoon-icon-arrow-right-3\"></span>QHTL Firewall</a></li>'\n";
}

if (file_exists("/usr/local/cwpsrv/htdocs/resources/admin/modules/cxs.php")) {
	echo "+'\t\t<li><a href=\"index.php?module=cxs\"><span class=\"icon16 icomoon-icon-arrow-right-3\"></span>ConfigServer Exploit Scanner</a></li>'\n";
}
?>
		+'	</ul>'
		+'</li>';
		$(".mainnav > ul").append(newButtons);
	});
</script>
