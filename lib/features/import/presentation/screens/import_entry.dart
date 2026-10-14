import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/google_calendar_service.dart';
import '../../../../services/calendar_auto_sync.dart';
import '../providers/import_providers.dart';
import 'import_screen.dart';

/// Temporarily gates the one-tap Google Calendar/Tasks import behind a
/// "coming soon" message. Flip to `true` to re-enable the real import — e.g.
/// for the OAuth verification demo build — once Google has approved the
/// calendar.readonly / tasks.readonly scopes. Keep it `false` for public store
/// builds until then.
const bool kGoogleImportEnabled = true;

/// Bottom sheet offering the ways to import a timetable: straight from Google
/// Calendar, or via the AI photo/text importer. Shared by the Schedule and
/// Calendar screens so both expose the same entry point.
void showImportOptions(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Import schedule', style: theme.textTheme.titleLarge),
            ),
            ListTile(
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('Google Calendar'),
              subtitle: const Text(
                kGoogleImportEnabled
                    ? 'Save your calendar events & tasks into Tasks'
                    : 'Coming soon',
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (kGoogleImportEnabled) {
                  runGoogleCalendarImport(context, ref);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Google Calendar & Tasks import — coming soon!',
                      ),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('Photo, PDF or text (AI)'),
              subtitle: const Text('Scan an image, upload a PDF, or paste text'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(settings: const RouteSettings(name: 'Import'), builder: (_) => const ImportScreen()),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Signs into Google, fetches the user's upcoming calendar events AND their
/// Google Tasks, and saves them into the Tasks list (events as `event`-type
/// items, to-dos as `task`-type items). Shows a blocking spinner while it works
/// and surfaces friendly messages for the cancel / empty / error cases. Safe to
/// re-run: already-imported items are skipped (no duplicates).
Future<void> runGoogleCalendarImport(
  BuildContext context,
  WidgetRef ref,
) async {
  final repo = ref.read(importRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  if (repo == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Please sign in first.')));
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final events = await repo.parseGoogleCalendarEvents();
    final tasks = await repo.parseGoogleTasks();
    if (events.isEmpty && tasks.isEmpty) {
      navigator.pop(); // dismiss the spinner
      messenger.showSnackBar(const SnackBar(
        content:
            Text('No upcoming events or tasks found in your Google account.'),
      ));
      return;
    }
    final result = await repo.commitGoogleImport(events: events, tasks: tasks);
    // Google is now linked with the calendar/tasks scopes granted, so the daily
    // 7 PM background auto-sync can run silently from here on.
    await ref.read(googleAutoSyncConnectedProvider.notifier).set(true);
    navigator.pop(); // dismiss the spinner
    final n = result.tasks;
    final message = n == 0
        ? 'Your Google Calendar & Tasks are already up to date.'
        : 'Imported $n item${n == 1 ? '' : 's'} from Google Calendar & Tasks.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } on GoogleCalendarCancelled {
    navigator.pop(); // just close the spinner, no error
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Google Calendar import failed: $e')),
    );
  }
}
