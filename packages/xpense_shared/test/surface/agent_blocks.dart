/// Express blocks written as the agent would, one per fixture in
/// `test/fixtures/surfaces/agent_*.json`. Each is compiled by genkit_a2ui
/// (the server's compiler, strict mode), so the fixtures are real server
/// output. Together with the local fixtures they cover every component of
/// the catalog, for the app's golden tests.
library;

/// Express source by fixture name (without `agent_` and `.json`).
const Map<String, String> agentBlocks = {
  // A2UI_CATALOG 7, verbatim.
  'two_entries': r'''
surface("cap_k3m9")
$/drafts = [
  {id: "d1", intent: "income", amountMinor: 320000, currency: "USD", categoryId: "salary",
   accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Salary",
   confidence: {intent: 0.99, category: 0.97, account: 0.96}},
  {id: "d2", intent: "expense", amountMinor: 140000, currency: "USD", categoryId: "rent",
   accountId: "acc_chk", who: "joint", occurredOn: "2026-11-22", title: "Rent",
   confidence: {intent: 0.98, category: 0.99, account: 0.97}, guessed: ["who"]}
]
root = EntryList($/drafts, "review", "I found two things in that:")''',
  'intent_question': r'''
surface("cap_p7x2")
$/drafts = [{id: "d1", intent: "loan_given", amountMinor: 30000, currency: "USD",
  personName: "Alex", accountId: "acc_chk", occurredOn: "2026-11-22", missing: ["intent"]}]
root = Column([ask, list])
ask = ChoicePrompt("Quick check, so I file it right: will Alex pay this back?",
  [{label: "Yes, it's a loan", value: "loan_given", hint: "Alex owes us"},
   {label: "No, gift or payment", value: "expense", hint: "Expense"},
   {label: "I was paying Alex back", value: "repayment_made", hint: "Debt"}],
  $/drafts/0/intent)
list = EntryList($/drafts)''',
  'analytics_answer': r'''
surface("ans_food_nov")
$/result = {total: 48650, rows: [{label: "Groceries", amountMinor: 38600, share: 0.79},
  {label: "Dining", amountMinor: 10050, share: 0.21}]}
root = Column([head, total, rows, chips])
head = Text("Food in November")
total = MoneyText($/result/total, "USD", "large")
rows = BreakdownList($/result/rows, "USD")
chips = SuggestionChips([{label: "By week", message: "Show food spending by week this month"},
  {label: "Compare to October", message: "Compare food spending with October"}])''',
  // A month review: Markdown text, ledger rows, the thin chart, a budget.
  'month_review': r'''
surface("ans_month_nov")
$/result = {days: [120, 80, 0, 210, 340, 95, 180, 260, 150, 75, 300, 410, 220, 190],
  income: 565000, spent: 312040, saved: 60000}
root = Column([intro, ledger, rule, chart, budget])
intro = Text("## November so far\nYou spent **less** than October. Two things stood out:\n- Dining is *near* its limit\n- Rent is paid")
ledger = Column([inc, out, sav])
inc = LedgerRow("Income", $/result/income, "USD", "income")
out = LedgerRow("Spent", $/result/spent, "USD", "spent")
sav = LedgerRow("Saved", $/result/saved, "USD", "saved")
rule = Divider()
chart = MiniBars($/result/days, "avg 202/day", "last", "Daily spending for November 1 to 14; today is the highest")
budget = BudgetMeter("Dining", 85000, 120000, "IQD")''',
  // Loans, goals and recent transactions; a template list of money rows.
  'loans_goals': r'''
surface("ans_people")
$/result = {txns: [
  {txnId: "t_101", title: "Lunch with the kids", subtitle: "Dining · Cash", amountMinor: 10000, currency: "IQD", type: "expense", occurredOn: "2026-11-22"},
  {txnId: "t_102", title: "Salary", subtitle: "Income · Checking", amountMinor: 320000, currency: "USD", type: "income", occurredOn: "2026-11-21"}],
  rows: [{label: "Alex", amountMinor: 20000}, {label: "Sam", amountMinor: 5000}]}
root = Column([loan, goal, people, recent])
loan = LoanCard("Alex", "given", 20000, 30000, "USD", "2026-12-15", "loan_7")
goal = GoalCard("Holiday", 120000, 300000, "USD", "On track, 120/mo", "goal_2")
people = List(_template($/result/rows, person))
person = Row([who, owed], "spaceBetween")
who = Text($label)
owed = MoneyText($amountMinor, "USD", "small", "none", "loan")
recent = TransactionList($/result/txns, "Nothing yet.")''',
  // An agent form: inputs with checks, a button that echoes the paths.
  'refine_form': r'''
surface("ref_note")
$/answer = {note: "", day: "2026-11-22"}
root = Column([ask, note, day, send])
ask = Text("What should I change?", "caption")
note = TextField("Note", $/answer/note, "e.g. it was split with my sister", "longText")
day = DateTimeInput($/answer/day, true, false, _, _, "Day")
send = Button(sendLabel, "primary", Event("xp.refine", {note: $/answer/note, day: $/answer/day}), [?required($/answer/note, "Say a few words")])
sendLabel = Text("Send")''',
  // Conversation cards from the agent, with real (not local) actions.
  'nudges': '''
surface("nudge_mix")
root = Column([rate, report, offline])
rate = Nudge("No dollar rate yet today.", "rate", "Set it", Event("xp.more", {topic: "rate"}))
report = Nudge("Your October report is ready.", "report")
offline = Notice("Answers need a connection; typed entries still save.", "privacy")''',
  // A receipt read in the cloud, not split.
  'receipt_cloud': r'''
surface("rcpt_cloud")
$/receipt = {merchant: "Café Nawroz", occurredOn: "2026-11-22", occurredTime: "09:40", currency: "USD", totalMinor: 1250,
  lines: [{text: "Flat white", amountMinor: 450, categoryId: "dining"}, {text: "Croissant", amountMinor: 800, categoryId: "dining"}]}
$/drafts = [{id: "r", intent: "expense", amountMinor: 1250, currency: "USD", categoryId: "dining", accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Café Nawroz"}]
$/ui = {split: false}
root = ReceiptSummary($/receipt, $/drafts, $/ui/split, "cloud")''',
  // A draft the model got wrong: it renders as "Needs review".
  'needs_review': r'''
surface("cap_bad")
$/drafts = [{id: "d1", intent: "gift", amountMinor: "ten thousand", currency: "IQD"},
  {id: "d2", intent: "expense", amountMinor: 2500, currency: "USD", categoryId: "transport", accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Taxi"}]
root = EntryList($/drafts)''',
};
