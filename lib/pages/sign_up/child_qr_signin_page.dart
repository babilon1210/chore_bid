import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class ChildQrSignInPage extends StatefulWidget {
  const ChildQrSignInPage({super.key});

  @override
  State<ChildQrSignInPage> createState() => _ChildQrSignInPageState();
}

class _ChildQrSignInPageState extends State<ChildQrSignInPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? _controller;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void reassemble() {
    super.reassemble();
    _controller?.pauseCamera();
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Tries to parse proper JSON first.
  /// If the string looks like "{familyId: abc}" (Dart-style map .toString()),
  /// we do a tiny normalization to JSON.
  Map<String, dynamic>? _tryParseJsonish(String raw) {
    // 1) real JSON
    try {
      final obj = jsonDecode(raw);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {
      // ignore and try next
    }

    // 2) handle "{familyId: xyz}" style
    final trimmed = raw.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}') && trimmed.contains(':')) {
      // Very naive normalization: {familyId: abc} -> {"familyId":"abc"}
      // This is just to avoid crashing on the old parent QR.
      final withoutBraces = trimmed.substring(1, trimmed.length - 1); // familyId: abc
      final parts = withoutBraces.split(':');
      if (parts.length == 2) {
        final key = parts[0].trim();
        final value = parts[1].trim();
        return {
          key.replaceAll('"', ''): value.replaceAll('"', ''),
        };
      }
    }

    return null;
  }

  Future<void> _handleScan(String raw) async {
    if (_busy || _done) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      String? code;

      // Try to understand what we got
      final obj = _tryParseJsonish(raw);

      if (obj != null) {
        // We got a structured object
        final type = obj['type'];
        if (type == 'signin' && obj['code'] is String) {
          code = obj['code'] as String;
        } else if (type == 'invite') {
          // Parent showed "Sign-up QR", child is trying to scan on sign-IN page
          throw Exception('This is a ChoreBid sign-up QR. Ask parent for “Sign-in QR”.');
        } else if (obj['familyId'] != null) {
          // This is the family QR
          throw Exception('This QR is for joining/viewing a family, not for child sign-in.');
        } else {
          // some other structured QR
          throw Exception('Not a ChoreBid sign-in QR.');
        }
      } else {
        // Fallback: accept raw code if long enough
        if (raw.trim().length >= 12) {
          code = raw.trim();
        }
      }

      if (code == null) {
        throw Exception('Not a ChoreBid sign-in QR.');
      }

      // consume code via CF
      final callable =
          FirebaseFunctions.instance.httpsCallable('consumeChildSignInCode');
      final res = await callable.call({'code': code});
      final data =
          (res.data is Map) ? Map<String, dynamic>.from(res.data) : {};
      final token = data['customToken'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('No token returned.');
      }

      await FirebaseAuth.instance.signInWithCustomToken(token);

      if (!mounted) return;
      setState(() => _done = true);
      Navigator.pushReplacementNamed(context, '/splash');
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child sign-in')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: QRView(
              key: qrKey,
              onQRViewCreated: (c) {
                _controller = c;
                c.scannedDataStream.listen((scanData) {
                  _handleScan(scanData.code ?? '');
                });
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_busy) const CircularProgressIndicator(),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Ask a parent to show your “Sign-in QR”, then point the camera at it.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
