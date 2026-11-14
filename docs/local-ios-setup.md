# 喺本機跑 SplitLa / Run SplitLa locally

用 Docker Desktop 喺 Mac 起 Supabase，然後揀用 iPhone Simulator 定真 iPhone 跑 app。兩邊可以用同一套 Supabase、一齊試入組同分帳。

Run Supabase on your Mac with Docker Desktop, then run SplitLa on an iPhone Simulator or a physical iPhone. Both can use the same Supabase instance to test invites and split expenses together.

## 1. 準備 Mac / Set up your Mac

1. 裝 [Xcode](https://developer.apple.com/xcode/) 16.2 或以上。用模擬器嘅話，喺 **Xcode → Settings → Platforms**（較新版叫 **Components**）下載 iOS Simulator runtime。用真機嘅話，揀支援你部 iPhone 嘅 iOS 版本嘅 Xcode。SplitLa 最低要求 iOS 17。

   Install [Xcode](https://developer.apple.com/xcode/) 16.2 or later. For Simulator, download an iOS Simulator runtime in **Xcode → Settings → Platforms** (called **Components** in newer versions). For a physical iPhone, use a version of Xcode that supports the iOS version on your phone. SplitLa requires iOS 17 or later.

2. 裝 [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/) 同 [Node.js](https://nodejs.org/en/download) 20 或以上。開 Docker Desktop，等 Docker engine 起好。

   Install [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/) and [Node.js](https://nodejs.org/en/download) 20 or later. Open Docker Desktop and wait for the Docker engine to start.

3. 開 Terminal，clone repo。之後嘅指令都喺 repo 根目錄跑。

   Open Terminal and clone the repository. Run the remaining commands from the repository root.

   ```bash
   git clone https://github.com/LoHK2016/SplitLa.git
   cd SplitLa
   ```

## 2. 起本機 Supabase / Start local Supabase

1. 跑以下指令。第一次會下載 Docker 映像同套用 repo 嘅 migrations。本機 Supabase 毋須開帳戶。

   Run the following commands. The first start downloads Docker images and applies the repository's migrations. Local Supabase runs without a Supabase account.

   ```bash
   npx supabase start
   npx supabase status
   ```

2. 打開 [App/Config/Local.xcconfig](../App/Config/Local.xcconfig)。`SUPABASE_ANON_KEY` 要填 `supabase status` 顯示嘅 **Publishable key**。如果同預設值一致，就可以直接用。App 用呢條公開 key，`service_role` 同 secret key 只供 server 用。

   Open [App/Config/Local.xcconfig](../App/Config/Local.xcconfig). Set `SUPABASE_ANON_KEY` to the **Publishable key** printed by `supabase status`. Keep the default if it matches. The app uses the publishable key. Reserve `service_role` and secret keys for server use.

3. 喺 Mac 打開[本機測試信箱](http://127.0.0.1:54324)，之後用嚟睇登入驗證碼。

   Open the [local test inbox](http://127.0.0.1:54324) on your Mac. You'll use it to read sign-in codes.

## 3A. 喺 iPhone Simulator 跑 / Run on iPhone Simulator

1. `Local.xcconfig` 入面嘅 `SUPABASE_URL` 用以下預設值。`$()` 係用嚟保留 URL 入面嘅 `//`。

   Use the default `SUPABASE_URL` below in `Local.xcconfig`. `$()` preserves the `//` in the URL.

   ```xcconfig
   SUPABASE_URL = http:/$()/127.0.0.1:54321
   ```

2. 用以下指令開 Xcode。揀 `SplitLa` scheme 同一部 iPhone Simulator，再撳 **Run**（`⌘R`）。第一次 build 要等 Xcode 下載 Swift packages。

   Open Xcode with the command below. Select the `SplitLa` scheme and an iPhone Simulator, then click **Run** (`⌘R`). Xcode downloads the Swift packages on the first build.

   ```bash
   open App/SplitLa.xcodeproj
   ```

## 3B. 喺真 iPhone 跑 / Run on a physical iPhone

1. 將 Mac 同 iPhone 接駁去同一個可信嘅 Wi-Fi。喺 Mac 開 **System Settings → Wi-Fi → Details → TCP/IP**，搵部 Mac 嘅 IPv4 位址。在 iPhone Safari 開 `http://<Mac-IP>:54321/auth/v1/health`（換成實際 IP）。見到 JSON 回應，即係部 iPhone 搵到 Supabase。如果逾時，檢查 Docker 有冇開、Mac 防火牆有冇擋住連線，同 Wi-Fi 有冇隔開裝置。記住將本機 Supabase 留喺私人網絡。

   Put the Mac and iPhone on the same trusted Wi-Fi network. On the Mac, find its IPv4 address under **System Settings → Wi-Fi → Details → TCP/IP**. On the iPhone, open `http://<Mac-IP>:54321/auth/v1/health` in Safari, replacing `<Mac-IP>` with the actual address. A JSON response means the iPhone can reach Supabase. If it times out, check that Docker is running, the Mac firewall allows the connection, and the Wi-Fi network allows devices to reach one another. Keep the local Supabase instance on your private network.

2. 喺 `Local.xcconfig` 將 `SUPABASE_URL` 改做 Mac 嘅 IP。下面用 `192.168.1.23` 做例子。真機嘅 `127.0.0.1` 指向部 iPhone 自己。如果 Mac IP 變咗，更新設定再 build。

   Set `SUPABASE_URL` in `Local.xcconfig` to the Mac's IP address. The example uses `192.168.1.23`. On a physical iPhone, `127.0.0.1` points to the phone itself. If the Mac's IP changes, update the setting and rebuild.

   ```xcconfig
   SUPABASE_URL = http:/$()/192.168.1.23:54321
   ```

3. 喺 [App/Info.plist](../App/Info.plist) 最外層嘅 `<dict>` 入面加以下兩行。iPhone 問 SplitLa 可唔可以連區域網絡嗰陣，會顯示呢句原因。Repo 已經有 `NSAllowsLocalNetworking`，用嚟容許本機 HTTP 連線。

   Add these two lines inside the top-level `<dict>` in [App/Info.plist](../App/Info.plist). iOS displays this explanation when SplitLa requests local network access. The repository already sets `NSAllowsLocalNetworking` to allow local HTTP connections. [Apple local network permissions](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>SplitLa connects to the development server on your Mac.</string>
   ```

4. 用 USB 將 iPhone 接駁去 Mac。解鎖 iPhone，有提示就撳 **Trust**。喺 Xcode 開 `App/SplitLa.xcodeproj`，去 **Settings → Accounts** 加 Apple Account。喺 `SplitLa` target 嘅 **Signing & Capabilities** 保持 **Automatically manage signing**，同揀自己嘅 **Team**。免費帳戶可以用 **Personal Team**，安裝簽署 7 日後到期，到期用 Xcode 再裝。若 Xcode 話 bundle identifier 用唔到，就改成自己獨有嘅值，例如 `com.yourname.splitla.dev`，將 `yourname` 換成自己嘅名。

   Connect and unlock the iPhone over USB, then tap **Trust** if asked. Open `App/SplitLa.xcodeproj` in Xcode and add your Apple Account under **Settings → Accounts**. In the `SplitLa` target's **Signing & Capabilities**, keep **Automatically manage signing** enabled and select your **Team**. A free account can use a **Personal Team**. Its provisioning profile expires after seven days, at which point you can reinstall from Xcode. If Xcode reports that the bundle identifier is unavailable, use one unique to you, such as `com.yourname.splitla.dev` with your own name in place of `yourname`. [Apple Personal Team and provisioning](https://developer.apple.com/help/account/basics/about-your-developer-account)

5. 喺 Xcode 揀部 iPhone。按提示去 iPhone **Settings → Privacy & Security → Developer Mode** 開啟 Developer Mode，重啟後再確認。返 Xcode 撳 **Run**。App 第一次問區域網絡權限時揀 **Allow**。如果之前揀咗唔畀，可以喺 iPhone **Settings → Privacy & Security → Local Network** 開返 SplitLa 嘅權限。[Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

   Select your iPhone in Xcode. When prompted, enable **Developer Mode** under **Settings → Privacy & Security → Developer Mode** on the iPhone, restart it, and confirm. Back in Xcode, click **Run**. Tap **Allow** when SplitLa first asks for local network access. If you previously denied access, enable it for SplitLa under **Settings → Privacy & Security → Local Network**. [Apple Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)

Mac IP 同個人簽署設定留喺自己部機。轉返用 Simulator 嗰陣，可以將 URL 調返去 `127.0.0.1`。

Keep your Mac IP and personal signing settings local. If you switch back to Simulator, you can restore `127.0.0.1` in the URL.

## 4. 登入同拍 demo / Sign in and record a demo

1. 開 SplitLa，輸入測試電郵，例如 `demo-a@example.com`，撳 **Send Me a Code**。喺 Mac 嘅[本機測試信箱](http://127.0.0.1:54324) 搵返嗰封信，拎六位數字返 app 登入。Supabase 會將郵件留喺測試信箱。

   Open SplitLa, enter a test address such as `demo-a@example.com`, and tap **Send Me a Code**. Find the message in the [local test inbox](http://127.0.0.1:54324) on the Mac, then enter the six-digit code in SplitLa. Supabase keeps the message in the test inbox.

2. 用 **New Group → New Activity → Record an Expense** 準備 demo 資料。試邀請流程可以喺另一部 Simulator 或 iPhone 用 `demo-b@example.com` 登入同一套 Supabase，再開第一個帳戶用 **Invite Friends** 分享嘅連結。如果用 Simulator，可以將以下指令嘅 `SIMULATOR_UDID` 同 `INVITATION_TOKEN` 換成目標模擬器 ID 同邀請碼。

   Prepare demo data with **New Group → New Activity → Record an Expense**. To test an invite, sign in to the same Supabase instance on another Simulator or iPhone as `demo-b@example.com`, then open the link shared via **Invite Friends** by the first account. For Simulator, replace `SIMULATOR_UDID` and `INVITATION_TOKEN` in the command below with the destination Simulator ID and invite token.

   ```bash
   xcrun simctl list devices booted
   xcrun simctl openurl SIMULATOR_UDID 'splitla://join?token=INVITATION_TOKEN'
   ```

3. 錄 Simulator 畫面就跑以下指令，錄完撳 `Ctrl+C`。如果同時開住幾部 Simulator，將 `booted` 換成目標模擬器 ID。真 iPhone 可以用控制中心嘅 **螢幕錄製**，片段會儲存喺「相片」。

   Run the command below to record Simulator. Press `Ctrl+C` to finish. If multiple Simulators are running, replace `booted` with the destination Simulator ID. On a physical iPhone, use **Screen Recording** in Control Center. The recording is saved in Photos. [Simulator recording](https://developer.apple.com/videos/play/wwdc2020/10647/) · [iPhone screen recording](https://support.apple.com/en-us/102653)

   ```bash
   xcrun simctl io booted recordVideo --codec=h264 SplitLa-demo.mp4
   ```

## 5. 更新同停止 Supabase / Update and stop Supabase

- 拉到新 migrations 之後，保持 Docker 同 Supabase 開住，再跑 `npx supabase migration up`。要試資料庫權限同函數，可以跑 `npx supabase test db`。

  After pulling new migrations, keep Docker and Supabase running and apply them with `npx supabase migration up`. Run `npx supabase test db` to test database permissions and functions.

- 想試 Simulator 離線，就先登入同開一次要試嘅 group。用 `docker ps` 搵 Supabase API gateway（名稱以 `supabase_kong_` 開頭），用 `docker stop <container>` 停佢，再重新開 app。試完用 `docker start <container>` 開返。

  To test offline access in Simulator, sign in and open the group once. Use `docker ps` to find the Supabase API gateway (its name starts with `supabase_kong_`), stop it with `docker stop <container>`, then reopen the app. Restart the gateway with `docker start <container>` when finished.

- 用完喺 repo 根目錄跑 `npx supabase stop`。下次跑 `npx supabase start` 可以繼續用返原有資料。

  When you're done, run `npx supabase stop` from the repository root. Run `npx supabase start` next time to resume with the same data.
