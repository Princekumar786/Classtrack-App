import 'package:flutter/material.dart';
import '../../../../core/utils/url_launcher_util.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    TextStyle? h = theme.textTheme.titleMedium;
    TextStyle? b = theme.textTheme.bodyMedium;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('ClassTrack Privacy Policy', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Last updated: July 2026', style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          Text('Data we collect', style: h),
          const SizedBox(height: 6),
          Text(
            'ClassTrack stores the information you provide to run the app: your name and email '
            '(via Firebase Authentication), the subjects, class schedule, resource links and '
            'attendance records you create. Timetable images or PDFs you upload for AI import are '
            'stored temporarily in Firebase Cloud Storage so they can be processed.',
            style: b,
          ),
          const SizedBox(height: 16),
          Text('How we use it', style: h),
          const SizedBox(height: 6),
          Text(
            'Your data is used solely to provide app features — tracking attendance, showing your '
            'schedule, sending local reminders, and generating exports. Uploaded timetables are sent '
            'to Google’s Gemini API through our secure Cloud Function only to extract your schedule; '
            'they are not used to train models by us.',
            style: b,
          ),
          const SizedBox(height: 16),
          Text('Storage & security', style: h),
          const SizedBox(height: 6),
          Text(
            'Data is stored in Google Firebase under security rules that restrict every document to '
            'its owner. Only you, when signed in, can read or write your data.',
            style: b,
          ),
          const SizedBox(height: 16),
          Text('Your choices', style: h),
          const SizedBox(height: 6),
          Text(
            'You can edit or delete any subject, class or attendance record at any time. You can '
            'delete your entire account and all associated data from Settings → Delete account.',
            style: b,
          ),
          const SizedBox(height: 16),
          Text('Contact', style: h),
          const SizedBox(height: 6),
          Text('Questions or requests about your privacy?', style: b),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.email_outlined, size: 20),
              label: const Text(AppConstants.supportEmail),
              onPressed: () => _launch(
                'mailto:${AppConstants.supportEmail}'
                '?subject=${Uri.encodeComponent('ClassTrack privacy')}',
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: const Text('Read the full privacy policy online'),
              onPressed: () => _launch(AppConstants.privacyPolicyUrl),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    await safeLaunchUri(uri);
  }
}
