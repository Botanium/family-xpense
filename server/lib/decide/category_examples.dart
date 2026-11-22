/// Typical examples per default category slug, shown in the `category`
/// option descriptions. From WP-S4, where category was 27/27 with them;
/// the D-41 categories were added in WP-33.
/// Categories a household adds have no examples; their name is enough.
library;

/// Examples by slug.
const Map<String, String> categoryExamples = {
  'food': 'food in general',
  'groceries': 'supermarket, market, fruit, vegetables, meat, food shopping',
  'dining': 'restaurants, lunch or dinner out, takeaway, delivery, cafes',
  'bakery_tea': 'bread, samoon, bakery, tea, coffee, sweets',
  'home': 'home costs in general',
  'electricity_generator':
      'electricity bill, neighbourhood generator fee (ampere), fuel for a '
      'home generator',
  'water': 'water bill, drinking water delivery',
  'apartment_gas': 'apartment gas bill, gas cylinder, cooking gas',
  'internet_fee': 'home internet, fibre, wifi, internet subscription',
  'phone_mobile_credit':
      'mobile credit top-up, phone bill, mobile data package',
  'household_goods': 'furniture, appliances, kitchen items, cleaning supplies',
  'repairs': 'plumber, electrician, home repairs',
  'transport': 'transport in general',
  'fuel': 'petrol, benzine, diesel for the car',
  'taxi': 'taxi, ride hailing (Careem, Uber)',
  'car_maintenance': 'mechanic, car repair, tyres, oil change, car wash',
  'public_transport': 'bus, minibus, train',
  'family': 'family costs in general',
  'kids_school': 'school fees, books, school supplies, kindergarten, toys',
  'clothing': 'clothes, shoes',
  'health': 'doctor, pharmacy, medicine, hospital, dentist',
  'personal_care': 'barber, salon, cosmetics, toiletries',
  'social': 'social costs in general',
  'gifts': 'presents bought for others',
  'family_support': 'money given to support parents or relatives',
  'charity': 'donations, zakat, mosque, charity',
  'occasions': 'weddings, funerals, Eid, parties, celebrations',
  'leisure': 'leisure in general',
  'entertainment': 'cinema, games, outings, hobbies',
  'travel': 'flights, hotels, trips',
  'online_subscriptions':
      'streaming, apps, online memberships (Netflix, Spotify, iCloud)',
  'finance': 'financial costs in general',
  'fees': 'bank fees, transfer fees, card fees',
  'interest': 'interest paid',
  'taxes': 'taxes, government fees',
  'other_expense': 'spending that fits no other category',
  'earned': 'earned income in general',
  'salary': 'monthly salary, wages, bonus',
  'freelance': 'freelance or side work paid per job',
  'business': 'business or shop income',
  'received': 'money received in general',
  'gift_received': 'money given to us as a gift, Eid money',
  'refund': 'refunds, returned purchases, cashback',
  'sale': 'selling our own things',
  'rental_income': 'rent received from a tenant',
  'other_income': 'income that fits no other category',
};
