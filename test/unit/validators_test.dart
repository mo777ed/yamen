import 'package:flutter_test/flutter_test.dart';
import 'package:yemen_chat/core/utils/validators.dart';

void main() {
  group('Validators.username', () {
    test('accepts lowercase letters, digits and underscore', () {
      expect(Validators.username('ali_99'), isTrue);
      expect(Validators.username('ABC'), isTrue); // normalised to lowercase
    });
    test('rejects short, long and special characters', () {
      expect(Validators.username('ab'), isFalse);
      expect(Validators.username('a' * 21), isFalse);
      expect(Validators.username('ali name'), isFalse);
      expect(Validators.username('علي'), isFalse);
    });
  });

  group('Validators.phoneE164', () {
    test('requires + and country code', () {
      expect(Validators.phoneE164('+967771234567'), isTrue);
      expect(Validators.phoneE164('0771234567'), isFalse);
      expect(Validators.phoneE164('+0123456789'), isFalse);
    });
  });

  test('email and password', () {
    expect(Validators.email('a@b.co'), isTrue);
    expect(Validators.email('a@b'), isFalse);
    expect(Validators.password('123456'), isTrue);
    expect(Validators.password('12345'), isFalse);
  });

  group('Validators.oldEnough', () {
    final today = DateTime(2026, 6, 15);
    test('exactly 13 today is allowed', () => expect(Validators.oldEnough(DateTime(2013, 6, 15), today: today), isTrue));
    test('one day short is rejected', () => expect(Validators.oldEnough(DateTime(2013, 6, 16), today: today), isFalse));
    test('adult is allowed', () => expect(Validators.oldEnough(DateTime(1990, 1, 1), today: today), isTrue));
  });
}
