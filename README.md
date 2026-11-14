# SplitLa

English | [廣東話](README.zh-HK.md)

A bill-splitting app for recording expenses between friends and checking future spending against a budget before spending.

- [Local setup guide (English and Cantonese)](docs/local-ios-setup.md) for Docker, Supabase, iPhone Simulator, and physical iPhone.
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
