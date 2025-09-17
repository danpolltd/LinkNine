//#############################################################################
//# Copyright (C) 2025 Daniel Nowakowski
//#
//# https://qhtlf.danpol.co.uk
//#############################################################################

var QHTLFIREWALLscript = '';
var QHTLFIREWALLcountval = 6;
var QHTLFIREWALLlineval = 100;
var QHTLFIREWALLcounter;
var QHTLFIREWALLcount = 1;
var QHTLFIREWALLpause = 0;
var QHTLFIREWALLfrombot = 120;
var QHTLFIREWALLfromright = 10;
var QHTLFIREWALLsettimer = 0;
var QHTLFIREWALLheight = 0;
var QHTLFIREWALLwidth = 0;
var QHTLFIREWALLajaxHTTP = QHTLFIREWALLcreateRequestObject();

function QHTLFIREWALLcreateRequestObject() {
	var QHTLFIREWALLajaxRequest;
	if (window.XMLHttpRequest) {
		QHTLFIREWALLajaxRequest = new XMLHttpRequest();
	}
	else if (window.ActiveXObject) {
		QHTLFIREWALLajaxRequest = new ActiveXObject("Microsoft.XMLHTTP");
	}
	else {
		alert('There was a problem creating the XMLHttpRequest object in your browser');
		QHTLFIREWALLajaxRequest = '';
	}
	return QHTLFIREWALLajaxRequest;
}

function QHTLFIREWALLsendRequest(url) {
	var now = new Date();
	QHTLFIREWALLajaxHTTP.open('get', url + '&nocache=' + now.getTime());
	QHTLFIREWALLajaxHTTP.onreadystatechange = QHTLFIREWALLhandleResponse;
	QHTLFIREWALLajaxHTTP.send();
	document.getElementById("QHTLFIREWALLrefreshing").style.display = "inline";
} 

function QHTLFIREWALLhandleResponse() {
	if(QHTLFIREWALLajaxHTTP.readyState == 4 && QHTLFIREWALLajaxHTTP.status == 200){
		if(QHTLFIREWALLajaxHTTP.responseText) {
			var QHTLFIREWALLobj = document.getElementById("QHTLFIREWALLajax");
			QHTLFIREWALLobj.innerHTML = QHTLFIREWALLajaxHTTP.responseText;
			waitForElement("QHTLFIREWALLajax",function(){
				QHTLFIREWALLobj.scrollTop = QHTLFIREWALLobj.scrollHeight;
			});
			document.getElementById("QHTLFIREWALLrefreshing").style.display = "none";
			if (QHTLFIREWALLsettimer) {QHTLFIREWALLcounter = setInterval(QHTLFIREWALLtimer, 1000);}
		}
	}
}

function waitForElement(elementId, callBack){
	window.setTimeout(function(){
		var element = document.getElementById(elementId);
		if(element){
			callBack(elementId, element);
		}else{
			waitForElement(elementId, callBack);
		}
	},500)
}

function QHTLFIREWALLgrep() {
	QHTLFIREWALLsettimer = 0;
	var QHTLFIREWALLlogobj = document.getElementById("QHTLFIREWALLlognum");
	var QHTLFIREWALLlognum;
	if (QHTLFIREWALLlogobj) {QHTLFIREWALLlognum = '&lognum=' + QHTLFIREWALLlogobj.options[QHTLFIREWALLlogobj.selectedIndex].value}
	else {QHTLFIREWALLlognum = ""}
	if (document.getElementById("QHTLFIREWALLgrep_i").checked) {QHTLFIREWALLlognum = QHTLFIREWALLlognum + "&grepi=1"}
	if (document.getElementById("QHTLFIREWALLgrep_E").checked) {QHTLFIREWALLlognum = QHTLFIREWALLlognum + "&grepE=1"}
	if (document.getElementById("QHTLFIREWALLgrep_Z").checked) {QHTLFIREWALLlognum = QHTLFIREWALLlognum + "&grepZ=1"}
	var QHTLFIREWALLurl = QHTLFIREWALLscript + '&grep=' + document.getElementById("QHTLFIREWALLgrep").value + QHTLFIREWALLlognum;
	QHTLFIREWALLsendRequest(QHTLFIREWALLurl);
}

function QHTLFIREWALLtimer() {
	QHTLFIREWALLsettimer = 1;
	if (QHTLFIREWALLpause) {return}
	QHTLFIREWALLcount = QHTLFIREWALLcount - 1;
	document.getElementById("QHTLFIREWALLtimer").innerHTML = QHTLFIREWALLcount;
	if (QHTLFIREWALLcount <= 0) {
		clearInterval(QHTLFIREWALLcounter);
		var QHTLFIREWALLlogobj = document.getElementById("QHTLFIREWALLlognum");
		var QHTLFIREWALLlognum;
		if (QHTLFIREWALLlogobj) {QHTLFIREWALLlognum = '&lognum=' + QHTLFIREWALLlogobj.options[QHTLFIREWALLlogobj.selectedIndex].value}
		else {QHTLFIREWALLlognum = ""}
		QHTLFIREWALLsendRequest(QHTLFIREWALLscript + '&lines=' + document.getElementById("QHTLFIREWALLlines").value + QHTLFIREWALLlognum);
		QHTLFIREWALLcount = QHTLFIREWALLcountval;
		return;
	}
}

function QHTLFIREWALLpausetimer() {
	if (QHTLFIREWALLpause) {
		QHTLFIREWALLpause = 0;
		document.getElementById("QHTLFIREWALLpauseID").innerHTML = "Pause";
	}
	else {
		QHTLFIREWALLpause = 1;
		document.getElementById("QHTLFIREWALLpauseID").innerHTML = "Continue";
	}
}

function QHTLFIREWALLrefreshtimer() {
	var pause = QHTLFIREWALLpause;
	QHTLFIREWALLcount = 1;
	QHTLFIREWALLpause = 0;
	QHTLFIREWALLtimer();
	QHTLFIREWALLpause = pause;
	QHTLFIREWALLcount = QHTLFIREWALLcountval - 1;
	document.getElementById("QHTLFIREWALLtimer").innerHTML = QHTLFIREWALLcount;
}

function windowSize() {
	if( typeof( window.innerHeight ) == 'number' ) {
		QHTLFIREWALLheight = window.innerHeight;
		QHTLFIREWALLwidth = window.innerWidth;
	}
	else if (document.documentElement && (document.documentElement.clientHeight)) {
		QHTLFIREWALLheight = document.documentElement.clientHeight;
		QHTLFIREWALLwidth = document.documentElement.clientWidth;
	}
	else if (document.body && (document.body.clientHeight)) {
		QHTLFIREWALLheight = document.body.clientHeight;
		QHTLFIREWALLwidth = document.body.clientWidth;
	}
}
