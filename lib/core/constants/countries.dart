class Country {
  final String code;
  final String dial;
  final String ar;
  final String en;
  const Country(this.code, this.dial, this.ar, this.en);
  String name(bool arabic) => arabic ? ar : en;
  String get flag => code.toUpperCase().codeUnits.map((c) => String.fromCharCode(0x1F1E6 + c - 65)).join();
}

const kCountries = <Country>[
  Country('YE', '+967', 'اليمن', 'Yemen'),
  Country('SA', '+966', 'السعودية', 'Saudi Arabia'),
  Country('AE', '+971', 'الإمارات', 'United Arab Emirates'),
  Country('KW', '+965', 'الكويت', 'Kuwait'),
  Country('QA', '+974', 'قطر', 'Qatar'),
  Country('BH', '+973', 'البحرين', 'Bahrain'),
  Country('OM', '+968', 'عُمان', 'Oman'),
  Country('EG', '+20', 'مصر', 'Egypt'),
  Country('JO', '+962', 'الأردن', 'Jordan'),
  Country('LB', '+961', 'لبنان', 'Lebanon'),
  Country('SY', '+963', 'سوريا', 'Syria'),
  Country('IQ', '+964', 'العراق', 'Iraq'),
  Country('PS', '+970', 'فلسطين', 'Palestine'),
  Country('SD', '+249', 'السودان', 'Sudan'),
  Country('LY', '+218', 'ليبيا', 'Libya'),
  Country('TN', '+216', 'تونس', 'Tunisia'),
  Country('DZ', '+213', 'الجزائر', 'Algeria'),
  Country('MA', '+212', 'المغرب', 'Morocco'),
  Country('SO', '+252', 'الصومال', 'Somalia'),
  Country('TR', '+90', 'تركيا', 'Türkiye'),
  Country('GB', '+44', 'المملكة المتحدة', 'United Kingdom'),
  Country('US', '+1', 'الولايات المتحدة', 'United States'),
];

Country countryByCode(String code) => kCountries.firstWhere((c) => c.code == code, orElse: () => kCountries.first);
