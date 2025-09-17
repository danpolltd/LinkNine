# -*- coding: utf-8 -*-
from __future__ import unicode_literals

import os
import os.path
import sys
import django
sys.path.append('/usr/local/CyberCP')
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "CyberCP.settings")
django.setup()
from plogical.acl import ACLManager
from django.shortcuts import HttpResponse, render
from django.views.decorators.csrf import csrf_exempt
import tempfile
from django.views.decorators.clickjacking import xframe_options_exempt
from plogical.processUtilities import ProcessUtilities


def qhtlfirewall(request):
    userID = request.session['userID']
    currentACL = ACLManager.loadedACL(userID)

    if currentACL['admin'] == 1:
        pass
    else:
        return ACLManager.loadError()

    return render(request, 'qhtlfirewall/index.html')


@csrf_exempt
@xframe_options_exempt
def qhtlfirewalliframe(request):
    userID = request.session['userID']
    currentACL = ACLManager.loadedACL(userID)

    if currentACL['admin'] == 1:
        pass
    else:
        return ACLManager.loadError()

    if request.method == 'GET':
        qs = request.GET.urlencode()
    elif request.method == 'POST':
        qs = request.POST.urlencode()

    try:
        tmp = tempfile.NamedTemporaryFile(mode="w", delete=False)
        tmp.write(qs)
        tmp.close()
        command = "/usr/local/qhtlfirewall/bin/cyberpanel.pl '" + tmp.name + "'"

        try:
            output = ProcessUtilities.outputExecutioner(command)
        except Exception:
            output = "Output Error from qhtlfirewall UI script"

        os.unlink(tmp.name)
    except Exception:
        output = "Unable to create qhtlfirewall UI temp file"

    return HttpResponse(output)
