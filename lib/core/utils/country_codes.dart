/// Country data for the Telegram-style phone input.
///
/// Contains every country with its dialing code and flag emoji, plus
/// per-country national-number digit ranges used to validate the number
/// the user types (the same way Telegram validates by country).
class CountryCode {
  final String name;
  final String code;
  final String flag;

  const CountryCode({
    required this.name,
    required this.code,
    required this.flag,
  });
}

class CountryCodes {
  static const List<CountryCode> countries = [
    CountryCode(name: 'Afghanistan', code: '+93', flag: '🇦🇫'),
    CountryCode(name: 'Albania', code: '+355', flag: '🇦🇱'),
    CountryCode(name: 'Algeria', code: '+213', flag: '🇩🇿'),
    CountryCode(name: 'Andorra', code: '+376', flag: '🇦🇩'),
    CountryCode(name: 'Angola', code: '+244', flag: '🇦🇴'),
    CountryCode(name: 'Antigua and Barbuda', code: '+1268', flag: '🇦🇬'),
    CountryCode(name: 'Argentina', code: '+54', flag: '🇦🇷'),
    CountryCode(name: 'Armenia', code: '+374', flag: '🇦🇲'),
    CountryCode(name: 'Australia', code: '+61', flag: '🇦🇺'),
    CountryCode(name: 'Austria', code: '+43', flag: '🇦🇹'),
    CountryCode(name: 'Azerbaijan', code: '+994', flag: '🇦🇿'),
    CountryCode(name: 'Bahamas', code: '+1242', flag: '🇧🇸'),
    CountryCode(name: 'Bahrain', code: '+973', flag: '🇧🇭'),
    CountryCode(name: 'Bangladesh', code: '+880', flag: '🇧🇩'),
    CountryCode(name: 'Barbados', code: '+1246', flag: '🇧🇧'),
    CountryCode(name: 'Belarus', code: '+375', flag: '🇧🇾'),
    CountryCode(name: 'Belgium', code: '+32', flag: '🇧🇪'),
    CountryCode(name: 'Belize', code: '+501', flag: '🇧🇿'),
    CountryCode(name: 'Benin', code: '+229', flag: '🇧🇯'),
    CountryCode(name: 'Bhutan', code: '+975', flag: '🇧🇹'),
    CountryCode(name: 'Bolivia', code: '+591', flag: '🇧🇴'),
    CountryCode(name: 'Bosnia and Herzegovina', code: '+387', flag: '🇧🇦'),
    CountryCode(name: 'Botswana', code: '+267', flag: '🇧🇼'),
    CountryCode(name: 'Brazil', code: '+55', flag: '🇧🇷'),
    CountryCode(name: 'Brunei', code: '+673', flag: '🇧🇳'),
    CountryCode(name: 'Bulgaria', code: '+359', flag: '🇧🇬'),
    CountryCode(name: 'Burkina Faso', code: '+226', flag: '🇧🇫'),
    CountryCode(name: 'Burundi', code: '+257', flag: '🇧🇮'),
    CountryCode(name: 'Cambodia', code: '+855', flag: '🇰🇭'),
    CountryCode(name: 'Cameroon', code: '+237', flag: '🇨🇲'),
    CountryCode(name: 'Canada', code: '+1', flag: '🇨🇦'),
    CountryCode(name: 'Cape Verde', code: '+238', flag: '🇨🇻'),
    CountryCode(name: 'Central African Republic', code: '+236', flag: '🇨🇫'),
    CountryCode(name: 'Chad', code: '+235', flag: '🇹🇩'),
    CountryCode(name: 'Chile', code: '+56', flag: '🇨🇱'),
    CountryCode(name: 'China', code: '+86', flag: '🇨🇳'),
    CountryCode(name: 'Colombia', code: '+57', flag: '🇨🇴'),
    CountryCode(name: 'Comoros', code: '+269', flag: '🇰🇲'),
    CountryCode(name: 'Congo', code: '+242', flag: '🇨🇬'),
    CountryCode(name: 'Congo (DRC)', code: '+243', flag: '🇨🇩'),
    CountryCode(name: 'Costa Rica', code: '+506', flag: '🇨🇷'),
    CountryCode(name: 'Croatia', code: '+385', flag: '🇭🇷'),
    CountryCode(name: 'Cuba', code: '+53', flag: '🇨🇺'),
    CountryCode(name: 'Cyprus', code: '+357', flag: '🇨🇾'),
    CountryCode(name: 'Czech Republic', code: '+420', flag: '🇨🇿'),
    CountryCode(name: 'Denmark', code: '+45', flag: '🇩🇰'),
    CountryCode(name: 'Djibouti', code: '+253', flag: '🇩🇯'),
    CountryCode(name: 'Dominica', code: '+1767', flag: '🇩🇲'),
    CountryCode(name: 'Dominican Republic', code: '+1849', flag: '🇩🇴'),
    CountryCode(name: 'Ecuador', code: '+593', flag: '🇪🇨'),
    CountryCode(name: 'Egypt', code: '+20', flag: '🇪🇬'),
    CountryCode(name: 'El Salvador', code: '+503', flag: '🇸🇻'),
    CountryCode(name: 'Equatorial Guinea', code: '+240', flag: '🇬🇶'),
    CountryCode(name: 'Eritrea', code: '+291', flag: '🇪🇷'),
    CountryCode(name: 'Estonia', code: '+372', flag: '🇪🇪'),
    CountryCode(name: 'Eswatini', code: '+268', flag: '🇸🇿'),
    CountryCode(name: 'Ethiopia', code: '+251', flag: '🇪🇹'),
    CountryCode(name: 'Fiji', code: '+679', flag: '🇫🇯'),
    CountryCode(name: 'Finland', code: '+358', flag: '🇫🇮'),
    CountryCode(name: 'France', code: '+33', flag: '🇫🇷'),
    CountryCode(name: 'Gabon', code: '+241', flag: '🇬🇦'),
    CountryCode(name: 'Gambia', code: '+220', flag: '🇬🇲'),
    CountryCode(name: 'Georgia', code: '+995', flag: '🇬🇪'),
    CountryCode(name: 'Germany', code: '+49', flag: '🇩🇪'),
    CountryCode(name: 'Ghana', code: '+233', flag: '🇬🇭'),
    CountryCode(name: 'Greece', code: '+30', flag: '🇬🇷'),
    CountryCode(name: 'Grenada', code: '+1473', flag: '🇬🇩'),
    CountryCode(name: 'Guatemala', code: '+502', flag: '🇬🇹'),
    CountryCode(name: 'Guinea', code: '+224', flag: '🇬🇳'),
    CountryCode(name: 'Guinea-Bissau', code: '+245', flag: '🇬🇼'),
    CountryCode(name: 'Guyana', code: '+592', flag: '🇬🇾'),
    CountryCode(name: 'Haiti', code: '+509', flag: '🇭🇹'),
    CountryCode(name: 'Honduras', code: '+504', flag: '🇭🇳'),
    CountryCode(name: 'Hungary', code: '+36', flag: '🇭🇺'),
    CountryCode(name: 'Iceland', code: '+354', flag: '🇮🇸'),
    CountryCode(name: 'India', code: '+91', flag: '🇮🇳'),
    CountryCode(name: 'Indonesia', code: '+62', flag: '🇮🇩'),
    CountryCode(name: 'Iran', code: '+98', flag: '🇮🇷'),
    CountryCode(name: 'Iraq', code: '+964', flag: '🇮🇶'),
    CountryCode(name: 'Ireland', code: '+353', flag: '🇮🇪'),
    CountryCode(name: 'Italy', code: '+39', flag: '🇮🇹'),
    CountryCode(name: 'Jamaica', code: '+1876', flag: '🇯🇲'),
    CountryCode(name: 'Japan', code: '+81', flag: '🇯🇵'),
    CountryCode(name: 'Jordan', code: '+962', flag: '🇯🇴'),
    CountryCode(name: 'Kazakhstan', code: '+7', flag: '🇰🇿'),
    CountryCode(name: 'Kenya', code: '+254', flag: '🇰🇪'),
    CountryCode(name: 'Kiribati', code: '+686', flag: '🇰🇮'),
    CountryCode(name: 'Kuwait', code: '+965', flag: '🇰🇼'),
    CountryCode(name: 'Kyrgyzstan', code: '+996', flag: '🇰🇬'),
    CountryCode(name: 'Laos', code: '+856', flag: '🇱🇦'),
    CountryCode(name: 'Latvia', code: '+371', flag: '🇱🇻'),
    CountryCode(name: 'Lebanon', code: '+961', flag: '🇱🇧'),
    CountryCode(name: 'Lesotho', code: '+266', flag: '🇱🇸'),
    CountryCode(name: 'Liberia', code: '+231', flag: '🇱🇷'),
    CountryCode(name: 'Libya', code: '+218', flag: '🇱🇾'),
    CountryCode(name: 'Liechtenstein', code: '+423', flag: '🇱🇮'),
    CountryCode(name: 'Lithuania', code: '+370', flag: '🇱🇹'),
    CountryCode(name: 'Luxembourg', code: '+352', flag: '🇱🇺'),
    CountryCode(name: 'Madagascar', code: '+261', flag: '🇲🇬'),
    CountryCode(name: 'Malawi', code: '+265', flag: '🇲🇼'),
    CountryCode(name: 'Malaysia', code: '+60', flag: '🇲🇾'),
    CountryCode(name: 'Maldives', code: '+960', flag: '🇲🇻'),
    CountryCode(name: 'Mali', code: '+223', flag: '🇲🇱'),
    CountryCode(name: 'Malta', code: '+356', flag: '🇲🇹'),
    CountryCode(name: 'Marshall Islands', code: '+692', flag: '🇲🇭'),
    CountryCode(name: 'Mauritania', code: '+222', flag: '🇲🇷'),
    CountryCode(name: 'Mauritius', code: '+230', flag: '🇲🇺'),
    CountryCode(name: 'Mexico', code: '+52', flag: '🇲🇽'),
    CountryCode(name: 'Micronesia', code: '+691', flag: '🇫🇲'),
    CountryCode(name: 'Moldova', code: '+373', flag: '🇲🇩'),
    CountryCode(name: 'Monaco', code: '+377', flag: '🇲🇨'),
    CountryCode(name: 'Mongolia', code: '+976', flag: '🇲🇳'),
    CountryCode(name: 'Montenegro', code: '+382', flag: '🇲🇪'),
    CountryCode(name: 'Morocco', code: '+212', flag: '🇲🇦'),
    CountryCode(name: 'Mozambique', code: '+258', flag: '🇲🇿'),
    CountryCode(name: 'Myanmar', code: '+95', flag: '🇲🇲'),
    CountryCode(name: 'Namibia', code: '+264', flag: '🇳🇦'),
    CountryCode(name: 'Nauru', code: '+674', flag: '🇳🇷'),
    CountryCode(name: 'Nepal', code: '+977', flag: '🇳🇵'),
    CountryCode(name: 'Netherlands', code: '+31', flag: '🇳🇱'),
    CountryCode(name: 'New Zealand', code: '+64', flag: '🇳🇿'),
    CountryCode(name: 'Nicaragua', code: '+505', flag: '🇳🇮'),
    CountryCode(name: 'Niger', code: '+227', flag: '🇳🇪'),
    CountryCode(name: 'Nigeria', code: '+234', flag: '🇳🇬'),
    CountryCode(name: 'North Korea', code: '+850', flag: '🇰🇵'),
    CountryCode(name: 'North Macedonia', code: '+389', flag: '🇲🇰'),
    CountryCode(name: 'Norway', code: '+47', flag: '🇳🇴'),
    CountryCode(name: 'Oman', code: '+968', flag: '🇴🇲'),
    CountryCode(name: 'Pakistan', code: '+92', flag: '🇵🇰'),
    CountryCode(name: 'Palau', code: '+680', flag: '🇵🇼'),
    CountryCode(name: 'Palestine', code: '+970', flag: '🇵🇸'),
    CountryCode(name: 'Panama', code: '+507', flag: '🇵🇦'),
    CountryCode(name: 'Papua New Guinea', code: '+675', flag: '🇵🇬'),
    CountryCode(name: 'Paraguay', code: '+595', flag: '🇵🇾'),
    CountryCode(name: 'Peru', code: '+51', flag: '🇵🇪'),
    CountryCode(name: 'Philippines', code: '+63', flag: '🇵🇭'),
    CountryCode(name: 'Poland', code: '+48', flag: '🇵🇱'),
    CountryCode(name: 'Portugal', code: '+351', flag: '🇵🇹'),
    CountryCode(name: 'Qatar', code: '+974', flag: '🇶🇦'),
    CountryCode(name: 'Romania', code: '+40', flag: '🇷🇴'),
    CountryCode(name: 'Russia', code: '+7', flag: '🇷🇺'),
    CountryCode(name: 'Rwanda', code: '+250', flag: '🇷🇼'),
    CountryCode(name: 'Saint Kitts and Nevis', code: '+1869', flag: '🇰🇳'),
    CountryCode(name: 'Saint Lucia', code: '+1758', flag: '🇱🇨'),
    CountryCode(name: 'Saint Vincent and the Grenadines', code: '+1784', flag: '🇻🇨'),
    CountryCode(name: 'Samoa', code: '+685', flag: '🇼🇸'),
    CountryCode(name: 'San Marino', code: '+378', flag: '🇸🇲'),
    CountryCode(name: 'Sao Tome and Principe', code: '+239', flag: '🇸🇹'),
    CountryCode(name: 'Saudi Arabia', code: '+966', flag: '🇸🇦'),
    CountryCode(name: 'Senegal', code: '+221', flag: '🇸🇳'),
    CountryCode(name: 'Serbia', code: '+381', flag: '🇷🇸'),
    CountryCode(name: 'Seychelles', code: '+248', flag: '🇸🇨'),
    CountryCode(name: 'Sierra Leone', code: '+232', flag: '🇸🇱'),
    CountryCode(name: 'Singapore', code: '+65', flag: '🇸🇬'),
    CountryCode(name: 'Slovakia', code: '+421', flag: '🇸🇰'),
    CountryCode(name: 'Slovenia', code: '+386', flag: '🇸🇮'),
    CountryCode(name: 'Solomon Islands', code: '+677', flag: '🇸🇧'),
    CountryCode(name: 'Somalia', code: '+252', flag: '🇸🇴'),
    CountryCode(name: 'South Africa', code: '+27', flag: '🇿🇦'),
    CountryCode(name: 'South Korea', code: '+82', flag: '🇰🇷'),
    CountryCode(name: 'South Sudan', code: '+211', flag: '🇸🇸'),
    CountryCode(name: 'Spain', code: '+34', flag: '🇪🇸'),
    CountryCode(name: 'Sri Lanka', code: '+94', flag: '🇱🇰'),
    CountryCode(name: 'Sudan', code: '+249', flag: '🇸🇩'),
    CountryCode(name: 'Suriname', code: '+597', flag: '🇸🇷'),
    CountryCode(name: 'Sweden', code: '+46', flag: '🇸🇪'),
    CountryCode(name: 'Switzerland', code: '+41', flag: '🇨🇭'),
    CountryCode(name: 'Syria', code: '+963', flag: '🇸🇾'),
    CountryCode(name: 'Taiwan', code: '+886', flag: '🇹🇼'),
    CountryCode(name: 'Tajikistan', code: '+992', flag: '🇹🇯'),
    CountryCode(name: 'Tanzania', code: '+255', flag: '🇹🇿'),
    CountryCode(name: 'Thailand', code: '+66', flag: '🇹🇭'),
    CountryCode(name: 'Timor-Leste', code: '+670', flag: '🇹🇱'),
    CountryCode(name: 'Togo', code: '+228', flag: '🇹🇬'),
    CountryCode(name: 'Tonga', code: '+676', flag: '🇹🇴'),
    CountryCode(name: 'Trinidad and Tobago', code: '+1868', flag: '🇹🇹'),
    CountryCode(name: 'Tunisia', code: '+216', flag: '🇹🇳'),
    CountryCode(name: 'Turkey', code: '+90', flag: '🇹🇷'),
    CountryCode(name: 'Turkmenistan', code: '+993', flag: '🇹🇲'),
    CountryCode(name: 'Tuvalu', code: '+688', flag: '🇹🇻'),
    CountryCode(name: 'Uganda', code: '+256', flag: '🇺🇬'),
    CountryCode(name: 'Ukraine', code: '+380', flag: '🇺🇦'),
    CountryCode(name: 'United Arab Emirates', code: '+971', flag: '🇦🇪'),
    CountryCode(name: 'United Kingdom', code: '+44', flag: '🇬🇧'),
    CountryCode(name: 'United States', code: '+1', flag: '🇺🇸'),
    CountryCode(name: 'Uruguay', code: '+598', flag: '🇺🇾'),
    CountryCode(name: 'Uzbekistan', code: '+998', flag: '🇺🇿'),
    CountryCode(name: 'Vanuatu', code: '+678', flag: '🇻🇺'),
    CountryCode(name: 'Vatican City', code: '+379', flag: '🇻🇦'),
    CountryCode(name: 'Venezuela', code: '+58', flag: '🇻🇪'),
    CountryCode(name: 'Vietnam', code: '+84', flag: '🇻🇳'),
    CountryCode(name: 'Yemen', code: '+967', flag: '🇾🇪'),
    CountryCode(name: 'Zambia', code: '+260', flag: '🇿🇲'),
    CountryCode(name: 'Zimbabwe', code: '+263', flag: '🇿🇼'),
  ];

  /// National-number digit ranges (min, max) per dialing code (without the
  /// leading '+'). Used to validate the number typed by the user, the same
  /// way Telegram checks the digit count for the selected country.
  static const Map<String, List<int>> _phoneLengths = {
    '+93': [9, 9], // Afghanistan
    '+355': [9, 9], // Albania
    '+213': [9, 9], // Algeria
    '+376': [6, 6], // Andorra
    '+244': [9, 9], // Angola
    '+1268': [10, 10], // Antigua and Barbuda
    '+54': [10, 10], // Argentina
    '+374': [8, 8], // Armenia
    '+61': [9, 9], // Australia
    '+43': [9, 10], // Austria
    '+994': [9, 9], // Azerbaijan
    '+1242': [10, 10], // Bahamas
    '+973': [8, 8], // Bahrain
    '+880': [10, 10], // Bangladesh
    '+1246': [10, 10], // Barbados
    '+375': [9, 9], // Belarus
    '+32': [9, 9], // Belgium
    '+501': [7, 7], // Belize
    '+229': [8, 8], // Benin
    '+975': [8, 8], // Bhutan
    '+591': [8, 8], // Bolivia
    '+387': [8, 8], // Bosnia and Herzegovina
    '+267': [7, 7], // Botswana
    '+55': [10, 11], // Brazil
    '+673': [7, 7], // Brunei
    '+359': [9, 9], // Bulgaria
    '+226': [8, 8], // Burkina Faso
    '+257': [8, 8], // Burundi
    '+855': [9, 9], // Cambodia
    '+237': [9, 9], // Cameroon
    '+1': [10, 10], // Canada / US / shared NANP
    '+238': [7, 7], // Cape Verde
    '+236': [8, 8], // Central African Republic
    '+235': [8, 8], // Chad
    '+56': [9, 9], // Chile
    '+86': [11, 11], // China
    '+57': [10, 10], // Colombia
    '+269': [7, 7], // Comoros
    '+242': [9, 9], // Congo
    '+243': [9, 9], // Congo (DRC)
    '+506': [8, 8], // Costa Rica
    '+385': [9, 9], // Croatia
    '+53': [8, 8], // Cuba
    '+357': [8, 8], // Cyprus
    '+420': [9, 9], // Czech Republic
    '+45': [8, 8], // Denmark
    '+253': [6, 6], // Djibouti
    '+1767': [10, 10], // Dominica
    '+1849': [10, 10], // Dominican Republic
    '+593': [9, 9], // Ecuador
    '+20': [10, 10], // Egypt
    '+503': [8, 8], // El Salvador
    '+240': [9, 9], // Equatorial Guinea
    '+291': [7, 7], // Eritrea
    '+372': [8, 8], // Estonia
    '+268': [8, 8], // Eswatini
    '+251': [9, 9], // Ethiopia
    '+679': [7, 7], // Fiji
    '+358': [9, 9], // Finland
    '+33': [9, 9], // France
    '+241': [6, 6], // Gabon
    '+220': [7, 7], // Gambia
    '+995': [9, 9], // Georgia
    '+49': [10, 11], // Germany
    '+233': [9, 9], // Ghana
    '+30': [10, 10], // Greece
    '+1473': [10, 10], // Grenada
    '+502': [8, 8], // Guatemala
    '+224': [8, 8], // Guinea
    '+245': [7, 7], // Guinea-Bissau
    '+592': [7, 7], // Guyana
    '+509': [8, 8], // Haiti
    '+504': [8, 8], // Honduras
    '+36': [9, 9], // Hungary
    '+354': [7, 7], // Iceland
    '+91': [10, 10], // India
    '+62': [9, 11], // Indonesia
    '+98': [10, 10], // Iran
    '+964': [10, 10], // Iraq
    '+353': [9, 9], // Ireland
    '+39': [9, 10], // Italy
    '+1876': [10, 10], // Jamaica
    '+81': [10, 10], // Japan
    '+962': [9, 9], // Jordan
    '+7': [10, 10], // Kazakhstan / Russia
    '+254': [9, 9], // Kenya
    '+686': [8, 8], // Kiribati
    '+965': [8, 8], // Kuwait
    '+996': [9, 9], // Kyrgyzstan
    '+856': [8, 8], // Laos
    '+371': [8, 8], // Latvia
    '+961': [7, 8], // Lebanon
    '+266': [8, 8], // Lesotho
    '+231': [7, 7], // Liberia
    '+218': [9, 9], // Libya
    '+423': [7, 7], // Liechtenstein
    '+370': [8, 8], // Lithuania
    '+352': [8, 8], // Luxembourg
    '+261': [9, 9], // Madagascar
    '+265': [9, 9], // Malawi
    '+60': [9, 10], // Malaysia
    '+960': [7, 7], // Maldives
    '+223': [8, 8], // Mali
    '+356': [8, 8], // Malta
    '+692': [7, 7], // Marshall Islands
    '+222': [8, 8], // Mauritania
    '+230': [8, 8], // Mauritius
    '+52': [10, 10], // Mexico
    '+691': [7, 7], // Micronesia
    '+373': [8, 8], // Moldova
    '+377': [8, 9], // Monaco
    '+976': [8, 8], // Mongolia
    '+382': [8, 8], // Montenegro
    '+212': [9, 9], // Morocco
    '+258': [9, 9], // Mozambique
    '+95': [8, 10], // Myanmar
    '+264': [9, 9], // Namibia
    '+674': [7, 7], // Nauru
    '+977': [10, 10], // Nepal
    '+31': [9, 9], // Netherlands
    '+64': [9, 10], // New Zealand
    '+505': [8, 8], // Nicaragua
    '+227': [8, 8], // Niger
    '+234': [10, 10], // Nigeria
    '+850': [10, 10], // North Korea
    '+389': [8, 8], // North Macedonia
    '+47': [8, 8], // Norway
    '+968': [8, 8], // Oman
    '+92': [10, 10], // Pakistan
    '+680': [7, 7], // Palau
    '+970': [9, 9], // Palestine
    '+507': [8, 8], // Panama
    '+675': [7, 7], // Papua New Guinea
    '+595': [9, 9], // Paraguay
    '+51': [9, 9], // Peru
    '+63': [10, 10], // Philippines
    '+48': [9, 9], // Poland
    '+351': [9, 9], // Portugal
    '+974': [8, 8], // Qatar
    '+40': [9, 9], // Romania
    '+250': [9, 9], // Rwanda
    '+1869': [10, 10], // Saint Kitts and Nevis
    '+1758': [10, 10], // Saint Lucia
    '+1784': [10, 10], // Saint Vincent and the Grenadines
    '+685': [6, 6], // Samoa
    '+378': [9, 10], // San Marino
    '+239': [7, 7], // Sao Tome and Principe
    '+966': [9, 9], // Saudi Arabia
    '+221': [9, 9], // Senegal
    '+381': [9, 9], // Serbia
    '+248': [7, 7], // Seychelles
    '+232': [8, 8], // Sierra Leone
    '+65': [8, 8], // Singapore
    '+421': [9, 9], // Slovakia
    '+386': [8, 8], // Slovenia
    '+677': [7, 7], // Solomon Islands
    '+252': [7, 9], // Somalia
    '+27': [9, 9], // South Africa
    '+82': [9, 10], // South Korea
    '+211': [9, 9], // South Sudan
    '+34': [9, 9], // Spain
    '+94': [9, 9], // Sri Lanka
    '+249': [9, 9], // Sudan
    '+597': [7, 7], // Suriname
    '+46': [9, 9], // Sweden
    '+41': [9, 9], // Switzerland
    '+963': [9, 9], // Syria
    '+886': [9, 9], // Taiwan
    '+992': [9, 9], // Tajikistan
    '+255': [9, 9], // Tanzania
    '+66': [9, 9], // Thailand
    '+670': [8, 8], // Timor-Leste
    '+228': [8, 8], // Togo
    '+676': [5, 7], // Tonga
    '+1868': [10, 10], // Trinidad and Tobago
    '+216': [8, 8], // Tunisia
    '+90': [10, 10], // Turkey
    '+993': [8, 8], // Turkmenistan
    '+688': [5, 5], // Tuvalu
    '+256': [9, 9], // Uganda
    '+380': [9, 9], // Ukraine
    '+971': [9, 9], // United Arab Emirates
    '+44': [10, 10], // United Kingdom
    '+598': [8, 8], // Uruguay
    '+998': [9, 9], // Uzbekistan
    '+678': [7, 7], // Vanuatu
    '+379': [9, 9], // Vatican City
    '+58': [10, 10], // Venezuela
    '+84': [9, 10], // Vietnam
    '+967': [9, 9], // Yemen
    '+260': [9, 9], // Zambia
    '+263': [9, 9], // Zimbabwe
  };

  /// Fallback digit range for countries not listed above (6–13 digits).
  static const List<int> _defaultLength = [6, 13];

  // Map for quick lookup by country name (case-insensitive)
  static final Map<String, CountryCode> nameMap = {
    for (var country in countries) country.name.toLowerCase(): country,
  };

  // Map for quick lookup by country code
  static final Map<String, CountryCode> codeMap = {
    for (var country in countries) country.code: country,
  };

  // Get country by name (case-insensitive)
  static CountryCode? getByName(String name) {
    return nameMap[name.toLowerCase()];
  }

  // Get country by code
  static CountryCode? getByCode(String code) {
    return codeMap[code];
  }

  // Search countries by name (partial match)
  static List<CountryCode> searchByName(String query) {
    final lowerQuery = query.toLowerCase();
    return countries.where((country) => country.name.toLowerCase().contains(lowerQuery)).toList();
  }

  // Search countries by code (partial match)
  static List<CountryCode> searchByCode(String query) {
    final lowerQuery = query.toLowerCase();
    return countries.where((country) => country.code.toLowerCase().contains(lowerQuery)).toList();
  }

  // Search countries by name OR code (partial match)
  static List<CountryCode> search(String query) {
    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isEmpty) return countries;
    return countries.where((country) {
      return country.name.toLowerCase().contains(lowerQuery) ||
          country.code.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// The (min, max) digit count for the national number of [country].
  /// The national number is the number typed by the user WITHOUT the
  /// country code (e.g. Egypt +20 → 10 digits).
  static (int, int) phoneNumberLength(CountryCode country) {
    final lengths = _phoneLengths[country.code];
    if (lengths != null) return (lengths[0], lengths[1]);
    return (_defaultLength[0], _defaultLength[1]);
  }

  // Get all country names as list
  static List<String> getCountryNames() {
    return countries.map((c) => c.name).toList();
  }

  // Get all country codes as list
  static List<String> getCountryCodes() {
    return countries.map((c) => c.code).toList();
  }

  // Get country flag by code
  static String? getFlagByCode(String code) {
    final country = codeMap[code];
    return country?.flag;
  }

  // Get country name by code
  static String? getNameByCode(String code) {
    final country = codeMap[code];
    return country?.name;
  }

  // Get country code by flag emoji
  static String? getCodeByFlag(String flag) {
    for (var country in countries) {
      if (country.flag == flag) {
        return country.code;
      }
    }
    return null;
  }

  // Check if a country has a flag emoji
  static bool hasFlagEmoji(String countryName) {
    final country = getByName(countryName);
    return country != null && country.flag.isNotEmpty;
  }

  // Get countries with flags only
  static List<CountryCode> getCountriesWithFlags() {
    return countries.where((country) => country.flag.isNotEmpty).toList();
  }
}
