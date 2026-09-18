"""Simple stock movement list (audit trail, E1/C6)."""
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import StockMovement
from .serializers import StockMovementSerializer
from .tenancy import tenant_queryset


class StockMovementListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = tenant_queryset(StockMovement, request.user).select_related('item', 'staff')[:200]
        if request.query_params.get('item'):
            qs = qs.filter(item_id=request.query_params['item'])[:100]
        return Response({'results': StockMovementSerializer(qs, many=True).data})
