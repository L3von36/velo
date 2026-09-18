"""API views — all tenant-scoped, role-checked, transactional where it matters."""
from datetime import timedelta
from decimal import Decimal, ROUND_HALF_UP

from django.db import transaction
from django.db.models import Count, DecimalField, F, Q, Sum
from django.db.models.functions import Coalesce, TruncDate
from django.http import JsonResponse
from django.utils import timezone

from rest_framework import status, viewsets
from rest_framework.decorators import action, api_view, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .business_types import BUSINESS_TYPES, ROLE_MATRIX
from .models import (Appointment, Branch, CatalogItem, Category, Customer,
                     CustomerLedger, Expense, ExpenseCategory, HeldSale,
                     ItemVariant, Payment, Sale, SaleItem, StockMovement,
                     Tenant, User)
from .pagination import DefaultPagination
from .permissions import HasCapability, OwnerOnly
from .serializers import (AppointmentSerializer, BranchSerializer,
                          CatalogItemSerializer, CatalogItemWriteSerializer,
                          CategorySerializer, CustomerLedgerSerializer,
                          CustomerSerializer, ExpenseCategorySerializer,
                          ExpenseSerializer, HeldSaleSerializer,
                          LoginSerializer, MeSerializer, SaleSerializer,
                          StaffWriteSerializer, StockMovementSerializer,
                          SignupSerializer, TenantSerializer, UserSerializer)
from .tenancy import get_object_for_user, require_capability, tenant_queryset

MONEY = Decimal('0.01')


def money(v) -> Decimal:
    return Decimal(v).quantize(MONEY, rounding=ROUND_HALF_UP)


# ------------------------------------------------------------------ public
@api_view(['GET'])
@permission_classes([AllowAny])
def business_types(request):
    """Config matrix — PRD §2. Public: onboarding needs it pre-signup."""
    return Response({'results': list(BUSINESS_TYPES.values())})


@api_view(['GET'])
@permission_classes([AllowAny])
def demo_accounts(request):
    """Sandbox convenience: demo tenant logins surfaced on the login screen."""
    from django.conf import settings as dj_settings
    if not getattr(dj_settings, 'DEMO_MODE', False):
        return Response({'results': []})
    rows = []
    for u in User.objects.filter(role='owner', tenant__isnull=False).order_by('id')[:3]:
        rows.append({
            'phone': u.phone, 'password': 'demo1234', 'name': u.name,
            'tenant': u.tenant.name, 'business_type': u.tenant.business_type,
        })
    return Response({'results': rows})


class SignupAPIView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        s = SignupSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = s.save()
        return Response(_auth_payload(user), status=status.HTTP_201_CREATED)


class LoginAPIView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        s = LoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        return Response(s.validated_data)


class MeAPIView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        branches = Branch.objects.filter(tenant_id=user.tenant_id)
        return Response(MeSerializer({
            'user': user, 'tenant': user.tenant, 'branches': branches
        }).data)

    def patch(self, request):
        user = request.user
        if 'language' in request.data:
            user.tenant.language = request.data['language']
            user.tenant.save(update_fields=['language'])
        if 'name' in request.data:
            user.name = request.data['name']
            user.save(update_fields=['name'])
        if 'branch' in request.data and request.data['branch']:
            b = Branch.objects.filter(tenant_id=user.tenant_id, id=request.data['branch']).first()
            if b:
                user.branch = b
                user.save(update_fields=['branch'])
        return Response(_auth_payload_refreshed(user))


class TenantSettingsAPIView(APIView):
    permission_classes = [IsAuthenticated, HasCapability]
    required_capability = 'manage_settings'

    def patch(self, request):
        tenant = request.user.tenant
        s = TenantSerializer(tenant, data=request.data, partial=True)
        s.is_valid(raise_exception=True)
        s.save()
        return Response(s.data)


class BranchViewSet(viewsets.ModelViewSet):
    serializer_class = BranchSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return tenant_queryset(Branch, self.request.user)

    def perform_create(self, serializer):
        require_capability(self.request.user, 'manage_settings')
        serializer.save(tenant=self.request.user.tenant)

    def perform_update(self, serializer):
        require_capability(self.request.user, 'manage_settings')
        serializer.save()


def _auth_payload(user):
    from rest_framework_simplejwt.tokens import RefreshToken
    refresh = RefreshToken.for_user(user)
    refresh['role'] = user.role
    return {
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'user': UserSerializer(user).data,
    }


def _auth_payload_refreshed(user):
    return _auth_payload(user)


# ------------------------------------------------------------------ catalog
class CategoryViewSet(viewsets.ModelViewSet):
    serializer_class = CategorySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return tenant_queryset(Category, self.request.user).annotate(
            item_count=Coalesce(Sum('items__id'), Decimal('0'), output_field=DecimalField())
        )

    def perform_create(self, serializer):
        serializer.save(tenant=self.request.user.tenant)

    def perform_destroy(self, instance):
        """C2: deleting a category never orphans items — they go uncategorized."""
        instance.items.update(category=None)
        instance.delete()


class CatalogItemViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated]
    pagination_class = DefaultPagination

    def get_serializer_class(self):
        if self.action in ('create', 'update', 'partial_update'):
            return CatalogItemWriteSerializer
        return CatalogItemSerializer

    def get_queryset(self):
        qs = tenant_queryset(CatalogItem, self.request.user).select_related('category').prefetch_related('variants')
        p = self.request.query_params
        if p.get('type'):
            qs = qs.filter(type=p['type'])
        if p.get('category'):
            qs = qs.filter(category_id=p['category'])
        if p.get('search'):
            term = p['search']
            qs = qs.filter(Q(name__icontains=term) | Q(barcode=term))
        if p.get('barcode'):
            qs = qs.filter(barcode=p['barcode'])
        if p.get('low_stock') == '1':
            qs = qs.filter(type='product', requires_stock=True).annotate(
                total_stock=Coalesce(Sum('variants__stock_qty'), 0)
            ).filter(total_stock__lte=F('low_stock_threshold'))
        return qs

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data, context={'request': request})
        s.is_valid(raise_exception=True)
        item = s.save()
        return Response(CatalogItemSerializer(item).data, status=201)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop('partial', False)
        instance = self.get_object()
        s = self.get_serializer(instance, data=request.data, partial=partial, context={'request': request})
        s.is_valid(raise_exception=True)
        item = s.save()
        return Response(CatalogItemSerializer(item).data)

    @action(detail=True, methods=['post'])
    def stock_adjust(self, request, pk=None):
        """E1 — manual stock correction; always audit-logged."""
        item = self.get_object()
        variant = None
        if request.data.get('variant_id'):
            variant = item.variants.filter(id=request.data['variant_id']).first()
        if variant is None:
            variant = item.variants.first()
        if variant is None:
            raise ValidationError('This item has no stock variant to adjust.')
        mode = request.data.get('mode', 'delta')  # delta | set
        try:
            if mode == 'set':
                new_qty = int(request.data['new_qty'])
                delta = new_qty - variant.stock_qty
            else:
                delta = int(request.data['delta'])
        except (KeyError, TypeError, ValueError):
            raise ValidationError('Provide a valid quantity.')
        if delta == 0:
            return Response({'detail': 'No change.', 'stock_qty': variant.stock_qty})
        if variant.stock_qty + delta < 0:
            raise ValidationError(f'Cannot go below zero (current {variant.stock_qty}).')
        reason = request.data.get('reason', 'other')
        with transaction.atomic():
            variant.stock_qty = F('stock_qty') + delta
            variant.save(update_fields=['stock_qty'])
            variant.refresh_from_db()
            StockMovement.objects.create(
                tenant=request.user.tenant, branch=request.user.branch, item=item,
                variant=variant, delta_qty=delta, reason=reason,
                reference_type='adjustment', staff=request.user,
                note=request.data.get('note', ''),
            )
        return Response({'stock_qty': variant.stock_qty})

    @action(detail=True, methods=['get'])
    def history(self, request, pk=None):
        item = self.get_object()
        movements = StockMovement.objects.filter(item=item).select_related('staff')[:100]
        sales = Sale.objects.filter(tenant=request.user.tenant, items__item=item).distinct()[:20]
        return Response({
            'stock_movements': StockMovementSerializer(movements, many=True).data,
            'recent_sales': SaleSerializer(_with_cogs(sales), many=True).data,
        })


def _with_cogs(qs):
    return qs


# ------------------------------------------------------------------ customers
class CustomerViewSet(viewsets.ModelViewSet):
    serializer_class = CustomerSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = tenant_queryset(Customer, self.request.user)
        p = self.request.query_params
        if p.get('search'):
            term = p['search']
            qs = qs.filter(Q(name__icontains=term) | Q(phone__icontains=term))
        if p.get('debtors') == '1':
            qs = qs.filter(balance__gt=0).order_by('-balance')
        if p.get('sort') == 'top_spender':
            qs = qs.annotate(spent=Coalesce(Sum('sales__total'), Decimal('0'),
                                            output_field=DecimalField())).order_by('-spent')
        return qs

    def perform_create(self, serializer):
        phone = serializer.validated_data.get('phone')
        if phone:
            dup = tenant_queryset(Customer, self.request.user).filter(phone=phone).first()
            if dup:
                raise ValidationError({'phone': f'Customer with this phone already exists: {dup.name}.'})
        serializer.save(tenant=self.request.user.tenant)

    @action(detail=True, methods=['get'])
    def detail(self, request, pk=None):
        customer = self.get_object()
        sales = Sale.objects.filter(customer=customer)[:50]
        ledger = customer.ledger_entries.select_related('staff')[:100]
        return Response({
            'customer': CustomerSerializer(customer).data,
            'sales': SaleSerializer(sales, many=True).data,
            'ledger': CustomerLedgerSerializer(ledger, many=True).data,
        })

    @action(detail=True, methods=['post'])
    def ledger(self, request, pk=None):
        """F4 — append-only credit/debt entry (charge|payment|adjustment)."""
        customer = self.get_object()
        entry_type = request.data.get('type')
        if entry_type not in ('charge', 'payment', 'adjustment'):
            raise ValidationError('type must be charge | payment | adjustment.')
        try:
            amount = money(request.data['amount'])
        except (KeyError, TypeError, ValueError, ArithmeticError):
            raise ValidationError('Provide a valid amount.')
        if amount <= 0:
            raise ValidationError('Amount must be positive.')
        with transaction.atomic():
            if entry_type == 'charge':
                customer.balance = money(customer.balance + amount)
            else:  # payment or negative adjustment
                customer.balance = money(customer.balance - amount)
            customer.save(update_fields=['balance'])
            entry = CustomerLedger.objects.create(
                tenant=request.user.tenant, customer=customer, type=entry_type,
                amount=amount, balance_after=customer.balance,
                note=request.data.get('note', ''), staff=request.user,
            )
        return Response(CustomerLedgerSerializer(entry).data, status=201)


# ------------------------------------------------------------------ staff
class StaffViewSet(viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated, HasCapability]
    required_capability = 'manage_staff'
    serializer_class = StaffWriteSerializer

    def get_queryset(self):
        return tenant_queryset(User, self.request.user).select_related('branch')

    def list(self, request, *args, **kwargs):
        qs = self.get_queryset()
        data = []
        today = timezone.localdate()
        for u in qs:
            row = UserSerializer(u).data
            todays = Sale.objects.filter(staff=u, created_at__date=today, status='completed')
            row['sales_today_count'] = todays.count()
            row['sales_today_total'] = money(todays.aggregate(t=Coalesce(Sum('total'), Decimal('0')))['t'])
            data.append(row)
        return Response({'results': data})

    def destroy(self, request, *args, **kwargs):
        staff = self.get_object()
        if staff.role == 'owner':
            raise ValidationError('The owner account cannot be deactivated from staff settings.')
        staff.active = False
        staff.save(update_fields=['active'])
        return Response({'detail': 'Staff deactivated.'})


# ------------------------------------------------------------------ expenses
class ExpenseViewSet(viewsets.ModelViewSet):
    serializer_class = ExpenseSerializer
    permission_classes = [IsAuthenticated, HasCapability]
    required_capability = 'manage_expenses'

    def get_queryset(self):
        qs = tenant_queryset(Expense, self.request.user).select_related('category')
        p = self.request.query_params
        if p.get('category'):
            qs = qs.filter(category_id=p['category'])
        if p.get('month'):
            from datetime import date
            y, m = p['month'].split('-')
            start = date(int(y), int(m), 1)
            nxt = date(int(y) + (int(m) == 12), (int(m) % 12) + 1, 1)
            qs = qs.filter(date__gte=start, date__lt=nxt)
        return qs

    def perform_create(self, serializer):
        serializer.save(tenant=self.request.user.tenant, staff=self.request.user,
                        branch=self.request.user.branch)


class ExpenseCategoryViewSet(viewsets.ModelViewSet):
    serializer_class = ExpenseCategorySerializer
    permission_classes = [IsAuthenticated, HasCapability]
    required_capability = 'manage_expenses'

    def get_queryset(self):
        return tenant_queryset(ExpenseCategory, self.request.user)

    def perform_create(self, serializer):
        serializer.save(tenant=self.request.user.tenant)


# ------------------------------------------------------------------ checkout
class CheckoutAPIView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        data = request.data
        cart = data.get('items') or []
        pays = data.get('payments') or []
        if not cart or not pays:
            raise ValidationError('Cart and payments are required.')

        user = request.user
        tenant = user.tenant
        branch = user.branch or Branch.objects.filter(tenant=tenant, is_default=True).first()

        with transaction.atomic():
            sale = Sale(tenant=tenant, branch=branch, staff=user)
            sale.receipt_number = (Sale.objects.filter(tenant=tenant)
                                   .order_by('-receipt_number')
                                   .values_list('receipt_number', flat=True).first() or 0) + 1

            subtotal = Decimal('0.00')
            discount_total = money(data.get('discount') or 0)
            cogs = Decimal('0.00')
            sale_items = []

            customer = None
            if data.get('customer_id'):
                customer = get_object_for_user(Customer, data['customer_id'], user)

            for line in cart:
                item = get_object_for_user(CatalogItem, line.get('item_id'), user)
                variant = None
                if line.get('variant_id'):
                    variant = item.variants.filter(id=line['variant_id']).first()
                if variant is None:
                    variant = item.variants.first()
                unit_price = money(variant.effective_price if variant and variant.price_override is not None else item.price)
                qty = Decimal(str(line.get('qty') or 1)).quantize(Decimal('0.01'))
                line_discount = money(line.get('discount') or 0)
                if qty <= 0:
                    raise ValidationError('Quantity must be positive.')
                if unit_price < 0 or line_discount < 0:
                    raise ValidationError('Negative amounts are not allowed.')

                if item.type == 'product' and item.requires_stock and variant is not None:
                    if variant.stock_qty < qty:
                        raise ValidationError(
                            f'Not enough stock for {item.name} (available {variant.stock_qty}).')
                    variant.stock_qty = F('stock_qty') - qty
                    variant.save(update_fields=['stock_qty'])
                    StockMovement.objects.create(
                        tenant=tenant, branch=branch, item=item, variant=variant,
                        delta_qty=-qty, reason='sale', reference_type='sale',
                        staff=user,
                    )

                line_total = (unit_price * qty) - line_discount
                subtotal += line_total
                cogs += (item.cost or Decimal('0.00')) * qty
                sale_items.append(SaleItem(
                    item=item, variant=variant, name_snapshot=item.name,
                    qty=qty, unit_price=unit_price, discount=line_discount,
                    cost_at_sale=(item.cost or Decimal('0.00')) * qty,
                ))

            subtotal = money(subtotal)
            total = money(subtotal - discount_total)
            if tenant.tax_enabled:
                tax = money(total * (tenant.tax_rate_percent / Decimal('100')))
                total = money(total + tax)
            else:
                tax = Decimal('0.00')

            sale.subtotal = subtotal
            sale.discount_total = discount_total
            sale.tax_total = tax
            sale.total = total
            sale.save()

            for si in sale_items:
                si.sale = sale
            SaleItem.objects.bulk_create(sale_items)

            paid = Decimal('0.00')
            credit_amount = Decimal('0.00')
            for pay in pays:
                method = pay.get('method')
                if method not in ('cash', 'telebirr', 'cbe', 'credit'):
                    raise ValidationError(f'Unknown payment method: {method}')
                amount = money(pay.get('amount') or 0)
                if amount <= 0:
                    continue
                if method == 'credit':
                    if customer is None:
                        raise ValidationError('Credit sales require a customer (no walk-in credit).')
                    if not tenant.accept_credit:
                        raise ValidationError('Credit sales are disabled in settings.')
                    credit_amount += amount
                    Payment.objects.create(sale=sale, method='credit', amount=amount,
                                           status='verified')
                else:
                    ref = (pay.get('reference_number') or '').strip()
                    if method == 'telebirr' and not tenant.accept_telebirr:
                        raise ValidationError('Telebirr is disabled in settings.')
                    if method == 'cbe' and not tenant.accept_cbe:
                        raise ValidationError('CBE Birr is disabled in settings.')
                    if method in ('telebirr', 'cbe') and ref:
                        # D5: reference entered → pending verification (manual gateway in Phase 3)
                        Payment.objects.create(sale=sale, method=method, amount=amount,
                                               reference_number=ref, status='pending_verification')
                    elif method in ('telebirr', 'cbe'):
                        Payment.objects.create(sale=sale, method=method, amount=amount,
                                               reference_number=ref, status='manual')
                    else:
                        Payment.objects.create(sale=sale, method=method, amount=amount,
                                               status='verified')
                paid += amount

            if paid < total:
                shortfall = money(total - paid)
                if customer is None:
                    raise ValidationError(f'Payment short by {shortfall} ETB.')
                # Remainder goes on the customer's account automatically.
                credit_amount += shortfall
                Payment.objects.create(sale=sale, method='credit', amount=shortfall, status='verified')

            if credit_amount > 0 and customer is not None:
                customer.balance = money(customer.balance + credit_amount)
                customer.save(update_fields=['balance'])
                CustomerLedger.objects.create(
                    tenant=tenant, customer=customer, type='charge',
                    amount=credit_amount, balance_after=customer.balance,
                    note=f'Credit sale #{sale.receipt_number}', staff=user, sale=sale,
                )

            if data.get('held_sale_id'):
                HeldSale.objects.filter(tenant=tenant, id=data['held_sale_id']).delete()

        return Response(SaleSerializer(sale).data, status=201)


# ------------------------------------------------------------------ sales
def _sale_queryset(user):
    return Sale.objects.filter(tenant_id=user.tenant_id).select_related(
        'staff', 'customer', 'branch').prefetch_related('items', 'payments')


class SaleViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = SaleSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = DefaultPagination

    def get_queryset(self):
        qs = _sale_queryset(self.request.user)
        p = self.request.query_params
        if p.get('date_from'):
            qs = qs.filter(created_at__date__gte=p['date_from'])
        if p.get('date_to'):
            qs = qs.filter(created_at__date__lte=p['date_to'])
        if p.get('staff_id'):
            qs = qs.filter(staff_id=p['staff_id'])
        if p.get('customer_id'):
            qs = qs.filter(customer_id=p['customer_id'])
        if p.get('method'):
            qs = qs.filter(payments__method=p['method'])
        if p.get('search'):
            qs = qs.filter(receipt_number__icontains=p['search'].lstrip('#'))
        return qs

    @action(detail=True, methods=['post'])
    def refund(self, request, pk=None):
        """D15 — void/refund with full audit trail + stock restore."""
        require_capability(request.user, 'void_sales')
        sale = self.get_object()
        if sale.status != 'completed':
            raise ValidationError('Only completed sales can be refunded.')
        reason = request.data.get('reason') or 'Not specified'
        with transaction.atomic():
            sale.status = 'refunded'
            sale.void_reason = reason
            sale.save(update_fields=['status', 'void_reason'])
            for si in sale.items.select_related('variant', 'item'):
                if si.variant is not None and si.item.type == 'product':
                    si.variant.stock_qty = F('stock_qty') + si.qty
                    si.variant.save(update_fields=['stock_qty'])
                    StockMovement.objects.create(
                        tenant=sale.tenant, branch=sale.branch, item=si.item,
                        variant=si.variant, delta_qty=si.qty, reason='refund',
                        reference_type='sale', reference_id=str(sale.id),
                        staff=request.user, note=f'Refund: {reason}',
                    )
            credit = sale.payments.filter(method='credit').aggregate(t=Coalesce(Sum('amount'), Decimal('0')))['t']
            if credit > 0 and sale.customer_id:
                cust = sale.customer
                cust.balance = money(max(Decimal('0.00'), cust.balance - credit))
                cust.save(update_fields=['balance'])
                CustomerLedger.objects.create(
                    tenant=sale.tenant, customer=cust, type='adjustment',
                    amount=credit, balance_after=cust.balance,
                    note=f'Refund sale #{sale.receipt_number}', staff=request.user, sale=sale,
                )
        return Response(SaleSerializer(sale).data)


class HeldSaleViewSet(viewsets.ModelViewSet):
    serializer_class = HeldSaleSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return tenant_queryset(HeldSale, self.request.user)

    def perform_create(self, serializer):
        serializer.save(tenant=self.request.user.tenant, staff=self.request.user,
                        branch=self.request.user.branch)


# ------------------------------------------------------------------ appointments (P2 — model-ready)
class AppointmentViewSet(viewsets.ModelViewSet):
    serializer_class = AppointmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = tenant_queryset(Appointment, self.request.user).select_related('staff', 'customer').prefetch_related('services')
        if self.request.query_params.get('date'):
            qs = qs.filter(start_time__date=self.request.query_params['date'])
        return qs

    def perform_create(self, serializer):
        serializer.save(tenant=self.request.user.tenant, branch=self.request.user.branch)


# ------------------------------------------------------------------ reports (J1–J7)
def _range_params(request):
    today = timezone.localdate()
    default_from = today - timedelta(days=30)
    try:
        date_from = timezone.datetime.fromisoformat(request.query_params.get('from', str(default_from))).date()
        date_to = timezone.datetime.fromisoformat(request.query_params.get('to', str(today))).date()
    except ValueError:
        date_from, date_to = default_from, today
    return date_from, date_to


def _completed_sales(user, date_from, date_to):
    return Sale.objects.filter(
        tenant_id=user.tenant_id, status='completed',
        created_at__date__gte=date_from, created_at__date__lte=date_to,
    )


@api_view(['GET'])
def report_dashboard(request):
    user = request.user
    today = timezone.localdate()
    yesterday = today - timedelta(days=1)

    def day_total(d):
        return _completed_sales(user, d, d).aggregate(t=Coalesce(Sum('total'), Decimal('0')))['t']

    today_sales = day_total(today)
    yesterday_sales = day_total(yesterday)
    week_start = today - timedelta(days=today.weekday())
    week_sales = _completed_sales(user, week_start, today).aggregate(t=Coalesce(Sum('total'), Decimal('0')))['t']

    top_items = (SaleItem.objects.filter(sale__tenant_id=user.tenant_id, sale__status='completed',
                                         sale__created_at__date=today)
                 .values('name_snapshot')
                 .annotate(qty_sum=Sum('qty'),
                           revenue=Sum(F('qty') * F('unit_price'), output_field=DecimalField()))
                 .order_by('-qty_sum')[:3])

    low_stock = 0
    if user.tenant.sells_products:
        low_stock = (CatalogItem.objects.filter(tenant_id=user.tenant_id, type='product',
                                                requires_stock=True, is_active=True)
                     .annotate(total_stock=Coalesce(Sum('variants__stock_qty'), 0))
                     .filter(total_stock__lte=F('low_stock_threshold')).count())

    my_sales_today = _completed_sales(user, today, today).filter(staff=user).count()
    pending_verify = Payment.objects.filter(sale__tenant_id=user.tenant_id, status='pending_verification').count()

    return Response({
        'today': {'total': money(today_sales), 'count': _completed_sales(user, today, today).count(),
                  'yesterday_total': money(yesterday_sales),
                  'trend_pct': (float((today_sales - yesterday_sales) / yesterday_sales * 100)
                                if yesterday_sales else None)},
        'week_total': money(week_sales),
        'top_items': [{'name': r['name_snapshot'], 'qty': float(r['qty_sum']), 'revenue': money(r['revenue'])} for r in top_items],
        'low_stock_count': low_stock,
        'my_sales_today': my_sales_today,
        'pending_verifications': pending_verify,
    })


@api_view(['GET'])
def report_sales(request):
    user = request.user
    date_from, date_to = _range_params(request)
    sales = _completed_sales(user, date_from, date_to)

    series = (sales.annotate(day=TruncDate('created_at'))
              .values('day')
              .annotate(total=Coalesce(Sum('total'), Decimal('0')), count=Count('id'))
              .order_by('day'))

    by_method = (Payment.objects.filter(sale__in=sales)
                 .values('method')
                 .annotate(total=Coalesce(Sum('amount'), Decimal('0')), count=Count('id')))

    by_staff = (sales.values('staff__name')
                .annotate(total=Coalesce(Sum('total'), Decimal('0')), count=Count('id'))
                .order_by('-total'))

    agg = sales.aggregate(total=Coalesce(Sum('total'), Decimal('0')), count=Count('id'))
    count = agg['count'] or 0

    return Response({
        'range': {'from': str(date_from), 'to': str(date_to)},
        'total': money(agg['total']), 'count': count,
        'average': money(agg['total'] / count) if count else Decimal('0.00'),
        'series': [{'date': str(r['day']), 'total': money(r['total']), 'count': r['count']} for r in series],
        'by_method': [{'method': r['method'], 'total': money(r['total']), 'count': r['count']} for r in by_method],
        'by_staff': [{'staff': r['staff__name'] or '—', 'total': money(r['total']), 'count': r['count']} for r in by_staff],
    })


@api_view(['GET'])
def report_best_sellers(request):
    user = request.user
    date_from, date_to = _range_params(request)
    by = request.query_params.get('by', 'qty')  # qty | revenue
    lines = SaleItem.objects.filter(sale__tenant_id=user.tenant_id, sale__status='completed',
                                    sale__created_at__date__gte=date_from,
                                    sale__created_at__date__lte=date_to)
    if request.query_params.get('category'):
        lines = lines.filter(item__category_id=request.query_params['category'])
    order = '-revenue' if by == 'revenue' else '-qty_sum'
    rows = (lines.values('name_snapshot')
            .annotate(qty_sum=Sum('qty'),
                      revenue=Sum(F('qty') * F('unit_price'), output_field=DecimalField()))
            .order_by(order)[:20])
    return Response({'results': [
        {'name': r['name_snapshot'], 'qty': float(r['qty_sum']), 'revenue': money(r['revenue'])} for r in rows
    ]})


@api_view(['GET'])
def report_staff_performance(request):
    require_capability(request.user, 'view_reports')
    user = request.user
    date_from, date_to = _range_params(request)
    sales = _completed_sales(user, date_from, date_to)
    rows = (sales.values('staff__name', 'staff__role')
            .annotate(total=Coalesce(Sum('total'), Decimal('0')), count=Count('id'))
            .order_by('-total'))
    return Response({'results': [
        {'staff': r['staff__name'] or '—', 'role': r['staff__role'],
         'total': money(r['total']), 'count': r['count']} for r in rows
    ]})


@api_view(['GET'])
def report_pnl(request):
    user = request.user
    date_from, date_to = _range_params(request)
    sales = _completed_sales(user, date_from, date_to)
    revenue = sales.aggregate(t=Coalesce(Sum('total'), Decimal('0')))['t']
    cogs = sales.aggregate(c=Coalesce(Sum('items__cost_at_sale'), Decimal('0')))['c']
    expenses = Expense.objects.filter(tenant_id=user.tenant_id, date__gte=date_from, date__lte=date_to)
    expense_rows = list(expenses.values('category__name').annotate(total=Coalesce(Sum('amount'), Decimal('0'))))
    expense_total = sum((r['total'] for r in expense_rows), Decimal('0'))
    missing_cost = CatalogItem.objects.filter(
        tenant_id=user.tenant_id, type='product', cost__isnull=True).count()
    return Response({
        'range': {'from': str(date_from), 'to': str(date_to)},
        'revenue': money(revenue), 'cogs': money(cogs),
        'gross_profit': money(revenue - cogs),
        'expenses': [{'category': r['category__name'] or 'Other', 'total': money(r['total'])} for r in expense_rows],
        'expense_total': money(expense_total),
        'net_profit': money(revenue - cogs - expense_total),
        'estimate_warning': missing_cost > 0,
        'missing_cost_items': missing_cost,
    })


@api_view(['GET'])
def report_debtors(request):
    user = request.user
    rows = (tenant_queryset(Customer, user).filter(balance__gt=0)
            .order_by('-balance').values('id', 'name', 'phone', 'balance'))
    total = sum((r['balance'] for r in rows), Decimal('0'))
    return Response({'total_outstanding': money(total), 'results': list(rows)})


@api_view(['GET'])
def report_inventory_valuation(request):
    user = request.user
    items = (CatalogItem.objects.filter(tenant_id=user.tenant_id, type='product', requires_stock=True)
             .annotate(stock=Coalesce(Sum('variants__stock_qty'), 0)))
    at_cost = sum(((i.cost or Decimal('0')) * i.stock for i in items), Decimal('0'))
    at_retail = sum((i.price * i.stock for i in items), Decimal('0'))
    slow = [{'name': i.name, 'stock': i.stock} for i in items if i.stock > (i.low_stock_threshold * 10 + 20)][:10]
    return Response({'value_at_cost': money(at_cost), 'value_at_retail': money(at_retail),
                     'slow_moving': slow})
