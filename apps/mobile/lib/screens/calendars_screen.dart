import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/auth.dart';
import '../state/family.dart';

/// Calendar connections (delivery destinations) with a guided per-provider
/// connect flow (incl. CalDAV calendar discovery) and edit/delete.
class CalendarsScreen extends ConsumerWidget {
  const CalendarsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetsAsync = ref.watch(targetsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Calendars')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final added = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const ConnectCalendarPage()),
          );
          if (added == true) ref.invalidate(targetsProvider);
        },
        icon: const Icon(Icons.add_link),
        label: const Text('Connect'),
      ),
      body: targetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (targets) => targets.isEmpty
            ? const Center(child: Text('No calendars connected yet'))
            : ListView(
                children: [
                  for (final t in targets)
                    ListTile(
                      leading: CircleAvatar(child: Icon(_iconFor(t['method'] as String))),
                      title: Text(t['name'] as String),
                      subtitle: Text(
                        '${_methodLabel(t)} · ${t['memberRelation']} · ${t['addressOrUrl']}'
                        '${(t['active'] as bool? ?? true) ? '' : ' · paused'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => _onAction(context, ref, v, t),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Map<String, dynamic> target,
  ) async {
    if (action == 'edit') {
      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => _EditTargetDialog(target: target),
      );
      if (changed == true) ref.invalidate(targetsProvider);
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete connection?'),
          content: Text('Remove "${target['name']}"? This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
          ],
        ),
      );
      if (confirm == true) {
        final familyId = await ref.read(familyProvider.future);
        await ref.read(apiClientProvider).deleteCalendarTarget(familyId, target['id'] as String);
        ref.invalidate(targetsProvider);
      }
    }
  }

  IconData _iconFor(String method) => switch (method) {
        'email' => Icons.mail_outline,
        'google' => Icons.calendar_month,
        _ => Icons.cloud_outlined,
      };

  String _methodLabel(Map<String, dynamic> t) {
    final hint = t['providerHint'];
    if (hint == 'icloud') return 'iCloud';
    if (hint == 'google' || t['method'] == 'google') return 'Google';
    if (hint == 'generic_caldav') return 'CalDAV';
    return t['method'] as String;
  }
}

/// Rename + pause/resume an existing connection. (Changing the calendar or
/// credentials = delete and reconnect.)
class _EditTargetDialog extends ConsumerStatefulWidget {
  const _EditTargetDialog({required this.target});
  final Map<String, dynamic> target;

  @override
  ConsumerState<_EditTargetDialog> createState() => _EditTargetDialogState();
}

class _EditTargetDialogState extends ConsumerState<_EditTargetDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.target['name'] as String? ?? '');
  late bool _active = widget.target['active'] as bool? ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final familyId = await ref.read(familyProvider.future);
      await ref.read(apiClientProvider).updateCalendarTarget(
            familyId,
            widget.target['id'] as String,
            name: _name.text.trim(),
            active: _active,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit connection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Connection name'),
          ),
          SwitchListTile(
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: const Text('Active'),
            subtitle: const Text('Deliver tasks to this calendar'),
            contentPadding: EdgeInsets.zero,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

enum _Provider { email, icloud, genericCaldav, google }

class ConnectCalendarPage extends ConsumerStatefulWidget {
  const ConnectCalendarPage({super.key});

  @override
  ConsumerState<ConnectCalendarPage> createState() => _ConnectCalendarPageState();
}

class _ConnectCalendarPageState extends ConsumerState<ConnectCalendarPage> {
  _Provider _provider = _Provider.email;
  String? _memberId;
  final _name = TextEditingController();
  final _address = TextEditingController(); // email, or CalDAV server URL
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _calendarId = TextEditingController(text: 'primary');
  final _accessToken = TextEditingController();

  // CalDAV discovery state.
  List<Map<String, dynamic>> _discovered = const [];
  String? _selectedCalendarUrl;
  bool _discovering = false;

  bool _busy = false;
  String? _error;

  bool get _isCalDav =>
      _provider == _Provider.icloud || _provider == _Provider.genericCaldav;

  @override
  void dispose() {
    for (final c in [_name, _address, _username, _password, _calendarId, _accessToken]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onProviderChanged(_Provider p) {
    setState(() {
      _provider = p;
      _discovered = const [];
      _selectedCalendarUrl = null;
      if (p == _Provider.icloud) {
        _address.text = 'https://caldav.icloud.com';
      } else if (p == _Provider.genericCaldav && _address.text == 'https://caldav.icloud.com') {
        _address.clear();
      }
    });
  }

  Future<void> _fetchCalendars() async {
    setState(() {
      _discovering = true;
      _error = null;
    });
    try {
      final familyId = await ref.read(familyProvider.future);
      final cals = await ref.read(apiClientProvider).discoverCalDavCalendars(
            familyId,
            serverUrl: _address.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
          );
      setState(() {
        _discovered = cals.cast<Map<String, dynamic>>();
        _selectedCalendarUrl =
            _discovered.isNotEmpty ? _discovered.first['url'] as String : null;
        if (_discovered.isEmpty) _error = 'No calendars found for those credentials';
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _save() async {
    if (_memberId == null) return setState(() => _error = 'Pick a caretaker');
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the connection a name');
    if (_isCalDav && _selectedCalendarUrl == null) {
      return setState(() => _error = 'Fetch and pick a calendar first');
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final familyId = await ref.read(familyProvider.future);
      final api = ref.read(apiClientProvider);

      late String method;
      String? providerHint;
      String addressOrUrl;
      String? externalCalendarId;
      Map<String, String>? credential;

      switch (_provider) {
        case _Provider.email:
          method = 'email';
          addressOrUrl = _address.text.trim();
        case _Provider.icloud:
        case _Provider.genericCaldav:
          method = 'caldav';
          providerHint = _provider == _Provider.icloud ? 'icloud' : 'generic_caldav';
          addressOrUrl = _selectedCalendarUrl!;
          credential = {'username': _username.text.trim(), 'password': _password.text};
        case _Provider.google:
          method = 'google';
          providerHint = 'google';
          externalCalendarId = _calendarId.text.trim();
          addressOrUrl = _calendarId.text.trim();
          credential = {'accessToken': _accessToken.text.trim()};
      }

      await api.createCalendarTarget(
        familyId,
        memberId: _memberId!,
        name: _name.text.trim(),
        method: method,
        providerHint: providerHint,
        addressOrUrl: addressOrUrl,
        externalCalendarId: externalCalendarId,
        credential: credential,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caretakers = ref.watch(caretakersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect a calendar')),
      body: caretakers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (people) {
          if (people.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a caretaker on the Family tab first.'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _memberId,
                decoration: const InputDecoration(labelText: 'Caretaker'),
                items: [
                  for (final c in people)
                    DropdownMenuItem(value: c.id, child: Text(c.relationName)),
                ],
                onChanged: (v) => setState(() => _memberId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<_Provider>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: const [
                  DropdownMenuItem(value: _Provider.email, child: Text('Email invite')),
                  DropdownMenuItem(value: _Provider.icloud, child: Text('iCloud (CalDAV)')),
                  DropdownMenuItem(value: _Provider.genericCaldav, child: Text('Other CalDAV')),
                  DropdownMenuItem(value: _Provider.google, child: Text('Google Calendar')),
                ],
                onChanged: (p) => p == null ? null : _onProviderChanged(p),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Connection name',
                  hintText: 'e.g. Work calendar',
                ),
              ),
              const SizedBox(height: 16),
              ..._providerFields(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Connect'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _providerFields() {
    switch (_provider) {
      case _Provider.email:
        return [
          TextField(
            controller: _address,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Delivery email', hintText: 'you@example.com'),
          ),
          const _Hint('A full-detail invite is emailed here. Note: outbound email is '
              'currently disabled until a paid plan is enabled.'),
        ];
      case _Provider.icloud:
      case _Provider.genericCaldav:
        return [
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'CalDAV server URL',
              hintText: 'https://caldav.icloud.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: InputDecoration(
              labelText: _provider == _Provider.icloud ? 'Apple ID email' : 'Username',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _provider == _Provider.icloud ? 'App-specific password' : 'Password',
            ),
          ),
          if (_provider == _Provider.icloud)
            const _Hint('Create an app-specific password at appleid.apple.com → Sign-In '
                'and Security → App-Specific Passwords.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _discovering ? null : _fetchCalendars,
            icon: _discovering
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text('Fetch calendars'),
          ),
          if (_discovered.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedCalendarUrl,
              decoration: const InputDecoration(labelText: 'Calendar'),
              items: [
                for (final cal in _discovered)
                  DropdownMenuItem(
                    value: cal['url'] as String,
                    child: Text(cal['displayName'] as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _selectedCalendarUrl = v),
            ),
          ],
        ];
      case _Provider.google:
        return [
          TextField(
            controller: _calendarId,
            decoration: const InputDecoration(
              labelText: 'Google calendar ID',
              hintText: 'primary or …@group.calendar.google.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _accessToken,
            decoration: const InputDecoration(labelText: 'OAuth access token'),
          ),
          const _Hint('A proper Google sign-in flow is coming; for now paste an OAuth '
              'access token with the calendar.events scope.'),
        ];
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
