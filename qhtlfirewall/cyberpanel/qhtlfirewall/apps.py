from django.apps import AppConfig


class QhtlfirewallConfig(AppConfig):
    name = 'qhtlfirewall'

    def ready(self):
        import qhtlfirewall.signals  # noqa: F401
