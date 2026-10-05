"""Serialization helpers for the module's small YAML option set."""


def parse_allowed_components(raw_options):
    components = []
    in_allowed_components = False

    for line in (raw_options or '').splitlines():
        stripped = line.strip()
        if not stripped:
            continue

        if stripped.startswith('allowed_components:'):
            in_allowed_components = True
            value = stripped.split(':', 1)[1].strip()
            if value and value not in ('[]', '{}'):
                components.append(value.strip('"\''))
            continue

        if not in_allowed_components:
            continue

        if stripped.startswith('-'):
            components.append(stripped[1:].strip().strip('"\''))
        elif not line.startswith((' ', '\t')):
            in_allowed_components = False

    return [component for component in components if component]


def dump_allowed_components(components):
    if not components:
        return 'allowed_components: []\n'

    lines = ['allowed_components:']
    for component in components:
        escaped = component.replace('"', '\\"')
        lines.append('  - "%s"' % escaped)
    return '\n'.join(lines) + '\n'
