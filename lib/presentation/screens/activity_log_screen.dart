import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/clipboard_service.dart';
import '../../domain/models/activity_event.dart';
import '../../domain/repositories/activity_log_repository.dart';
import '../view_models/activity_log_view_model.dart';
import '../widgets/centered_body.dart';

/// Read-only history of everything the user changed, newest first and grouped
/// by day, with a per-day "copy" that produces a plain-text recap to paste
/// into a standup.
///
/// Rows can be ticked to narrow what gets copied: with nothing ticked the copy
/// buttons take whole days, and as soon as one row is ticked they take only
/// the ticked rows.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  /// Route that carries the log repository across the [Navigator], which sits
  /// above the providers created after sign-in — exactly like `NodeScreen.route`.
  static Route<void> route(BuildContext context) {
    final repository = context.read<ActivityLogRepository>();
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/history'),
      builder: (_) => Provider<ActivityLogRepository>.value(
        value: repository,
        child: const ActivityLogScreen(),
      ),
    );
  }

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  static const List<int> _windows = [1, 7, 14, 30];

  late final ActivityLogViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ActivityLogViewModel(context.read<ActivityLogRepository>());
    _vm.load();
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ActivityLogViewModel>.value(
      value: _vm,
      child: Consumer<ActivityLogViewModel>(
        builder: (context, vm, _) => Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            actions: [
              PopupMenuButton<int>(
                icon: const Icon(Icons.date_range),
                tooltip: 'Period',
                initialValue: vm.windowDays,
                onSelected: (days) => vm.load(windowDays: days),
                itemBuilder: (_) => [
                  for (final days in _windows)
                    PopupMenuItem<int>(
                      value: days,
                      child: Text(days == 1 ? 'Today' : 'Last $days days'),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.copy_all),
                tooltip: vm.hasSelection
                    ? 'Copy the ticked rows'
                    : 'Copy everything shown',
                onPressed: vm.days.isEmpty ? null : () => _copyAll(vm),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reload',
                onPressed: () => vm.load(),
              ),
            ],
          ),
          body: CenteredBody(child: _body(vm)),
        ),
      ),
    );
  }

  Widget _body(ActivityLogViewModel vm) {
    if (vm.isLoading && vm.days.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load the history: ${vm.error}'),
              const SizedBox(height: 12),
              const Text(
                'If this is a fresh server, apply '
                'supabase/volumes/db/init/004_activity_log.sql.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (vm.days.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing recorded in this period.\n'
            'Changes you make from now on show up here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: vm.days.length,
      itemBuilder: (context, index) => _DaySection(
        day: vm.days[index],
        vm: vm,
        onCopy: () => _copyDay(vm, vm.days[index]),
      ),
    );
  }

  /// The app-bar button: every day shown, or the ticked rows of every day.
  Future<void> _copyAll(ActivityLogViewModel vm) async {
    if (!vm.hasSelection) {
      await _copy(
        vm.days.map((day) => day.digest()).join('\n\n'),
        'Copied ${vm.days.length} day${vm.days.length == 1 ? '' : 's'}',
      );
      return;
    }
    final digests = <String>[];
    for (final day in vm.days) {
      final digest = day.digestOf(vm.selectedIn(day));
      if (digest.isNotEmpty) digests.add(digest);
    }
    await _copy(
      digests.join('\n\n'),
      'Copied ${_changes(vm.selectedCount)}',
    );
  }

  /// A day header's button: that whole day, or just its ticked rows.
  Future<void> _copyDay(ActivityLogViewModel vm, ActivityDay day) async {
    final label = _dayLabel(day.day).toLowerCase();
    if (!vm.hasSelection) {
      await _copy(day.digest(), 'Copied $label');
      return;
    }
    final selected = vm.selectedIn(day);
    await _copy(
      day.digestOf(selected),
      'Copied ${_changes(selected.length)} from $label',
    );
  }

  Future<void> _copy(String text, String confirmation) async {
    final copied = await copyToClipboard(text);
    if (!mounted) return;
    if (!copied) {
      await _showManualCopy(text);
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(confirmation)));
  }

  /// Last resort when the platform would not take the text: show it, so the
  /// user can select it, instead of claiming a copy that never happened.
  Future<void> _showManualCopy(String text) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy it manually'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'The clipboard is out of reach here. Select the text '
                  'below and copy it yourself.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                SelectableText(text),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

String _changes(int count) => '$count change${count == 1 ? '' : 's'}';

/// `Today` / `Yesterday` / `2026-10-04`, whichever the day deserves.
String _dayLabel(DateTime day) {
  final today = DateTime.now();
  final midnight = DateTime(today.year, today.month, today.day);
  final diff = midnight.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return ActivityDay.formatDay(day);
}

class _DaySection extends StatelessWidget {
  final ActivityDay day;
  final ActivityLogViewModel vm;
  final VoidCallback onCopy;

  const _DaySection({
    required this.day,
    required this.vm,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = vm.selectedIn(day).length;
    // Null is the tri-state "some of them", which the checkbox draws as a dash.
    final value = selected == 0
        ? false
        : selected == day.events.length
            ? true
            : null;
    // With rows ticked elsewhere, this day's button has nothing of its own.
    final canCopy = !vm.hasSelection || selected > 0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Row(
              children: [
                Checkbox(
                  tristate: true,
                  value: value,
                  // The value the checkbox offers next would be `null` from a
                  // full tick; "all or nothing" is what a header should do.
                  onChanged: (_) => vm.setDaySelected(day, value != true),
                  semanticLabel: 'Select ${_dayLabel(day.day)}',
                ),
                Expanded(
                  child: Text(
                    '${_dayLabel(day.day)} · ${day.events.length} change'
                    '${day.events.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: vm.hasSelection
                      ? 'Copy the ticked rows of this day'
                      : 'Copy this day for the standup',
                  onPressed: canCopy ? onCopy : null,
                ),
              ],
            ),
          ),
          for (final event in day.events)
            _EventTile(
              event: event,
              selected: vm.isSelected(event.id),
              onSelected: (value) => vm.setEventSelected(event.id, value),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final ActivityEvent event;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _EventTile({
    required this.event,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _actionColor(event.action);
    final subtitle = [
      if (event.details.isNotEmpty) event.details,
      if (event.path.isNotEmpty) 'in ${event.pathLabel}',
    ].join(' · ');

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: () => onSelected(!selected),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onSelected(value ?? false),
            semanticLabel: 'Select ${event.nodeTitle}',
          ),
          Tooltip(
            message: event.action.label,
            child: CircleAvatar(
              radius: 14,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(_actionIcon(event.action), size: 16, color: color),
            ),
          ),
        ],
      ),
      title: Text(event.nodeTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        _time(event.at),
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  static String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  static IconData _actionIcon(ActivityAction action) => switch (action) {
        ActivityAction.created => Icons.add,
        ActivityAction.updated => Icons.edit_outlined,
        ActivityAction.prioritized => Icons.flag_outlined,
        ActivityAction.moved => Icons.move_to_inbox,
        ActivityAction.reordered => Icons.swap_vert,
        ActivityAction.deleted => Icons.delete_outline,
      };

  static Color _actionColor(ActivityAction action) => switch (action) {
        ActivityAction.created => Colors.green,
        ActivityAction.updated => Colors.blue,
        ActivityAction.prioritized => Colors.deepOrange,
        ActivityAction.moved => Colors.purple,
        ActivityAction.reordered => Colors.teal,
        ActivityAction.deleted => Colors.red,
      };
}
