"""DRF permission classes backed by the role matrix (PRD G3).

Hard-locked rules (§G3): subscription/billing + delete-business stay
owner-only in code, not just hidden UI.
"""
from rest_framework.permissions import BasePermission

from .business_types import ROLE_MATRIX


class HasCapability(BasePermission):
    """Usage: permission_classes = [HasCapability]; required_capability = 'edit_prices'."""

    message = 'Your role does not allow this action.'

    def has_permission(self, request, view):
        required = getattr(view, 'required_capability', None)
        if not required:
            return True
        caps = ROLE_MATRIX.get(getattr(request.user, 'role', ''), {})
        return bool(caps.get(required, False))


class OwnerOnly(BasePermission):
    message = 'Only the business owner can perform this action.'

    def has_permission(self, request, view):
        return getattr(request.user, 'role', '') == 'owner'
