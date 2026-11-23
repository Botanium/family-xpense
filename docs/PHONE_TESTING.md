# Testing on your iPhones

How to put the dev build ("Xpense Dev") on your iPhone 17 Pro and iPhone
15 Pro Max. It talks to the dev Firebase project `expense-family-cc6ee` and
the dev server `xpense-agent` on Cloud Run (me-central1). Test data only.

## 1. Once, on the Mac

- [ ] Xcode → Settings → Accounts → **+** → Apple ID: sign in. It then
      shows a "Personal Team"; that is the free team `7TMGB6MVP7` the
      project uses. Without it every build stops at "No Accounts" (the
      script checks this first).
- [ ] `gcloud` and `firebase` are signed in as you. The script needs them
      only on the first run (to fetch the Firebase config and register an
      App Check token), and again if you delete `~/.config/xpense/`.

```bash
gcloud auth login
```

```bash
firebase login
```

## 2. Once, on each phone

- [ ] Plug the phone in with a USB cable, unlock it, tap **Trust This
      Computer** and enter the passcode.
- [ ] Turn on **Developer Mode**: Settings → Privacy & Security → Developer
      Mode → On, restart, then tap **Turn On** after the restart. If the
      switch is missing, run the install script once (it fails), and the
      switch appears.

## 3. Install

From the main checkout, with the phones plugged in and unlocked:

```bash
cd ~/Developer/family-xpense && git pull
```

```bash
tools/install_dev_on_iphone.sh
```

It builds once per phone and installs on every connected iPhone. For one
phone only, pass part of its name or its id:

```bash
tools/install_dev_on_iphone.sh -d "Botan"
```

The first build takes a few minutes.

**First time on each phone, "Untrusted Developer":** the app is installed
but iOS does not trust your free certificate yet. On the phone: Settings →
General → VPN & Device Management → your Apple ID under "Developer App" →
**Trust**. Then tap **Xpense Dev** on the home screen. No need to rerun the
script.

## 4. Free-team limits

The free Personal Team works for this, with limits:

- **7 days.** The app stops opening a week after it was installed ("no
  longer available"). Reinstall (section 7). Your data is kept.
- **3 devices** per team. Your two phones use two of them.
- **No push notifications, no TestFlight, no Sign in with Apple, no App
  Attest.** These need the paid Apple Developer Program (D-39).
- Up to 10 new app ids a week; this build uses one.

Because App Attest is not available, the dev build uses an App Check
**debug token** instead. The script makes one, registers it on "Family
Xpense Dev" in Firebase, and keeps it in
`~/.config/xpense/appcheck-debug-token-dev` (only you can read it). Never
paste it into chat, issues or PRs. Production builds never use debug tokens.

## 5. Sign in and set up the household

1. **Phone 1:** open Xpense Dev → **Get started** → **Continue with email**
   → **Create account** with your email and a password. Use email, not
   Google or Apple. If it offers "Tell me your last purchase", try it or tap
   **Skip for now**.
2. Phone 1: enter the household name and the base currency (USD; it can't
   be changed later), then **Continue**.
3. Phone 1: under **Invite your partner**, the code shows (like
   `ABCDE-12345`). Tap **Share**, or read it out.
4. **Phone 2:** open Xpense Dev → **I have an invite from my partner** →
   **Continue with email** → create its own account with a different email.
5. Phone 2: enter the code → **Join household**. A code works once, for
   7 days.

Forgot a password? "Forgot password?" on the sign-in screen sends a reset
email.

## 6. What to try

Works now:

- Email sign-in, creating the household, inviting and joining.
- Accounts: add your own and joint accounts, and share one with your
  partner. ("Sharing…" can stay on a shared account's history for now; the
  background job that finishes it is not deployed yet.)
- **Ask** with typed text (once PR #36 is on main): "Paid 12,000 dinars for
  bread", "How much did we spend on groceries this week?". Check the card
  and save it.
- **Home** (once PR #37 is on main): balances and what you added.
- **Add manually** (PR #39) and **Activity** (PR #38), if they are on main
  when you build. Run `git log --oneline -5` to see what you have.

Not yet:

- Voice capture and receipts (photos or scans).
- Budgets, goals, loans, insights and monthly reports.
- Push notifications and reminders.
- Sign in with Apple; the on-device (private) mode.

Saving works offline and syncs later; Ask, invites and joins need a
connection.

## 7. Reinstall after 7 days (or after a new build)

Plug the phone in, unlock it, and run the script again:

```bash
cd ~/Developer/family-xpense && git pull && tools/install_dev_on_iphone.sh
```

Do **not** delete the app first: installing over it keeps you signed in.
Your household lives in the cloud either way.

## 8. If something fails

| You see | Do this |
|---|---|
| "No iPhone found" | Unlock the phone, replug the cable, accept **Trust This Computer**. |
| "Developer Mode disabled" | Section 2. |
| Signing errors ("No Account for Team", "requires a development team") | Xcode → Settings → Accounts, sign in with your Apple ID; then rerun. |
| "maximum number of apps" or device limit | Free teams allow 3 devices and 10 app ids a week; remove an old test app or wait. |
| Ask says the server is unavailable | Check the server: `curl https://xpense-agent-648682359990.me-central1.run.app/health` should print `{"status":"ok","role":"agent"}`. |
| Ask or invites fail with "app check" in the logs | The token is not registered. Delete `~/.config/xpense/appcheck-debug-token-dev` and rerun the script; it registers a new one. |

**App Check token by hand** (only if the script cannot register it): Firebase
console → App Check → Apps → **Family Xpense Dev** → ⋮ → **Manage debug
tokens** → **Add debug token** → **Generate token** → copy it → **Save**.
Then store it without echoing it:

```bash
mkdir -p ~/.config/xpense && read -rs "T?Debug token: " && (umask 077 && printf %s "$T" > ~/.config/xpense/appcheck-debug-token-dev); unset T
```

To retire a phone's token later, delete it in the same console screen.
