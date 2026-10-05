from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.http import HttpResponseRedirect
from django.urls import reverse
from django.views.generic import RedirectView, TemplateView

from xabber_server_panel.base_modules.config.models import Module
from xabber_server_panel.base_modules.config.utils import make_xmpp_config
from xabber_server_panel.base_modules.modules.models import ModuleServerConfig
from xabber_server_panel.base_modules.users.decorators import permission_read, permission_write

from .forms import ModuleServerConfigForm
from .options import dump_allowed_components, parse_allowed_components


MODULE_NAME = 'mod_transport'
DEFAULT_CONFIG_NAME = 'mod_transport'


class RootView(LoginRequiredMixin, RedirectView):
    pattern_name = 'mod_transport:info'


class InfoView(LoginRequiredMixin, TemplateView):
    template_name = 'mod_transport/info.html'
    app = MODULE_NAME

    def _get_module(self):
        return Module.objects.filter(name=MODULE_NAME).first()

    def _get_server_config(self, module):
        if not module:
            return None
        return ModuleServerConfig.objects.filter(
            module=module,
            name=DEFAULT_CONFIG_NAME,
        ).first()

    def _get_form_initial(self, server_config, host):
        enabled = bool(server_config and host and host.name in server_config.get_hosts())
        allowed_components = parse_allowed_components(
            server_config.get_options() if server_config else ''
        )
        return {
            'status': 'enabled' if enabled else 'disabled',
            'allowed_components': '\n'.join(allowed_components),
        }

    @permission_read
    def get(self, request, *args, **kwargs):
        module = self._get_module()
        server_config = self._get_server_config(module)
        form = ModuleServerConfigForm(
            initial=self._get_form_initial(server_config, request.current_host)
        )
        return self.render_to_response({
            'form': form,
            'module': module,
            'server_config': server_config,
        })

    @permission_write
    def post(self, request, *args, **kwargs):
        module = self._get_module()
        server_config = self._get_server_config(module)
        form = ModuleServerConfigForm(request.POST)

        if not module or not server_config:
            messages.error(request, 'Installed server configuration was not found.')
            return self.render_to_response({
                'form': form,
                'module': module,
                'server_config': server_config,
            })

        if form.is_valid():
            host = request.current_host
            hosts = server_config.get_hosts()
            status = form.cleaned_data['status']
            if status == 'enabled' and host and host.name not in hosts:
                hosts.append(host.name)
            elif status == 'disabled' and host and host.name in hosts:
                hosts.remove(host.name)

            allowed_components = [
                line.strip()
                for line in form.cleaned_data['allowed_components'].splitlines()
                if line.strip()
            ]
            server_config.set_hosts(sorted(hosts))
            server_config.set_options(dump_allowed_components(allowed_components))
            server_config.save()
            make_xmpp_config()
            messages.success(request, 'Module configuration updated successfully.')
            return HttpResponseRedirect(reverse('mod_transport:info'))

        return self.render_to_response({
            'form': form,
            'module': module,
            'server_config': server_config,
        })
