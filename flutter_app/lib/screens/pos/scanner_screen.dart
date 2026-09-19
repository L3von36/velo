import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app.dart';
import '../../models/models.dart';
import '../../providers/shop.dart';
import '../../theme/app_theme.dart' show AppTheme;
import '../../utils/format.dart';

/// D1b — Full-screen barcode scanner for the POS. Stays open for continuous
/// scanning: every detected code is looked up through [lookup]; hits are
/// handed to [onItem] (which adds them to the cart) and confirmed with a
/// green flash + haptic. Unknown codes flash red with a "not found" chip.
/// Popping with `checkout: true` tells the POS to open the checkout sheet.
class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({
    super.key,
    required this.lookup,
    required this.onItem,
  });

  final Future<CatalogItem?> Function(String barcode) lookup;
  final void Function(CatalogItem item) onItem;

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.itf14,
      BarcodeFormat.qrCode,
    ],
  );

  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _flashTimer;
  _ScanFlash _flash = _ScanFlash.none;
  bool _torchOn = false;

  static const _sameCodeCooldown = Duration(milliseconds: 2500);

  Future<void> _onDetect(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code == null || code.isEmpty) continue;

      final now = DateTime.now();
      if (code == _lastCode && now.difference(_lastAt) < _sameCodeCooldown) {
        continue;
      }
      _lastCode = code;
      _lastAt = now;

      CatalogItem? item;
      try {
        item = await widget.lookup(code);
      } catch (_) {
        item = null;
      }
      if (!mounted) return;

      if (item != null) {
        widget.onItem(item);
        HapticFeedback.mediumImpact();
        _setFlash(_ScanFlash.hit);
      } else {
        HapticFeedback.heavyImpact();
        _setFlash(_ScanFlash.miss);
      }
      break; // handle one code per frame batch
    }
  }

  void _setFlash(_ScanFlash f) {
    _flashTimer?.cancel();
    setState(() => _flash = f);
    _flashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = _ScanFlash.none);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (_flash) {
      _ScanFlash.hit => AppTheme.success,
      _ScanFlash.miss => theme.colorScheme.error,
      _ScanFlash.none => Colors.white,
    };
    final statusText = switch (_flash) {
      _ScanFlash.hit => '✓ +1',
      _ScanFlash.miss => t(context).barcodeNotFound,
      _ScanFlash.none => t(context).scanHint,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(
              message: error.errorCode.name,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
          // Dark scrim with a rounded scan window.
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            final windowW = (w - 72).clamp(200.0, 340.0);
            final windowH = windowW * 0.62;
            final rect = Rect.fromCenter(
              center: Offset(w / 2, constraints.maxHeight / 2 - 60),
              width: windowW,
              height: windowH,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _ScanWindowPainter(rect: rect, accent: accent),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: rect.bottom + 16,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _flash == _ScanFlash.none ? 0.85 : 1,
                    child: Text(
                      statusText,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _flash == _ScanFlash.hit
                            ? AppTheme.success
                            : _flash == _ScanFlash.miss
                                ? theme.colorScheme.error
                                : Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black54)
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
          // Top bar: close, title, torch.
          SafeArea(
            bottom: false,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Text(t(context).scanBarcode,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _torchOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () async {
                    try {
                      await _controller.toggleTorch();
                      if (mounted) setState(() => _torchOn = !_torchOn);
                    } catch (_) {
                      // Torch unsupported (e.g. some browsers) — ignore.
                    }
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          // Bottom: live cart summary + checkout shortcut.
          SafeArea(
            top: false,
            child: _ScannerCartBar(onCheckout: () => Navigator.pop(context, 'checkout')),
          ),
        ],
      ),
    );
  }
}

enum _ScanFlash { none, hit, miss }

/// Live cart summary while scanning; taps jump straight to checkout.
class _ScannerCartBar extends ConsumerWidget {
  const _ScannerCartBar({required this.onCheckout});
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final empty = cart.lines.isEmpty;
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_cart_rounded,
              size: 20,
              color: empty ? Colors.white54 : AppTheme.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              empty
                  ? t(context).scanHint
                  : '${cart.itemCount} · ${Money.etb(cart.total)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: empty ? null : onCheckout,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(t(context).charge),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_rounded,
              size: 44, color: Colors.white38),
          const SizedBox(height: 14),
          Text(t(context).scanHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: onClose,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            child: Text(t(context).cancel),
          ),
        ],
      ),
    );
  }
}

/// Draws the dark scrim around the scan window plus a rounded accent border.
class _ScanWindowPainter extends CustomPainter {
  const _ScanWindowPainter({required this.rect, required this.accent});
  final Rect rect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final window = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)));
    canvas.drawPath(Path.combine(PathOperation.difference, full, window), scrim);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_ScanWindowPainter old) =>
      old.rect != rect || old.accent != accent;
}
