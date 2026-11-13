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

## 開發環境

- Xcode 16.2 或以上
- iOS 模擬器 runtime（Xcode › Settings › Components）
- Docker，用嚟跑本機 Supabase
