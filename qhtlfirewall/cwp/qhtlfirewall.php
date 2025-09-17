<script type="text/javascript">
	$(document).ready(function() {
		var newButtons = ''
		+' <li>'
		+' <a href="#" class="hasUl"><span aria-hidden="true" class="icon16 icomoon-icon-bug"></span>QhtLink Firewall Scripts<span class="hasDrop icon16 icomoon-icon-arrow-down-2"></span></a>'
		+'\t<ul class="sub">'
<?php 
	
	if (file_exists("/usr/local/cwpsrv/htdocs/resources/admin/modules/qhtlfirewallofficial.php")) {
		echo "+'\\t\\t<li><a href=\"index.php?module=qhtlfirewallofficial\"><span class=\"icon16 icomoon-icon-arrow-right-3\"></span>QhtLink Firewall</a></li>'\n";
	}

	if (file_exists("/usr/local/cwpsrv/htdocs/resources/admin/modules/qhtlwatcher.php")) {
		echo "+'\\t\\t<li><a href=\"index.php?module=qhtlwatcher\"><span class=\"icon16 icomoon-icon-arrow-right-3\"></span>QhtLink Watcher</a></li>'\n";
	}

?>
		+'\t</ul>'
		+'</li>';
		$(".mainnav > ul").append(newButtons);
	});
</script>
