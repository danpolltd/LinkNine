# -*- coding: utf-8 -*-
from __future__ import unicode_literals

from django.apps import AppConfig

class configserverqhtlfirewallConfig(AppConfig):
    name = 'configserverqhtlfirewall'

    def ready(self):
        import signals
