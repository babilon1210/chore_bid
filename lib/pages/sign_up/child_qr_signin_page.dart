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
    // iOS doesn’t need this, but it’s harmless
    _controller?.pauseCamera();
    _controller?.resumeCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleScan(String raw) async {
    if (_busy || _done) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // Expecting {"v":1,"type":"signin","code":"..."}
      String? code;
      try {
        final obj = jsonDecode(raw);
        if (obj is Map && obj['type'] == 'signin' && obj['code'] is String) {
          code = obj['code'] as String;
        }
      } catch (_) {
        // Fallback: accept raw code if it looks like one
        if (raw.trim().length >= 12) code = raw.trim();
      }
      if (code == null) {
        throw Exception('Not a ChoreBid sign-in QR.');
      }

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
