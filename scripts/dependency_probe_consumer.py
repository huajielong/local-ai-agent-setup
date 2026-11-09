from dependency_probe_api import lookup


def handler(name: str) -> str:
    return lookup(name)
