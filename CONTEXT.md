# SplitLa

一個分帳 App：記錄朋友之間已發生嘅開支並計出邊個欠邊個，同時喺洗錢之前用預算檢查未來開支。

## Language

### 人同事

**Group（群組）**:
一班長期一齊夾錢嘅朋友。群組係人，唔係事。
_Avoid_: 團、Party

**Member（成員）**:
屬於某個群組嘅一個人。

**Placeholder Member（佔位成員）**:
未裝 App 嘅成員，得個名，由其他成員代佢入數，之後可以由本人認領。冇個人預算，亦冇預算檢查。
_Avoid_: Guest、Ghost、虛擬成員

**Attendance（出席狀態）**:
一個成員對一個活動嘅表態：去、唔去、未覆。
_Avoid_: RSVP、報名

**Activity（活動）**:
群組入面一次有開支嘅聚會或行程，例如一餐飯或一次旅行。預算同分帳都係跟活動。
_Avoid_: Event、聚會、Trip

**Organiser（主辦人）**:
開某個活動嘅成員。只有佢可以定活動預算同揀選定提案。
_Avoid_: Owner、Admin、Host

### 分帳

**Expense（開支）**:
活動入面已經發生嘅一筆消費，記錄邊個畀咗錢同每個成員佔幾多。
_Avoid_: Bill、Transaction、單

**Share（份額）**:
一個成員喺一筆開支或提案入面應該負擔嘅金額，同佢實際畀出幾多錢無關。
_Avoid_: Portion、Split

**Balance（結餘）**:
一個成員喺成個群組入面，跨晒所有活動加埋之後淨欠人或者淨被欠嘅金額。
_Avoid_: Debt、欠款

**Settlement（找數）**:
一個成員已經喺 App 以外畀錢另一個成員嘅記錄。App 唔處理真錢。
_Avoid_: Payment、Transfer、還款

### 預算同預測

**Activity Budget（活動預算）**:
成個活動預計總共洗幾多錢嘅上限，全組成員都睇到。
_Avoid_: 群組總預算、Group Total Budget、Group Budget

**Personal Budget（個人預算）**:
一個人每月社交開支嘅上限，跨晒佢所有群組同活動，只有佢自己睇到。
_Avoid_: 私人預算、Private Budget

**Proposal（提案）**:
活動入面一筆未發生嘅預計開支（例如「餐廳 A，每人 $800」），全組成員都睇到。
_Avoid_: What-if、模擬、Estimate

**Chosen Proposal（選定提案）**:
一個活動入面，由主辦人揀定嘅嗰一個提案。一個活動最多得一個。
_Avoid_: Accepted、Winner、確認提案

**What-if Check（預算檢查）**:
將一個提案同活動預算及個人預算對比嘅結果。活動層面嘅結果全組可見，個人層面嘅結果只有本人睇到，群組唔會收到任何訊號。
_Avoid_: 模擬測試、Simulation

**Committed Spend（已承諾開支）**:
一個人喺某個曆月入面，已發生開支嘅份額，加埋佢覆咗「去」嘅活動入面選定提案嘅份額。個人預算就係同呢個數比較；SplitLa 以外嘅開支唔計。提案轉做開支之後，實際份額取代預計份額。
