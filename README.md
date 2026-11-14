# SplitLa

English | [廣東話](README.zh-HK.md)

A bill-splitting app for recording expenses between friends and checking future spending against a budget before spending.

- Glossary: `CONTEXT.md`
- First version spec: `.scratch/splitla-v1/spec.md`
- Tickets: `.scratch/splitla-v1/issues/`

## Ledger core

`Packages/Ledger` is a pure Swift module with no UI, networking, or storage dependencies. It contains all money rules, including shares, balances, suggested transfers, proposals, Committed Spend, and What-if Check.

Run the tests:

```bash
swift test --package-path Packages/Ledger
```

## Database

Tables, row-level permissions, and functions are in `supabase/migrations/`. After starting local Supabase, apply new migrations:

```bash
npx supabase migration up
```

Row-level permission tests are in `supabase/tests/` and exercise reads and writes as authenticated users:

```bash
npx supabase test db
```

## Language

The app uses English as its primary language, with Cantonese translations in `App/SplitLa/Localizable.xcstrings`. All UI text in code is written in English, and the English sentence is used as the key. After adding text, open the catalog in Xcode to add the Cantonese translation; untranslated text falls back to English.

Users can choose English or Cantonese in the account menu (top left). The choice takes effect the next time the app opens.

## Personal budget privacy check

Personal budgets are stored only on the device. This check ensures that code communicating with the server cannot access them:

```bash
scripts/check-personal-budget-privacy.sh
```

## Run the app in the simulator

1. Open Docker Desktop, then start local Supabase (the first run downloads images):

   ```bash
   npx supabase start
   ```

2. Open `App/SplitLa.xcodeproj` in Xcode, select an iPhone simulator, and press Run.
3. Sign in with an email verification code. Local development does not send real email; find the code in the test inbox at <http://127.0.0.1:54324>.

Invitation links use `splitla://join?token=…`. To test one in the simulator:

```bash
xcrun simctl openurl booted "splitla://join?token=<invitation-token>"
```

The simulator cannot enable airplane mode. To test offline behavior, stop the local API gateway and reopen the app; restart the gateway when finished:

```bash
docker stop supabase_kong_SplitLa
```

```bash
docker start supabase_kong_SplitLa
```

`App/Config/Local.xcconfig` determines which Supabase instance the app connects to. It contains a public key for local development, not a secret.

## Development requirements

- Xcode 16.2 or later, with an iOS simulator runtime
- Docker Desktop for running local Supabase
- Node.js for running the Supabase CLI via `npx`
