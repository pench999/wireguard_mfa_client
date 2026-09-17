import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum MfaAuthDialogResult { completed, cancelled, externalBrowser }

bool isSameOrigin(Uri expected, Uri candidate) {
  int effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme == 'https' ? 443 : 80;
  }

  return expected.scheme.toLowerCase() == candidate.scheme.toLowerCase() &&
      expected.host.toLowerCase() == candidate.host.toLowerCase() &&
      effectivePort(expected) == effectivePort(candidate);
}

Future<MfaAuthDialogResult?> showMfaAuthDialog(
  BuildContext context,
  Uri authenticationUrl,
) async {
  final opened = await launchUrl(
    authenticationUrl,
    mode: LaunchMode.externalApplication,
  );
  return opened ? MfaAuthDialogResult.externalBrowser : null;
}
