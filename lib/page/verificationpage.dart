import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../widgets/verification/done_view.dart';
import '../widgets/verification/emoji_view.dart';
import '../widgets/verification/error_view.dart';
import '../widgets/verification/idle_view.dart';
import '../widgets/verification/loading_view.dart';
import '../widgets/verification/waiting_view.dart';
import '../main.dart';

/// Full interactive SAS (emoji) verification page.
class VerificationPage extends StatefulWidget {
  final Client client;
  final KeyVerification? request;

  const VerificationPage({
    super.key,
    required this.client,
    this.request,
  });

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

enum _VerifStep { idle, loading, waitingForOther, showEmojis, done, error }

class _VerificationPageState extends State<VerificationPage> with SingleTickerProviderStateMixin {
  KeyVerification? _verification;
  _VerifStep _step = _VerifStep.idle;
  List<KeyVerificationEmoji>? _emojis;
  String? _error;
  StreamSubscription? _verifSubscription;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    if (widget.request != null) {
      _acceptIncoming(widget.request!);
    }

    bool isVerified = widget.client.unverifiedDevices.where((device) => device.deviceId == widget.client.deviceID).isEmpty;
    if (isVerified) {
      _step = _VerifStep.done;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _verifSubscription?.cancel();
    _verifSubscription = null;
    final verif = _verification;
    _verification = null;
    verif?.onUpdate = null;
    verif?.cancel();
    super.dispose();
  }

  Future<void> _startSelfVerification() async {
    setState(() {
      _step = _VerifStep.loading;
      _error = null;
    });
    try {
      final userId = widget.client.userID!;
      final userKeys = widget.client.userDeviceKeys[userId];
      if (userKeys == null) throw Exception('No user device keys found');
      final verif = await userKeys.startVerification();
      widget.client.encryption?.keyVerificationManager.addRequest(verif);
      _listenTo(verif);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _step = _VerifStep.idle;
        });
      }
    }
  }

  Future<void> _acceptIncoming(KeyVerification req) async {
    setState(() {
      _step = _VerifStep.loading;
      _error = null;
    });
    try {
      await req.acceptVerification();
      _listenTo(req);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _step = _VerifStep.idle;
        });
      }
    }
  }

  void _listenTo(KeyVerification verif) {
    _verification = verif;
    if (mounted) setState(() => _step = _VerifStep.waitingForOther);

    verif.onUpdate = () {
      if (!mounted) return;
      _applyVerifState(verif);
    };

    _verifSubscription?.cancel();
    _verifSubscription = widget.client.onSync.stream.listen((_) {
      if (!mounted) return;
      _applyVerifState(verif);
    });
  }

  void _applyVerifState(KeyVerification verif) {
    if (!mounted || _verification == null) return;
    setState(() {
      switch (verif.state) {
        case KeyVerificationState.askAccept:
          verif.acceptVerification().catchError((e) {
            if (mounted) {
              setState(() {
                _error = e.toString();
                _step = _VerifStep.error;
              });
            }
          });
          _step = _VerifStep.waitingForOther;
          break;
        case KeyVerificationState.waitingAccept:
          _step = _VerifStep.waitingForOther;
          break;
        case KeyVerificationState.askSas:
          _emojis = verif.sasEmojis;
          _step = _VerifStep.showEmojis;
          break;
        case KeyVerificationState.waitingSas:
          _step = _VerifStep.waitingForOther;
          break;
        case KeyVerificationState.askSSSS:
          _step = _VerifStep.waitingForOther;
          break;
        case KeyVerificationState.done:
          _step = _VerifStep.done;
          break;
        case KeyVerificationState.error:
          _error = 'Verification failed or was cancelled.';
          _step = _VerifStep.error;
          break;
        case KeyVerificationState.askChoice:
        case KeyVerificationState.showQRSuccess:
        case KeyVerificationState.confirmQRScan:
          break;
      }
    });
  }

  Future<void> _confirmEmojisMatch() async {
    setState(() => _step = _VerifStep.loading);
    try {
      await _verification?.acceptSas();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _step = _VerifStep.error;
        });
      }
    }
  }

  Future<void> _denyEmojisMismatch() async {
    await _verification?.rejectSas();
    if (mounted) {
      setState(() {
        _error = 'You indicated the emojis did not match.';
        _step = _VerifStep.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 520 : double.infinity),
            child: _buildBody(),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Back',
      ),
      title: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _stepColor(_step),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _stepColor(_step).withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                )
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Device Verification',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppTheme.border),
      ),
    );
  }

  Color _stepColor(_VerifStep step) {
    switch (step) {
      case _VerifStep.done:
        return AppTheme.green;
      case _VerifStep.error:
        return AppTheme.red;
      case _VerifStep.loading:
      case _VerifStep.waitingForOther:
        return AppTheme.blue;
      default:
        return AppTheme.textMuted;
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case _VerifStep.idle:
        return IdleView(error: _error, onStart: _startSelfVerification);
      case _VerifStep.loading:
        return const LoadingView();
      case _VerifStep.waitingForOther:
        return const WaitingView();
      case _VerifStep.showEmojis:
        return EmojiView(
          emojis: _emojis ?? [],
          onConfirm: _confirmEmojisMatch,
          onDeny: _denyEmojisMismatch,
        );
      case _VerifStep.done:
        return DoneView(onClose: () => Navigator.of(context).pop());
      case _VerifStep.error:
        return ErrorView(
          message: _error ?? 'Unknown error',
          onRetry: () => setState(() {
            _step = _VerifStep.idle;
            _error = null;
          }),
          onClose: () => Navigator.of(context).pop(),
        );
    }
  }
}