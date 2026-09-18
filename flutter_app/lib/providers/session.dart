import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../api/api_client.dart';
import '../models/models.dart';

/// Global app state: session, locale, connectivity, theme.

enum AppPhase { boot, language, loggedOut, onboarding, ready }

class SessionState {
  const SessionState({
    this.phase = AppPhase.boot,
    this.user,
    this.tenant,
    this.branches = const [],
    this.errorMessage,
  });

  final AppPhase phase;
  final UserAccount? user;
  final TenantInfo? tenant;
  final List<BranchInfo> branches;
  final String? errorMessage;

  bool get isOwnerOrManager => user?.role == 'owner' || user?.role == 'manager';
  bool get canViewReports => user?.can('view_reports') ?? false;
  bool get canManageStaff => user?.can('manage_staff') ?? false;
  bool get canEditPrices => user?.can('edit_prices') ?? false;
  bool get canVoidSales => user?.can('void_sales') ?? true;
  bool get canManageSettings => user?.can('manage_settings') ?? false;
  bool get canManageExpenses => user?.can('manage_expenses') ?? true;

  SessionState copyWith({
    AppPhase? phase,
    UserAccount? user,
    TenantInfo? tenant,
    List<BranchInfo>? branches,
    String? errorMessage,
  }) =>
      SessionState(
        phase: phase ?? this.phase,
        user: user ?? this.user,
        tenant: tenant ?? this.tenant,
        branches: branches ?? this.branches,
        errorMessage: errorMessage,
      );
}

class SessionController extends AsyncNotifier<SessionState> {
  Api get _api => Api();

  @override
  Future<SessionState> build() async {
    await ApiClient.I.loadTokens();
    // Restore language preference before anything (A2).
    final sp = await SharedPreferences.getInstance();
    final lang = sp.getString('lang');

    if (!ApiClient.I.hasTokens) {
      return SessionState(phase: lang == null ? AppPhase.language : AppPhase.loggedOut);
    }
    // Silent restore — me() may 401 if refresh failed.
    try {
      final me = await _api.me();
      final user = UserAccount.fromJson(me['user'] as Map<String, dynamic>);
      final tenant = TenantInfo.fromJson(me['tenant'] as Map<String, dynamic>);
      final branches = ((me['branches'] ?? []) as List)
          .map((e) => BranchInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      if (lang != null && lang != tenant.language) {
        // local preference wins until changed in Settings
      }
      return SessionState(
        phase: AppPhase.ready,
        user: user,
        tenant: tenant,
        branches: branches,
      );
    } catch (_) {
      await ApiClient.I.clearTokens();
      return SessionState(phase: lang == null ? AppPhase.language : AppPhase.loggedOut);
    }
  }

  Future<void> setLanguage(String lang) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('lang', lang);
    ref.read(localeProvider.notifier).set(lang);
  }

  Future<String> currentLanguage() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('lang') ?? 'en';
  }

  Future<void> login(String phone, String password) async {
    final prev = state.value ?? const SessionState();
    state = AsyncData(prev.copyWith(errorMessage: null));
    final d = await _api.login(phone, password);
    await ApiClient.I.saveTokens(d['access'] as String, d['refresh'] as String);
    final user = UserAccount.fromJson(d['user'] as Map<String, dynamic>);
    // Fetch tenant context.
    final me = await _api.me();
    final tenant = TenantInfo.fromJson(me['tenant'] as Map<String, dynamic>);
    final branches = ((me['branches'] ?? []) as List)
        .map((e) => BranchInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    ref.read(localeProvider.notifier).set(tenant.language);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('lang', tenant.language);
    state = AsyncData(SessionState(phase: AppPhase.ready, user: user, tenant: tenant, branches: branches));
  }

  Future<void> signup(Map<String, dynamic> payload) async {
    final d = await _api.signup(payload);
    await ApiClient.I.saveTokens(d['access'] as String, d['refresh'] as String);
    final user = UserAccount.fromJson(d['user'] as Map<String, dynamic>);
    final me = await _api.me();
    final tenant = TenantInfo.fromJson(me['tenant'] as Map<String, dynamic>);
    final branches = ((me['branches'] ?? []) as List)
        .map((e) => BranchInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    state = AsyncData(SessionState(
      phase: AppPhase.onboarding, // new tenants land on the wizard
      user: user,
      tenant: tenant,
      branches: branches,
    ));
  }

  Future<void> finishOnboarding() async {
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(phase: AppPhase.ready));
  }

  Future<void> refreshTenant() async {
    try {
      final me = await _api.me();
      final tenant = TenantInfo.fromJson(me['tenant'] as Map<String, dynamic>);
      final user = UserAccount.fromJson(me['user'] as Map<String, dynamic>);
      final s = state.value;
      if (s != null) state = AsyncData(s.copyWith(tenant: tenant, user: user));
    } catch (_) {/* keep old tenant on failure */}
  }

  Future<void> logout() async {
    await ApiClient.I.clearTokens();
    state = const AsyncData(SessionState(phase: AppPhase.loggedOut));
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, SessionState>(SessionController.new);

/// Locale controller (en | am).
class LocaleController extends Notifier<String> {
  @override
  String build() => 'en';

  void set(String lang) => state = lang;
}

final localeProvider = NotifierProvider<LocaleController, String>(LocaleController.new);

/// Theme mode controller persisted locally.
class ThemeController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    state = !state;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('dark', state);
  }

  Future<void> restore() async {
    final sp = await SharedPreferences.getInstance();
    state = sp.getBool('dark') ?? false;
  }
}

final darkModeProvider = NotifierProvider<ThemeController, bool>(ThemeController.new);
