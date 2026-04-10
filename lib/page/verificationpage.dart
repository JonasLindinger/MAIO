import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

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

class _VerificationPageState extends State<VerificationPage>
    with SingleTickerProviderStateMixin {
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
      backgroundColor: _AppTheme.bg,
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
      backgroundColor: _AppTheme.surface,
      foregroundColor: _AppTheme.textPrimary,
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
              color: _AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _AppTheme.border),
      ),
    );
  }

  Color _stepColor(_VerifStep step) {
    switch (step) {
      case _VerifStep.done:
        return _AppTheme.green;
      case _VerifStep.error:
        return _AppTheme.red;
      case _VerifStep.loading:
      case _VerifStep.waitingForOther:
        return _AppTheme.blue;
      default:
        return _AppTheme.textMuted;
    }
  }

  Widget _buildBody() {
    switch (_step) {
      case _VerifStep.idle:
        return _IdleView(error: _error, onStart: _startSelfVerification);
      case _VerifStep.loading:
        return const _LoadingView();
      case _VerifStep.waitingForOther:
        return const _WaitingView();
      case _VerifStep.showEmojis:
        return _EmojiView(
          emojis: _emojis ?? [],
          onConfirm: _confirmEmojisMatch,
          onDeny: _denyEmojisMismatch,
        );
      case _VerifStep.done:
        return _DoneView(onClose: () => Navigator.of(context).pop());
      case _VerifStep.error:
        return _ErrorView(
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

enum _VerifStep { idle, loading, waitingForOther, showEmojis, done, error }

// ── Theme ────────────────────────────────────────────────────────────────────

abstract class _AppTheme {
  static const bg = Color(0xFF0C0F14);
  static const surface = Color(0xFF131820);
  static const surfaceRaised = Color(0xFF1A2030);
  static const border = Color(0xFF1E2736);
  static const borderLight = Color(0xFF2A3548);
  static const blue = Color(0xFF4C8DF6);
  static const green = Color(0xFF34C759);
  static const red = Color(0xFFFF453A);
  static const textPrimary = Color(0xFFEDF1F7);
  static const textSecondary = Color(0xFF8A95A8);
  static const textMuted = Color(0xFF4A5568);
}

// ── Shared Widgets ───────────────────────────────────────────────────────────

class _PageShell extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets padding;

  const _PageShell({
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final double size;

  const _StatusIcon({
    required this.icon,
    required this.color,
    required this.bgColor,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: _AppTheme.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.2,
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  final String text;

  const _SectionBody(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: _AppTheme.textSecondary,
        fontSize: 14,
        height: 1.6,
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final Color color;

  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = _AppTheme.blue,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  const _SecondaryButton({
    required this.label,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? _AppTheme.textSecondary;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withOpacity(0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _InfoCard({
    required this.text,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withOpacity(0.9),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step Views ───────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final String? error;
  final VoidCallback onStart;

  const _IdleView({required this.error, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      children: [
        const _StatusIcon(
          icon: Icons.verified_user_rounded,
          color: _AppTheme.blue,
          bgColor: Color(0xFF0D1829),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Verify this device'),
        const SizedBox(height: 12),
        const _SectionBody(
          'Verify your identity so others can trust your messages. '
              'Open Element or another Matrix client on a verified device '
              'and accept the incoming request.',
        ),
        const SizedBox(height: 24),
        _InfoCard(
          icon: Icons.devices_rounded,
          color: _AppTheme.blue,
          text:
          'Keep both devices unlocked and in the foreground during verification.',
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          _InfoCard(
            icon: Icons.warning_amber_rounded,
            color: _AppTheme.red,
            text: error!,
          ),
        ],
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Start Verification',
          icon: Icons.shield_rounded,
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: _AppTheme.blue,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Initialising…',
            style: TextStyle(
              color: _AppTheme.textSecondary,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView();

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _AppTheme.blue.withOpacity(0.15), width: 1),
              ),
            ),
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                color: _AppTheme.blue,
                strokeWidth: 2,
              ),
            ),
            const Icon(Icons.smartphone_rounded,
                color: _AppTheme.blue, size: 20),
          ],
        ),
        const SizedBox(height: 28),
        const _SectionTitle('Waiting for response'),
        const SizedBox(height: 12),
        const _SectionBody(
          'Accept the verification request on your other device to continue.',
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _AppTheme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _AppTheme.blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Request sent',
                style: TextStyle(
                  color: _AppTheme.textSecondary,
                  fontSize: 13,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmojiView extends StatelessWidget {
  final List<KeyVerificationEmoji> emojis;
  final VoidCallback onConfirm;
  final VoidCallback onDeny;

  const _EmojiView({
    required this.emojis,
    required this.onConfirm,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    final crossCount = isWide ? 4 : 4;

    return _PageShell(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _AppTheme.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _AppTheme.blue.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compare_arrows_rounded,
                  color: _AppTheme.blue, size: 14),
              SizedBox(width: 6),
              Text(
                'Compare on both devices',
                style: TextStyle(
                  color: _AppTheme.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle('Do the emojis match?'),
        const SizedBox(height: 8),
        const _SectionBody(
            'Check that these emojis appear in the same order on your other device.'),
        const SizedBox(height: 28),
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.9,
          ),
          itemCount: emojis.length,
          itemBuilder: (_, i) => _EmojiCell(emoji: emojis[i]),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text("No match"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _AppTheme.red,
                    side:
                    BorderSide(color: _AppTheme.red.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text("They match"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppTheme.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmojiCell extends StatelessWidget {
  final KeyVerificationEmoji emoji;

  const _EmojiCell({required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _AppTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              emoji.name,
              style: const TextStyle(
                color: _AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final VoidCallback onClose;

  const _DoneView({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      children: [
        const _StatusIcon(
          icon: Icons.verified_rounded,
          color: _AppTheme.green,
          bgColor: Color(0xFF0A1F12),
          size: 64,
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Verification complete'),
        const SizedBox(height: 12),
        const _SectionBody(
          'This device is now trusted. Your messages will show a verified '
              'badge in other Matrix clients.',
        ),
        const SizedBox(height: 24),
        _InfoCard(
          icon: Icons.check_circle_outline_rounded,
          color: _AppTheme.green,
          text: 'The unverified badge will disappear from your messages.',
        ),
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Done',
          onPressed: onClose,
          color: _AppTheme.green,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      children: [
        const _StatusIcon(
          icon: Icons.error_outline_rounded,
          color: _AppTheme.red,
          bgColor: Color(0xFF1F0A0A),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Verification failed'),
        const SizedBox(height: 12),
        _InfoCard(
          icon: Icons.info_outline_rounded,
          color: _AppTheme.red,
          text: message,
        ),
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: onRetry,
        ),
        const SizedBox(height: 12),
        _SecondaryButton(
          label: 'Cancel',
          onPressed: onClose,
        ),
      ],
    );
  }
}