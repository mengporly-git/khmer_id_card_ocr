import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'card_edge_detector.dart';
import 'prepare_image.dart';

typedef CardCorners = List<math.Point<double>>;
typedef CardCropPhoto = ({
  Uint8List preview,
  int width,
  int height,
  CardCorners corners,
});
typedef CardCropRequest = ({Uint8List bytes, CardCorners corners});

const _cardAspectRatio = 1.586;
const _outputWidth = 1650;

CardCropPhoto loadCardCropPhoto(Uint8List bytes) {
  final source = _decodeCropPhoto(bytes);
  final preview = math.max(source.width, source.height) <= 1440
      ? source
      : img.copyResize(
          source,
          width: source.width >= source.height ? 1440 : null,
          height: source.height > source.width ? 1440 : null,
          interpolation: img.Interpolation.average,
        );
  final detected = detectCardEdges(preview);
  final corners = detected != null && isValidCardCrop(detected)
      ? detected
      : const <math.Point<double>>[
          math.Point(0, 0),
          math.Point(1, 0),
          math.Point(1, 1),
          math.Point(0, 1),
        ];
  return (
    preview: img.encodeJpg(preview, quality: 88),
    width: preview.width,
    height: preview.height,
    corners: corners,
  );
}

bool isValidCardCrop(CardCorners corners) {
  if (corners.length != 4) return false;
  for (var i = 0; i < 4; i++) {
    final start = corners[i];
    if (!start.x.isFinite ||
        !start.y.isFinite ||
        start.x < 0 ||
        start.x > 1 ||
        start.y < 0 ||
        start.y > 1) {
      return false;
    }
    final edge = corners[(i + 1) % 4] - start;
    final next = corners[(i + 2) % 4] - corners[(i + 1) % 4];
    if (edge.magnitude < .025 || _cross(edge, next) <= .0005) return false;
  }
  return true;
}

Uint8List straightenCardCrop(CardCropRequest crop) {
  if (!isValidCardCrop(crop.corners)) {
    throw const FormatException(
      'Move the crop handles to the four card corners.',
    );
  }
  final photo = _decodeCropPhoto(crop.bytes);
  final points = crop.corners
      .map((p) => math.Point(p.x * (photo.width - 1), p.y * (photo.height - 1)))
      .toList();
  final [topLeft, topRight, bottomRight, bottomLeft] = points;
  final edgeX = topRight - bottomRight;
  final edgeY = bottomLeft - bottomRight;
  final offset = topLeft - topRight + bottomRight - bottomLeft;
  // Inverse perspective transform from the preview rectangle to the photo.
  final determinant = _cross(edgeX, edgeY);
  final g = _cross(offset, edgeY) / determinant;
  final h = _cross(edgeX, offset) / determinant;
  final across = topRight * (1 + g) - topLeft;
  final down = bottomLeft * (1 + h) - topLeft;
  final card = img.Image(
    width: _outputWidth,
    height: (_outputWidth / _cardAspectRatio).round(),
  );
  for (final pixel in card) {
    final u = pixel.x / (card.width - 1);
    final v = pixel.y / (card.height - 1);
    final scale = 1 + g * u + h * v;
    final x = (topLeft.x + across.x * u + down.x * v) / scale;
    final y = (topLeft.y + across.y * u + down.y * v) / scale;
    final sample = photo.getPixelInterpolate(
      x.clamp(0.0, photo.width - 1.0),
      y.clamp(0.0, photo.height - 1.0),
      interpolation: img.Interpolation.linear,
    );
    pixel.setRgb(
      sample.rNormalized * 255,
      sample.gNormalized * 255,
      sample.bNormalized * 255,
    );
  }
  return img.encodeJpg(card, quality: 94);
}

double _cross(math.Point<double> a, math.Point<double> b) =>
    a.x * b.y - a.y * b.x;

img.Image _decodeCropPhoto(Uint8List bytes) {
  final source = decodeIdCardPhoto(bytes);
  if (source.width < 2 || source.height < 2) {
    throw const FormatException('The photo is too small to crop.');
  }
  return source.numChannels >= 3 && !source.hasPalette
      ? source
      : source.convert(format: img.Format.uint8, numChannels: 3);
}
