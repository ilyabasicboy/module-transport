from django import forms


class ModuleServerConfigForm(forms.Form):
    status = forms.ChoiceField(
        label='Transport server operations',
        choices=(
            ('disabled', 'disabled'),
            ('enabled', 'enabled'),
        ),
        widget=forms.Select(attrs={'class': 'form-select'}),
    )
    allowed_components = forms.CharField(
        label='Allowed transport components',
        required=False,
        help_text='One component domain per line, for example max.example.com.',
        widget=forms.Textarea(attrs={'class': 'form-control', 'rows': 5}),
    )
    iq_auth_secret = forms.CharField(
        label='Roster IQ HMAC secret',
        min_length=32,
        strip=False,
        help_text='Must match security.iq_auth_secret in transports.ini.',
        widget=forms.PasswordInput(
            render_value=True,
            attrs={'class': 'form-control', 'autocomplete': 'new-password'},
        ),
    )
