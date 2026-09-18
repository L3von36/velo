import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../api/api_client.dart';
import '../providers/session.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'login_screen.dart';

/// A4 — create the owner account (first user of a new tenant).
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _shop = TextEditingController();
  bool _terms = false;
  bool _obscure = true;
  bool _loading = false;
  ApiException? _error;

  bool get _valid =>
      _name.text.trim().length >= 2 &&
      _shop.text.trim().length >= 2 &&
      _password.text.length >= 6 &&
      _password.text == _confirm.text &&
      _terms;

  Future<void> _submit() async {
    final norm = EthPhone.normalize(_phone.text);
    if (norm == null) {
      setState(() => _error = ApiException(
          'Enter a valid Ethiopian phone number (+251 9XX XXX XXX).'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Signup creates tenant; onboarding wizard collects business details next.
      await ref.read(sessionProvider.notifier).signup({
        'name': _name.text.trim(),
        'phone': norm,
        'password': _password.text,
        'shop_name': _shop.text.trim(),
        'business_type': 'general',
      });
    } catch (e) {
      final err =
          e is ApiException ? e : ApiException(e.toString());
      setState(() => _error = err);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goLogin() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => LoginScreen(initialPhone: EthPhone.normalize(_phone.text))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t(context).createAccount,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Owner account for your business',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 22),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onErrorContainer),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!.message,
                                    style: TextStyle(
                                        color:
                                            theme.colorScheme.onErrorContainer,
                                        fontSize: 13)),
                              ),
                            ],
                          ),
                          // Duplicate account: give the user a direct path
                          // to log in with the number they just typed.
                          if (_error!.code == 'user_already_exists') ...[
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: _goLogin,
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.onErrorContainer,
                                foregroundColor:
                                    theme.colorScheme.errorContainer,
                                minimumSize: const Size.fromHeight(38),
                              ),
                              icon: const Icon(Icons.login_rounded, size: 18),
                              label: Text(
                                  '${t(context).haveAccount} ${t(context).login}'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                        labelText: t(context).fullName,
                        prefixIcon: const Icon(Icons.person_outline_rounded)),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _shop,
                    decoration: InputDecoration(
                        labelText: t(context).shopName,
                        prefixIcon: const Icon(Icons.store_mall_directory_outlined)),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: t(context).phoneNumber,
                        hintText: t(context).phoneHint,
                        prefixIcon: const Icon(Icons.phone_android_rounded)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: t(context).password,
                      helperText: 'Min 6 characters',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                        labelText: t(context).confirmPassword,
                        errorText: _confirm.text.isNotEmpty &&
                                _confirm.text != _password.text
                            ? 'Passwords do not match'
                            : null,
                        prefixIcon: const Icon(Icons.lock_rounded)),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _terms,
                    onChanged: (v) => setState(() => _terms = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t(context).terms, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: (_valid && !_loading) ? _submit : null,
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                    child: _loading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(t(context).signup),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: Text('${t(context).haveAccount} ${t(context).login}'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
