from django.urls import include, path
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView

from . import views
from .stock_views import StockMovementListView
from .views import (AppointmentViewSet, BranchViewSet, CatalogItemViewSet,
                    CategoryViewSet, CheckoutAPIView, CustomerViewSet,
                    ExpenseCategoryViewSet, ExpenseViewSet, HeldSaleViewSet,
                    LoginAPIView, MeAPIView, SaleViewSet, SignupAPIView,
                    StaffViewSet, TenantSettingsAPIView)

router = DefaultRouter(trailing_slash=False)
router.register('categories', CategoryViewSet, basename='categories')
router.register('items', CatalogItemViewSet, basename='items')
router.register('customers', CustomerViewSet, basename='customers')
router.register('staff', StaffViewSet, basename='staff')
router.register('expenses', ExpenseViewSet, basename='expenses')
router.register('expense-categories', ExpenseCategoryViewSet, basename='expense-categories')
router.register('sales', SaleViewSet, basename='sales')
router.register('held-sales', HeldSaleViewSet, basename='held-sales')
router.register('appointments', AppointmentViewSet, basename='appointments')
router.register('branches', BranchViewSet, basename='branches')

urlpatterns = [
    # public
    path('business-types', views.business_types),
    path('demo-accounts', views.demo_accounts),
    path('auth/signup', SignupAPIView.as_view()),
    path('auth/login', LoginAPIView.as_view()),
    path('auth/refresh', TokenRefreshView.as_view()),
    # session
    path('me', MeAPIView.as_view()),
    path('settings', TenantSettingsAPIView.as_view()),
    # pos
    path('checkout', CheckoutAPIView.as_view()),
    # reports
    path('reports/dashboard', views.report_dashboard),
    path('reports/sales', views.report_sales),
    path('reports/best-sellers', views.report_best_sellers),
    path('reports/staff-performance', views.report_staff_performance),
    path('reports/pnl', views.report_pnl),
    path('reports/debtors', views.report_debtors),
    path('reports/inventory-valuation', views.report_inventory_valuation),
    path('stock-movements', StockMovementListView.as_view()),
    path('', include(router.urls)),
]
