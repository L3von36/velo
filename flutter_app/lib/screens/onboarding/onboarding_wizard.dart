import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Onboarding wizard — business kind → business type → location (GPS) →
/// currency → checklist. Each step skippable where allowed.
class OnboardingWizard extends ConsumerStatefulWidget {
  const OnboardingWizard({super.key});

  @override
  ConsumerState<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends ConsumerState<OnboardingWizard> {
  final _page = PageController();
  int _step = 0;

  /// 'products' | 'services' | 'both' — drives the type grid filter.
  String? _kind;
  String? _businessType;
  List<BusinessTypeConfig> _types = [];

  Position? _pos;
  bool _locating = false;
  String? _locError;
  final _address = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await Api().businessTypes();
      if (mounted) setState(() => _types = types);
    } catch (_) {/* grid shows fallback */}
  }

  /// Business types matching the chosen shop kind.
  List<BusinessTypeConfig> get _filteredTypes {
    switch (_kind) {
      case 'products':
        return _types.where((c) => c.sellsProducts).toList();
      case 'services':
        return _types.where((c) => !c.sellsProducts).toList();
      default:
        return _types;
    }
  }

  String _lang(BuildContext c) =>
      Localizations.localeOf(c).languageCode == 'am' ? 'am' : 'en';

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

  Future<void> _saveLocation() async {
    setState(() => _saving = true);
    try {
      await Api().updateSettings({
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        if (_pos != null) 'latitude': _pos!.latitude,
        if (_pos != null) 'longitude': _pos!.longitude,
      });
      await ref.read(sessionProvider.notifier).refreshTenant();
      _next();
    } catch (e) {
      _toast(e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _captureLocation() async {
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final denied =
          perm == LocationPermission.denied || perm == LocationPermission.deniedForever;
      final serviceOn = denied ? false : await Geolocator.isLocationServiceEnabled();
      if (denied || !serviceOn) {
        if (!mounted) return;
        setState(() {
          _locError = t(context).locationDenied;
          _locating = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() {
        _pos = pos;
        _locating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locError = t(context).locationDenied;
        _locating = false;
      });
    }
  }

  void _next() {
    if (_step < 4) {
      _page.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
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
      t(context).kindTitle,
      t(context).businessTypeTitle,
      t(context).locationTitle,
      t(context).currencyConfirmTitle,
      t(context).setupComplete,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_step]),
        actions: [
          if (_step < 4)
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
              value: (_step + 1) / 5,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _page,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildKind(theme),
                _buildBusinessType(theme),
                _buildLocation(theme),
                _buildCurrency(theme),
                _buildChecklist(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------- step 1: shop kind (NEW)
  Widget _buildKind(ThemeData theme) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t(context).kindSubtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          _KindCard(
            icon: Icons.shopping_basket_rounded,
            title: t(context).products,
            subtitle: t(context).kindProductsSub,
            selected: _kind == 'products',
            onTap: () => setState(() => _kind = 'products'),
          ),
          const SizedBox(height: 12),
          _KindCard(
            icon: Icons.handyman_rounded,
            title: t(context).services,
            subtitle: t(context).kindServicesSub,
            selected: _kind == 'services',
            onTap: () => setState(() => _kind = 'services'),
          ),
          const SizedBox(height: 12),
          _KindCard(
            icon: Icons.widgets_rounded,
            title: t(context).kindBoth,
            subtitle: t(context).kindBothSub,
            selected: _kind == 'both',
            onTap: () => setState(() => _kind = 'both'),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _kind == null ? null : _next,
            child: Text(t(context).continueLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ step 2: business type
  Widget _buildBusinessType(ThemeData theme) {
    final types = _filteredTypes;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t(context).businessTypeSubtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (_types.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (types.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(t(context).businessTypeSubtitle,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: types.map((cfg) {
                final selected = _businessType == cfg.key;
                return _TypeCard(
                  config: cfg,
                  selected: selected,
                  lang: _lang(context),
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

  // --------------------------------------------- step 3: location (NEW)
  Widget _buildLocation(ThemeData theme) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(t(context).locationSubtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          // GPS capture card.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _pos != null
                  ? AppTheme.successSoft
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.rMd),
              border: Border.all(
                  color: _pos != null
                      ? AppTheme.success
                      : theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _pos != null
                          ? Icons.location_on_rounded
                          : Icons.location_searching_rounded,
                      size: 22,
                      color: _pos != null
                          ? AppTheme.success
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locating
                            ? t(context).locating
                            : _pos != null
                                ? t(context).locationCaptured
                                : t(context).useMyLocation,
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: _pos != null ? AppTheme.success : null),
                      ),
                    ),
                    if (_locating)
                      const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2)),
                  ],
                ),
                if (_pos != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Lat ${_pos!.latitude.toStringAsFixed(5)} · Lng ${_pos!.longitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (_locError != null) ...[
                  const SizedBox(height: 8),
                  Text(_locError!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _locating ? null : _captureLocation,
                  icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                  label: Text(_pos != null
                      ? t(context).useMyLocation
                      : t(context).useMyLocation),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            decoration: InputDecoration(
                labelText: t(context).address,
                prefixIcon: const Icon(Icons.map_rounded)),
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
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _saveLocation,
            child: Text(_saving ? '…' : t(context).continueLabel),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------ step 4: currency confirm
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

  // ------------------------------------------------ step 5: checklist
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
          _CheckRow(done: true, label: '${t(context).locationTitle} ✓'),
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

/// Big selectable card for the shop-kind question.
class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon,
                    size: 24,
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight:
                                selected ? FontWeight.w800 : FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.config,
    required this.selected,
    required this.lang,
    required this.onTap,
  });
  final BusinessTypeConfig config;
  final bool selected;
  final String lang;
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
                config.label(lang),
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
