from django.apps import AppConfig


class ModuleConfig(AppConfig):
    default = True
    default_auto_field = "django.db.models.BigAutoField"
    name = "modules.mod_transport"
    verbose_name = "Transport"
    root_page = True


class ModTransportConfig(ModuleConfig):
    default = False
