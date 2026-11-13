# 01: 專案骨架同 email 驗證碼登入

**What to build:** 用戶打開 App，用 email 收驗證碼登入，之後見到一個空嘅群組列表；登出再登入仍然係同一個帳戶。同時建立 SwiftUI App、本機 Supabase 同 Ledger 核心模組嘅骨架，等之後每張 ticket 都有地方落手。唔需要 Apple Developer 帳戶，全部喺模擬器同本機 Supabase 跑。

**Blocked by:** None (can start immediately)

**Status:** done

- [x] 喺模擬器用 email 驗證碼登入到，驗證碼由本機 Supabase 嘅測試信箱收
- [x] 登入狀態重開 App 之後仍然保留，可以登出
- [x] 登入後顯示空嘅群組列表同空狀態提示
- [x] Ledger 核心係獨立嘅純 Swift 模組，冇 UI、網絡、儲存依賴，有至少一個測試跑到
- [x] 金額類型用整數仙表示，有測試
- [x] README 寫明點樣起本機 Supabase 同跑測試

## Comments

**2026-11-14（agent）：** 做咗 Ledger 核心部分，其餘未做。

- 完成：Ledger 核心係獨立純 Swift 模組，金額用整數仙，48 個測試全部通過。除咗呢張要求嘅骨架，亦已經包埋 03、04、06、07、08、09、10、11 嘅 Ledger 規則同測試，嗰幾張剩低嘅係數據庫、同步同畫面。
- 未做：SwiftUI App、email 驗證碼登入、本機 Supabase。
- 卡住嘅原因：呢部 Mac 冇裝 Docker（本機 Supabase 要用），亦冇裝任何 iOS 模擬器 runtime，所以登入同畫面寫咗都冇辦法跑嚟驗證。

**2026-11-14（agent）：** 完成。Docker 同 iOS 18.3 模擬器裝好之後，起咗本機 Supabase、開咗 SwiftUI App 專案同做咗 email 驗證碼登入。

- 喺 iPhone 16 模擬器行過一次完整流程：入電郵 → 本機測試信箱收到 6 位數驗證碼 → 入碼自動登入 → 見到空群組列表 → 重開 App 仍然登入 → 登出返去登入頁。
- 冇喺畫面試過嘅：入錯驗證碼同斷網嘅錯誤提示。
