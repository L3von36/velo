import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../api/api.dart';
import '../providers/session.dart';
import '../utils/format.dart';
import 'signup_screen.dart';

/// A3 — phone-first login (matches how Ethiopians register for services).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 18),
            Text('Velo',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(t(context).tagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 26),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
              const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: t(context).password,
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Text(t(context).login),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SignupScreen()),
              ),
              child: Text('${t(context).noAccount} ${t(context).signup}'),
            ),
            if (_demos.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(t(context).demoAccounts,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _demos.map((d) {
                  return ActionChip(
                    avatar: const Icon(Icons.bolt_rounded, size: 16),
                    label: Text('${d['tenant']}', overflow: TextOverflow.ellipsis),
                    onPressed: () {
                      _phone.text = '${d['phone']}';
                      _password.text = '${d['password']}';
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );

    if (!wide) return Scaffold(body: SafeArea(child: Center(child: form)));

    // Desktop: branded side panel (PRD A3 platform note).
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Container(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_rounded, size: 90, color: Colors.black26),
                    const SizedBox(height: 8),
                    Text('One app.\nEvery kind of shop.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700, color: Colors.black45)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 460,
            child: SafeArea(child: Center(child: SingleChildScrollView(child: form))),
          ),
        ],
      ),
    );
  }
}
