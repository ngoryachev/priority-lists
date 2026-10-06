import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../domain/models/activity_event.dart';
import '../../domain/repositories/activity_log_repository.dart';
import '../view_models/activity_log_view_model.dart';
import '../widgets/centered_body.dart';

/// Read-only history of everything the user changed, newest first and grouped
/// by day, with a per-day "copy" that produces a plain-text recap to paste
/// into a standup.
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
                tooltip: 'Copy everything shown',
                onPressed: vm.days.isEmpty
                    ? null
                    : () => _copy(
                        vm.days.map((day) => day.digest()).join('\n\n'),
                        'Copied ${vm.days.length} day'
                            '${vm.days.length == 1 ? '' : 's'}',
                      ),
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
        onCopy: () => _copy(
          vm.days[index].digest(),
          'Copied ${_dayLabel(vm.days[index].day).toLowerCase()}',
        ),
      ),
    );
  }

  Future<void> _copy(String text, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(confirmation)));
  }
}

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
  final VoidCallback onCopy;

  const _DaySection({required this.day, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_dayLabel(day.day)} · ${day.events.length} change'
                    '${day.events.length == 1 ? '' : 's'}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy this day for the standup',
                  onPressed: onCopy,
                ),
              ],
            ),
          ),
          for (final event in day.events) _EventTile(event: event),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final ActivityEvent event;

  const _EventTile({required this.event});

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
      leading: Tooltip(
        message: event.action.label,
        child: CircleAvatar(
          radius: 14,
          backgroundColor: color.withValues(alpha: 0.18),
          child: Icon(_actionIcon(event.action), size: 16, color: color),
        ),
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
