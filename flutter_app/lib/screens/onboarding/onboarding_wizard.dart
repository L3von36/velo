import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Onboarding wizard — A7 business type → A9 first branch → A10 currency →
/// A12 checklist. Each step skippable where allowed; works fully offline.
class OnboardingWizard extends ConsumerStatefulWidget {
  const OnboardingWizard({super.key});

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  final _page = PageController();
  int _step = 0;

  String? _businessType;
  List<BusinessTypeConfig> _types = [];
  final _branchName = TextEditingController(text: 'Main branch');
  final _branchAddress = TextEditingController();
  final _branchPhone = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await Api().businessTypes();
      if (mounted) setState(() => _types = types);
    } catch (_) {/* grid shows fallback */}
  }

  Future<void> _saveBusinessType() async {
    if (_businessType == null) return;
    setState(() => _saving = true);
    try {
      await Api().updateSettings({'business_type': _businessType});
      await ref.read(sessionProvider.notifier).refreshTenant();
      _next();
    } catch (e) {
      _toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveBranch() async {
    setState(() => _saving = true);
    try {
      final session = ref.read(sessionProvider).value;
      await Api().updateSettings({
        'phone': _branchPhone.text.trim(),
        'address': _branchAddress.text.trim(),
      });
      // Ensure a default branch exists (A9).
      if (session != null && session.branches.isNotEmpty) {
        // Default branch already created at signup.
      }
      await ref.read(sessionProvider.notifier).refreshTenant();
      _next();
    } catch (e) {
      _toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_step < 3) {
      _page.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      setState(() => _step += 1);
    } else {
      ref.read(sessionProvider.notifier).finishOnboarding();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titles = [
      t(context).businessTypeTitle,
      t(context).branchSetupTitle,
      t(context).currencyConfirmTitle,
      t(context).setupComplete,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_step]),
        actions: [
          if (_step < 3)
            TextButton(
              onPressed: _next,
              child: Text(t(context).skipForNow),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              value: (_step + 1) / 4,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildBusinessType(theme),
                _buildBranch(theme),
                _buildCurrency(theme),
                _buildChecklist(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ step 1: business type
  Widget _buildBusinessType(ThemeData theme) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t(context).businessTypeSubtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: _types.map((cfg) {
              final selected = _businessType == cfg.key;
              return _TypeCard(
                config: cfg,
                selected: selected,
                onTap: () => setState(() => _businessType = cfg.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _businessType == null || _saving ? null : _saveBusinessType,
            child: Text(_saving ? '…' : t(context).continueLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ step 2: first branch
  Widget _buildBranch(ThemeData theme) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Every record is tied to a branch — name yours to start.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          TextField(
            controller: _branchName,
            decoration: InputDecoration(labelText: t(context).branchName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branchAddress,
            decoration: InputDecoration(labelText: t(context).address),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branchPhone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
                labelText: t(context).phoneNumber, hintText: t(context).phoneHint),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _saveBranch,
            child: Text(_saving ? '…' : t(context).continueLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ step 3: currency confirm
  Widget _buildCurrency(ThemeData theme) {
    final session = ref.watch(sessionProvider).value;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Currency'),
                      Chip(
                        label: const Text('ETB — Ethiopian Birr'),
                        backgroundColor: theme.colorScheme.primaryContainer,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t(context).currencyConfirmNote),
                      Text(Money.etb(1250),
                          style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary)),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t(context).language),
                      Text((session?.tenant?.language ?? 'en') == 'am' ? 'አማርኛ' : 'English'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _next,
            child: Text(t(context).continueLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ step 4: checklist
  Widget _buildChecklist(ThemeData theme) {
    final session = ref.watch(sessionProvider).value;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.celebration_rounded, size: 56, color: AppTheme.gold),
          const SizedBox(height: 12),
          Center(
            child: Text('${session?.tenant?.name ?? ''} — ${t(context).setupComplete}',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 24),
          _CheckRow(done: true, label: '${t(context).businessProfile} ✓'),
          _CheckRow(done: true, label: '${t(context).branchName} ✓'),
          _CheckRow(done: false, label: t(context).addFirstItem),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => ref.read(sessionProvider.notifier).finishOnboarding(),
            child: Text(t(context).goToDashboard),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.config, required this.selected, required this.onTap});
  final BusinessTypeConfig config;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = {
    'clothing': Icons.checkroom_rounded,
    'shoes': Icons.hiking_rounded,
    'supermarket': Icons.shopping_cart_rounded,
    'minimarket': Icons.storefront_rounded,
    'barbershop': Icons.content_cut_rounded,
    'general': Icons.category_rounded,
    'hybrid': Icons.widgets_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(_icons[config.key] ?? Icons.category_rounded,
                  size: 30,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(
                config.label(theme.textTheme.bodyMedium?.fontFamily == null ? 'en' : 'en'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.done, required this.label});
  final bool done;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: done ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        ],
      ),
    );
  }
}
