# module-transport

Provider-neutral Xabber Server roster helper for the unified
`xmpp-transport` framework.

The module exposes one narrow trusted IQ API to configured XEP-0114 component
domains. It supports only:

- `add-roster-contact`
- `rename-roster-contact`
- `remove-roster-contact`

Groups, members, messages, avatars, archives, media, fanout and loop suppression
remain in the transport or existing Xabber protocol paths.

## Namespace

```text
urn:xabber:transport:roster:1
```

Both `max.example.com` and `telegram.example.com` can be placed in the same
`allowed_components` list. A component may manage only contacts whose JIDs
belong to one of the allowed component domains.

Every roster IQ must also contain `auth-signature`, an HMAC-SHA256 signature of
the stanza `id`. Configure the same secret (at least 32 bytes) in the module UI
and in the transport configuration:

```ini
[security]
iq_auth_secret = replace-with-a-long-random-secret
```

## Build

```bash
cp .env.example .env
make
```

The archive is written to:

```text
build/module_mod_transport_00.01.tar.gz
```
