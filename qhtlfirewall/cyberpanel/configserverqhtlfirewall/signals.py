from django.dispatch import receiver
from django.shortcuts import redirect
from firewall.signals import preFirewallHome, preCSF

@receiver(preFirewallHome)
def qhtlfirewallFirewallHome(sender, **kwargs):
    request = kwargs['request']
    return redirect('/configserverqhtlfirewall/')

@receiver(preCSF)
def qhtlfirewallCSF(sender, **kwargs):
    request = kwargs['request']
    return redirect('/configserverqhtlfirewall/')
