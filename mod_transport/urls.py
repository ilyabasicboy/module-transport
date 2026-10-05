from django.urls import path

from .views import InfoView, RootView


app_name = 'mod_transport'

urlpatterns = [
    path('', RootView.as_view(), name='root'),
    path('info/', InfoView.as_view(), name='info'),
]
