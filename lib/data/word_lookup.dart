import 'package:url_launcher/url_launcher.dart';

Uri wordLookupUri(String selection) =>
    Uri.https('www.google.com', '/search', {'q': 'define ${selection.trim()}'});

Future<bool> canLookupSelectedWord() async {
  try {
    return await supportsLaunchMode(LaunchMode.inAppBrowserView);
  } catch (_) {
    return false;
  }
}

Future<bool> lookupSelectedWord(String selection) async {
  final word = selection.trim();
  if (word.isEmpty ||
      word.length > 160 ||
      word.split(RegExp(r'\s+')).length > 12) {
    return false;
  }
  try {
    // Avoid the launcher's automatic external-app fallback on unsupported devices.
    if (!await canLookupSelectedWord()) {
      return false;
    }
    return await launchUrl(
      wordLookupUri(word),
      mode: LaunchMode.inAppBrowserView,
      browserConfiguration: const BrowserConfiguration(showTitle: true),
    );
  } catch (_) {
    return false;
  }
}
