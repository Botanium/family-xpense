"""The DESIGN_SYSTEM section 9 screens in Signal, as HTML on a 390 x 844 frame.

Every screen is a function `(t, link)` that returns the inner markup of the
frame. `t` is a theme from tokens.THEMES; `link(num)` returns the file name of
another v4 artboard in the same theme, so the canvas can play the flow.
Sample data is one household ("Our home": you and Sam), USD base currency
and a market rate of 1,705 dinars per dollar (DECISIONS D-16).
"""

from components import (
    amount, amount_field, app_mark, attr, avatar_pair, barrier, button, capture_dock,
    chips, content_color, dashed_rule, disclosure, dot, entry_slip, esc, filter_bar,
    gap, glass_css, glass_icon_button, glass_pill, glass_sheet, goal_bar, hairline,
    hero_balance, history_row, icon, ledger_row, list_row, mini_bars, mode_chip_on_device,
    pressable, progress_ring, rate_prompt, search_field, section_label, slip_field,
    spinner, step_bar, switch, tab_bar, text, text_field, thin_bar, top_bar,
    transcript_quote, ts, undo_toast, DOCK_LEVELS,
)
from tokens import (
    BOTTOM_OFFSET, BUTTON_HEIGHT, CAMERA_SCRIM, CONTENT_BOTTOM_PADDING, FRAME_H, ICON_ROW,
    MIN_TARGET, PAPER_SHADOW, R_PAPER, S2, S4, S6, S8, S12, S16, S20, S24, S32,
    SAFE_BOTTOM, SAFE_TOP, SCAN_BRACKET, SCAN_STROKE, SCREEN_MARGIN, TOP_ROW,
)

CONTENT_TOP = TOP_ROW + MIN_TARGET + S16  # 115: first content line under a top bar


def column(inner, top, bottom=None, margin=SCREEN_MARGIN, z=1):
    bottom_css = f" bottom: {bottom}px;" if bottom is not None else ""
    return (
        f'<div style="position: absolute; left: 0; right: 0; top: {top}px;{bottom_css} padding: 0 {margin}px; '
        f'display: flex; flex-direction: column; z-index: {z}">{inner}</div>'
    )


def bottom_stack(inner, bottom=BOTTOM_OFFSET):
    return (
        f'<div style="position: absolute; left: {SCREEN_MARGIN}px; right: {SCREEN_MARGIN}px; bottom: {bottom}px; '
        f'display: flex; flex-direction: column; gap: {S8}px; z-index: 2">{inner}</div>'
    )


def heading(t, words):
    """Onboarding headings use `quote`, the largest sans style (no display style exists)."""
    return f'<h2 style="margin: 0; {ts(t, "quote")}">{esc(words)}</h2>'


def para(t, words, color=None):
    return f'<p style="margin: 0; {ts(t, "body", color or t["ink2"])}">{esc(words)}</p>'


def back(t, href, label="Back"):
    return glass_icon_button(t, "back", label, href=href)


def row_amount(t, value, color=None, converted=None):
    return amount(t, value, "figureBody", color, converted)


# 1 Welcome -----------------------------------------------------------------

def welcome(t, link):
    mark = (
        f'<div style="display: flex; align-items: center; gap: {S12}px; height: {MIN_TARGET}px">'
        f'<span style="width: 44px; height: 44px; border-radius: 22px; background: {t["primary"]}; display: flex; '
        f'align-items: center; justify-content: center; flex: none">{icon("sparkle", 20, t["onPrimary"])}</span>'
        f'<span style="{ts(t, "title")}">Family Xpense</span></div>'
    )
    quote = transcript_quote(t, "Paid 60 for gas on the way home", "0:03", [v / 14 for v in [4, 8, 12, 6, 14, 10, 14, 8, 12, 6, 10, 8]])
    money = amount(t, "USD 60.00", "figureLarge", converted="≈ IQD 102,300", align="left")
    slip = entry_slip(
        t, "Expense · Fuel", "96%", money,
        [("Who", "You"), ("When", "Today 18:40"), ("From", "Joint Visa")],
        label="Expense, fuel, 60 US dollars, today",
    )
    body = (
        mark + gap(S32) + quote + gap(S16) + slip + gap(S32) + heading(t, "Say it. We'll sort it.") + gap(S8)
        + para(t, "Tell it what you spent, earned, lent or saved, in your own words. It works out the category, the account and who it was, for both of you.")
    )
    actions = button(t, "primary", "Get started", href=link("02")) + button(t, "text", "I have an invite from my partner", href=link("02"))
    return column(body, TOP_ROW) + bottom_stack(actions)


# 2 Create account ----------------------------------------------------------

def create_account(t, link):
    lock_note = (
        f'<div style="display: flex; gap: {S8}px; align-items: flex-start">{icon("lock", ICON_ROW, t["ink2"])}'
        f'<p style="margin: 0; {ts(t, "caption", t["ink2"])}"><span style="color: {t["ink"]}; font-weight: 500">Private by default.</span> '
        f'Only people you invite see your household\'s money. Personal accounts stay yours unless you share them.</p></div>'
    )
    legal = (
        f'<p style="margin: 0; text-align: center; {ts(t, "meta", t["ink2"])}">By continuing you agree to the '
        f'<a href="#terms" style="color: {t["ink"]}; font-weight: 600">Terms</a> and the '
        f'<a href="#privacy" style="color: {t["ink"]}; font-weight: 600">Privacy Policy</a>.</p>'
    )
    body = (
        step_bar(t, 1) + gap(S24) + heading(t, "Create your account") + gap(S8)
        + para(t, "Each of you signs in on your own phone. Your partner joins the same household later with an invite.")
        + gap(S32)
        + f'<div style="display: flex; flex-direction: column; gap: {S12}px">'
        + button(t, "secondary", "Continue with Apple", href=link("03"))
        + button(t, "secondary", "Continue with Google", href=link("03"))
        + button(t, "secondary", "Continue with email", href=link("03"))
        + "</div>"
    )
    return (
        top_bar(t, "Create account", back(t, link("01")))
        + column(body, CONTENT_TOP)
        + bottom_stack(lock_note + gap(S8) + legal)
    )


# 3 Household and invite ----------------------------------------------------

def household(t, link):
    invite = (
        f'<div style="display: flex; align-items: center; justify-content: space-between">'
        f'<span aria-label="Invite code X P 4 8 2 1" style="{ts(t, "figureMedium")}">XP-4821</span>'
        + button(t, "secondary", "Share", expand=False) + "</div>"
    )
    body = (
        step_bar(t, 2) + gap(S24) + heading(t, "Set up your household") + gap(S24)
        + text_field(t, "Household name", f"hh-name-{t['name']}", value="Our home") + gap(S16)
        + text_field(t, "Your name", f"hh-you-{t['name']}", hint="How Sam will see you") + gap(S24)
        + section_label(t, "Base currency") + gap(S8) + chips(t, ["USD", "IQD"], "USD") + gap(S24)
        + section_label(t, "Invite your partner") + gap(S8) + invite + gap(S12)
        + ledger_row(t, "Shared", "Joint money, goals") + ledger_row(t, "Private", "Your own accounts")
    )
    actions = button(t, "primary", "Continue", href=link("04")) + button(t, "text", "Invite later", href=link("04"))
    return top_bar(t, "Household", back(t, link("02"))) + column(body, CONTENT_TOP) + bottom_stack(actions)


# 4 Add accounts ------------------------------------------------------------

def abbr(t, label):
    return f'<span style="width: 40px; flex: none; {ts(t, "monoLabel", t["ink2"])}">{esc(label)}</span>'


def add_accounts(t, link):
    rows = (
        list_row(t, "My checking ••1187", "Bank account · You", abbr(t, "CHK"), row_amount(t, "3,940.00"))
        + list_row(t, "Joint Visa ••4021", "Credit card · Joint", abbr(t, "VISA"), row_amount(t, "−612.00"))
    )
    say = (
        f'<p style="margin: 0; {ts(t, "caption", t["ink2"])}">Or just say it: <span style="color: {t["ink"]}">'
        f'“I have 3,940 in checking, 250,000 dinars cash, and we owe 612 on the joint Visa.”</span></p>'
    )
    body = (
        step_bar(t, 3) + gap(S24) + heading(t, "Where does your money live?") + gap(S8)
        + para(t, "Add each account with today's balance. You can add more later.") + gap(S16)
        + chips(t, ["Cash", "Bank", "Card", "Savings", "Loan"], "Cash") + gap(S16)
        + section_label(t, "Cash · opening balance") + amount_field(t, "IQD", "250,000", f"acc-amt-{t['name']}", "Opening balance")
        + gap(S24) + section_label(t, "Added") + rows + gap(S16) + say
    )
    return (
        top_bar(t, "Add accounts", back(t, link("03")))
        + column(body, CONTENT_TOP)
        + bottom_stack(button(t, "primary", "Continue", href=link("05")))
    )


# 5 Try it ------------------------------------------------------------------

def try_it(t, link):
    def example(tag, words, href):
        lead = f'<span style="width: 88px; flex: none; {ts(t, "monoLabel", t["ink2"])}">{esc(tag)}</span>'
        return list_row(t, words, None, lead, "", href=href)
    pre = (
        f'<div style="display: flex; gap: {S8}px; align-items: flex-start">{icon("mic", ICON_ROW, t["ink2"])}'
        f'<p style="margin: 0; {ts(t, "caption", t["ink2"])}">The microphone and speech recognition work only while you hold '
        f'the orange button. On this phone, speech becomes text on the device.</p></div>'
    )
    body = (
        step_bar(t, 4) + gap(S24) + heading(t, "Tell me your last purchase") + gap(S8)
        + para(t, "Talk or type the way you'd text a friend. Nothing is saved until you confirm it.") + gap(S16)
        + pre + gap(S24) + section_label(t, "Things you can say")
        + example("EXPENSE", "“42.80 at Costco for groceries”", link("07"))
        + example("TWO AT ONCE", "“Salary came in, and I paid rent”", link("07"))
        + example("LOAN", "“Gave Alex 300”", link("07"))
        + example("QUESTION", "“How much did we spend on food?”", link("07"))
    )
    links = (
        f'<div style="position: absolute; left: {SCREEN_MARGIN}px; right: {SCREEN_MARGIN}px; bottom: {BOTTOM_OFFSET + 84 + S8}px; '
        f'display: flex; justify-content: space-between; z-index: 2">'
        + button(t, "text", "Type instead", expand=False, href=link("07"))
        + button(t, "text", "Skip for now", expand=False, href=link("06")) + "</div>"
    )
    return (
        top_bar(t, "Try it", back(t, link("04")))
        + column(body, CONTENT_TOP) + links + capture_dock(t, scan_href=link("08"))
    )


# 6 Home --------------------------------------------------------------------

SPEND = [18, 30, 12, 44, 22, 8, 26, 38, 14, 20, 52, 16, 24, 10, 34, 28, 12, 40, 18, 30, 62]


def home_body(t, link):
    header = (
        f'<div style="display: flex; align-items: center; justify-content: space-between; height: {MIN_TARGET}px">'
        f'<span style="{ts(t, "monoLabel", t["ink2"])}">NOV 2026 · OUR HOME</span>'
        f'<span style="display: flex; align-items: center; gap: {S8}px">'
        + glass_icon_button(t, "bell", "Notifications, 2 new", unread=True, href=link("19"))
        + f'<a href="{link("20")}" aria-label="Settings" style="display: flex">{avatar_pair(t)}</a></span></div>'
    )
    chart_head = (
        f'<div style="display: flex; justify-content: space-between; align-items: baseline">'
        f'<span style="{ts(t, "caption", t["ink2"])}">Daily spending</span>'
        f'<span style="{ts(t, "figureSmall", t["ink2"])}">AVG 210/DAY</span></div>'
    )
    recent = (
        list_row(t, "Costco", "Groceries · You", "", row_amount(t, "−42.80"), href=link("17"))
        + list_row(t, "Salary", "Income · You", "", row_amount(t, "+3,200.00", t["income"]), href=link("17"))
        + list_row(t, "Rent", "Housing · Joint", "", row_amount(t, "−1,400.00"), href=link("17"))
        + list_row(t, "Shell", "Fuel · Sam", "", row_amount(t, "−58.10"), href=link("17"))
    )
    body = (
        header + gap(S32)
        + hero_balance(t, "Household balance", "$", "12,480", ".00", "+1,240.00 this month", "IQD 21.3M")
        + gap(S24) + chart_head + gap(S8)
        + mini_bars(t, SPEND, "Daily spending for November 1 to 21; today is the highest")
        + gap(S24)
        + ledger_row(t, "Income", "5,650.00", t["income"])
        + ledger_row(t, "Spent", "4,410.00", t["ink"])
        + ledger_row(t, "Saved", "650.00", t["saved"])
        + gap(S12) + rate_prompt(t, link_change=link("20b"))
        + gap(S20) + section_label(t, "Recent", "See all", href=link("16")) + recent
    )
    return column(body, TOP_ROW)


def home(t, link):
    return home_body(t, link) + tab_bar(t, "home", link)


# 7 Ask ---------------------------------------------------------------------

def ask(t, link):
    quote = transcript_quote(
        t, "Spent ten thousand dinars on lunch with the kids", "0:06",
        [v / 14 for v in [4, 8, 12, 6, 14, 10, 14, 8, 12, 6, 10, 14, 8, 12, 14, 10, 6, 10, 6, 4]],
    )
    money = amount(t, "IQD 10,000", "figureLarge", converted="≈ USD 5.87", align="left")
    choices = chips(t, ["Cash (IQD)", "Joint Visa", "Sam paid"], "Cash (IQD)")
    slip = entry_slip(
        t, "Expense · Dining out", "94%", money,
        [("Who", "You + kids"), ("When", "Today 13:20"), ("From", "Cash · IQD")],
        question="Which wallet did you pay from?", choices=choices,
        action=button(t, "primary", "Save", href=link("06")),
        label="Expense, dining out, 10,000 Iraqi dinars, today",
    )
    return (
        top_bar(t, "Ask", back(t, link("06"), "Back to Home"), mode_chip_on_device(t))
        + column(quote + gap(S16) + slip, TOP_ROW + MIN_TARGET + S24)
        + capture_dock(t, recording=True, levels=DOCK_LEVELS, spoken=20, scan_href=link("08"))
    )


# 8 Receipt scan ------------------------------------------------------------

def receipt(t, link):
    lines = [("RICE 5KG", "12,000"), ("CHICKEN", "9,500"), ("VEGETABLES", "6,000"), ("DISH SOAP", "4,000"), ("NOTEBOOK x3", "15,000")]
    ink = t["receiptInk"]
    mono = f"font-family: 'Geist Mono', ui-monospace, monospace; font-size: 10px; line-height: 15px; color: {ink}"
    paper_lines = "".join(
        f'<div style="display: flex; justify-content: space-between"><span>{a}</span><span>{b}</span></div>' for a, b in lines
    )
    rule = f'<div style="border-top: 1px dashed {ink}; opacity: 0.4; margin: 7px 0"></div>'
    paper = (
        f'<div role="img" aria-label="Receipt from City Market, total 46,500 dinars" style="position: absolute; left: 90px; top: 150px; '
        f'width: 210px; box-sizing: border-box; padding: 16px 18px 20px; background: {t["paper"]}; border-radius: {R_PAPER}px; '
        f'transform: rotate(-3deg); box-shadow: {PAPER_SHADOW}; {mono}">'
        f'<div style="text-align: center; font-weight: 500; font-size: 12px; letter-spacing: 1px">CITY MARKET</div>'
        f'<div style="text-align: center; opacity: 0.6">22/11/2026  18:05</div>{rule}{paper_lines}{rule}'
        f'<div style="display: flex; justify-content: space-between; font-weight: 500; font-size: 11px"><span>TOTAL IQD</span><span>46,500</span></div></div>'
    )
    a, s, c = SCAN_BRACKET, SCAN_STROKE, t["accent"]
    frame_box = (70, 124, 250, 320)  # left, top, width, height of the scan frame
    x, y, w, h = frame_box
    brackets = "".join(
        f'<span style="position: absolute; {pos}; width: {a}px; height: {a}px; box-sizing: border-box; {edges}"></span>'
        for pos, edges in [
            (f"left: {x}px; top: {y}px", f"border-left: {s}px solid {c}; border-top: {s}px solid {c}"),
            (f"left: {x + w - a}px; top: {y}px", f"border-right: {s}px solid {c}; border-top: {s}px solid {c}"),
            (f"left: {x}px; top: {y + h - a}px", f"border-left: {s}px solid {c}; border-bottom: {s}px solid {c}"),
            (f"left: {x + w - a}px; top: {y + h - a}px", f"border-right: {s}px solid {c}; border-bottom: {s}px solid {c}"),
        ]
    )
    scrim = (
        f'<div aria-hidden="true" style="position: absolute; left: 0; right: 0; top: 0; height: {CAMERA_SCRIM + SAFE_TOP}px; '
        f'background: linear-gradient(rgba(0,0,0,0.35), rgba(0,0,0,0)); z-index: 2"></div>'
    )
    controls = (
        f'<div style="position: absolute; left: 16px; right: 16px; top: {TOP_ROW}px; height: {MIN_TARGET}px; display: flex; '
        f'align-items: center; justify-content: space-between; z-index: 3">'
        + glass_icon_button(t, "close", "Close", over_media=True, href=link("07"))
        + glass_pill(t, "Read on device", glyph="lock", mono=True, over_media=True)
        + f'<span style="width: {MIN_TARGET}px"></span></div>'
    )
    fg = content_color(t, "sheet")
    groups = [("Groceries", "3 items", "27,500"), ("Household", "1 item", "4,000"), ("Kids & school", "1 item", "15,000")]
    group_rows = "".join(
        hairline(t) + f'<div style="display: flex; align-items: center; min-height: 44px; gap: {S8}px">'
        f'<span style="{ts(t, "subhead", fg)}">{esc(n)}</span><span style="flex: 1; {ts(t, "meta", t["ink2"])}">{esc(i)}</span>'
        f'<span style="{ts(t, "figureBody", fg)}">{esc(v)}</span></div>'
        for n, i, v in groups
    )
    head = (
        f'<div style="display: flex; align-items: flex-end"><div style="flex: 1">'
        f'<div style="{ts(t, "title", fg)}">City Market</div>'
        f'<div style="{ts(t, "monoLabel", t["ink2"], extra="letter-spacing: 0px")}">TODAY 18:05 · CASH</div></div>'
        + amount(t, "IQD 46,500", "figureMedium", fg, "≈ USD 27.27") + "</div>"
    )
    split = (
        f'<div style="display: flex; align-items: center"><span style="flex: 1; {ts(t, "subhead", fg)}">Split by category</span>'
        + switch(t, True, "Split by category") + "</div>"
    )
    actions = (
        f'<div style="display: flex; gap: {S12}px"><div style="flex: 1; display: flex">'
        + button(t, "secondary", "Retake", href=link("07")) + '</div><div style="flex: 2; display: flex">'
        + button(t, "primary", "Save 3 entries", href=link("06")) + "</div></div>"
    )
    sheet = glass_sheet(t, head + gap(S8) + split + group_rows + gap(S16) + actions, over_media=True)
    return (
        f'<div style="position: absolute; inset: 0; background: {t["scan"]}"></div>'
        + paper + f'<div role="img" aria-label="Scan frame" style="position: absolute; inset: 0">{brackets}</div>'
        + scrim + controls + sheet
    )


# 9 Add manually ------------------------------------------------------------

def add_manually(t, link):
    who = section_label(t, "Who") + chips(t, ["You", "Sam", "Joint"], "You")
    content = (
        gap(S8) + filter_bar(t, ["Expense", "Income", "Transfer", "Loan"], "Expense") + gap(S16)
        + amount_field(t, "USD", "42.80", f"man-amt-{t['name']}") + gap(S20)
        + section_label(t, "Category")
        + chips(t, ["Groceries", "Dining out", "Transport", "Housing", "Bills", "Kids", "Health", "Other"], "Groceries")
        + gap(S12) + who + gap(S8)
        + disclosure(t, "Account", "Joint Visa ••4021")
        + disclosure(t, "Date", "Today")
        + text_field(t, "Note", f"man-note-{t['name']}", hint="Add a note")
        + gap(S8) + button(t, "text", "Scan a receipt", glyph="camera", expand=False, href=link("08"))
        + f'<div style="flex: 1"></div>' + button(t, "primary", "Save expense", href=link("06"))
    )
    sheet = glass_sheet(t, content, header=("Cancel", "Add manually", "Save"), top=SAFE_TOP + S8)
    return home_body(t, link) + tab_bar(t, "home", link) + barrier(t) + sheet


# 10 Accounts ---------------------------------------------------------------

def accounts(t, link):
    acc = [
        ("CHK", "My checking ••1187", "Bank account · You", "3,940.00", None),
        ("CHK", "Sam's checking ••5530", "Bank account · Sam, shared", "2,615.00", None),
        ("VISA", "Joint Visa ••4021", "Credit card · Joint", "−612.00", None),
        ("CASH", "Cash (IQD)", "Cash · You", "IQD 315,425", "≈ 185.00"),
        ("SAV", "Emergency fund", "Savings · Joint", "5,200.00", None),
        ("SAV", "Summer trip", "Savings · Joint", "1,152.00", None),
    ]
    rows = "".join(
        list_row(t, n, s, abbr(t, a), row_amount(t, v, converted=c), href=link("11")) for a, n, s, v, c in acc
    )
    loans = list_row(
        t, "Loans and debts", "Owed to you 300.00 · You owe 4,200.00", abbr(t, "LOAN"),
        icon("forward", ICON_ROW, t["ink2"]), href=link("14"),
    )
    total = (
        f'<div style="{ts(t, "caption", t["ink2"])}">Household total</div>{gap(S2)}'
        f'<div style="{ts(t, "figureMedium")}">USD 12,480.00</div>'
    )
    body = total + gap(S16) + filter_bar(t, ["All", "Mine", "Sam", "Joint"], "All") + gap(S8) + rows + loans
    return (
        top_bar(t, "Accounts", "", glass_icon_button(t, "plus", "Add an account"))
        + column(body, CONTENT_TOP) + tab_bar(t, "accounts", link)
    )


# 11 Account detail ---------------------------------------------------------

def account_detail(t, link):
    share = (
        f'<div style="display: flex; align-items: center; gap: {S12}px; padding: {S8}px 0">'
        f'<div style="flex: 1"><div style="{ts(t, "bodyStrong")}">Share with Sam</div>'
        f'<div style="{ts(t, "meta", t["ink2"])}">Sam sees this account and its entries</div></div>'
        + switch(t, True, "Share with Sam") + "</div>"
    )
    sharing = (
        f'<div role="status" style="display: flex; align-items: center; gap: {S8}px; padding-bottom: {S8}px; '
        f'border-bottom: 0.33px solid {t["hair"]}">{spinner(t)}'
        f'<span style="{ts(t, "meta", t["ink2"])}">Sharing past entries… 18 of 42</span></div>'
    )
    entries = [
        ("Salary", "Nov 21 · Income", "+3,200.00", t["income"]),
        ("Rent", "Nov 20 · Housing, Joint", "−1,400.00", None),
        ("To Summer trip", "Nov 18 · Transfer", "−225.00", None),
        ("Electricity", "Nov 15 · Bills", "−86.40", None),
        ("Gave Alex", "Nov 12 · Loan", "−300.00", None),
        ("Pharmacy", "Nov 9 · Health", "−24.15", None),
    ]
    rows = "".join(list_row(t, a, b, "", row_amount(t, c, d), href=link("17")) for a, b, c, d in entries)
    body = (
        f'<div style="{ts(t, "caption", t["ink2"])}">My checking ••1187 · You</div>{gap(S2)}'
        f'<div style="{ts(t, "figureMedium")}">USD 3,940.00</div>{gap(S2)}'
        f'<div style="{ts(t, "figureSmall", t["ink2"])}">BANK ACCOUNT · +1,164.45 THIS MONTH</div>'
        + gap(S16) + share + sharing + gap(S20) + section_label(t, "Entries") + rows
    )
    return (
        top_bar(t, "Account", back(t, link("10")), glass_icon_button(t, "more", "More actions"))
        + column(body, CONTENT_TOP)
    )


# 12 Goals ------------------------------------------------------------------

def goals(t, link):
    def goal(name, value, pace):
        return (
            f'<a href="{link("13")}" style="display: block; padding: {S12}px 0; border-bottom: 0.33px solid {t["hairSoft"]}; color: inherit">'
            + goal_bar(t, name, value, pace) + "</a>"
        )
    body = (
        hero_balance(t, "Saved this month", "$", "650", ".00", "81% of the 800.00 plan", "You 400 · Sam 250", delta_positive=False)
        + gap(S24) + section_label(t, "Goals")
        + goal("Emergency fund", 0.58, "5,200 of 9,000 · 320/mo · Nov 2027")
        + goal("Summer trip", 0.46, "1,152 of 2,500 · 225/mo · May 2027")
        + goal("New car", 0.08, "480 of 6,000 · 400/mo · Aug 2028")
        + gap(S24) + section_label(t, "Try saying")
        + chips(t, ["Move 200 to the trip fund", "A new goal: 6,000 for a car"])
    )
    return (
        top_bar(t, "Goals", "", glass_icon_button(t, "plus", "Add a goal"))
        + column(body, CONTENT_TOP) + tab_bar(t, "goals", link)
    )


# 13 Goal detail ------------------------------------------------------------

def goal_detail(t, link):
    figure = (
        f'<div style="display: flex; align-items: center; gap: {S16}px"><div style="flex: 1">'
        f'<div style="{ts(t, "caption", t["ink2"])}">Emergency fund · Joint</div>{gap(S2)}'
        f'<div style="{ts(t, "figureMedium")}">USD 5,200.00</div>{gap(S2)}'
        f'<div style="{ts(t, "figureSmall", t["ink2"])}">OF 9,000.00</div></div>{progress_ring(t, 0.58)}</div>'
    )
    facts = (
        ledger_row(t, "Target", "9,000.00") + ledger_row(t, "Monthly pace", "320.00")
        + ledger_row(t, "On track for", "NOV 2027") + ledger_row(t, "Kept in", "SAVINGS ••2210")
    )
    contrib = [
        ("Monthly transfer", "Nov 1 · Joint", "+320.00"),
        ("Sam's bonus", "Oct 15 · Sam", "+500.00"),
        ("Monthly transfer", "Oct 1 · Joint", "+320.00"),
        ("Monthly transfer", "Sep 1 · Joint", "+320.00"),
    ]
    rows = "".join(list_row(t, a, b, "", row_amount(t, c, t["income"])) for a, b, c in contrib)
    body = figure + gap(S20) + facts + gap(S20) + section_label(t, "Contributions") + rows
    return (
        top_bar(t, "Goal", back(t, link("12")), glass_icon_button(t, "more", "More actions"))
        + column(body, CONTENT_TOP)
        + bottom_stack(button(t, "primary", "Add money", href=link("07")))
    )


# 14 Loans and debts --------------------------------------------------------

def loans(t, link):
    def fig(label, value, note, dot_color):
        return (
            f'<div style="flex: 1"><div style="display: flex; align-items: center; gap: {S8}px">{dot(dot_color)}'
            f'<span style="{ts(t, "caption", t["ink2"])}">{esc(label)}</span></div>{gap(S2)}'
            f'<div style="{ts(t, "figureMedium")}">{esc(value)}</div>'
            f'<div style="{ts(t, "figureSmall", t["ink2"])}">{esc(note)}</div></div>'
        )
    lead_due = dot(t["loan"])
    lead_none = '<span style="width: 7px; flex: none"></span>'
    owed = list_row(t, "Alex", "Lent Nov 21 · due Dec 15", lead_due, row_amount(t, "300.00"), href=link("15"))
    owe = (
        list_row(t, "Car loan", "Joint · bank · next 250.00 on Dec 1", lead_due, row_amount(t, "3,600.00"))
        + list_row(t, "Jordan", "Sam borrowed · no due date", lead_none, row_amount(t, "600.00"))
    )
    hint = (
        f'<p style="margin: 0; {ts(t, "caption", t["ink2"])}">Say <span style="color: {t["ink"]}">“Alex paid back 100”</span> '
        f'or <span style="color: {t["ink"]}">“Paid the car loan 250”</span>.</p>'
    )
    body = (
        f'<div style="display: flex; gap: {S16}px">' + fig("Owed to you", "300.00", "1 PERSON", t["income"])
        + fig("You owe", "4,200.00", "2 DEBTS", t["loan"]) + "</div>"
        + gap(S24) + section_label(t, "Owed to you") + owed
        + gap(S20) + section_label(t, "You owe") + owe + gap(S20) + hint
    )
    return (
        top_bar(t, "Loans and debts", back(t, link("10")), glass_icon_button(t, "plus", "Add a loan or debt"))
        + column(body, CONTENT_TOP)
    )


# 15 Loan detail ------------------------------------------------------------

def loan_detail(t, link):
    body = (
        f'<div style="{ts(t, "caption", t["ink2"])}">Alex still owes you</div>{gap(S2)}'
        f'<div style="{ts(t, "figureMedium")}">USD 300.00</div>{gap(S2)}'
        f'<div style="{ts(t, "figureSmall", t["ink2"])}">NOTHING PAID BACK YET</div>{gap(S12)}'
        + thin_bar(t, 0, label="0% paid back") + gap(S16)
        + ledger_row(t, "Lent from", "MY CHECKING ••1187")
        + ledger_row(t, "Lent on", "NOV 21, 2026")
        + ledger_row(t, "Pay back by", "DEC 15, 2026", t["loan"])
        + ledger_row(t, "Reminder", "DEC 14 · TO YOU")
        + gap(S24) + section_label(t, "Record a repayment")
        + f'<div style="{ts(t, "subhead")}">How much did Alex pay back?</div>{gap(S4)}'
        + chips(t, ["100.00", "150.00", "All 300.00", "Other"])
        + gap(S20) + section_label(t, "History")
        + history_row(t, "Due date changed", "Nov 22 · Sam", "DEC 1 → DEC 15", "Restore")
        + history_row(t, "You lent Alex", "Nov 21 · added by voice", "300.00")
    )
    return (
        top_bar(t, "Loan", back(t, link("14")), glass_icon_button(t, "more", "More actions"))
        + column(body, CONTENT_TOP)
    )


# 16 Activity ---------------------------------------------------------------

def activity(t, link):
    def day(label, net):
        return (
            f'<div style="display: flex; align-items: baseline; justify-content: space-between; min-height: 18px">'
            f'<h2 style="margin: 0; {ts(t, "caption", t["ink2"], extra="font-weight: 400")}">{esc(label)}</h2>'
            f'<span style="{ts(t, "figureSmall", t["ink2"])}">{esc(net)}</span></div>'
        )
    def row(title, sub, value, color=None):
        return list_row(t, title, sub, "", row_amount(t, value, color), href=link("17"))
    body = (
        search_field(t, "Search or ask", f"act-search-{t['name']}") + gap(S12)
        + filter_bar(t, ["All", "Spent", "Income", "Loans", "You", "Sam"], "All") + gap(S8)
        + day("Today", "+1,757.20")
        + row("Costco", "Groceries · You · Joint Visa", "−42.80")
        + row("Alex", "Loan given · You · My checking", "300.00")
        + row("Salary", "Income · You · My checking", "+3,200.00", t["income"])
        + row("Rent", "Housing · Joint · My checking", "−1,400.00")
        + gap(S20) + day("Yesterday", "+91.90")
        + row("Shell", "Fuel · Sam · Joint Visa", "−58.10")
        + row("Bike sale", "Sale · Sam · Sam's checking", "+150.00", t["income"])
        + gap(S20) + day("Nov 20", "−112.35")
        + row("Pharmacy", "Health · You · Cash (IQD)", "IQD 41,175")
    )
    return (
        top_bar(t, "Activity")
        + column(body, TOP_ROW + MIN_TARGET + S8)
        + undo_toast(t, "Coffee deleted", "Undo") + tab_bar(t, "activity", link)
    )


# 17 Entry detail and history -----------------------------------------------

def entry_detail(t, link):
    body = (
        f'<div style="{ts(t, "monoLabel", t["ink2"], extra="letter-spacing: 1px")}">EXPENSE · DINING OUT</div>{gap(S4)}'
        f'<div style="{ts(t, "figureLarge")}">IQD 10,000</div>'
        f'<div style="{ts(t, "figureSmall", t["ink2"])}">≈ USD 5.87 AT 1,705 · MARKET</div>'
        + gap(S16)
        + disclosure(t, "Category", "Dining out") + disclosure(t, "Account", "Cash (IQD)")
        + disclosure(t, "Who", "You + kids") + disclosure(t, "When", "Today 13:20")
        + disclosure(t, "Note", "Lunch with the kids")
        + gap(S12) + ledger_row(t, "Rate used", "1,705 · MARKET") + ledger_row(t, "Source", "VOICE · ON-DEVICE")
        + gap(S20) + section_label(t, "Revisions")
        + history_row(t, "Account changed", "Today 13:24 · Sam", "JOINT VISA → CASH (IQD)", "Restore")
        + history_row(t, "Created by voice", "Today 13:20 · You", "IQD 10,000")
        + gap(S8) + button(t, "destructive", "Delete entry", expand=False, extra="align-self: flex-start")
    )
    return (
        top_bar(t, "Entry", back(t, link("16")), glass_icon_button(t, "more", "More actions"))
        + column(body, CONTENT_TOP)
    )


# 18 Budgets ----------------------------------------------------------------

def budgets(t, link):
    def meter(cat, name, spent, limit, value, over=None):
        color = t["danger"] if over else t["ink"]
        over_html = gap(S6) + f'<div style="{ts(t, "monoLabel", t["danger"])}">OVER BY {esc(over)}</div>' if over else ""
        return (
            f'<div style="padding: {S12}px 0; border-bottom: 0.33px solid {t["hairSoft"]}">'
            f'<div style="display: flex; align-items: center; gap: {S8}px">{dot(t["cats"][cat])}'
            f'<span style="flex: 1; {ts(t, "subhead")}">{esc(name)}</span>'
            f'<span style="{ts(t, "figureBody", color)}">{esc(spent)}<span style="color: {t["ink2"]}"> / {esc(limit)}</span></span></div>'
            f'{gap(S8)}{thin_bar(t, value, color)}{over_html}</div>'
        )
    body = (
        f'<div style="{ts(t, "caption", t["ink2"])}">November budget</div>{gap(S2)}'
        f'<div style="{ts(t, "figureMedium")}">USD 3,610.00</div>{gap(S2)}'
        f'<div style="{ts(t, "figureSmall", t["ink2"])}">OF 4,100.00 · 9 DAYS LEFT</div>{gap(S12)}'
        + thin_bar(t, 3610 / 4100, label="88% of the month's budget used")
        + gap(S24) + section_label(t, "By category")
        + meter(0, "Groceries", "820", "900", 820 / 900)
        + meter(4, "Dining out", "346", "300", 1, "46.00")
        + meter(1, "Transport", "210", "400", 210 / 400)
        + meter(2, "Housing", "1,400", "1,400", 1)
        + meter(3, "Kids", "418", "600", 418 / 600)
        + meter(5, "Bills", "416", "500", 416 / 500)
    )
    return top_bar(t, "Budgets", back(t, link("06"))) + column(body, CONTENT_TOP)


# 19 Notifications ----------------------------------------------------------

def notifications(t, link):
    def item(message, when, action, unread, href=None):
        lead = dot(t["accent"], 6) if unread else '<span style="width: 6px; flex: none"></span>'
        act = pressable(f'<span style="{ts(t, "caption", weight=600)}">{esc(action)}</span>', href=href)
        return (
            f'<div style="display: flex; align-items: center; gap: {S12}px; padding: {S8}px 0; border-bottom: 0.33px solid {t["hairSoft"]}">'
            f'{lead}<div style="flex: 1"><div style="{ts(t, "caption")}">{esc(message)}</div>'
            f'<div style="{ts(t, "monoLabel", t["ink2"])}">{esc(when.upper())}</div></div>{act}</div>'
        )
    body = (
        section_label(t, "Today")
        + item("Today's dollar rate? Yesterday it was 1,705.", "Today 09:00", "Answer", True, link("20b"))
        + item("Internet is usually paid by the 5th.", "Today 08:30", "Add", True, link("07"))
        + item("Dining out is over its budget by 46.00.", "Today 08:00", "View", False, link("18"))
        + gap(S20) + section_label(t, "Earlier")
        + item("Sam added 3 entries from a receipt.", "Yesterday 18:07", "See", False, link("16"))
        + item("Alex's loan is due on Dec 15.", "Nov 21", "Remind", False, link("15"))
        + item("Your October report is ready.", "Nov 1", "Open", False, link("22"))
    )
    return top_bar(t, "Notifications", back(t, link("06"))) + column(body, CONTENT_TOP)


# 20 Settings ---------------------------------------------------------------

def settings_body(t, link):
    def mode(title, sub, on):
        trail = icon("check", ICON_ROW, t["ink"]) if on else f'<span style="width: {ICON_ROW}px"></span>'
        return (
            f'<button type="button" aria-pressed="{"true" if on else "false"}" style="display: flex; align-items: center; gap: {S12}px; '
            f'width: 100%; text-align: left; min-height: 38px; padding: {S8}px 0; border-bottom: 0.33px solid {t["hairSoft"]}">'
            f'<span style="flex: 1"><span style="display: block; {ts(t, "bodyStrong")}">{esc(title)}</span>'
            f'<span style="display: block; {ts(t, "meta", t["ink2"])}">{esc(sub)}</span></span>{trail}</button>'
        )
    face = (
        f'<div style="display: flex; align-items: center; min-height: 54px; border-bottom: 0.33px solid {t["hairSoft"]}">'
        f'<span style="flex: 1; {ts(t, "body")}">Face ID</span>' + switch(t, True, "Face ID") + "</div>"
    )
    body = (
        section_label(t, "Privacy")
        + mode("On-device only", "No entry text, audio or photo leaves this phone", True)
        + mode("Smart", "The phone first; the cloud for hard cases", False)
        + mode("Cloud", "The cloud does the AI work", False)
        + gap(S24) + section_label(t, "Exchange rate")
        + disclosure(t, "Today's rate", "1,705 · Market", href=link("20b"))
        + disclosure(t, "Daily reminder", "09:00")
        + gap(S24) + section_label(t, "App")
        + face + disclosure(t, "Categories") + disclosure(t, "Export data")
        + gap(S24) + section_label(t, "Account")
        + disclosure(t, "Sign out") + disclosure(t, "Delete account", title_color=t["danger"], divider=False)
    )
    return top_bar(t, "Settings", back(t, link("06"))) + column(body, CONTENT_TOP)


def settings(t, link):
    return settings_body(t, link)


# 20b Settings: today's rate (RateChangeSheet) ------------------------------

def settings_rate(t, link):
    fg = content_color(t, "sheet")
    keys = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
    pad = "".join(
        f'<div style="display: flex">' + "".join(
            f'<button type="button" aria-label="{"Delete" if k == "⌫" else k}" style="flex: 1; min-height: {BUTTON_HEIGHT}px; '
            f'display: flex; align-items: center; justify-content: center; {ts(t, "figureMedium", fg)}">{k}</button>'
            for k in row
        ) + "</div>"
        for row in keys
    )
    content = (
        f'<h2 style="margin: 0; text-align: center; {ts(t, "title", fg)}">Today\'s dollar rate</h2>{gap(S12)}'
        f'<div aria-live="polite" style="text-align: center; {ts(t, "figureLarge", fg)}">1,705</div>'
        f'<div style="text-align: center; {ts(t, "monoLabel", t["ink2"])}">IQD PER USD</div>{gap(S12)}'
        + pad + gap(S12) + button(t, "primary", "Save", href=link("20"))
    )
    return settings_body(t, link) + barrier(t) + glass_sheet(t, content)


# 21 Lock -------------------------------------------------------------------

def lock(t, link):
    overlay = (
        f'<div style="position: absolute; inset: 0; background: {t["lockCanvas"]}; backdrop-filter: blur(30px); '
        f'-webkit-backdrop-filter: blur(30px); z-index: 7"></div>'
    )
    inner = (
        f'<div style="position: absolute; left: {SCREEN_MARGIN}px; right: {SCREEN_MARGIN}px; top: {SAFE_TOP + SCREEN_MARGIN}px; '
        f'bottom: {SAFE_BOTTOM + SCREEN_MARGIN}px; display: flex; flex-direction: column; align-items: center; z-index: 8">'
        f'<div style="flex: 1"></div>{app_mark(t)}<div style="flex: 1"></div>'
        + button(t, "secondary", "Unlock with Face ID", glyph="faceId", href=link("06")) + "</div>"
    )
    return home_body(t, link) + tab_bar(t, "home", link) + overlay + inner


# 22 Monthly report ---------------------------------------------------------

def monthly_report(t, link):
    cats = [
        (2, "Housing", "1,400.00"), (0, "Groceries", "980.20"), (4, "Dining out", "512.00"),
        (3, "Kids", "470.00"), (5, "Bills", "461.60"), (1, "Transport", "388.60"),
    ]
    breakdown = "".join(ledger_row(t, n, v, t["cats"][c]) for c, n, v in cats)
    compare = (
        ledger_row(t, "Income", "5,410.00 → 5,650.00")
        + ledger_row(t, "Spent", "4,480.10 → 4,212.40")
        + ledger_row(t, "Saved", "600.00 → 650.00")
    )
    body = (
        f'<div style="{ts(t, "monoLabel", t["ink2"])}">OCT 2026 · OUR HOME</div>{gap(S16)}'
        f'<div style="{ts(t, "caption", t["ink2"])}">Spent in October</div>{gap(S2)}'
        f'<div style="{ts(t, "figureMedium")}">USD 4,212.40</div>{gap(S2)}'
        f'<div style="{ts(t, "figureSmall", t["ink2"])}">6% LESS THAN SEPTEMBER</div>{gap(S16)}'
        + para(t, "You spent a little less than in September. Housing and groceries were more than half of it. Alex's loan and Sam's bike sale are not counted as spending.", t["ink"])
        + gap(S20) + section_label(t, "Breakdown") + breakdown
        + gap(S20) + section_label(t, "Compared with September") + compare
    )
    return (
        top_bar(t, "October report", back(t, link("19")))
        + column(body, CONTENT_TOP)
        + bottom_stack(button(t, "primary", "Export PDF"))
    )


# Registry ------------------------------------------------------------------

# number, file stem, title, function, components drawn, group
SCREENS = [
    ("01", "Welcome", "Welcome", welcome, "TranscriptQuote, EntrySlip, DashedRule, XpButton (primary, text)", "onboarding"),
    ("02", "CreateAccount", "Create account", create_account, "XpTopBar, GlassIconButton, StepBar, XpButton (secondary)", "onboarding"),
    ("03", "Household", "Household and invite", household, "XpTopBar, StepBar, XpTextField, SectionLabel, ChoiceChips, XpButton, LedgerRow", "onboarding"),
    ("04", "AddAccounts", "Add accounts", add_accounts, "XpTopBar, StepBar, ChoiceChips, SectionLabel, AmountField, XpListRow, XpButton", "onboarding"),
    ("05", "TryIt", "Try it", try_it, "XpTopBar, StepBar, SectionLabel, XpListRow, XpButton (text), CaptureDock", "onboarding"),
    ("06", "Home", "Home", home, "AvatarPair, GlassIconButton (unread), HeroBalance, MiniBars, LedgerRow, RatePrompt (home), SectionLabel, XpListRow, XpTabBarWithAsk", "everyday"),
    ("07", "Ask", "Ask", ask, "XpTopBar, GlassIconButton, ModeChip, TranscriptQuote, EntrySlip, ChoiceChips, XpButton, CaptureDock (recording), Waveform", "everyday"),
    ("08", "Receipt", "Receipt scan", receipt, "ScanFrame, CameraScrim, GlassIconButton (overMedia), GlassPill (overMedia), GlassSheet, ReceiptSheet, XpSwitch, XpButton", "everyday"),
    ("09", "AddManually", "Add manually", add_manually, "GlassSheet (large, Cancel and Save), XpFilterBar, AmountField, ChoiceChips, XpDisclosure, XpTextField, XpButton", "everyday"),
    ("16", "Activity", "Activity", activity, "XpTopBar, XpSearchField, XpFilterBar, XpListRow, UndoToast, XpTabBarWithAsk", "everyday"),
    ("17", "EntryDetail", "Entry detail and history", entry_detail, "XpTopBar, XpDisclosure, LedgerRow, SectionLabel, HistoryRow, XpButton (destructive)", "everyday"),
    ("10", "Accounts", "Accounts", accounts, "XpTopBar, GlassIconButton, MoneyText (medium), XpFilterBar, XpListRow, XpTabBarWithAsk", "money"),
    ("11", "AccountDetail", "Account detail", account_detail, "XpTopBar, MoneyText (medium), XpSwitch, XpSpinner, SectionLabel, XpListRow", "money"),
    ("12", "Goals", "Goals", goals, "XpTopBar, HeroBalance, GoalBar, SectionLabel, XpChip (as suggestions), XpTabBarWithAsk", "money"),
    ("13", "GoalDetail", "Goal detail", goal_detail, "XpTopBar, MoneyText (medium), ProgressRing, LedgerRow, XpListRow, XpButton", "money"),
    ("14", "Loans", "Loans and debts", loans, "XpTopBar, Dot, MoneyText (medium), SectionLabel, XpListRow", "money"),
    ("15", "LoanDetail", "Loan detail", loan_detail, "XpTopBar, MoneyText (medium), ThinBar, LedgerRow, ChoiceChips, HistoryRow", "money"),
    ("18", "Budgets", "Budgets", budgets, "XpTopBar, MoneyText (medium), ThinBar, Dot, SectionLabel", "more"),
    ("19", "Notifications", "Notifications", notifications, "XpTopBar, Dot (unread), SectionLabel", "more"),
    ("20", "Settings", "Settings", settings, "XpTopBar, SectionLabel, XpDisclosure, XpSwitch", "more"),
    ("20b", "SettingsRate", "Settings, today's rate", settings_rate, "GlassSheet, RateChangeSheet, XpNumberPad, XpButton", "more"),
    ("21", "Lock", "Lock", lock, "LockOverlay, XpButton (secondary, Face ID glyph)", "more"),
    ("22", "MonthlyReport", "Monthly report", monthly_report, "XpTopBar, MoneyText (medium), LedgerRow (as BreakdownList), SectionLabel, XpButton", "more"),
]
