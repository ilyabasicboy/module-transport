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
