# SplitLa

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

## 喺模擬器跑 App

1. 開 Docker Desktop，然後起本機 Supabase（第一次要下載映像檔）：

   ```bash
   npx supabase start
   ```

2. 用 Xcode 開 `App/SplitLa.xcodeproj`，揀一部 iPhone 模擬器，撳 Run。
3. 登入用 email 驗證碼。本機唔會真係寄電郵，驗證碼喺測試信箱度睇：<http://127.0.0.1:54324>。

App 連去邊個 Supabase 由 `App/Config/Local.xcconfig` 決定，入面係本機開發用嘅公開金鑰，唔係秘密。

## 開發環境

- Xcode 16.2 或以上，連 iOS 模擬器 runtime
- Docker Desktop，用嚟跑本機 Supabase
- Node.js，用嚟經 `npx` 跑 Supabase CLI
