"""Serializers — API shapes consumed by the Flutter app."""
import re
from decimal import Decimal

from django.contrib.auth.hashers import check_password
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .business_types import BUSINESS_TYPES, ROLE_MATRIX, business_config
from .models import (Appointment, Branch, CatalogItem, Category, Customer,
                     CustomerLedger, Expense, ExpenseCategory, HeldSale,
                     ItemVariant, Payment, Sale, SaleItem, StockMovement,
                     Tenant, User)

ETHIOPIAN_PHONE_RE = re.compile(r'^(?:\+251|251|0)?9\d{8}$')


def normalize_phone(raw: str) -> str:
    digits = re.sub(r'[^\d+]', '', (raw or '').strip())
    if digits.startswith('+251'):
        digits = '0' + digits[4:]
    elif digits.startswith('251'):
        digits = '0' + digits[3:]
    if not ETHIOPIAN_PHONE_RE.match(digits):
        raise serializers.ValidationError({'phone': 'Enter a valid Ethiopian phone number (+251 9XX XXX XXX).'})
    return digits


# ---------------------------------------------------------------- auth
class SignupSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    phone = serializers.CharField(max_length=20)
    password = serializers.CharField(min_length=6, write_only=True)
    shop_name = serializers.CharField(max_length=120)
    business_type = serializers.ChoiceField(choices=list(BUSINESS_TYPES.keys()))
    branch_name = serializers.CharField(max_length=120, required=False, allow_blank=True, default='Main branch')

    def validate_phone(self, value):
        phone = normalize_phone(value)
        if User.objects.filter(phone=phone).exists():
            raise serializers.ValidationError('This phone number is already registered.')
        return phone

    def create(self, validated):
        cfg = business_config(validated['business_type'])
        tenant = Tenant.objects.create(
            name=validated['shop_name'],
            business_type=validated['business_type'],
            sells_products=cfg['sells_products'],
            sells_services=cfg['sells_services'],
        )
        branch = Branch.objects.create(
            tenant=tenant, name=validated.get('branch_name') or 'Main branch',
            is_default=True,
        )
        user = User.objects.create_user(
            phone=validated['phone'], password=validated['password'],
            name=validated['name'], role='owner', tenant=tenant, branch=branch,
        )
        # Seed default categories per business type (PRD A7/C2).
        for i, cat in enumerate(cfg['default_categories']):
            Category.objects.create(tenant=tenant, name=cat, sort_order=i)
        for i, cat in enumerate(['Rent', 'Salaries', 'Utilities', 'Supplies', 'Other']):
            ExpenseCategory.objects.create(tenant=tenant, name=cat)
        return user


class LoginSerializer(TokenObtainPairSerializer):
    """Phone + password JWT login (A3)."""

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['role'] = user.role
        token['tenant_id'] = user.tenant_id
        token['name'] = user.name
        return token

    def validate(self, attrs):
        phone = normalize_phone(attrs.get('phone') or '')
        try:
            user = User.objects.get(phone=phone)
        except User.DoesNotExist:
            raise serializers.ValidationError({'detail': 'Wrong phone or password.'})
        if not check_password(attrs.get('password') or '', user.password):
            raise serializers.ValidationError({'detail': 'Wrong phone or password.'})
        if not user.active:
            raise serializers.ValidationError({'detail': 'This account is deactivated.'})
        refresh = self.get_token(user)
        data = {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserSerializer(user).data,
        }
        return data


class UserSerializer(serializers.ModelSerializer):
    capabilities = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'name', 'phone', 'role', 'branch', 'branch_id',
                  'commission_percent', 'active', 'capabilities']

    def get_branch_id(self, obj):
        return obj.branch_id

    def get_capabilities(self, obj):
        return ROLE_MATRIX.get(obj.role, {})


class BranchSerializer(serializers.ModelSerializer):
    class Meta:
        model = Branch
        fields = ['id', 'name', 'address', 'phone', 'is_default']


class TenantSerializer(serializers.ModelSerializer):
    config = serializers.SerializerMethodField()

    class Meta:
        model = Tenant
        fields = ['id', 'name', 'business_type', 'sells_products', 'sells_services',
                  'plan', 'language', 'currency', 'phone', 'address',
                  'telebirr_number', 'cbe_number', 'accept_telebirr', 'accept_cbe',
                  'accept_credit', 'receipt_footer', 'receipt_logo_enabled',
                  'tax_enabled', 'tax_rate_percent', 'config']

    def get_config(self, obj):
        return business_config(obj.business_type)


class MeSerializer(serializers.Serializer):
    user = UserSerializer()
    tenant = TenantSerializer()
    branches = BranchSerializer(many=True)


# ---------------------------------------------------------------- catalog
class VariantSerializer(serializers.ModelSerializer):
    effective_price = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = ItemVariant
        fields = ['id', 'item', 'attributes', 'sku', 'barcode', 'price_override',
                  'stock_qty', 'effective_price']


class CategorySerializer(serializers.ModelSerializer):
    item_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Category
        fields = ['id', 'name', 'sort_order', 'item_count']


class CatalogItemSerializer(serializers.ModelSerializer):
    variants = VariantSerializer(many=True, read_only=True)
    category_name = serializers.CharField(source='category.name', read_only=True, default=None)
    stock_qty = serializers.IntegerField(read_only=True)
    is_low_stock = serializers.SerializerMethodField()

    class Meta:
        model = CatalogItem
        fields = ['id', 'type', 'category', 'category_name', 'name', 'description',
                  'price', 'cost', 'duration_minutes', 'requires_stock',
                  'low_stock_threshold', 'barcode', 'unit', 'expiry_date',
                  'is_active', 'variants', 'stock_qty', 'is_low_stock']

    def get_is_low_stock(self, obj):
        if obj.type != CatalogItem.TYPE_PRODUCT or not obj.requires_stock:
            return False
        return obj.stock_qty <= obj.low_stock_threshold


class CatalogItemWriteSerializer(serializers.ModelSerializer):
    variants = VariantSerializer(many=True, required=False)

    class Meta:
        model = CatalogItem
        fields = ['id', 'type', 'category', 'name', 'description', 'price', 'cost',
                  'duration_minutes', 'requires_stock', 'low_stock_threshold',
                  'barcode', 'unit', 'expiry_date', 'is_active', 'variants']

    def validate(self, attrs):
        tenant = self.context['request'].user.tenant
        cfg = business_config(tenant.business_type)
        item_type = attrs.get('type', getattr(self.instance, 'type', 'product'))
        if item_type == 'service':
            if not cfg['sells_services']:
                raise serializers.ValidationError('This business type does not sell services.')
            duration = attrs.get('duration_minutes', getattr(self.instance, 'duration_minutes', None))
            if duration is not None and not (5 <= duration <= 480):
                raise serializers.ValidationError('Service duration must be 5–480 minutes.')
        else:
            if not cfg['sells_products']:
                raise serializers.ValidationError('This business type does not sell products.')
        price = attrs.get('price', getattr(self.instance, 'price', None))
        if price is not None and Decimal(str(price)) < 0:
            raise serializers.ValidationError('Price cannot be negative.')
        barcode = attrs.get('barcode', getattr(self.instance, 'barcode', ''))
        if barcode:
            qs = CatalogItem.objects.filter(tenant=tenant, barcode=barcode)
            if self.instance:
                qs = qs.exclude(pk=self.instance.pk)
            if qs.exists():
                raise serializers.ValidationError({'barcode': 'This barcode is already used by another item.'})
        return attrs

    def _upsert_variants(self, item, variants_data):
        keep_ids = []
        for v in variants_data:
            vid = v.get('id')
            if vid:
                obj = item.variants.filter(id=vid).first()
                if obj:
                    for f in ['attributes', 'sku', 'barcode', 'price_override', 'stock_qty']:
                        if f in v:
                            setattr(obj, f, v[f])
                    obj.save()
                    keep_ids.append(obj.id)
            else:
                obj = ItemVariant.objects.create(item=item, **{
                    'attributes': v.get('attributes', {}),
                    'sku': v.get('sku', ''),
                    'barcode': v.get('barcode', ''),
                    'price_override': v.get('price_override'),
                    'stock_qty': int(v.get('stock_qty') or 0),
                })
                if obj.stock_qty:
                    StockMovement.objects.create(
                        tenant=item.tenant, item=item, variant=obj,
                        delta_qty=obj.stock_qty, reason='initial',
                        reference_type='initial', staff=self.context['request'].user,
                    )
                keep_ids.append(obj.id)
        item.variants.exclude(id__in=keep_ids).delete()

    def create(self, validated):
        variants = validated.pop('variants', None)
        validated['tenant'] = self.context['request'].user.tenant
        item = super().create(validated)
        if variants:
            self._upsert_variants(item, variants)
        else:
            ItemVariant.objects.create(item=item, attributes={},
                                       stock_qty=int(validated.get('initial_stock') or 0))
        return item

    def update(self, instance, validated):
        variants = validated.pop('variants', None)
        item = super().update(instance, validated)
        if variants is not None:
            self._upsert_variants(item, variants)
        return item


# ---------------------------------------------------------------- customers
class CustomerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Customer
        fields = ['id', 'name', 'phone', 'notes', 'balance', 'birthday', 'created_at']


class CustomerLedgerSerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source='staff.name', read_only=True, default=None)

    class Meta:
        model = CustomerLedger
        fields = ['id', 'customer', 'type', 'amount', 'balance_after', 'note',
                  'staff_name', 'created_at']


# ---------------------------------------------------------------- sales
class PaymentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Payment
        fields = ['id', 'method', 'amount', 'reference_number', 'status']


class SaleItemSerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source='name_snapshot', read_only=True)

    class Meta:
        model = SaleItem
        fields = ['id', 'item', 'variant', 'item_name', 'name_snapshot', 'qty',
                  'unit_price', 'discount', 'cost_at_sale']


class SaleSerializer(serializers.ModelSerializer):
    items = SaleItemSerializer(many=True, read_only=True)
    payments = PaymentSerializer(many=True, read_only=True)
    staff_name = serializers.CharField(source='staff.name', read_only=True, default=None)
    customer_name = serializers.CharField(source='customer.name', read_only=True, default=None)
    cogs = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = Sale
        fields = ['id', 'receipt_number', 'branch', 'staff', 'staff_name',
                  'customer', 'customer_name', 'subtotal', 'discount_total',
                  'tax_total', 'total', 'cogs', 'status', 'void_reason',
                  'items', 'payments', 'created_at']


class CheckoutSerializer(serializers.Serializer):
    """D1–D10 checkout — transactional: sale + items + payments + stock + ledger."""

    items = serializers.ListField(child=serializers.DictField(), allow_empty=False)
    payments = serializers.ListField(child=serializers.DictField(), allow_empty=False)
    customer_id = serializers.IntegerField(required=False, allow_null=True)
    discount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False, default=Decimal('0.00'))
    discount_note = serializers.CharField(max_length=120, required=False, allow_blank=True, default='')
    held_sale_id = serializers.IntegerField(required=False, allow_null=True)

    def validate_items(self, value):
        if not value:
            raise serializers.ValidationError('Cart is empty.')
        return value


class HeldSaleSerializer(serializers.ModelSerializer):
    staff_name = serializers.CharField(source='staff.name', read_only=True, default=None)

    class Meta:
        model = HeldSale
        fields = ['id', 'label', 'payload', 'staff_name', 'created_at']


# ---------------------------------------------------------------- staff
class StaffWriteSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = User
        fields = ['id', 'name', 'phone', 'role', 'branch', 'commission_percent',
                  'active', 'password']

    def validate_phone(self, value):
        phone = normalize_phone(value)
        qs = User.objects.filter(phone=phone)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError('This phone number is already registered.')
        return phone

    def validate_role(self, value):
        requester = self.context['request'].user
        if value in ('owner', 'manager') and requester.role not in ('owner', 'manager'):
            raise serializers.ValidationError('Only managers/owners can assign elevated roles.')
        if value == 'owner' and requester.role != 'owner':
            raise serializers.ValidationError('Only the owner can create another owner.')
        return value

    def create(self, validated):
        password = validated.pop('password', None) or 'temp1234'
        validated['tenant'] = self.context['request'].user.tenant
        return User.objects.create_user(password=password, **validated)

    def update(self, instance, validated):
        password = validated.pop('password', None)
        for f, v in validated.items():
            setattr(instance, f, v)
        if password:
            instance.password = make_password_stub(password)
        instance.save()
        return instance


def make_password_stub(raw):
    from django.contrib.auth.hashers import make_password
    return make_password(raw)


# ---------------------------------------------------------------- expenses
class ExpenseSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source='category.name', read_only=True, default=None)

    class Meta:
        model = Expense
        fields = ['id', 'category', 'category_name', 'amount', 'note', 'date', 'created_at']


class ExpenseCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = ExpenseCategory
        fields = ['id', 'name']


class AppointmentSerializer(serializers.ModelSerializer):
    service_names = serializers.SerializerMethodField()
    staff_name = serializers.CharField(source='staff.name', read_only=True, default=None)
    customer_name = serializers.CharField(source='customer.name', read_only=True, default=None)

    class Meta:
        model = Appointment
        fields = ['id', 'customer', 'customer_name', 'staff', 'staff_name',
                  'services', 'service_names', 'start_time', 'duration_minutes',
                  'status', 'note']

    def get_service_names(self, obj):
        return [s.name for s in obj.services.all()]


class StockMovementSerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source='item.name', read_only=True)
    staff_name = serializers.CharField(source='staff.name', read_only=True, default=None)

    class Meta:
        model = StockMovement
        fields = ['id', 'item', 'item_name', 'variant', 'delta_qty', 'reason',
                  'reference_type', 'reference_id', 'staff_name', 'note', 'created_at']
