import 'id_card_data.dart';

final _khmerDigits = RegExp(r'[០-៩]');
final _datePattern = RegExp(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b');
final _nameLabel = RegExp(r'^.*?នាម\s*(?:និង|នឹង)\s*នាម\s*[:៖ៈ]?\s*');
final _birthplaceLabel = RegExp(r'^ទី\s*កន្លែង\s*កំណើត\s*[:៖ៈ]?\s*');
final _addressLabel = RegExp(r'^.*?អាស.{0,5}ដ[\u17D2]?[ឋធ]ាន\s*[:៖ៈ]?\s*');
final _focusedAddressLabel = RegExp(
  r'^(?:[អរ]ាស.{0,5}|ស?យ)?ដ[\u17D2]?[ឋធ]ាន\s*[:៖ៈ]\s*',
);
final _addressContinuation = RegExp(
  r'^(?:ភូមិ|ឃុំ|សង្កាត់|ស្រុក|ខណ្ឌ|ក្រុង|ខេត្ត|រាជធានី|ផ្លូវ|ផ្ទះ|ក្រុម)',
);
final _addressNumberSuffix = RegExp(
  r'(ផ្ទះ|ផ្លូវ)\s*(?:លេខ\s*)?[:៖ៈ]?\s*([0-9០-៩]+)([C0០])(?=$|[^A-Za-z0-9០-៩])',
);
final _latinName = RegExp(
  r"^[A-Z]+(?:['-][A-Z]+)*(?: [A-Z]+(?:['-][A-Z]+)*)+$",
);
final _nameWhitespace = RegExp(r'[\s\u200B]+');
final _khmerNameWord = RegExp(r'^[\u1780-\u17B3][\u1780-\u17D3\u17DD]*$');
final _fillers = RegExp(r'^[<KLSCEAX]*$');
final _duplicateZero = RegExp(r'^[0O]*O[0O]*$');
final _asciiDigit = RegExp(r'^[0-9]$');

KhmerIdCardResult parseIdCard({
  required String mrz,
  required String printed,
  String mrzWide = '',
  String mrzCheck = '',
  String printedId = '',
  String? printedKhmerName,
  String? printedKhmerNameLine,
  String? printedEnglishName,
  String? printedLatinNameLine,
  String printedBirthplaceLine = '',
  List<String> printedAddressLines = const [],
  String printedAddressDetail = '',
  String printedValidityLine = '',
  required DateTime now,
}) {
  final printedLines = printed
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final printedLatinParts = printedEnglishName == null
      ? printedLines
            .map(_printedLatinParts)
            .firstWhere((parts) => parts.isNotEmpty, orElse: () => const [])
      : _printedLatinParts(printedEnglishName.toUpperCase());
  final latinParts = printedLatinParts.isNotEmpty
      ? printedLatinParts
      : _printedLatinParts(printedLatinNameLine?.toUpperCase() ?? '');

  final primary = _readMrz(mrz, latinParts, now, mrzCheck.trim());
  final alternate = primary.second == null && mrzWide.isNotEmpty
      ? _readMrz(mrzWide, latinParts, now, mrzCheck.trim())
      : null;
  // A second read can fill missing fields only after validating its complete
  // TD1 check digit and agreeing with any fields the first read recovered.
  final recovered =
      alternate != null &&
          alternate.second != null &&
          (primary.idNumber == null ||
              primary.idNumber == alternate.idNumber) &&
          (primary.dob == null || primary.dob == alternate.dob) &&
          (primary.expiry == null || primary.expiry == alternate.expiry) &&
          (primary.gender == null || primary.gender == alternate.gender)
      ? alternate
      : null;
  final mrz1 = primary.first ?? recovered?.first;
  final mrz2 = primary.second ?? recovered?.second;
  final mrz3 = primary.third ?? recovered?.third;
  var idNumber = primary.idNumber ?? recovered?.idNumber;
  var gender = primary.gender ?? recovered?.gender;
  var dob = primary.dob ?? recovered?.dob;
  var expiry = primary.expiry ?? recovered?.expiry;

  final visualId =
      RegExp(r'^\d{9}$').firstMatch(printedId.trim())?.group(0) ??
      printedLines.firstWhere(
        (line) => RegExp(r'^\d{9}$').hasMatch(line),
        orElse: () => '',
      );
  final khmerNameLine = printedLines.firstWhere(
    _nameLabel.hasMatch,
    orElse: () => '',
  );
  final addressIndex = printedLines.indexWhere(_addressLabel.hasMatch);
  if (!primary.hasHeader &&
      recovered == null &&
      (visualId.isEmpty || (khmerNameLine.isEmpty && addressIndex < 0))) {
    throw const FormatException(
      'Could not identify a Cambodian national ID card.',
    );
  }
  idNumber ??= visualId.isEmpty ? null : visualId;

  final fullNameLine = printedKhmerNameLine?.trim() ?? '';
  final fullName = _nameLabel.hasMatch(fullNameLine)
      ? _khmerName(fullNameLine.replaceFirst(_nameLabel, ''))
      : const <String>[];
  final khmerParts = fullName.length >= 2
      ? fullName
      : _khmerName(
          printedKhmerName ?? khmerNameLine.replaceFirst(_nameLabel, ''),
        );
  final printedDates = _printedDates(printedLines);
  final focusedDates = _printedDates([
    ...printedAddressLines,
    printedValidityLine,
  ]);
  final birthDate = printedDates.birth;
  // The printed year resolves the MRZ's two-digit year when the day agrees.
  if (birthDate != null && (dob == null || _sameShortDate(birthDate, dob))) {
    dob = birthDate;
  }
  for (final date in [
    focusedDates.expiry,
    printedDates.expiry,
  ].whereType<DateTime>()) {
    if (expiry == null || _sameShortDate(date, expiry)) {
      expiry = date;
      break;
    }
  }
  final issue = [focusedDates.issue, printedDates.issue]
      .whereType<DateTime>()
      .where((date) => expiry == null || date.isBefore(expiry))
      .firstOrNull;
  if (gender == null) {
    final birthLine = printedLines.firstWhere(
      (line) => line.contains('កំណើ'),
      orElse: () => '',
    );
    if (birthLine.contains('ប្រុស')) gender = 'M';
    if (birthLine.contains('ស្រី')) gender = 'F';
  }

  final mrzNames = _splitMrzNames(mrz3);
  final printedLatin = latinParts.join(' ');
  String? surname = mrzNames?.surname;
  String? given = mrzNames?.given;
  if (mrzNames != null &&
      printedLatin.replaceAll(RegExp(r"[-']"), ' ') ==
          '${mrzNames.surname} ${mrzNames.given}') {
    // Keep printed punctuation and use the MRZ's surname boundary.
    surname = printedLatin.substring(0, mrzNames.surname.length);
    given = printedLatin.substring(mrzNames.surname.length + 1);
  } else if (latinParts.isNotEmpty) {
    surname = latinParts.first;
    given = latinParts.skip(1).join(' ');
  }
  final focusedAddress = _readAddress(
    printedAddressLines,
    _focusedAddressLabel,
  );
  final printedAddress = _readAddress(printedLines, _addressLabel);
  final address = focusedAddress.length >= printedAddress.length
      ? focusedAddress
      : printedAddress;
  final placeOfBirth = [printedBirthplaceLine.trim(), ...printedLines]
      .where(_birthplaceLabel.hasMatch)
      .map((line) => line.replaceFirst(_birthplaceLabel, '').trim())
      .where((value) => value.isNotEmpty)
      .firstOrNull;

  return KhmerIdCardResult(
    KhmerIdCardData(
      idNumber: idNumber,
      lastNameKh: khmerParts.length >= 2 ? khmerParts.first : null,
      firstNameKh: khmerParts.length >= 2 ? khmerParts.skip(1).join(' ') : null,
      dob: _formatDate(dob),
      placeOfBirth: placeOfBirth,
      gender: gender,
      lastNameEn: surname,
      firstNameEn: given,
      expiredDate: _formatDate(expiry),
      issuedDate: _formatDate(issue),
      address: address.isEmpty
          ? null
          : _repairAddressSuffix(address.join(' '), printedAddressDetail),
      mrz1: mrz1,
      mrz2: mrz2,
      mrz3: mrz3,
    ),
  );
}

typedef _MrzRead = ({
  bool hasHeader,
  String? first,
  String? second,
  String? third,
  String? idNumber,
  String? gender,
  DateTime? dob,
  DateTime? expiry,
});

_MrzRead _readMrz(
  String mrz,
  List<String> latinParts,
  DateTime now,
  String mrzCheck,
) {
  final lines = mrz
      .toUpperCase()
      .split(RegExp(r'[\r\n]+'))
      .map(
        (line) =>
            line.replaceAll('«', '<<').replaceAll(RegExp(r'[^A-Z0-9<]'), ''),
      )
      .where((line) => line.isNotEmpty)
      .toList();
  String? mrz1;
  String? mrz2;
  String? mrz3;
  String? idNumber;
  String? gender;
  DateTime? dob;
  DateTime? expiry;
  final header = lines.indexWhere((line) => line.startsWith('IDKHM'));
  if (header >= 0) {
    final upper = lines[header];
    if (upper.length >= 15) {
      var end = 15;
      var numberAndCheck = _digits(upper.substring(5, end));
      // OCR can duplicate the leading zero. Only try the shifted number
      // when the extra glyphs resemble zero and the filler starts as expected.
      final filler = upper.indexOf('<', end);
      if (!_validCheck(numberAndCheck) &&
          (filler == 16 || filler == 17) &&
          _duplicateZero.hasMatch(upper.substring(5, filler - 9))) {
        end = filler;
        numberAndCheck = _digits(upper.substring(end - 10, end));
      }
      if (_validCheck(numberAndCheck)) {
        idNumber = numberAndCheck.substring(0, 9);
        if (_fillers.hasMatch(upper.substring(end))) {
          mrz1 = 'IDKHM$numberAndCheck'.padRight(30, '<');
        }
      }
    }
    if (header + 1 < lines.length) {
      final middle = lines[header + 1];
      if (middle.length >= 18 && middle.substring(15, 18) == 'KHM') {
        final birth = _digits(middle.substring(0, 7));
        final expiration = _digits(middle.substring(8, 15));
        final sex = middle[7];
        gender = sex == 'M' || sex == 'F' ? sex : null;
        if (_validCheck(birth)) {
          dob = _mrzDate(birth, now: now, birth: true);
        }
        if (_validCheck(expiration)) {
          expiry = _mrzDate(expiration, now: now, birth: false);
        }
        final tail = middle.substring(18);
        if (mrz1 != null &&
            dob != null &&
            expiry != null &&
            (gender != null || sex == '<') &&
            tail.isNotEmpty &&
            _fillers.hasMatch(tail.substring(0, tail.length - 1))) {
          final normalized = '$birth$sex${expiration}KHM'.padRight(29, '<');
          final composite = _checkDigit(
            '${mrz1.substring(5)}$birth$expiration${normalized.substring(18)}',
          );
          final terminal = tail[tail.length - 1];
          if (_digits(terminal) == composite ||
              (!_asciiDigit.hasMatch(terminal) && mrzCheck == composite)) {
            mrz2 = '$normalized$composite';
          }
        }
      }
    }
    if (header + 2 < lines.length) {
      mrz3 = _readNameLine(lines[header + 2], latinParts);
    }
  }

  return (
    hasHeader: header >= 0,
    first: mrz1,
    second: mrz2,
    third: mrz3,
    idNumber: idNumber,
    gender: gender,
    dob: dob,
    expiry: expiry,
  );
}

List<String> _readAddress(List<String> lines, RegExp label) {
  final start = lines.indexWhere(label.hasMatch);
  if (start < 0) return const [];
  final address = <String>[];
  final first = lines[start].replaceFirst(label, '');
  if (first.isNotEmpty) address.add(first);
  for (final line in lines.skip(start + 1)) {
    if (!_addressContinuation.hasMatch(line)) break;
    address.add(line);
  }
  return address;
}

String _repairAddressSuffix(String address, String detail) {
  if (!_focusedAddressLabel.hasMatch(detail)) return address;
  (String, String) numberKey(Match match) =>
      (match[1]!, _normalizeKhmerDigits(match[2]!));

  final confirmed = {
    for (final match in _addressNumberSuffix.allMatches(detail))
      if (match[3] == 'C') numberKey(match),
  };
  if (confirmed.isEmpty) return address;
  return address.replaceAllMapped(_addressNumberSuffix, (match) {
    final number = match[0]!;
    if (match[3] == 'C' || !confirmed.contains(numberKey(match))) return number;
    return '${number.substring(0, number.length - 1)}C';
  });
}

String _normalizeKhmerDigits(String text) => text.replaceAllMapped(
  _khmerDigits,
  (match) => '${match[0]!.codeUnitAt(0) - 0x17E0}',
);

List<String> _printedLatinParts(String text) {
  final name = text.trim().replaceAll(_nameWhitespace, ' ');
  return _latinName.hasMatch(name) ? name.split(' ') : const [];
}

List<String> _khmerName(String text) {
  final parts = text.trim().split(_nameWhitespace);
  return parts.every(_khmerNameWord.hasMatch) ? parts : const [];
}

({String surname, String given})? _splitMrzNames(String? line) {
  if (line == null) return null;
  final separator = line.indexOf('<<');
  if (separator < 0) return null;
  final surname = line.substring(0, separator).replaceAll('<', ' ').trim();
  final given = line.substring(separator + 2).replaceAll('<', ' ').trim();
  return surname.isEmpty || given.isEmpty
      ? null
      : (surname: surname, given: given);
}

String? _readNameLine(String line, List<String> printed) {
  // A complete TD1 line supplies the surname boundary.
  final exact = RegExp(r'^([A-Z]+(?:<[A-Z]+)*)<<([A-Z]+(?:<[A-Z]+)*)(<*)$');
  if (line.length == 30 && exact.hasMatch(line)) return line;
  if (printed.length >= 2) {
    final surname = printed.first.replaceAll(RegExp(r"[-']"), '<');
    final given = printed.skip(1).join('<').replaceAll(RegExp(r"[-']"), '<');
    final name = '$surname<<$given';
    final givenIndex = line.indexOf(given, surname.length);
    if (name.length <= 30 &&
        line.startsWith(surname) &&
        givenIndex >= 0 &&
        line.substring(surname.length, givenIndex).contains('<') &&
        _fillers.hasMatch(line.substring(givenIndex + given.length))) {
      return name.padRight(30, '<');
    }
  }
  // A long filler suffix distinguishes the end of the printed name from
  // a single '<' between components. Only repair after a real separator.
  final match = RegExp(
    r'^([A-Z]+(?:<[A-Z]+)*<<[A-Z]+(?:<[A-Z]+)*?)(<[<KLSCEAX]{8,})$',
  ).firstMatch(line);
  final normalized = match?.group(1);
  if (normalized != null && normalized.length <= 30) {
    return normalized.padRight(30, '<');
  }
  return null;
}

String _digits(String text) {
  const confusion = {
    'O': '0',
    'Q': '0',
    'D': '0',
    'I': '1',
    'L': '1',
    'Z': '2',
    'S': '5',
    'G': '6',
    'B': '8',
  };
  return text.split('').map((char) => confusion[char] ?? char).join();
}

bool _validCheck(String text) =>
    RegExp(r'^\d+$').hasMatch(text) &&
    _checkDigit(text.substring(0, text.length - 1)) == text[text.length - 1];

String _checkDigit(String text) {
  const weights = [7, 3, 1];
  var sum = 0;
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    final value = code == 60
        ? 0
        : code >= 65
        ? code - 55
        : code - 48;
    sum += value * weights[i % 3];
  }
  return '${sum % 10}';
}

DateTime? _date(int year, int month, int day) {
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

DateTime? _mrzDate(String value, {required DateTime now, required bool birth}) {
  final year = int.parse(value.substring(0, 2));
  final month = int.parse(value.substring(2, 4));
  final day = int.parse(value.substring(4, 6));
  final limit = birth ? now : DateTime(now.year + 30, now.month, now.day);
  final candidate = _date(limit.year ~/ 100 * 100 + year, month, day);
  if (candidate == null) return null;
  return candidate.isAfter(limit)
      ? _date(candidate.year - 100, month, day)
      : candidate;
}

bool _sameShortDate(DateTime first, DateTime second) =>
    first.year % 100 == second.year % 100 &&
    first.month == second.month &&
    first.day == second.day;

String? _formatDate(DateTime? date) => date == null
    ? null
    : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

({DateTime? birth, DateTime? issue, DateTime? expiry}) _printedDates(
  List<String> lines,
) {
  DateTime? birth;
  DateTime? issue;
  DateTime? expiry;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final next = index + 1 < lines.length ? lines[index + 1] : '';
    List<DateTime> dates(String text) => _datePattern
        .allMatches(_normalizeKhmerDigits(text))
        .map((m) => _date(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!)))
        .whereType<DateTime>()
        .where((date) => date.year >= 1900 && date.year <= 2199)
        .toList();
    final current = dates(line);
    if (line.contains('កំណើ') && !line.contains('កន្លែង')) {
      birth ??= current.firstOrNull ?? dates(next).firstOrNull;
    }
    if (line.contains('សុពលភាព') ||
        line.contains('ដល់') ||
        line.contains('ចេញ')) {
      final separator = line.indexOf('ដល់');
      if (separator >= 0) {
        issue ??= dates(line.substring(0, separator)).firstOrNull;
        expiry ??=
            dates(line.substring(separator)).firstOrNull ??
            dates(next).firstOrNull;
      } else if (current.isNotEmpty) {
        if (current.length >= 2) {
          issue ??= current.first;
          expiry ??= current[1];
        } else {
          issue ??= current.first;
          if (next.contains('ដល់')) {
            expiry ??= dates(next).firstOrNull;
          }
        }
      }
    }
  }
  return (birth: birth, issue: issue, expiry: expiry);
}
