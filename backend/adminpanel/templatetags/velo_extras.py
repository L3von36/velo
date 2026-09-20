"""Tiny template helpers for the Velo owner console."""
from django import template

register = template.Library()


@register.filter
def get(mapping, key):
    """Dict lookup by dynamic key: {{ t.flags|get:f.flag }} → truthy."""
    try:
        return bool((mapping or {}).get(key))
    except Exception:
        return False
