import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/table_model.dart';
import '../../providers/pos_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../order_flow/table_actions_sheet.dart';
import '../../widgets/dialog_controller_scope.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/table_status_style.dart';

/// Dining sections (Garden / AC dining / Bar …) and the tables in each:
/// add, rename and remove sections, add tables and move them between
/// sections. Managers only; everyone else sees it read-only.
class DiningSectionsScreen extends StatelessWidget {
  const DiningSectionsScreen({super.key});

  /// Sections to edit against: the configured list when present, otherwise
  /// the sections in use by tables (legacy/empty config), as a fresh mutable
  /// copy so a partial edit never drops other sections.
  static List<String> _sectionBase(PosProvider provider) {
    final configured = provider.settings.sections;
    return List<String>.from(configured.isNotEmpty ? configured : provider.diningSections);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PosProvider>();
    final sections = provider.diningSections;
    final canManage = provider.canManage;
    final seats = provider.tables.fold<int>(0, (s, t) => s + t.seats);
    // Tables whose section is no longer configured still need a home here.
    final orphans = provider.tables.where((t) => !sections.contains(t.floor)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Sections & tables')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _addTable(context, provider, sections),
              icon: const Icon(Icons.table_restaurant),
              label: const Text('Add table'),
            )
          : null,
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: sections.isEmpty && provider.tables.isEmpty
                ? EmptyState(
                    icon: Icons.layers_outlined,
                    title: 'No sections or tables yet',
                    message: 'Create a section (e.g. Ground floor, Garden), then add its tables.',
                    actionLabel: canManage ? 'Add section' : null,
                    onAction: canManage ? () => _addSection(context, provider) : null,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Row(
                        children: [
                          _stat(Icons.layers_outlined, '${sections.length}', 'Sections'),
                          const SizedBox(width: 10),
                          _stat(Icons.table_restaurant_outlined, '${provider.tables.length}', 'Tables'),
                          const SizedBox(width: 10),
                          _stat(Icons.event_seat_outlined, '$seats', 'Seats'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      for (final name in sections)
                        _sectionCard(
                          context,
                          provider,
                          name,
                          provider.tables.where((t) => t.floor == name).toList(),
                          sections,
                          canManage,
                        ),
                      if (orphans.isNotEmpty)
                        _sectionCard(context, provider, null, orphans, sections, canManage),
                      if (canManage)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: OutlinedButton.icon(
                            onPressed: () => _addSection(context, provider),
                            icon: const Icon(Icons.add),
                            label: const Text('Add section'),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.creamCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primaryGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  /// One section with its tables. [name] null = tables whose section was
  /// removed from the configuration ("Unassigned").
  Widget _sectionCard(
    BuildContext context,
    PosProvider provider,
    String? name,
    List<RestaurantTable> tables,
    List<String> sections,
    bool canManage,
  ) {
    final title = name ?? 'Unassigned';
    final seats = tables.fold<int>(0, (s, t) => s + t.seats);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.creamCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(name == null ? Icons.help_outline : Icons.layers_outlined,
                color: name == null ? AppColors.warning : AppColors.primaryGreen),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${tables.length} ${tables.length == 1 ? 'table' : 'tables'} · $seats seats'),
            trailing: canManage && name != null
                ? PopupMenuButton<String>(
                    tooltip: 'Section options',
                    onSelected: (v) {
                      if (v == 'rename') _renameSection(context, provider, name);
                      if (v == 'delete') _deleteSection(context, provider, name);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  )
                : null,
          ),
          if (tables.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text('No tables in this section yet.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tables) _tableChip(context, provider, t, sections, canManage),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tableChip(
    BuildContext context,
    PosProvider provider,
    RestaurantTable t,
    List<String> sections,
    bool canManage,
  ) {
    final style = TableStatusStyle.of(t.status);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: style.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: style.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.tableNumber, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          const Icon(Icons.event_seat_outlined, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 2),
          Text('${t.seats}', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          const Icon(Icons.more_vert, size: 16, color: AppColors.textMuted),
        ],
      ),
    );
    // Tap a table for all its actions (status, edit, move, delete).
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showTableActions(context, t),
        child: chip,
      ),
    );
  }

  // ---- Dialogs (controllers owned by DialogControllerScope) ----

  void _addSection(BuildContext context, PosProvider provider) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [c],
        builder: (ctx, _) => AlertDialog(
          title: const Text('Add section'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Section name (e.g. Garden, AC Dining, Bar)'),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = c.text.trim();
                final base = _sectionBase(provider);
                if (name.isNotEmpty && !base.contains(name)) {
                  provider.updateSettings(provider.settings.copyWith(sections: [...base, name]));
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _renameSection(BuildContext context, PosProvider provider, String oldName) {
    final c = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [c],
        builder: (ctx, _) => AlertDialog(
          title: Text('Rename "$oldName"'),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'New section name'),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final newName = c.text.trim();
                if (newName.isNotEmpty && newName != oldName) {
                  // Re-home every table in this section first.
                  for (final t in provider.tables.where((t) => t.floor == oldName)) {
                    provider.updateTableSection(t.id, newName);
                  }
                  final list = _sectionBase(provider);
                  final idx = list.indexOf(oldName);
                  if (idx >= 0) {
                    list[idx] = newName;
                  } else {
                    list.add(newName); // renamed a table-derived section
                  }
                  provider.updateSettings(provider.settings.copyWith(sections: list));
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('Rename'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSection(BuildContext context, PosProvider provider, String name) async {
    final used = provider.tables.where((t) => t.floor == name).length;
    if (used > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$name" still has $used table(s). Move them to another section first.')),
      );
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Delete section?',
      message: 'Delete the dining section "$name"?',
      confirmLabel: 'Delete section',
    );
    if (!ok || !context.mounted) return;
    final next = _sectionBase(provider).where((s) => s != name).toList();
    if (next.length == provider.settings.sections.length && !provider.settings.sections.contains(name)) {
      return; // nothing configured changed
    }
    provider.updateSettings(provider.settings.copyWith(sections: next));
  }

  void _addTable(BuildContext context, PosProvider provider, List<String> sections) {
    final numC = TextEditingController();
    final seatsC = TextEditingController(text: '4');
    final newSectionC = TextEditingController();
    var section = sections.isNotEmpty ? sections.first : '';
    var creatingNew = sections.isEmpty;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => DialogControllerScope(
        controllers: [numC, seatsC, newSectionC],
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add table'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: numC,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Table number (e.g. T13)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: seatsC,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Seats'),
                  ),
                  const SizedBox(height: 12),
                  if (sections.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: creatingNew ? '__new__' : section,
                      decoration: const InputDecoration(labelText: 'Section'),
                      items: [
                        for (final s in sections) DropdownMenuItem(value: s, child: Text(s)),
                        const DropdownMenuItem(value: '__new__', child: Text('New section…')),
                      ],
                      onChanged: (v) => setLocal(() {
                        creatingNew = v == '__new__';
                        if (!creatingNew && v != null) section = v;
                      }),
                    ),
                  if (creatingNew) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: newSectionC,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'New section name'),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final num = numC.text.trim();
                final seats = int.tryParse(seatsC.text.trim()) ?? 0;
                final target = creatingNew ? newSectionC.text.trim() : section;
                if (num.isEmpty || seats <= 0 || target.isEmpty) {
                  setLocal(() => error = 'Enter a table number, seats and a section.');
                  return;
                }
                if (provider.tables.any((t) => t.tableNumber.toLowerCase() == num.toLowerCase())) {
                  setLocal(() => error = 'Table $num already exists.');
                  return;
                }
                if (creatingNew) {
                  final base = _sectionBase(provider);
                  if (!base.contains(target)) {
                    provider.updateSettings(provider.settings.copyWith(sections: [...base, target]));
                  }
                }
                provider.addTable(tableNumber: num, seats: seats, floor: target);
                Navigator.of(ctx).pop();
              },
              child: const Text('Add table'),
            ),
          ],
        ),
      ),
    );
  }
}
