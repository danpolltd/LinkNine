from django.conf.urls import url
from . import views

urlpatterns = [

    url(r'^$', views.configserverqhtlfirewall, name='configserverqhtlfirewall'),
    url(r'^iframe/$', views.configserverqhtlfirewalliframe, name='configserverqhtlfirewalliframe'),
]
