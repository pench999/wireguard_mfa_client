import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _installBundledTrustAnchors();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  runApp(const WireGuardMfaApp());
}

Future<void> _installBundledTrustAnchors() async {
  const certificateAssets = [
    'assets/certificates/isrg-root-x1.pem',
    'assets/certificates/isrg-root-x2.pem',
  ];
  for (final asset in certificateAssets) {
    final certificate = await rootBundle.load(asset);
    SecurityContext.defaultContext.setTrustedCertificatesBytes(
      certificate.buffer.asUint8List(
        certificate.offsetInBytes,
        certificate.lengthInBytes,
      ),
    );
  }
}
