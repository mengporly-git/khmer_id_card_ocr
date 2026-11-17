import 'dart:typed_data';

/// Decodes the CTC probabilities from the bundled Khmer text line model.
String decodeKhmerTextLine(
  Float32List scores,
  String dictionary, {
  double minimumCConfidence = 0,
}) {
  final tokens = ['', ...dictionary.trimRight().split(RegExp(r'\r?\n')), ' '];
  final classes = tokens.length;
  if (classes != 213 || scores.length % classes != 0) return '';

  final text = StringBuffer();
  var previous = 0;
  var confidence = 0.0;
  var characters = 0;
  for (var offset = 0; offset < scores.length; offset += classes) {
    var best = 0;
    for (var token = 1; token < classes; token++) {
      if (scores[offset + token] > scores[offset + best]) best = token;
    }
    if (best != previous && best != 0) {
      if (tokens[best] == 'C' && scores[offset + best] < minimumCConfidence) {
        return '';
      }
      text.write(tokens[best]);
      if (tokens[best] != ' ') {
        confidence += scores[offset + best];
        characters++;
      }
    }
    previous = best;
  }

  return characters > 0 && confidence / characters >= .85
      ? text.toString().trim()
      : '';
}
