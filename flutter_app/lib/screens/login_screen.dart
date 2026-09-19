import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../api/api.dart';
import '../providers/session.dart';
import '../theme/app_theme.dart' show AppTheme;
import '../utils/format.dart';
import '../widgets/common.dart';
import 'signup_screen.dart';

/// A3 + landing page — phone-first login (matches how Ethiopians register
/// for services). Premium "Emerald Pro" landing: gradient hero with brand
/// story + feature pills on top, clean sign-in sheet below; split panel
/// with the full pitch on wide screens.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.initialPhone});

  /// Pre-filled phone (e.g. arriving from signup "already exists" shortcut).
  final String? initialPhone;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _demos = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) {
      _phone.text = widget.initialPhone!;
    }
    _loadDemos();
  }

  Future<void> _loadDemos() async {
    try {
      final demos = await Api().demoAccounts();
      if (mounted) setState(() => _demos = demos);
    } catch (_) {/* optional */}
  }

  Future<void> _submit() async {
    final norm = EthPhone.normalize(_phone.text);
    if (norm == null || _password.text.isEmpty) {
      setState(() => _error = 'Enter a valid Ethiopian phone number and password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(norm, _password.text);
      // Success: reveal whatever the root router now renders (HomeShell).
      // If this login screen was pushed on top of the app (e.g. from signup),
      // it must be popped — otherwise the user stays stuck on the form even
      // though the session is live.
      if (mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLanguage() async {
    final am = Localizations.localeOf(context).languageCode == 'am';
    final next = am ? 'en' : 'am';
    await ref.read(sessionProvider.notifier).setLanguage(next);
    ref.read(localeProvider.notifier).set(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width > 800;

    // ── Sign-in form (shared by both layouts) ────────────────────────────
    final form = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppTheme.rSm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Text(t(context).welcomeBack,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(t(context).loginSubtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t(context).phoneNumber,
                hintText: t(context).phoneHint,
                prefixIcon: const Icon(Icons.phone_android_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: t(context).password,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.seed,
                foregroundColor: Colors.white,
              ),
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: theme.colorScheme.onPrimary))
                  : Text(t(context).login),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SignupScreen()),
              ),
              child: Text('${t(context).noAccount} ${t(context).signup}'),
            ),
            if (_demos.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(t(context).demoAccounts,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
                ],
              ),
              const SizedBox(height: 10),
              ..._demos.map((d) => _DemoTile(d: d, onPick: _fillDemo)),
            ],
          ],
        ),
      ),
    );

    if (!wide) {
      // ── Mobile: gradient hero + white sheet ────────────────────────────
      // The gradient fills the whole body so the sheet's rounded top
      // corners reveal it — clean overlap without transform hacks.
      return Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppTheme.authGradient),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 4),
                    child: _LanguagePill(onToggle: _toggleLanguage),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  builder: (context, s, child) =>
                      Transform.scale(scale: s, child: child),
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const BrandMark(size: 64, radius: 18),
                      ),
                      const SizedBox(height: 12),
                      const Text('Velo',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 29,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.9)),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          t(context).tagline,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _HeroPills(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
                // Sheet with rounded top — carries the form (theme-aware).
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.rXl)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Center(child: form),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Wide: branded pitch panel + form ──────────────────────────────────
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
              child: Stack(
                children: [
                  Positioned(
                    right: -80,
                    top: -80,
                    child: _circle(260, Colors.white.withValues(alpha: 0.05)),
                  ),
                  Positioned(
                    left: -60,
                    bottom: -60,
                    child: _circle(220, Colors.white.withValues(alpha: 0.04)),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const BrandMark(size: 46, radius: 13),
                                const SizedBox(width: 12),
                                Text('Velo',
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5)),
                              ],
                            ),
                            const SizedBox(height: 26),
                            Text('One app.\nEvery kind of shop.',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                    color: Colors.white, height: 1.2)),
                            const SizedBox(height: 12),
                            Text(t(context).tagline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75))),
                            const SizedBox(height: 30),
                            _feature(Icons.bolt_rounded,
                                'Sell in seconds — POS built for speed'),
                            _feature(Icons.document_scanner_rounded,
                                'Scan barcodes straight into the cart'),
                            _feature(Icons.people_alt_rounded,
                                'Track customer credit with a tamper-proof ledger'),
                            _feature(Icons.insights_rounded,
                                'Know your numbers — daily profit & best sellers'),
                            const SizedBox(height: 22),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _badge('ETB', Icons.payments_rounded),
                                _badge('አማርኛ · English', Icons.translate_rounded),
                                _badge('Telebirr · CBE', Icons.account_balance_rounded),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 480,
            child: SafeArea(child: Center(child: SingleChildScrollView(child: form))),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _feature(IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white.withValues(alpha: 0.88))),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _fillDemo(Map<String, dynamic> d) {
    _phone.text = '${d['phone']}';
    _password.text = '${d['password']}';
    setState(() => _error = null);
  }
}

/// Row of glassy feature icons in the mobile hero.
class _HeroPills extends StatelessWidget {
  const _HeroPills();

  static const _items = [
    Icons.point_of_sale_rounded,
    Icons.document_scanner_rounded,
    Icons.people_alt_rounded,
    Icons.insights_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38),
            ),
            child: Icon(_items[i], size: 20, color: Colors.white),
          ),
        ],
      ],
    );
  }
}

/// Compact EN/አማ toggle pill for the hero corner.
class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.onToggle});
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final am = Localizations.localeOf(context).languageCode == 'am';
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate_rounded,
                  size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              Text(am ? 'አማ' : 'EN',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Demo account tile — tonal card with bolt icon.
class _DemoTile extends StatelessWidget {
  const _DemoTile({required this.d, required this.onPick});
  final Map<String, dynamic> d;
  final void Function(Map<String, dynamic>) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.rSm),
          onTap: () => onPick(d),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.bolt_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${d['tenant']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text('${d['phone']}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
