from django.dispatch import receiver
from django.shortcuts import redirect
from firewall.signals import preFirewallHome, preQHTLFIREWALL

@receiver(preFirewallHome)
def qhtlfirewallFirewallHome(sender, **kwargs):
    request = kwargs['request']
    return redirect('/configserverqhtlfirewall/')

@receiver(preQHTLFIREWALL)
def qhtlfirewallQHTLFIREWALL(sender, **kwargs):
    request = kwargs['request']
    return redirect('/configserverqhtlfirewall/')
