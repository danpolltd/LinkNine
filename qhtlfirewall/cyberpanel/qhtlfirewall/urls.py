from django.conf.urls import url
from . import views

urlpatterns = [
    url(r'^$', views.qhtlfirewall, name='qhtlfirewall'),
    url(r'^iframe/$', views.qhtlfirewalliframe, name='qhtlfirewalliframe'),
]
