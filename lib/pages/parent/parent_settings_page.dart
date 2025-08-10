import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:chore_bid/services/user_service.dart';

class ParentSettingsPage extends StatefulWidget {
  const ParentSettingsPage({super.key});

  @override
  State<ParentSettingsPage> createState() => _ParentSettingsPageState();
}

class _ParentSettingsPageState extends State<ParentSettingsPage> {
  bool _showQR = false;

  @override
  Widget build(BuildContext context) {
    final user = UserService.currentUser;
    final familyId = user?.familyId ?? '';

    final qrData = {"familyId": familyId};

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.orange[200],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _showQR = !_showQR),
              child: Text(_showQR ? 'Hide QR Code' : 'Get Family QR Code'),
            ),
            const SizedBox(height: 20),
            if (_showQR)
              Center(
                child: QrImageView(
                  data: qrData.toString(),
                  version: QrVersions.auto,
                  size: 200.0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
