/// Pure functions so they can be unit-tested without Flutter.
class Validators {
  static final _username = RegExp(r'^[a-z0-9_]{3,20}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^\+[1-9]\d{7,14}$');

  static bool username(String v) => _username.hasMatch(v.trim().toLowerCase());
  static bool email(String v) => _email.hasMatch(v.trim());

  /// E.164 international format, e.g. +967771234567
  static bool phoneE164(String v) => _phone.hasMatch(v.trim());

  static bool password(String v) => v.length >= 6;

  /// Users must be at least [minAge] years old on [today].
  static bool oldEnough(DateTime dob, {int minAge = 13, DateTime? today}) {
    final now = today ?? DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age >= minAge;
  }
}
