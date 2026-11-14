# SplitLa

[English](README.md) | 廣東話

分帳 App：記錄朋友之間已發生嘅開支，並喺洗錢之前用預算檢查未來開支。

- 詞彙：`CONTEXT.md`
- 第一版 spec：`.scratch/splitla-v1/spec.md`
- Tickets：`.scratch/splitla-v1/issues/`

## Ledger 核心

`Packages/Ledger` 係一個純 Swift 模組，冇 UI、網絡、儲存依賴。所有金錢規則（份額、結餘、建議轉帳、提案、Committed Spend、What-if Check）都喺呢度。

跑測試：

```bash
swift test --package-path Packages/Ledger
```

## 數據庫

表、資料列權限同函數喺 `supabase/migrations/`。本機 Supabase 起咗之後，套用新嘅 migration：

```bash
npx supabase migration up
```

資料列權限嘅測試喺 `supabase/tests/`，用真實登入用戶嘅身份去試讀寫：

```bash
npx supabase test db
```

## 語言

App 以英文為主，廣東話翻譯喺 `App/SplitLa/Localizable.xcstrings`。程式碼入面所有畫面文字都寫英文，個 key 就係嗰句英文。加新文字之後，用 Xcode 打開個 catalog 補返廣東話，未翻譯嘅會顯示英文。

用戶喺帳戶選單（左上角）揀 English 或者廣東話，下次開 App 生效。

## 個人預算私隱檢查

個人預算只存喺部機。呢個檢查確保同 server 講嘢嘅程式碼掂唔到佢：

```bash
scripts/check-personal-budget-privacy.sh
```

## 喺模擬器跑 App

1. 開 Docker Desktop，然後起本機 Supabase（第一次要下載映像檔）：

   ```bash
   npx supabase start
   ```

2. 用 Xcode 開 `App/SplitLa.xcodeproj`，揀一部 iPhone 模擬器，撳 Run。
3. 登入用 email 驗證碼。本機唔會真係寄電郵，驗證碼喺測試信箱度睇：<http://127.0.0.1:54324>。

邀請連結係 `splitla://join?token=…`。喺模擬器試：

```bash
xcrun simctl openurl booted "splitla://join?token=<邀請碼>"
```

模擬器開唔到飛行模式。要試離線，可以停咗本機嘅 API 閘道再重開 App，試完啟動返：

```bash
docker stop supabase_kong_SplitLa
```

```bash
docker start supabase_kong_SplitLa
```

App 連去邊個 Supabase 由 `App/Config/Local.xcconfig` 決定，入面係本機開發用嘅公開金鑰，唔係秘密。

## 開發環境

- Xcode 16.2 或以上，連 iOS 模擬器 runtime
- Docker Desktop，用嚟跑本機 Supabase
- Node.js，用嚟經 `npx` 跑 Supabase CLI
