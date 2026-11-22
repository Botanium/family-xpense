# WP-S4 duplicate question: two wordings

| message | candidate | label | P(yes) v1 | P(yes) v2 |
|---|---|---|---|---|
| 42.80 at Costco for groceries, joint card | USD 42.80, 2026-11-22, Costco, Joint Visa card | true | 0.97 | 0.99 |
| Paid the generator guy 50,000 dinars for this month | IQD 50,000, 2026-11-21, Generator fee, November | true | 0.38 | 0.69 |
| Netflix subscription 15.99 on my checking account | USD 15.99, 2026-11-21, Netflix, Checking account | true | 0.23 | 0.80 |
| Took a taxi to work, 7,500 dinars | IQD 7,500, 2026-11-22, Taxi home | false | 0.03 | 0.12 |
| My salary came in, 3,200 dollars to checking | USD 3,200, 2026-11-21, Salary, Checking account | true | 0.39 | 0.89 |
| Sold the old fridge for 150,000 dinars | IQD 150,000, 2026-11-22, Sold the old washing machine | false | 0.01 | 0.08 |
| Alex paid me back the 300 he owed | USD 300, 2026-11-22, Repayment from Alex | true | 0.85 | 0.85 |
| Paid rent 450 from checking | USD 450, 2026-11-21, Rent, November, Checking account | true | 0.38 | 0.89 |
| Internet bill 35,000 dinars | IQD 35,000, 2026-11-21, Internet bill | true | 0.33 | 0.79 |
| Got 100 dollars from Mom for Eid | USD 100, 2026-11-22, Eid gift from Mom | true | 0.97 | 0.99 |
| Costco groceries 42.80 on the joint card | USD 42.80, 2026-11-21, Costco, Joint Visa card | true | 0.51 | 0.83 |
| Bread 2,000 | IQD 2,000, 2026-11-21, Bread | false | 0.14 | 0.20 |
| Taxi back home 5,000 | IQD 5,000, 2026-11-22, Taxi to work | false | 0.01 | 0.04 |
| Gave the neighbour's kid 5,000 dinars for Eid | IQD 5,000, 2026-11-22, Eid money for nephew Rawa | false | 0.06 | 0.15 |

- v1: 64.3% (9/14) at 0.5; Brier 0.176; at `dup_warn` 0.80: warns on 3 of 9 duplicates and 0 of 5 non-duplicates.
- v2: 100.0% (14/14) at 0.5; Brier 0.024; at `dup_warn` 0.80: warns on 6 of 9 duplicates and 0 of 5 non-duplicates.
