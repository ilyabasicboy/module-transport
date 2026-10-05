from mod_transport.options import dump_allowed_components, parse_allowed_components


def test_allowed_components_round_trip():
    components = ["max.example.com", "telegram.example.com"]

    dumped = dump_allowed_components(components)

    assert parse_allowed_components(dumped) == components


def test_empty_allowed_components():
    assert dump_allowed_components([]) == "allowed_components: []\n"
    assert parse_allowed_components("allowed_components: []\n") == []
