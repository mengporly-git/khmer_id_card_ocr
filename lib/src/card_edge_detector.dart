import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

List<math.Point<double>>? detectCardEdges(img.Image photo) {
  const limit = 320;
  final image = math.max(photo.width, photo.height) <= limit
      ? photo
      : img.copyResize(
          photo,
          width: photo.width >= photo.height ? limit : null,
          height: photo.height > photo.width ? limit : null,
          interpolation: img.Interpolation.average,
        );
  final width = image.width;
  final height = image.height;
  if (math.min(width, height) < 20) return null;
  final brightness = Uint8List(width * height);
  final histogram = List<int>.filled(256, 0);
  for (final pixel in image) {
    final level = (pixel.luminanceNormalized * 255).round();
    brightness[pixel.y * width + pixel.x] = level;
    histogram[level]++;
  }

  // The crop suggestion comes from the outline of a bright, card-shaped
  // component. Try multiple cutoffs so shadows do not decide the selection.
  final cutoffs = {145, 170, 195, 215, _otsu(histogram, brightness.length)};
  ({List<math.Point<double>> points, double score})? best;
  for (final cutoff in cutoffs) {
    final candidate = _findOutline(brightness, width, height, cutoff);
    if (candidate != null && (best == null || candidate.score > best.score)) {
      best = candidate;
    }
  }
  return best?.points;
}

({List<math.Point<double>> points, double score})? _findOutline(
  Uint8List brightness,
  int width,
  int height,
  int cutoff,
) {
  final visited = Uint8List(brightness.length);
  final queue = Int32List(brightness.length);
  ({List<math.Point<double>> points, double score})? best;
  for (var seed = 0; seed < brightness.length; seed++) {
    if (brightness[seed] <= cutoff || visited[seed] != 0) continue;
    var end = 1;
    queue[0] = seed;
    visited[seed] = 1;

    void add(int index) {
      if (visited[index] != 0 || brightness[index] <= cutoff) return;
      visited[index] = 1;
      queue[end++] = index;
    }

    for (var start = 0; start < end; start++) {
      final index = queue[start];
      final x = index % width;
      if (x > 0) add(index - 1);
      if (x < width - 1) add(index + 1);
      if (index >= width) add(index - width);
      if (index < brightness.length - width) add(index + width);
    }
    if (end < brightness.length * .06 || end > brightness.length * .96) {
      continue;
    }
    final candidate = _outlineComponent(queue, end, width, height);
    if (candidate != null && (best == null || candidate.score > best.score)) {
      best = candidate;
    }
  }
  return best;
}

({List<math.Point<double>> points, double score})? _outlineComponent(
  Int32List pixels,
  int count,
  int width,
  int height,
) {
  final left = List<int>.filled(height, width);
  final right = List<int>.filled(height, -1);
  final top = List<int>.filled(width, height);
  final bottom = List<int>.filled(width, -1);
  for (var i = 0; i < count; i++) {
    final index = pixels[i];
    final y = index ~/ width;
    final x = index % width;
    left[y] = math.min(left[y], x);
    right[y] = math.max(right[y], x);
    top[x] = math.min(top[x], y);
    bottom[x] = math.max(bottom[x], y);
  }
  final boundary = <math.Point<double>>[
    for (var y = 0; y < height; y++)
      if (right[y] >= 0) ...[
        math.Point(left[y].toDouble(), y.toDouble()),
        if (right[y] > left[y]) math.Point(right[y].toDouble(), y.toDouble()),
      ],
    for (var x = 0; x < width; x++)
      if (bottom[x] >= 0) ...[
        math.Point(x.toDouble(), top[x].toDouble()),
        if (bottom[x] > top[x]) math.Point(x.toDouble(), bottom[x].toDouble()),
      ],
  ];
  final hull = _convexHull(boundary);
  if (hull.length < 4) return null;

  // Collapse small bends from rounded corners and rough pixel edges.
  while (hull.length > 4) {
    var smallest = double.infinity;
    var drop = 0;
    for (var i = 0; i < hull.length; i++) {
      final area = _triangleArea(
        hull[(i - 1 + hull.length) % hull.length],
        hull[i],
        hull[(i + 1) % hull.length],
      );
      if (area < smallest) {
        smallest = area;
        drop = i;
      }
    }
    hull.removeAt(drop);
  }

  var start = 0;
  var twiceArea = 0.0;
  for (var i = 0; i < 4; i++) {
    final p = hull[i];
    final q = hull[(i + 1) % 4];
    if (p.x + p.y < hull[start].x + hull[start].y) start = i;
    twiceArea += p.x * q.y - q.x * p.y;
  }
  final across = hull[0].distanceTo(hull[1]) + hull[2].distanceTo(hull[3]);
  final down = hull[0].distanceTo(hull[3]) + hull[1].distanceTo(hull[2]);
  final aspect = math.max(across, down) / math.min(across, down);
  final coverage = 2 * count / twiceArea;
  if (twiceArea <= 0 ||
      coverage < .56 ||
      coverage > 1.2 ||
      aspect < 1.12 ||
      aspect > 2.25) {
    return null;
  }
  final sides = List.generate(
    4,
    (i) => _fitSide(hull[i], hull[(i + 1) % 4], boundary),
  );
  final corners = List.generate(4, (i) {
    final before = sides[(i + 3) % 4];
    final after = sides[i];
    final determinant = _cross(before.direction, after.direction);
    if (determinant.abs() < .25) return hull[i];
    final ratio =
        _cross(after.origin - before.origin, after.direction) / determinant;
    final intersection = before.origin + before.direction * ratio;
    return intersection.distanceTo(hull[i]) < math.min(across, down) * .075
        ? intersection
        : hull[i];
  });
  final center = (corners[0] + corners[1] + corners[2] + corners[3]) * .25;
  final points = List<math.Point<double>>.generate(4, (i) {
    final padded = center + (corners[(start + i) % 4] - center) * 1.018;
    return math.Point(
      (padded.x / (width - 1)).clamp(0.0, 1.0),
      (padded.y / (height - 1)).clamp(0.0, 1.0),
    );
  });
  final score =
      math.min(coverage, 1.0) -
      (aspect - 1.586).abs() * .25 +
      count / (width * height) * .18;
  return (points: points, score: score);
}

({math.Point<double> origin, math.Point<double> direction}) _fitSide(
  math.Point<double> start,
  math.Point<double> end,
  List<math.Point<double>> boundary,
) {
  final length = start.distanceTo(end);
  final axis = (end - start) * (1 / length);
  var count = 0;
  var sumX = 0.0;
  var sumY = 0.0;
  var sumXX = 0.0;
  var sumXY = 0.0;
  // Extend the fitted straight sections to where sharp corners would meet.
  for (final point in boundary) {
    final offset = point - start;
    final x = axis.x * offset.x + axis.y * offset.y;
    final y = _cross(axis, offset);
    if (x < length * .18 || x > length * .82 || y.abs() > length * .06) {
      continue;
    }
    count++;
    sumX += x;
    sumY += y;
    sumXX += x * x;
    sumXY += x * y;
  }
  final determinant = count * sumXX - sumX * sumX;
  if (count < 5 || determinant < 1) {
    return (origin: start, direction: axis);
  }
  final normal = math.Point(-axis.y, axis.x);
  final slope = (count * sumXY - sumX * sumY) / determinant;
  final intercept = (sumY - slope * sumX) / count;
  return (origin: start + normal * intercept, direction: axis + normal * slope);
}

double _cross(math.Point<double> a, math.Point<double> b) =>
    a.x * b.y - a.y * b.x;

List<math.Point<double>> _convexHull(List<math.Point<double>> points) {
  points.sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

  List<math.Point<double>> chain(Iterable<math.Point<double>> ordered) {
    final result = <math.Point<double>>[];
    for (final point in ordered) {
      while (result.length >= 2 &&
          _triangleArea(result[result.length - 2], result.last, point) <= 0) {
        result.removeLast();
      }
      result.add(point);
    }
    return result;
  }

  final lower = chain(points);
  final upper = chain(points.reversed);
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

double _triangleArea(
  math.Point<double> a,
  math.Point<double> b,
  math.Point<double> c,
) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

int _otsu(List<int> histogram, int total) {
  var totalLevels = 0;
  for (var level = 0; level < histogram.length; level++) {
    totalLevels += histogram[level] * level;
  }
  var lowerLevels = 0;
  var lowerCount = 0;
  var threshold = 0;
  var best = 0.0;
  for (var level = 0; level < histogram.length; level++) {
    lowerCount += histogram[level];
    lowerLevels += histogram[level] * level;
    final upperCount = total - lowerCount;
    if (lowerCount == 0 || upperCount == 0) continue;
    final difference =
        lowerLevels / lowerCount - (totalLevels - lowerLevels) / upperCount;
    final score = lowerCount * upperCount * difference * difference;
    if (score > best) {
      best = score;
      threshold = level;
    }
  }
  return threshold;
}
