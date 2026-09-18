import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../providers/session.dart';
import '../../widgets/common.dart';
import '../../utils/format.dart';
import '../login_screen.dart';

/// K1–K10 — settings hub: business profile, payment methods, receipt,
/// language, dark mode, plan, logout.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final tenant = session?.tenant;
    final user = session?.user;
    final lang = ref.watch(localeProvider);
    final dark = ref.watch(darkModeProvider);
    final canManageSettings = session?.canManageSettings ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(t(context).settings)),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Business identity header.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      (tenant?.name.isNotEmpty ?? false) ? tenant!.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tenant?.name ?? '—',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(
                          '${tenant?.config.labelEn ?? ''} · ${t(context).plan}: ${tenant?.plan ?? ''}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(t(context).businessProfile),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store_mall_directory_rounded),
                  title: Text(t(context).shopName),
                  subtitle: Text(tenant?.name ?? ''),
                  enabled: canManageSettings,
                  onTap: () => _editField(context,
                      title: t(context).shopName, initial: tenant?.name ?? '',
                      onSave: (v) => _saveSettings({'name': v})),
                ),
                ListTile(
                  leading: const Icon(Icons.category_rounded),
                  title: Text(t(context).businessType),
                  subtitle: Text(tenant?.config.labelEn ?? ''),
                  enabled: false,
                ),
                ListTile(
                  leading: const Icon(Icons.phone_rounded),
                  title: Text(t(context).phoneNumber),
                  subtitle: Text(tenant == null || tenant.cbeNumber.isEmpty
                      ? '—'
                      : EthPhone.pretty(tenant.cbeNumber)),
                  enabled: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(t(context).paymentSetup),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.phone_android_rounded,
                      color: Color(0xFFB3261E)),
                  title: Text(t(context).telebirrNumber),
                  subtitle: Text(
                      (tenant?.telebirrNumber.isEmpty ?? true) ? 'Not set' : tenant!.telebirrNumber),
                  enabled: canManageSettings,
                  onTap: () => _editField(context,
                      title: t(context).telebirrNumber,
                      initial: tenant?.telebirrNumber ?? '',
                      onSave: (v) => _saveSettings({'telebirr_number': v})),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_rounded,
                      color: Color(0xFF6A4BA1)),
                  title: Text(t(context).cbeNumber),
                  subtitle: Text(
                      (tenant?.cbeNumber.isEmpty ?? true) ? 'Not set' : tenant!.cbeNumber),
                  enabled: canManageSettings,
                  onTap: () => _editField(context,
                      title: t(context).cbeNumber,
                      initial: tenant?.cbeNumber ?? '',
                      onSave: (v) => _saveSettings({'cbe_number': v})),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader(t(context).receiptSettings),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_rounded),
              title: Text(t(context).receiptFooter),
              subtitle: Text(
                  (tenant?.receiptFooter.isEmpty ?? true) ? '—' : tenant!.receiptFooter),
              enabled: canManageSettings,
              onTap: () => _editField(context,
                  title: t(context).receiptFooter,
                  initial: tenant?.receiptFooter ?? '',
                  onSave: (v) => _saveSettings({'receipt_footer': v})),
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader('${t(context).language} & ${t(context).darkMode}'),
          Card(
            child: Column(
              children: [
                RadioGroup<String>(
                  groupValue: lang,
                  onChanged: (v) => _setLang(v!),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'en',
                        title: const Text('English'),
                      ),
                      RadioListTile<String>(
                        value: 'am',
                        title: const Text('አማርኛ'),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_rounded),
                  title: Text(t(context).darkMode),
                  value: dark,
                  onChanged: (_) => ref.read(darkModeProvider.notifier).toggle(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionHeader('Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_rounded),
                  title: Text(user?.name ?? ''),
                  subtitle: Text('${user?.phone ?? ''} · ${user?.role ?? ''}'),
                ),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
                  title: Text(t(context).logout,
                      style: TextStyle(color: theme.colorScheme.error)),
                  onTap: () async {
                    await ref.read(sessionProvider.notifier).logout();
                    if (context.mounted) {
                      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (_) => false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('Velo v1.0 · built for Ethiopian businesses',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _setLang(String lang) async {
    ref.read(localeProvider.notifier).set(lang);
    await ref.read(sessionProvider.notifier).setLanguage(lang);
    try {
      await Api().updateLanguage(lang);
    } catch (_) {/* local works offline */}
  }

  Future<void> _saveSettings(Map<String, dynamic> payload) async {
    try {
      await Api().updateSettings(payload);
      await ref.read(sessionProvider.notifier).refreshTenant();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t(context).saved)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('ApiException: ', ''))));
      }
    }
  }

  Future<void> _editField(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(context).cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(t(context).save)),
        ],
      ),
    );
    if (v != null && v != initial) await onSave(v);
  }
}
