import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../api/api.dart';
import '../../models/models.dart';
import '../../providers/session.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// G1–G2 — staff list + add/edit with role & commission. Owner/manager only
/// (shell hides the tab otherwise; the API enforces it too).
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  List<StaffMember>? _staff;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Api().staff();
      if (mounted) setState(() => _staff = s);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t(context).staffList)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'staffFab',
        onPressed: () => _showForm(context),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: Text(t(context).addStaff),
      ),
      body: _error != null
          ? ErrorRetry(message: _error!, onRetry: _load)
          : _staff == null
              ? const Center(child: CircularProgressIndicator())
              : _staff!.isEmpty
                  ? EmptyState(
                      icon: Icons.badge_rounded,
                      title: t(context).staffList,
                      subtitle: t(context).addStaff,
                      actionLabel: t(context).addStaff,
                      onAction: () => _showForm(context),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                      itemCount: _staff!.length,
                      itemBuilder: (ctx, i) {
                        final s = _staff![i];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            onTap: () => _showForm(context, existing: s),
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                                style: TextStyle(color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            title: Text(s.name,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${_roleLabel(context, s.role)}'
                              '${s.commissionPercent > 0 ? ' · ${t(context).commission} ${s.commissionPercent.toStringAsFixed(0)}%' : ''}'
                              ' · ${EthPhone.pretty(s.phone)}',
                              style: theme.textTheme.labelSmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${s.salesTodayCount}',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(fontWeight: FontWeight.w800)),
                                    Text(t(context).mySalesToday,
                                        style: theme.textTheme.labelSmall),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  value: s.active,
                                  onChanged: s.role == 'owner'
                                      ? null
                                      : (v) async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          try {
                                            await Api().updateStaff(s.id, {'active': v});
                                            await _load();
                                          } catch (e) {
                                            messenger.showSnackBar(
                                                SnackBar(content: Text('$e')));
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  String _roleLabel(BuildContext context, String role) => switch (role) {
        'owner' => t(context).owner,
        'manager' => t(context).manager,
        'cashier' => t(context).cashierRole,
        _ => t(context).staffRole,
      };

  Future<void> _showForm(BuildContext context, {StaffMember? existing}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StaffForm(existing: existing),
    );
    _load();
  }
}

// ---------------------------------------------------------------- form
class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({this.existing});
  final StaffMember? existing;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _password = TextEditingController();
  late final _commission = TextEditingController(
      text: widget.existing == null || widget.existing!.commissionPercent == 0
          ? ''
          : widget.existing!.commissionPercent.toStringAsFixed(0));
  late String _role = widget.existing?.role ?? 'cashier';
  bool _saving = false;
  String? _error;

  bool get _commissionEnabled =>
      ref.read(sessionProvider).value?.tenant?.config.staffCommission ?? false;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = t(context).required);
      return;
    }
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'phone': EthPhone.normalize(_phone.text) ?? _phone.text.trim(),
      'role': _role,
      if (_commissionEnabled && _commission.text.trim().isNotEmpty)
        'commission_percent': double.tryParse(_commission.text.trim()) ?? 0,
      if (widget.existing == null && _password.text.isNotEmpty) 'password': _password.text,
    };
    try {
      if (widget.existing == null) {
        await Api().createStaff(payload);
      } else {
        await Api().updateStaff(widget.existing!.id, payload);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.existing == null ? t(context).addStaff : t(context).edit,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: InputDecoration(labelText: t(context).fullName)),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            enabled: widget.existing?.role != 'owner',
            decoration: InputDecoration(labelText: t(context).phoneNumber, hintText: t(context).phoneHint),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: InputDecoration(labelText: t(context).role),
            items: [
              DropdownMenuItem(value: 'manager', child: Text(t(context).manager)),
              DropdownMenuItem(value: 'cashier', child: Text(t(context).cashierRole)),
              DropdownMenuItem(value: 'staff', child: Text(t(context).staffRole)),
            ],
            onChanged: widget.existing?.role == 'owner'
                ? null
                : (v) => setState(() => _role = v ?? 'cashier'),
          ),
          if (_commissionEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _commission,
              keyboardType: TextInputType.number,
              inputFormatters: [IntInputFormatter()],
              decoration: InputDecoration(labelText: t(context).commission),
            ),
          ],
          if (widget.existing == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: '${t(context).password} (temp)',
                  helperText: 'Share privately — staff can change later'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
                : Text(t(context).save),
          ),
        ],
      ),
    );
  }
}
