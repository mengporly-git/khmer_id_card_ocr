import 'package:flutter_test/flutter_test.dart';
import 'package:khmer_id_card_ocr/src/id_card_parser.dart';

void main() {
  const mrz =
      'IDKHM1234567897<<<<<<<<<<<<<<<\n'
      '8009124M3009129KHM<<<<<<<<<<<8\n'
      'HENG<<SAMOL<<<<<<<<<<<<<<<<<<<';

  test('parses the front and returns the requested envelope', () {
    final result = parseIdCard(
      mrz: mrz,
      printed:
          'គោត្តនាមនិងនាម: ហេង សំអុល\n'
          'HENG SAMOL\n'
          'អាសយដ្ឋាន៖ ភូមិព្រៃធំ ឃុំពេជសារ\n'
          'ស្រុកកោះអណ្តែត តាកែវ\n'
          'សុពលភាព៖ ១៣.០៩.២០២០ ដល់ថ្ងៃ ១២.០៩.២០៣០',
      now: DateTime(2026),
    );
    expect(result.toJson(), {
      'data': {
        'idNumber': '123456789',
        'lastNameKh': 'ហេង',
        'firstNameKh': 'សំអុល',
        'dob': '1980-09-12',
        'gender': 'M',
        'lastNameEn': 'HENG',
        'firstNameEn': 'SAMOL',
        'expiredDate': '2030-09-12',
        'issuedDate': '2020-09-13',
        'address': 'ភូមិព្រៃធំ ឃុំពេជសារ ស្រុកកោះអណ្តែត តាកែវ',
        'MRZ1': mrz.split('\n')[0],
        'MRZ2': mrz.split('\n')[1],
        'MRZ3': mrz.split('\n')[2],
      },
    });
  });

  test('repairs common digit OCR confusion using MRZ positions', () {
    final result = parseIdCard(
      mrz: mrz.replaceFirst('800912', '8OO9I2'),
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.dob, '1980-09-12');
  });

  test('recovers MRZ2 from a wider read with a valid composite digit', () {
    final middle = mrz.split('\n')[1];
    final result = parseIdCard(
      mrz: mrz.replaceFirst(middle, '8009124M3009129KHM<<<KLLKLKLKLLLE'),
      mrzWide: mrz.replaceFirst(middle, '8009124M3009129KHM<<<<K<<<KKKB'),
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.mrz2, middle);
  });

  test('rejects a wider read with a wrong composite digit', () {
    final middle = mrz.split('\n')[1];
    final result = parseIdCard(
      mrz: mrz.replaceFirst(middle, '8009124M3009129KHM<<<KLLKLKLKLLLE'),
      mrzWide: mrz.replaceFirst(middle, '8009124M3009129KHM<<<<<<<<<<<9'),
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.mrz2, isNull);
  });

  test('recovers MRZ2 from a separately read check digit', () {
    final middle = mrz.split('\n')[1];
    final result = parseIdCard(
      mrz: mrz.replaceFirst(middle, '8009124M3009129KHM<<<KLLKLKLKLLLS'),
      mrzCheck: '8',
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.mrz2, middle);
  });

  test('does not override a conflicting printed composite digit', () {
    final middle = mrz.split('\n')[1];
    final result = parseIdCard(
      mrz: mrz.replaceFirst(middle, '8009124M3009129KHM<<<<<<<<<<<9'),
      mrzCheck: '8',
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.mrz2, isNull);
  });

  test('rejects a checksum-valid wider read that disagrees with the first', () {
    final middle = mrz.split('\n')[1];
    final result = parseIdCard(
      mrz: mrz.replaceFirst(middle, '8009124M3009129KHM<<<KLLKLKLKLLLE'),
      // A TD1 composite digit does not cover the sex marker.
      mrzWide: mrz.replaceFirst('4M3009129', '4F3009129'),
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.mrz2, isNull);
    expect(result.data.gender, 'M');
  });

  test('repairs MRZ1 and MRZ2 together when the wider read checks out', () {
    final rows = mrz.split('\n');
    final result = parseIdCard(
      mrz: mrz.replaceFirst(rows[0], 'IDKHMTB1234567897<<<<<<<KKKKL'),
      mrzWide: mrz,
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.idNumber, '123456789');
    expect(result.data.mrz1, rows[0]);
    expect(result.data.mrz2, rows[1]);
  });

  test('recovers a checked card number after a duplicated leading zero', () {
    for (final extra in ['O', '0O']) {
      final result = parseIdCard(
        mrz: 'IDKHM${extra}0123456795<<<<<<<<<<<<<<<',
        printed: '',
        now: DateTime(2026),
      );
      expect(result.data.idNumber, '012345679', reason: extra);
      expect(result.data.mrz1, 'IDKHM0123456795<<<<<<<<<<<<<<<');
    }
  });

  test('does not use a corrupt MRZ date or infer an issue date', () {
    final result = parseIdCard(
      mrz: mrz.replaceFirst('800912', '800913'),
      printed: '',
      now: DateTime(2026),
    );
    expect(result.data.dob, isNull);
    expect(result.data.issuedDate, isNull);
  });

  test('uses the issue date read before the validity separator', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: 'ខ្លះ ដល់ថ្ងៃ ១២.០៩.២០៣០',
      printedValidityLine: 'សុពលភាព: ១៣.០៩.២០២០ ដល់',
      now: DateTime(2026),
    );
    expect(result.data.issuedDate, '2020-09-13');
    expect(result.data.expiredDate, '2030-09-12');
  });

  test('does not use the expiry date as the issue date', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: 'អានមិនច្បាស់ ដល់ថ្ងៃ ១២.០៩.២០៣០',
      now: DateTime(2026),
    );
    expect(result.data.issuedDate, isNull);
  });

  test('rejects OCR without a Cambodian ID signal', () {
    expect(
      () => parseIdCard(mrz: '', printed: 'HELLO', now: DateTime(2026)),
      throwsFormatException,
    );
  });

  test('uses the printed English name when MRZ3 is unreadable', () {
    final result = parseIdCard(
      mrz: mrz.split('\n').take(2).join('\n'),
      printed: 'HEADER NOISE',
      printedEnglishName: ' KHOEM   PHENG ',
      printedKhmerName: 'ឃឹម ផេង',
      now: DateTime(2026),
    );

    expect(result.data.lastNameEn, 'KHOEM');
    expect(result.data.firstNameEn, 'PHENG');
    expect(result.data.firstNameKh, 'ផេង');
    expect(result.data.mrz3, isNull);
  });

  test('keeps the MRZ name when the printed English name is unreadable', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: '',
      printedEnglishName: 'H3NG',
      now: DateTime(2026),
    );

    expect(result.data.lastNameEn, 'HENG');
    expect(result.data.firstNameEn, 'SAMOL');
  });

  test(
    'uses a second reading of the Latin row to repair an MRZ filler error',
    () {
      final result = parseIdCard(
        mrz: mrz.replaceFirst(
          mrz.split('\n').last,
          'HENG<<KSAMOL<<K<K<K<<KKKLKLLKLLKLK',
        ),
        printed: '',
        printedEnglishName: '',
        printedLatinNameLine: 'HENG SAMOL',
        now: DateTime(2026),
      );
      expect(result.data.lastNameEn, 'HENG');
      expect(result.data.firstNameEn, 'SAMOL');
      expect(result.data.mrz3, mrz.split('\n').last);
    },
  );

  test('uses the printed English spelling when MRZ OCR disagrees', () {
    final result = parseIdCard(
      mrz: mrz.replaceFirst('SAMOL', 'SAMDL'),
      printed: '',
      printedEnglishName: 'HENG SAMOL',
      now: DateTime(2026),
    );

    expect(result.data.firstNameEn, 'SAMOL');
  });

  test('uses the MRZ boundary and preserves printed name punctuation', () {
    final result = parseIdCard(
      mrz: mrz.replaceFirst(
        'HENG<<SAMOL<<<<<<<<<<<<<<<<<<<',
        'DE<SAINT<<ANNE<MARIE'.padRight(30, '<'),
      ),
      printed: '',
      printedEnglishName: 'DE SAINT ANNE-MARIE',
      now: DateTime(2026),
    );

    expect(result.data.lastNameEn, 'DE SAINT');
    expect(result.data.firstNameEn, 'ANNE-MARIE');
  });

  test('omits the Khmer name when the name recognizer could not read it', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: 'គោត្តនាមនិងនាម: ឃីម រផខ',
      printedKhmerName: '',
      now: DateTime(2026),
    );

    expect(result.data.lastNameKh, isNull);
    expect(result.data.firstNameKh, isNull);
  });

  test('takes Khmer names and dependent vowels from the complete Muol row', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: 'អាសយដ្ឋាន៖ ភូមិព្រៃធំ',
      printedKhmerName: 'ចៃ សុធ',
      printedKhmerNameLine: 'គនាមនិងនាមៈឆៃ សុធី',
      now: DateTime(2026),
    );

    expect(result.data.lastNameKh, 'ឆៃ');
    expect(result.data.firstNameKh, 'សុធី');
    expect(result.data.address, 'ភូមិព្រៃធំ');
  });

  test('uses the isolated Khmer name if the full row lacks the name label', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: '',
      printedKhmerName: 'ឆៃ សុធី',
      printedKhmerNameLine: 'ថ្ងៃខែកំណើត ឆៃ សុធី',
      now: DateTime(2026),
    );
    expect(result.data.lastNameKh, 'ឆៃ');
    expect(result.data.firstNameKh, 'សុធី');
  });

  test('recovers both printed address lines from the focused OCR rows', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: 'eg: ផ្លូវក្រុមទី១ ភូមិព្រៃធំ',
      printedAddressLines: const [
        'សយដ្ឋានៈ ផ្លូវក្រុមទី១ ភូមិព្រៃធំ',
        'ឃុំពេជសារ ស្រុកកោះអណ្តែត តាកែវ',
      ],
      now: DateTime(2026),
    );
    expect(
      result.data.address,
      'ផ្លូវក្រុមទី១ ភូមិព្រៃធំ ឃុំពេជសារ ស្រុកកោះអណ្តែត តាកែវ',
    );
  });

  test('keeps the broad text address if focused OCR has no address label', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: 'អាសយដ្ឋាន៖ ភូមិព្រៃធំ',
      printedAddressLines: const ['ទីកន្លែងកំណើត៖ ភូមិផ្សេង'],
      now: DateTime(2026),
    );
    expect(result.data.address, 'ភូមិព្រៃធំ');
  });

  test('preserves Latin house and road suffixes in Khmer addresses', () {
    final result = parseIdCard(
      mrz: mrz,
      printed: '',
      printedAddressLines: const [
        'អាសយដ្ឋានៈ ផ្ទះ១៣៩C ផ្លូវ៣៦A',
        'សង្កាត់ស្លក្រាម ក្រុងសៀមរាប',
      ],
      now: DateTime(2026),
    );
    expect(
      result.data.address,
      'ផ្ទះ១៣៩C ផ្លូវ៣៦A សង្កាត់ស្លក្រាម ក្រុងសៀមរាប',
    );
  });

  test(
    'uses a clearer read to recover a Latin C after the same address number',
    () {
      final result = parseIdCard(
        mrz: mrz,
        printed: '',
        printedAddressLines: const [
          'អាសយដ្ឋានៈ ផ្ទះ១៣៩០ ផ្លូវ៣៦A ភូមិព្រៃធំ',
          'ឃុំពេជសារ',
        ],
        printedAddressDetail: 'យដ្ឋាន: ផ្ទះ១៣៩C ផ្លូវ៣៦A ភូមិព្រៃធំ',
        now: DateTime(2026),
      );
      expect(result.data.address, 'ផ្ទះ១៣៩C ផ្លូវ៣៦A ភូមិព្រៃធំ ឃុំពេជសារ');
    },
  );

  test(
    'keeps a zero when the second reading does not confirm the same number',
    () {
      final result = parseIdCard(
        mrz: mrz,
        printed: '',
        printedAddressLines: const ['អាសយដ្ឋាន: ផ្ទះ១៣៩០'],
        printedAddressDetail: 'អាសយដ្ឋាន: ផ្ទះ១៣៨C ផ្លូវ១៣៩C',
        now: DateTime(2026),
      );
      expect(result.data.address, 'ផ្ទះ១៣៩០');
    },
  );
}
