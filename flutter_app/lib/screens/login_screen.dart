import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../api/api.dart';
import '../providers/session.dart';
import '../theme/app_theme.dart' show AppTheme;
import '../utils/format.dart';
import '../widgets/common.dart';
import 'signup_screen.dart';

/// A3 — phone-first login (matches how Ethiopians register for services).
/// v2: branded gradient panel on wide screens, card-less mobile layout.
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
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width > 800;

    final form = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: wide ? 0 : 24),
            Center(child: BrandMark(size: 76, radius: 22)),
            const SizedBox(height: 20),
            Text(t(context).welcomeBack,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(t(context).tagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 28),
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
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t(context).phoneNumber,
                hintText: t(context).phoneHint,
                prefixIcon: const Icon(Icons.phone_android_rounded),
              ),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
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
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SignupScreen()),
              ),
              child: Text('${t(context).noAccount} ${t(context).signup}'),
            ),
            if (_demos.isNotEmpty) ...[
              const SizedBox(height: 20),
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
              const SizedBox(height: 12),
              ..._demos.map((d) => _DemoTile(d: d, onPick: _fillDemo)),
            ],
          ],
        ),
      ),
    );

    if (!wide) {
      return Scaffold(
        body: SafeArea(
          child: Center(child: form),
        ),
      );
    }

    // Desktop: branded gradient panel + form (PRD A3 platform note).
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: AppTheme.authGradient),
              child: Stack(
                children: [
                  // Subtle decorative circles (solid fills, cheap to render).
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
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(Icons.storefront_rounded,
                                  size: 44, color: Colors.white),
                            ),
                            const SizedBox(height: 24),
                            Text('One app.\nEvery kind of shop.',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                    color: Colors.white, height: 1.2)),
                            const SizedBox(height: 12),
                            Text(t(context).tagline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.75))),
                            const SizedBox(height: 32),
                            _feature(Icons.bolt_rounded, 'Sell in seconds — POS built for speed'),
                            _feature(Icons.people_alt_rounded, 'Track customer credit with a tamper-proof ledger'),
                            _feature(Icons.insights_rounded, 'Know your numbers — daily profit & best sellers'),
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

  void _fillDemo(Map<String, dynamic> d) {
    _phone.text = '${d['phone']}';
    _password.text = '${d['password']}';
    setState(() => _error = null);
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
