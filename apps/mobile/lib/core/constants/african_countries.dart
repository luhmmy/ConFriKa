class AfricanCountryInfo {
  final String code;
  final String flag;
  final String name;
  final String region;
  final List<String> dialects;
  final String greeting;

  const AfricanCountryInfo({
    required this.code,
    required this.flag,
    required this.name,
    required this.region,
    required this.dialects,
    required this.greeting,
  });

  String get displayLabel => '$flag $name ($region) — ${dialects.join(', ')}';
  String get primaryDialectLabel => '$flag ${dialects.first} ($name)';
}

/// Complete catalog of all 54 sovereign African countries & their indigenous languages/dialects.
const List<AfricanCountryInfo> kAll54AfricanCountries = [
  AfricanCountryInfo(code: 'DZ', flag: '🇩🇿', name: 'Algeria', region: 'North Africa', dialects: ['Tamazight (Kabyle)', 'Algerian Darja', 'Tamasheq'], greeting: 'Azul fell-awen'),
  AfricanCountryInfo(code: 'AO', flag: '🇦🇴', name: 'Angola', region: 'Central/Southern Africa', dialects: ['Umbundu', 'Kimbundu', 'Kikongo', 'Chokwe'], greeting: 'Wakolapo'),
  AfricanCountryInfo(code: 'BJ', flag: '🇧🇯', name: 'Benin', region: 'West Africa', dialects: ['Fon (Fongbe)', 'Yorùbá (Nago)', 'Bariba', 'Dendi'], greeting: 'Kú àbọ̀ / Kudo'),
  AfricanCountryInfo(code: 'BW', flag: '🇧🇼', name: 'Botswana', region: 'Southern Africa', dialects: ['Setswana', 'Kalanga (Ikalanga)', 'Shekgalagari'], greeting: 'Dumelang'),
  AfricanCountryInfo(code: 'BF', flag: '🇧🇫', name: 'Burkina Faso', region: 'West Africa', dialects: ['Mooré (Mossi)', 'Dioula (Jula)', 'Fulfulde'], greeting: 'Ne y windga'),
  AfricanCountryInfo(code: 'BI', flag: '🇧🇮', name: 'Burundi', region: 'East Africa', dialects: ['Kirundi', 'Swahili'], greeting: 'Amahoro'),
  AfricanCountryInfo(code: 'CV', flag: '🇨🇻', name: 'Cabo Verde', region: 'West Africa', dialects: ['Kabuverdianu (Santiago)', 'Kabuverdianu (São Vicente)'], greeting: 'Mantenha'),
  AfricanCountryInfo(code: 'CM', flag: '🇨🇲', name: 'Cameroon', region: 'Central Africa', dialects: ['Duala', 'Ewondo', 'Bamiléké (Medumba)', 'Fulfulde'], greeting: 'Mbolo'),
  AfricanCountryInfo(code: 'CF', flag: '🇨🇫', name: 'Central African Republic', region: 'Central Africa', dialects: ['Sango', 'Banda', 'Gbaya'], greeting: 'Bara ala'),
  AfricanCountryInfo(code: 'TD', flag: '🇹🇩', name: 'Chad', region: 'Central Africa', dialects: ['Sara (Ngambay)', 'Chadian Arabic', 'Kanembu'], greeting: 'Lafia'),
  AfricanCountryInfo(code: 'KM', flag: '🇰🇲', name: 'Comoros', region: 'East Africa', dialects: ['Shikomori (Ngazidja)', 'Shindzuani', 'Shimwali'], greeting: 'Bariza djema'),
  AfricanCountryInfo(code: 'CG', flag: '🇨🇬', name: 'Congo (Republic of the)', region: 'Central Africa', dialects: ['Kituba (Munukutuba)', 'Lingala', 'Teke'], greeting: 'Mbote'),
  AfricanCountryInfo(code: 'CD', flag: '🇨🇩', name: 'Congo (DR Congo)', region: 'Central Africa', dialects: ['Lingala (Kinshasa)', 'Kiswahili (Katanga)', 'Tshiluba', 'Kikongo'], greeting: 'Mbote na bino'),
  AfricanCountryInfo(code: 'CI', flag: '🇨🇮', name: "Côte d'Ivoire", region: 'West Africa', dialects: ['Baoulé', 'Dioula', 'Bété', 'Sénoufo'], greeting: 'Akwaba'),
  AfricanCountryInfo(code: 'DJ', flag: '🇩🇯', name: 'Djibouti', region: 'East Africa', dialects: ['Somali (Issa)', 'Afar (Qafar af)'], greeting: 'Mahadsanid / Nagaa'),
  AfricanCountryInfo(code: 'EG', flag: '🇪🇬', name: 'Egypt', region: 'North Africa', dialects: ['Egyptian Masri', 'Sa’idi Arabic', 'Nubian (Nobiin)'], greeting: 'Ahlan wa sahlan'),
  AfricanCountryInfo(code: 'GQ', flag: '🇬🇶', name: 'Equatorial Guinea', region: 'Central Africa', dialects: ['Fang', 'Bube', 'Ndowe'], greeting: 'Mbolo'),
  AfricanCountryInfo(code: 'ER', flag: '🇪🇷', name: 'Eritrea', region: 'East Africa', dialects: ['Tigrinya', 'Tigre', 'Saho', 'Bilen'], greeting: 'Selam'),
  AfricanCountryInfo(code: 'SZ', flag: '🇸🇿', name: 'Eswatini', region: 'Southern Africa', dialects: ['siSwati'], greeting: 'Sawubona'),
  AfricanCountryInfo(code: 'ET', flag: '🇪🇹', name: 'Ethiopia', region: 'East Africa', dialects: ['Amharic (Amarinya)', 'Afaan Oromoo', 'Tigrinya', 'Somali'], greeting: 'Tenayistilign / Akkam'),
  AfricanCountryInfo(code: 'GA', flag: '🇬🇦', name: 'Gabon', region: 'Central Africa', dialects: ['Fang', 'Myene', 'Nzebi', 'Punu'], greeting: 'Mbolo'),
  AfricanCountryInfo(code: 'GM', flag: '🇬🇲', name: 'Gambia', region: 'West Africa', dialects: ['Mandinka', 'Wolof', 'Fula (Pulaar)', 'Jola'], greeting: 'I beodiring'),
  AfricanCountryInfo(code: 'GH', flag: '🇬🇭', name: 'Ghana', region: 'West Africa', dialects: ['Twi (Ashanti)', 'Fante', 'Ga', 'Ewe', 'Dagbani'], greeting: 'Akwaaba'),
  AfricanCountryInfo(code: 'GN', flag: '🇬🇳', name: 'Guinea', region: 'West Africa', dialects: ['Pular (Fouta Djallon)', 'Maninka', 'Susu (Sosoxui)'], greeting: 'Tana ala'),
  AfricanCountryInfo(code: 'GW', flag: '🇬🇼', name: 'Guinea-Bissau', region: 'West Africa', dialects: ['Kriol (Upper Guinea)', 'Balanta', 'Fula', 'Mandjak'], greeting: 'Kuma di korpu'),
  AfricanCountryInfo(code: 'KE', flag: '🇰🇪', name: 'Kenya', region: 'East Africa', dialects: ['Swahili (Nairobi/Mombasa)', 'Gikuyu', 'Dholuo', 'Kalenjin'], greeting: 'Karibu sana'),
  AfricanCountryInfo(code: 'LS', flag: '🇱🇸', name: 'Lesotho', region: 'Southern Africa', dialects: ['Sesotho (Southern Sotho)'], greeting: 'Khotso'),
  AfricanCountryInfo(code: 'LR', flag: '🇱🇷', name: 'Liberia', region: 'West Africa', dialects: ['Kpelle', 'Bassa', 'Kru', 'Liberian Kreyol'], greeting: 'Kua nu'),
  AfricanCountryInfo(code: 'LY', flag: '🇱🇾', name: 'Libya', region: 'North Africa', dialects: ['Libyan Arabic', 'Tamazight (Nafusi)', 'Teda'], greeting: 'Marhaba'),
  AfricanCountryInfo(code: 'MG', flag: '🇲🇬', name: 'Madagascar', region: 'East/Southern Africa', dialects: ['Malagasy (Merina)', 'Betsimisaraka', 'Sakalava'], greeting: 'Manao ahoana'),
  AfricanCountryInfo(code: 'MW', flag: '🇲🇼', name: 'Malawi', region: 'Southern Africa', dialects: ['Chichewa (Chinyanja)', 'Chitumbuka', 'Chiyao'], greeting: 'Moni onse'),
  AfricanCountryInfo(code: 'ML', flag: '🇲🇱', name: 'Mali', region: 'West Africa', dialects: ['Bambara (Bamanankan)', 'Fulfulde (Maasina)', 'Songhay', 'Dogon'], greeting: 'I ni ce'),
  AfricanCountryInfo(code: 'MR', flag: '🇲🇷', name: 'Mauritania', region: 'North/West Africa', dialects: ['Hassaniya', 'Pulaar', 'Soninke', 'Wolof'], greeting: 'Salam aleykoum'),
  AfricanCountryInfo(code: 'MU', flag: '🇲🇺', name: 'Mauritius', region: 'East/Southern Africa', dialects: ['Morisien (Mauritian Creole)', 'Bhojpuri'], greeting: 'Ki mannyer'),
  AfricanCountryInfo(code: 'MA', flag: '🇲🇦', name: 'Morocco', region: 'North Africa', dialects: ['Tamazight (Tashelhit/Riffian)', 'Moroccan Darija'], greeting: 'Azul / Merhba'),
  AfricanCountryInfo(code: 'MZ', flag: '🇲🇿', name: 'Mozambique', region: 'Southern Africa', dialects: ['Emakhuwa', 'Xichangana (Tsonga)', 'Cisena'], greeting: 'Salama'),
  AfricanCountryInfo(code: 'NA', flag: '🇳🇦', name: 'Namibia', region: 'Southern Africa', dialects: ['Oshiwambo', 'Khoekhoegowab', 'Otjiherero', 'Rukwangali'], greeting: 'Wa lalapo'),
  AfricanCountryInfo(code: 'NE', flag: '🇳🇪', name: 'Niger', region: 'West Africa', dialects: ['Hausa (Zinder/Maradi)', 'Zarma (Djerma)', 'Tamajaq', 'Kanuri'], greeting: 'Sannu da zuwa'),
  AfricanCountryInfo(
    code: 'NG',
    flag: '🇳🇬',
    name: 'Nigeria (520+ Languages)',
    region: 'West Africa',
    dialects: [
      'Yorùbá (Ọ̀yọ́ & Lagos/Èkó)',
      'Yorùbá (Ìjẹ̀bú)',
      'Yorùbá (Ẹ̀gbá & Yewa)',
      'Yorùbá (Ìjẹ̀ṣà & Ifẹ̀)',
      'Yorùbá (Èkìtì & Àkúrẹ́)',
      'Yorùbá (Oǹdó, Ìkálẹ̀ & Ìlàjẹ)',
      'Yorùbá (Ìgbómìnà, Ìlọrin & Okun)',
      'Igbo (Central / Anambra-Onitsha)',
      'Igbo (Owerri / Isuama)',
      'Igbo (Ngwa & Umuahia)',
      'Igbo (Nsukka / Enugu / Waawa)',
      'Igbo (Abakaliki: Izzi, Ezza & Ikwo)',
      'Igbo (Anioma / Delta Igbo / Ika)',
      'Igbo (Arochukwu / Ohafia / Abiriba)',
      'Hausa (Kano / Kananci)',
      'Hausa (Sokoto / Sakkwatanci)',
      'Hausa (Zaria / Zazzaganci & Katsina)',
      'Nigerian Pidgin (Naija — Nationwide)',
      'Fulfulde (Adamawa / Sokoto / Gombe)',
      'Kanuri (Yerwa / Maiduguri / Borno)',
      'Ibibio (Akwa Ibom)',
      'Efik (Calabar / Cross River)',
      'Annang (Ikot Ekpene / Akwa Ibom)',
      'Oron & Eket (Akwa Ibom)',
      'Ejagham & Bekwarra (Cross River)',
      'Tiv (Benue)',
      'Idoma & Igede (Benue)',
      'Ijaw / Izon (Bayelsa / Delta)',
      'Kalabari, Nembe & Okrika (Rivers)',
      'Ikwerre, Ekpeye & Etche (Rivers)',
      'Ogoni: Khana, Gokana & Eleme (Rivers)',
      'Edo / Bini (Benin City / Edo State)',
      'Esan / Ishan (Central Edo)',
      'Etsako / Afemai & Owan (Edo North)',
      'Urhobo (Delta Central)',
      'Isoko (Delta South)',
      'Itsekiri (Warri / Delta)',
      'Nupe (Niger / Kwara / Kogi)',
      'Igala (Kogi East)',
      'Ebira (Okene / Kogi Central)',
      'Gbagyi / Gwari (Niger / Kaduna / FCT Abuja)',
      'Berom, Ngas, Mwaghavul & Tarok (Plateau)',
      'Jukun / Wapan (Taraba)',
      'Bachama / Bwatiye, Kilba & Margi (Adamawa)',
      'Bura-Pabir, Karekare & Bade (Borno / Yobe)',
      'Bajju, Atyap (Kataf) & Ham/Jaba (Kaduna)',
    ],
    greeting: 'Ẹ káàbọ̀ / Nnọọ / Sannu da zuwa',
  ),
  AfricanCountryInfo(code: 'RW', flag: '🇷🇼', name: 'Rwanda', region: 'East Africa', dialects: ['Kinyarwanda', 'Swahili'], greeting: 'Muraho neza'),
  AfricanCountryInfo(code: 'ST', flag: '🇸🇹', name: 'São Tomé and Príncipe', region: 'Central Africa', dialects: ['Forro (Sãotomense)', 'Angolar', 'Principense'], greeting: 'Bôa tardi'),
  AfricanCountryInfo(code: 'SN', flag: '🇸🇳', name: 'Senegal', region: 'West Africa', dialects: ['Wolof (Dakar)', 'Serer', 'Pulaar', 'Jola'], greeting: 'Nanga def'),
  AfricanCountryInfo(code: 'SC', flag: '🇸🇨', name: 'Seychelles', region: 'East Africa', dialects: ['Seselwa (Seychellois Creole)'], greeting: 'Mon kontan war ou'),
  AfricanCountryInfo(code: 'SL', flag: '🇸🇱', name: 'Sierra Leone', region: 'West Africa', dialects: ['Krio', 'Mende', 'Temne', 'Limba'], greeting: 'Kushe'),
  AfricanCountryInfo(code: 'SO', flag: '🇸🇴', name: 'Somalia', region: 'East Africa', dialects: ['Somali (Maxaa Tiri)', 'Somali (Maay)'], greeting: 'Soo dhowow'),
  AfricanCountryInfo(code: 'ZA', flag: '🇿🇦', name: 'South Africa', region: 'Southern Africa', dialects: ['Zulu (isiZulu)', 'Xhosa (isiXhosa)', 'Sesotho', 'Sepedi', 'Setswana', 'Tshivenda', 'Xitsonga'], greeting: 'Sawubona / Molo'),
  AfricanCountryInfo(code: 'SS', flag: '🇸🇸', name: 'South Sudan', region: 'East Africa', dialects: ['Dinka (Thuɔŋjäŋ)', 'Nuer (Thok Naath)', 'Bari', 'Zande'], greeting: 'Cïï bak'),
  AfricanCountryInfo(code: 'SD', flag: '🇸🇩', name: 'Sudan', region: 'North/East Africa', dialects: ['Sudanese Arabic', 'Nubian', 'Beja (Bidhaawyeet)', 'Fur'], greeting: 'Habbabak'),
  AfricanCountryInfo(code: 'TZ', flag: '🇹🇿', name: 'Tanzania', region: 'East Africa', dialects: ['Swahili (Kiswahili Sanifu)', 'Sukuma', 'Chagga', 'Haya'], greeting: 'Hujambo / Karibu'),
  AfricanCountryInfo(code: 'TG', flag: '🇹🇬', name: 'Togo', region: 'West Africa', dialects: ['Ewe (Mina)', 'Kabiyè', 'Tem (Kotokoli)'], greeting: 'Woezɔ'),
  AfricanCountryInfo(code: 'TN', flag: '🇹🇳', name: 'Tunisia', region: 'North Africa', dialects: ['Tunisian Derja', 'Tamazight (Shelha)'], greeting: 'Aslema'),
  AfricanCountryInfo(code: 'UG', flag: '🇺🇬', name: 'Uganda', region: 'East Africa', dialects: ['Luganda', 'Runyankole', 'Acholi', 'Swahili'], greeting: 'Oli otya / Gyebale ko'),
  AfricanCountryInfo(code: 'ZM', flag: '🇿🇲', name: 'Zambia', region: 'Southern Africa', dialects: ['Bemba (Ichibemba)', 'Nyanja', 'Tonga', 'Lozi'], greeting: 'Mwapoleni'),
  AfricanCountryInfo(code: 'ZW', flag: '🇿🇼', name: 'Zimbabwe', region: 'Southern Africa', dialects: ['Shona (ChiShona)', 'Ndebele (isiNdebele)', 'Ndau'], greeting: 'Mauya / Salibonani'),
];

/// Flattened list of all indigenous dialects across all 54 African countries.
List<String> get kAll54AfricanDialects {
  final List<String> result = [];
  for (final c in kAll54AfricanCountries) {
    for (final d in c.dialects) {
      result.add('${c.flag} $d (${c.name})');
    }
  }
  return result;
}
