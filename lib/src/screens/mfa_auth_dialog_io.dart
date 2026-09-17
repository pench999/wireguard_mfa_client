import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

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
) {
  return showDialog<MfaAuthDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _MfaAuthDialog(authenticationUrl: authenticationUrl),
  );
}

class _MfaAuthDialog extends StatefulWidget {
  const _MfaAuthDialog({required this.authenticationUrl});

  final Uri authenticationUrl;

  @override
  State<_MfaAuthDialog> createState() => _MfaAuthDialogState();
}

class _MfaAuthDialogState extends State<_MfaAuthDialog> {
  WebviewController? _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      _setError('アプリ内認証はWindows版で利用できます。');
      return;
    }
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null) {
        _setError('Microsoft Edge WebView2 Runtimeが見つかりません。');
        return;
      }
      final controller = WebviewController();
      await controller.initialize();
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      await controller.setDefaultContextMenusEnabled(false);
      _subscriptions.add(
        controller.url.listen((value) {
          final candidate = Uri.tryParse(value);
          if (candidate == null ||
              !isSameOrigin(widget.authenticationUrl, candidate)) {
            unawaited(controller.stop());
            _setError('設定されたMFAサーバー以外への移動をブロックしました。');
          }
        }),
      );
      _subscriptions.add(
        controller.loadingState.listen((state) {
          if (mounted) setState(() => _loading = state == LoadingState.loading);
        }),
      );
      _subscriptions.add(
        controller.onLoadError.listen((_) {
          _setError('認証ページを読み込めませんでした。証明書とネットワークを確認してください。');
        }),
      );
      _controller = controller;
      await controller.loadUrl(widget.authenticationUrl.toString());
      if (mounted) setState(() {});
    } on PlatformException {
      _setError('WebView2を初期化できませんでした。');
    } catch (_) {
      _setError('アプリ内認証を開始できませんでした。');
    }
  }

  void _setError(String value) {
    if (!mounted) return;
    setState(() {
      _error = value;
      _loading = false;
    });
  }

  Future<void> _openExternalBrowser() async {
    final opened = await launchUrl(
      widget.authenticationUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted) return;
    if (!opened) {
      _setError('既定ブラウザを開けませんでした。');
      return;
    }
    Navigator.of(context).pop(MfaAuthDialogResult.externalBrowser);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: FractionallySizedBox(
        widthFactor: 0.96,
        heightFactor: 0.94,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 510),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.authenticationUrl.host,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _openExternalBrowser,
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: const Text('外部ブラウザ'),
                    ),
                    IconButton(
                      onPressed: () =>
                          Navigator.of(context)
                              .pop(MfaAuthDialogResult.cancelled),
                      tooltip: '認証をキャンセル',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Stack(
                  children: [
                    if (controller != null && controller.value.isInitialized)
                      Webview(
                        controller,
                        permissionRequested: (_, _, _) async =>
                            WebviewPermissionDecision.deny,
                      )
                    else if (_error == null)
                      const Center(child: CircularProgressIndicator()),
                    if (_error != null)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 38),
                                const SizedBox(height: 12),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: _openExternalBrowser,
                                  icon: const Icon(Icons.open_in_browser),
                                  label: const Text('外部ブラウザで続ける'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_loading && _error == null)
                      const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
