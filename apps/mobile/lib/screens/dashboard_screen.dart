import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../state/auth.dart';
import '../state/family.dart';
import '../util/format.dart';

/// Tasks view. Toggles between the unowned queue and all tasks (oversight).
/// Tasks group by day (Today/Tomorrow/date) with the child's name, a friendly
/// time, and the owner when claimed.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _showAll = false;

  void _refreshTasks() {
    ref.invalidate(unownedTasksProvider);
    ref.invalidate(allTasksProvider);
  }

  Future<void> _refreshFeeds() async {
    final familyId = await ref.read(familyProvider.future);
    await ref.read(apiClientProvider).refreshAllFeeds(familyId);
    _refreshTasks();
  }

  Future<void> _sync() async {
    final familyId = await ref.read(familyProvider.future);
    final res = await ref.read(apiClientProvider).resyncDeliveries(familyId);
    final created = res['created'] ?? 0;
    final updated = res['updated'] ?? 0;
    final removed = res['removed'] ?? 0;
    final errors = (res['errors'] as List?)?.length ?? 0;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Calendars synced: $created added, $updated updated, $removed removed'
          '${errors > 0 ? ' · $errors error(s)' : ''}',
        ),
      ),
    );
  }

  Future<void> _claim(String taskId) async {
    final familyId = await ref.read(familyProvider.future);
    await ref.read(apiClientProvider).assignTask(familyId, taskId);
    _refreshTasks();
  }

  Future<void> _assign(String taskId, String memberId) async {
    final familyId = await ref.read(familyProvider.future);
    await ref.read(apiClientProvider).assignTask(familyId, taskId, memberId: memberId);
    _refreshTasks();
  }

  Future<void> _release(String taskId) async {
    final familyId = await ref.read(familyProvider.future);
    await ref.read(apiClientProvider).unassignTask(familyId, taskId);
    _refreshTasks();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(_showAll ? allTasksProvider : unownedTasksProvider);
    final members = ref.watch(membersProvider).valueOrNull ?? const <Member>[];
    final names = {for (final m in members) m.id: m.relationName};
    final caretakers = members.where((m) => m.isCaretaker).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            tooltip: 'Sync to calendars',
            onPressed: _sync,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Refresh feeds',
            onPressed: _refreshFeeds,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Unowned')),
                ButtonSegment(value: true, label: Text('All')),
              ],
              selected: {_showAll},
              onSelectionChanged: (s) => setState(() => _showAll = s.first),
            ),
          ),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (tasks) => RefreshIndicator(
                onRefresh: () async {
                  _refreshTasks();
                  await ref.read(
                    (_showAll ? allTasksProvider : unownedTasksProvider).future,
                  );
                },
                child: tasks.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(_showAll
                                ? 'No tasks yet'
                                : 'Nothing unowned — all covered 🎉'),
                          ),
                        ],
                      )
                    : _GroupedTaskList(
                        tasks: tasks,
                        names: names,
                        caretakers: caretakers,
                        onClaim: _claim,
                        onRelease: _release,
                        onAssign: _assign,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedTaskList extends StatelessWidget {
  const _GroupedTaskList({
    required this.tasks,
    required this.names,
    required this.caretakers,
    required this.onClaim,
    required this.onRelease,
    required this.onAssign,
  });

  final List<TaskItem> tasks;
  final Map<String, String> names;
  final List<Member> caretakers;
  final void Function(String taskId) onClaim;
  final void Function(String taskId) onRelease;
  final void Function(String taskId, String memberId) onAssign;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sorted = [...tasks]..sort((a, b) => a.start.compareTo(b.start));

    final groups = <DateTime, List<TaskItem>>{};
    for (final t in sorted) {
      (groups[dayKey(t.start)] ??= []).add(t);
    }
    final days = groups.keys.toList()..sort();

    final theme = Theme.of(context);
    final children = <Widget>[];
    for (final day in days) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
          child: Text(
            dayHeading(day, now),
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      for (final t in groups[day]!) {
        final child = names[t.familyMemberId] ?? 'child';
        final owner = t.ownerMemberId != null ? names[t.ownerMemberId] : null;
        final subtitle = owner != null
            ? '${friendlyTime(t.start)} · ${t.status == 'owned' ? owner : ''}'
            : friendlyTime(t.start);
        final owned = t.status == 'owned';
        // Caretakers the task can be (re)assigned to — everyone but the owner.
        final assignable =
            caretakers.where((m) => m.id != t.ownerMemberId).toList();
        children.add(
          ListTile(
            leading: CircleAvatar(child: Icon(_iconFor(t.type))),
            title: Text('${t.typeLabel} · $child'),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                owned
                    ? TextButton(onPressed: () => onRelease(t.id), child: const Text('Release'))
                    : FilledButton(onPressed: () => onClaim(t.id), child: const Text('Claim')),
                if (assignable.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: owned ? 'Reassign' : 'Assign to…',
                    icon: const Icon(Icons.person_add_alt),
                    onSelected: (memberId) => onAssign(t.id, memberId),
                    itemBuilder: (_) => [
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(owned ? 'Reassign to' : 'Assign to'),
                      ),
                      for (final m in assignable)
                        PopupMenuItem<String>(value: m.id, child: Text(m.relationName)),
                    ],
                  ),
              ],
            ),
          ),
        );
      }
    }
    return ListView(children: children);
  }

  IconData _iconFor(String type) => switch (type) {
        'pickup' => Icons.directions_car,
        'dropoff' => Icons.login,
        _ => Icons.event,
      };
}
