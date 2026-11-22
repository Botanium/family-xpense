# WP-S4 token and latency breakdown per question

Message exp-02 with one duplicate candidate; shared input is 365 characters. Each row is 3 runs; latency is the median.

```text
Today: 2026-11-22 (Sunday). Household currency: USD. Speaker: Dara (me). Partner: Shilan.
People: Alex (friend), Karwan (Dara's brother), Rebin (colleague), Aram (Dara's uncle), Mom (Dara's mother).
Already parsed: amount USD 42.8, date today.
Message: """42.80 at Costco for groceries, joint card"""
Recent entries:
- USD 42.80, 2026-11-22, Costco, Joint Visa card
```

| request | input tokens | median ms |
|---|---|---|
| shared input + one 5-word yes/no question (baseline) | 220 | 426 |
| `intent` alone | 454 (+234) | 296 |
| `category` alone | 1037 (+817) | 285 |
| `account` alone | 500 (+280) | 296 |
| `who` alone | 260 (+40) | 326 |
| `multi_entry` alone | 272 (+52) | 284 |
| `repayable` alone | 279 (+59) | 269 |
| `needs_followup` alone | 293 (+73) | 275 |
| `is_recurring` alone | 271 (+51) | 280 |
| `duplicate` alone | 269 (+49) | 225 |
| `category` alone, 45 options (with groups) | 1179 (+959) | 281 |
| all 9 questions | 2227 | 321 |

Shared input billed once: the 9 questions alone add 1655 tokens over the baseline in total; the full request is 2007 over the baseline.
