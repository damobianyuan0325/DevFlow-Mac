"""Small teaching example; no network, services or project integration."""


def normalize_label(value: str) -> str:
    label = value.strip()
    if not label:
        raise ValueError("label must not be empty")
    return label
