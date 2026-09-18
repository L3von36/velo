"""Tenant isolation helpers — the backbone of multi-tenancy (PRD §6 note).

Every queryset for tenant-scoped data MUST go through `tenant_queryset`,
which pins results to the requesting user's tenant. Role capability checks
ride on top of this (permissions.py).
"""
from rest_framework.exceptions import NotFound, PermissionDenied

from .business_types import ROLE_MATRIX


def tenant_queryset(model, user):
    if user is None or not getattr(user, 'is_authenticated', False):
        return model.objects.none()
    if user.tenant_id is None:
        return model.objects.none()
    return model.objects.filter(tenant_id=user.tenant_id)


def require_capability(user, capability: str):
    caps = ROLE_MATRIX.get(user.role, {})
    if not caps.get(capability, False):
        raise PermissionDenied(
            detail={'detail': f'Your role ({user.role}) is not allowed to: {capability}.'}
        )


def get_object_for_user(model, pk, user, prefetch=None):
    qs = tenant_queryset(model, user)
    if prefetch:
        qs = qs.select_related(*prefetch.get('select_related', []))
        if prefetch.get('prefetch_related'):
            qs = qs.prefetch_related(*prefetch['prefetch_related'])
    try:
        return qs.get(pk=pk)
    except model.DoesNotExist:
        # Never leak existence across tenants — 404, not 403.
        raise NotFound(detail='Not found.')
