# -*- coding: utf-8 -*-
from __future__ import unicode_literals

# pyright: reportMissingImports=false, reportMissingModuleSource=false

import os
import sys
import tempfile

# Attempt to bootstrap CyberPanel's Django environment when available.
try:
    import django  # type: ignore
    sys.path.append('/usr/local/CyberCP')
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "CyberCP.settings")
    django.setup()  # type: ignore
except Exception:
    # In non-CyberPanel/dev environments, Django may be unavailable. That's fine for linting/editing.
    django = None  # type: ignore

# Try to import Django helpers; provide lightweight fallbacks if unavailable so this module can import in dev.
try:
    from django.shortcuts import render  # type: ignore
    from django.http import HttpResponse  # type: ignore
    from django.views.decorators.csrf import csrf_exempt  # type: ignore
    from django.views.decorators.clickjacking import xframe_options_exempt  # type: ignore
except Exception:  # pragma: no cover - dev fallback only
    def render(request, template_name, context=None):  # type: ignore
        return "Render unavailable outside CyberPanel/Django"

    class HttpResponse(str):  # type: ignore
        def __new__(cls, content='', status=200):
            return str.__new__(cls, content)

    def csrf_exempt(func):  # type: ignore
        return func

    def xframe_options_exempt(func):  # type: ignore
        return func

# Import CyberPanel logical utilities; fallback stubs allow local editing without the CyberPanel stack.
try:
    from plogical.acl import ACLManager  # type: ignore
    from plogical.processUtilities import ProcessUtilities  # type: ignore
except Exception:  # pragma: no cover - dev fallback only
    class ACLManager:  # type: ignore
        @staticmethod
        def loadedACL(userID):
            # Assume admin in dev so views can render text for quick checks
            return {'admin': 1}

        @staticmethod
        def loadError():
            return HttpResponse("Access denied", status=403)  # type: ignore

    class ProcessUtilities:  # type: ignore
        @staticmethod
        def outputExecutioner(command):
            try:
                import subprocess
                return subprocess.check_output(command, shell=True, text=True, stderr=subprocess.STDOUT)
            except Exception as e:
                return str(e)

def configservercsf(request):
    userID = request.session['userID']
    currentACL = ACLManager.loadedACL(userID)

    if currentACL['admin'] == 1:
        pass
    else:
        return ACLManager.loadError()

    return render(request,'configservercsf/index.html')

@csrf_exempt
@xframe_options_exempt
def configservercsfiframe(request):
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

        command = "/usr/local/qhtlfirewall/lib/cyberpanel/cyberpanel.pl '" + tmp.name + "'"
        try:
            output = ProcessUtilities.outputExecutioner(command)
        except Exception:
            output = "Output Error from qhtlfirewall UI script"

        os.unlink(tmp.name)
    except Exception:
        output = "Unable to create qhtlfirewall UI temp file"

    return HttpResponse(output)
