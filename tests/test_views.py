from mod_transport.options import dump_options, parse_allowed_components, parse_iq_auth_secret


def test_allowed_components_round_trip():
    components = ["max.example.com", "telegram.example.com"]

    dumped = dump_options(components, "shared-secret-at-least-32-bytes-long")

    assert parse_allowed_components(dumped) == components
    assert parse_iq_auth_secret(dumped) == "shared-secret-at-least-32-bytes-long"


def test_empty_allowed_components():
    dumped = dump_options([], "shared-secret-at-least-32-bytes-long")
    assert dumped.startswith("allowed_components: []\n")
    assert parse_allowed_components(dumped) == []
