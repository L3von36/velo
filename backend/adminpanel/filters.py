"""Unfold dropdown filters whose options are computed from the live data.

Every option list is the distinct set of values actually present in the
column (capped), so the filters never go stale when new payment methods,
plans or statuses appear in the app — no hard-coded enums to maintain.
"""
from django.utils.translation import gettext_lazy as _

from unfold.contrib.filters.admin import DropdownFilter


class DistinctDropdownFilter(DropdownFilter):
    """Dropdown filter fed by `SELECT DISTINCT <field>` on the changelist queryset."""

    field_name = None  # set on subclasses
    limit = 50

    @property
    def parameter_name(self):
        return self.field_name

    @property
    def title(self):
        return _(self.field_name.replace("_", " ").title())

    def lookups(self, request, model_admin):
        qs = model_admin.get_queryset(request)
        values = (
            qs.exclude(**{f"{self.field_name}__isnull": True})
            .exclude(**{f"{self.field_name}": ""})
            .order_by(self.field_name)
            .values_list(self.field_name, flat=True)
            .distinct()[: self.limit]
        )
        return [(v, v) for v in values]

    def queryset(self, request, queryset):
        if self.value():
            return queryset.filter(**{self.parameter_name: self.value()})
        return queryset


class PlanFilter(DistinctDropdownFilter):
    field_name = "plan"


class LanguageFilter(DistinctDropdownFilter):
    field_name = "language"


class SaleMethodFilter(DistinctDropdownFilter):
    field_name = "method"


class SaleStatusFilter(DistinctDropdownFilter):
    field_name = "status"


class ItemTypeFilter(DistinctDropdownFilter):
    field_name = "type"


class StaffRoleFilter(DistinctDropdownFilter):
    field_name = "role"


class LedgerTypeFilter(DistinctDropdownFilter):
    field_name = "type"


class PaymentMethodFilter(DistinctDropdownFilter):
    field_name = "method"


class PaymentStatusFilter(DistinctDropdownFilter):
    field_name = "status"


class StockReasonFilter(DistinctDropdownFilter):
    field_name = "reason"
    limit = 25
