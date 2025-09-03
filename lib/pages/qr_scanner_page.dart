import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool _scanned = false;

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) controller?.pauseCamera();
    controller?.resumeCamera();
  }

  void _onQRViewCreated(QRViewController c) {
    controller = c;
    c.scannedDataStream.listen((scanData) {
      if (_scanned) return;
      _scanned = true;
      c.pauseCamera();
      Navigator.pop(context, scanData.code);
    });
  }

  void _onPermissionSet(BuildContext context, QRViewController _, bool granted) {
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission denied.')),
      );
      Navigator.pop(context); // gracefully exit the scanner
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cutOut = MediaQuery.of(context).size.width * 0.8;

    return Scaffold(
      body: Stack(
        children: [
          QRView(
            key: qrKey,
            onQRViewCreated: _onQRViewCreated,
            onPermissionSet: (ctrl, p) => _onPermissionSet(context, ctrl, p),
            overlay: QrScannerOverlayShape(
              borderColor: Colors.indigo,
              borderRadius: 10,
              borderLength: 30,
              borderWidth: 8,
              cutOutSize: cutOut,
            ),
          ),
          Positioned(
            top: 50,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
