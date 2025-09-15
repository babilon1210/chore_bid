import 'dart:async';

import 'package:chore_bid/services/auth_service.dart';
import 'package:flutter/material.dart';

class EmailVerificationPage extends StatefulWidget {
  final String email;
  final AuthService authService;
  final Future<void> Function() onVerified;

  const EmailVerificationPage({
    super.key,
    required this.email,
    required this.authService,
    required this.onVerified,
  });

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  Timer? _timer;
  bool _checking = true;
  bool _justResent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // If already verified (rare), proceed immediately.
    _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();

    // First immediate check (no wait)
    _checkOnce();

    // Then poll every 2 seconds
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _checkOnce());
  }

  Future<void> _checkOnce() async {
    try {
      final verified = await widget.authService.reloadAndCheckVerified();
      if (verified) {
        _timer?.cancel();
        if (!mounted) return;
        setState(() => _checking = false);
        await widget.onVerified();
      } else {
        if (mounted) setState(() => _checking = false);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _justResent = true;
    });
    try {
      await widget.authService.sendVerificationEmail();
      // Cooldown UX (optional)
      await Future.delayed(const Duration(seconds: 2));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _justResent = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = const Color(0xFF0B102F);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 190, 71),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Verify your email'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              color: const Color.fromARGB(255, 253, 247, 193),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mark_email_read_outlined, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'Check your inbox',
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We sent a verification link to',
                      style: TextStyle(
                        color: textColor.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.email,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Tap the link in your email. We’ll detect it automatically and continue.',
                      style: TextStyle(
                        color: textColor.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (_checking)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _justResent ? null : _resend,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _justResent ? 'Sending…' : 'Resend verification email',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 244, 190, 71),
                          foregroundColor: const Color(0xFF0B102F),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => _checkOnce(),
                      child: const Text('I verified already, check again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
