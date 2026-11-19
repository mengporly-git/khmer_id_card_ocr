import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'id_card_crop.dart';

/// Opens a four-corner crop editor and returns a straightened JPEG on approval.
///
/// Supply a [context] with a [Navigator] and JPEG, PNG, or WebP image [bytes].
/// The returned JPEG is suitable for OCR. Returns `null` if the user closes
/// the editor. Throws [FormatException] if [bytes] is empty or exceeds 25 MB.
Future<Uint8List?> showKhmerIdCardCrop(BuildContext context, Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) {
    throw const FormatException('Choose an image between 1 byte and 25 MB.');
  }
  return Navigator.of(
    context,
  ).push<Uint8List>(_cropRoute<Uint8List>(_CardCropPage(bytes: bytes)));
}

MaterialPageRoute<T> _cropRoute<T>(Widget page) => MaterialPageRoute<T>(
  builder: (context) {
    if (Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) !=
        null) {
      return page;
    }

    // Apps using the SDK's MaterialApp supply a different localization type.
    const delegate = GlobalMaterialLocalizations.delegate;
    final locale = Localizations.localeOf(context);
    return Localizations.override(
      context: context,
      locale: delegate.isSupported(locale) ? locale : const Locale('en'),
      delegates: const [delegate],
      child: page,
    );
  },
);

const _background = Color(0xFF0C0D10);
const _action = Color(0xFF0678DD);

class _CardCropPage extends StatefulWidget {
  const _CardCropPage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_CardCropPage> createState() => _CardCropPageState();
}

class _CardCropPageState extends State<_CardCropPage> {
  CardCropPhoto? _photo;
  CardCorners _corners = const [];
  int _turns = 0;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    try {
      final photo = await compute(loadCardCropPhoto, widget.bytes);
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _corners = photo.corners;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : 'Could not open this photo.';
      });
    }
  }

  void _rotate() {
    setState(() {
      _turns = (_turns + 1) % 4;
      _corners = [
        for (final i in [3, 0, 1, 2])
          math.Point(1 - _corners[i].y, _corners[i].x),
      ];
      _error = null;
    });
  }

  void _reset() {
    setState(() {
      _turns = 0;
      _corners = _photo!.corners;
      _error = null;
    });
  }

  void _move(int index, Offset delta, Size size, {required bool edge}) {
    if (_working) return;
    final next = (index + 1) % 4;
    if (edge) {
      final segment = _corners[next] - _corners[index];
      final normal = Offset(-segment.y * size.height, segment.x * size.width);
      delta =
          normal *
          ((delta.dx * normal.dx + delta.dy * normal.dy) /
              normal.distanceSquared);
    }
    final points = _corners.toList();
    final start = points[index];
    final end = edge ? points[next] : start;
    final dx = (delta.dx / size.width).clamp(
      -math.min(start.x, end.x),
      1 - math.max(start.x, end.x),
    );
    final dy = (delta.dy / size.height).clamp(
      -math.min(start.y, end.y),
      1 - math.max(start.y, end.y),
    );
    final movement = math.Point(dx.toDouble(), dy.toDouble());
    points[index] = start + movement;
    if (edge) points[next] = end + movement;
    if (isValidCardCrop(points)) {
      setState(() => _corners = points);
    }
  }

  Future<void> _review() async {
    final sourceCorners = _corners.map((point) {
      for (var turn = 0; turn < _turns; turn++) {
        point = math.Point(point.y, 1 - point.x);
      }
      return point;
    }).toList();
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final cropped = await compute(straightenCardCrop, (
        bytes: widget.bytes,
        corners: sourceCorners,
      ));
      if (!mounted) return;
      final approved = await Navigator.of(
        context,
      ).push<bool>(_cropRoute<bool>(_CropPreview(bytes: cropped)));
      if (mounted && approved == true) Navigator.of(context).pop(cropped);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : 'Could not straighten this photo.';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    return Scaffold(
      backgroundColor: _background,
      appBar: _appBar(
        'Crop ID card',
        actions: [
          IconButton(
            onPressed: photo == null || _working ? null : _rotate,
            tooltip: 'Rotate clockwise',
            icon: const Icon(Icons.rotate_right_rounded),
          ),
          IconButton(
            onPressed: photo == null || _working ? null : _reset,
            tooltip: 'Reset crop',
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: photo == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : _statusText(_error!),
                    )
                  : _photoWithHandles(photo),
            ),
            if (photo != null) ...[
              _statusText(_error ?? 'Align the handles with the card edges.'),
              _bottomAction(
                label: 'Review crop',
                icon: Icons.arrow_forward_rounded,
                onPressed: _working ? null : _review,
                busy: _working,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoWithHandles(CardCropPhoto photo) {
    final previewSize = Size(photo.width.toDouble(), photo.height.toDouble());
    final oriented = _turns.isOdd
        ? Size(previewSize.height, previewSize.width)
        : previewSize;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = Size(
            math.max(0, constraints.maxWidth - 44),
            math.max(0, constraints.maxHeight - 44),
          );
          if (available.isEmpty) return const SizedBox.shrink();
          final size = applyBoxFit(
            BoxFit.contain,
            oriented,
            available,
          ).destination;
          final photoRect = const Offset(22, 22) & size;
          return Center(
            child: SizedBox(
              width: size.width + 44,
              height: size.height + 44,
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: photoRect,
                    child: RotatedBox(
                      quarterTurns: _turns,
                      child: Image.memory(
                        photo.preview,
                        fit: BoxFit.fill,
                        semanticLabel: 'Original ID photo',
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: photoRect,
                    child: CustomPaint(painter: _CropOutline(_corners)),
                  ),
                  for (var i = 0; i < _corners.length; i++)
                    _handle(i, size, edge: true),
                  for (var i = 0; i < _corners.length; i++)
                    _handle(i, size, edge: false),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _handle(int index, Size size, {required bool edge}) {
    const corners = ['Top left', 'Top right', 'Bottom right', 'Bottom left'];
    const edges = ['Top', 'Right', 'Bottom', 'Left'];
    final start = _corners[index];
    final end = _corners[(index + 1) % 4];
    final point = edge ? (start + end) * .5 : start;
    final angle = math.atan2(
      (end.y - start.y) * size.height,
      (end.x - start.x) * size.width,
    );
    return Positioned(
      left: point.x * size.width,
      top: point.y * size.height,
      width: 44,
      height: 44,
      child: Semantics(
        label: edge
            ? '${edges[index]} crop edge'
            : '${corners[index]} crop corner',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) =>
              _move(index, details.delta, size, edge: edge),
          child: Center(
            child: Transform.rotate(
              angle: edge ? angle : 0,
              child: Container(
                width: edge ? 27 : 15,
                height: edge ? 5 : 15,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 3),
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

class _CropOutline extends CustomPainter {
  const _CropOutline(this.corners);

  final CardCorners corners;

  @override
  void paint(Canvas canvas, Size size) {
    final points = corners.map(
      (p) => Offset(p.x * size.width, p.y * size.height),
    );
    final card = Path()..addPolygon(points.toList(), true);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(card, Offset.zero);
    canvas.drawPath(outside, Paint()..color = const Color(0xA6000000));
    canvas.drawPath(
      card,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_CropOutline oldDelegate) =>
      oldDelegate.corners != corners;
}

class _CropPreview extends StatelessWidget {
  const _CropPreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _background,
    appBar: _appBar('Review ID card'),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  semanticLabel: 'Straightened ID card',
                ),
              ),
            ),
          ),
          _bottomAction(
            label: 'Scan card',
            icon: Icons.document_scanner_outlined,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ),
  );
}

AppBar _appBar(String title, {List<Widget>? actions}) => AppBar(
  title: Text(title),
  actions: actions,
  backgroundColor: _background,
  foregroundColor: Colors.white,
);

Widget _statusText(String message) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
  child: Text(
    message,
    textAlign: TextAlign.center,
    style: const TextStyle(color: Colors.white70),
  ),
);

Widget _bottomAction({
  required String label,
  required IconData icon,
  required VoidCallback? onPressed,
  bool busy = false,
}) => Padding(
  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
  child: SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _action,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF203C58),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(icon),
      label: Text(label),
    ),
  ),
);
