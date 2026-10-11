import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone/safe_zone_screen.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ten quick taps on [child] release the safe mode for a while, after the
/// device check. Nothing on screen hints at it, so whoever holds the phone
/// does not learn the way out.
class SafeModeReleaseTap extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  static const taps = 10;
  static const maxGap = Duration(seconds: 2);

  final Widget child;

  @override
  ConsumerState<SafeModeReleaseTap> createState() => _SafeModeReleaseTapState();
}

class _SafeModeReleaseTapState extends ConsumerState<SafeModeReleaseTap> {
  var _count = 0;
  DateTime? _last;

  Future<void> _tap() async {
    final now = ref.read(clockProvider).now();
    final last = _last;
    _last = now;
    final quick =
        last != null && now.difference(last) <= SafeModeReleaseTap.maxGap;
    _count = quick ? _count + 1 : 1;
    if (_count < SafeModeReleaseTap.taps) return;
    _count = 0;
    if (!ref.read(safeModeLimitedProvider)) return;
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(l10n.safeZoneReleaseReason);
    if (!passed || !mounted) return;
    ref.read(safeModeProvider.notifier).release();
    await showCdToast(
      context,
      message: safeModeStatusLabel(l10n, ref.read(safeModeProvider), locale),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _tap,
    child: widget.child,
  );
}
