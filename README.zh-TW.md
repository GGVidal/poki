<p align="center">
  <img src="docs/images/poki-icon.png" width="64" height="64" alt="Poki icon">
</p>

<h1 align="center">Poki 用你的 iPhone，就像你自己在用</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="500" alt="Poki 官網首頁動畫">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | 繁體中文 | <a href="README.ja.md">日本語</a> | <a href="README.ko.md">한국어</a> | <a href="README.es.md">Español</a><br>
  <a href="https://poki.bot">poki.bot</a>
</p>

<!-- badges:start -->
<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0--only-blue" alt="License: AGPL-3.0-only"></a>
  <a href="https://github.com/JosssphZhou/poki/stargazers"><img src="https://img.shields.io/github/stars/JosssphZhou/poki" alt="GitHub stars"></a>
  <a href="https://github.com/JosssphZhou/poki/forks"><img src="https://img.shields.io/github/forks/JosssphZhou/poki" alt="GitHub forks"></a>
  <a href="https://github.com/JosssphZhou/poki/issues"><img src="https://img.shields.io/github/issues/JosssphZhou/poki" alt="GitHub issues"></a>
  <a href="https://github.com/JosssphZhou/poki/releases"><img src="https://img.shields.io/badge/Poki_App-0.4.4_Beta-blue" alt="Poki App 0.4.4 Beta"></a>
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20Windows-lightgrey" alt="Platform: iOS, macOS and Windows">
</p>
<!-- badges:end -->

<p align="center">
  <strong>如果 Poki 對你有幫助，請點擊 ★ Star 支持這個專案。</strong>
</p>

## Poki 是什麼

Poki 是開源的 iPhone agent，能替你操作整台 iPhone。Poki 應用程式直接執行在你的 iPhone 上，會讀取畫面，並在真實應用程式中點選、輸入和捲動，使用你自己的模型帳號。你可以選擇它如何徵求許可；付款、刪除和錢包中的操作始終需要你的確認。

## 為什麼用 Poki

- **日常瑣事不必在多個應用程式之間來回點選。** 直接在對話裡告訴 Poki，或長按動作按鈕、呼叫 Siri，就能透過內建瀏覽器查資料、查看明天天氣或建立備忘錄。在 iPhone Duo 上，Poki 還能在分割畫面中同時操作兩個應用程式。
- **重複流程點一下或說一句話就完成。** 不必每天重複相同的步驟，直接在首頁點選記住的常用流程，或使用「與 Poki 對話」進行語音互動，每一步進度都會顯示在動態島上。
- **不依賴電腦持續開機，直接操作實機。** 透過 Mac 或 Windows 電腦完成一次安裝後，Poki 即可在 iPhone 上獨立執行，遇到付款、刪除或錢包操作時會在鎖定畫面或動態島暫停等待你的確認。

## 怎麼用

### 在 iPhone 上安裝 Poki

1. **透過 Mac 或 Windows 電腦完成一次安裝。** 用 USB 傳輸線連接並解鎖 iPhone（免費 Apple 帳號即可），然後將以下內容傳給你的編碼代理程式（例如 Claude Code 或 Codex）：

   ```text
   從 https://github.com/JosssphZhou/poki 把 Poki 安裝到我的 iPhone 上
   ```

   也可以從 [GitHub Releases](https://github.com/JosssphZhou/poki/releases) 下載 macOS 版（`.dmg`）或 Windows 版（`.exe`）Poki Setup，依視窗指示操作。
2. **完成連線並設定模型帳號。** 依 iOS 提示點選「信任」、開啟開發者模式與自動化模式，在手機上安裝將 `10.7.0.1` 路由回本機的本地 VPN 應用程式（例如免費的 LocalDevVPN），再用 ChatGPT Plus 或 Pro 登入，或填入 Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter、OpenCode Go 的 API 金鑰，或接入 OpenAI 相容服務。
3. **執行第一個任務。** 開啟 Poki 並傳送：

   ```text
   在備忘錄中新建一則標題為“Poki Demo”的筆記，內文分三行寫 Milk、Eggs、Coffee。完成後開啟這則筆記，不修改現有筆記。
   ```

   完成後開啟備忘錄，確認標題為“Poki Demo”且內文包含這三行內容。

<details>
<summary>環境需求、更新方式、常見問題與文件索引</summary>

| 項目 | 需求 |
| --- | --- |
| iPhone | iOS 18 或更高版本（iPhone XS、XR、SE 第 2 代或更新機型；亦支援 iPadOS 18+）。實機已在 iOS 27 上測試。 |
| 電腦 | macOS 14+ 的 Mac（代理程式安裝需要 Node.js 24+），或已安裝 Apple Devices 或 iTunes 的 Windows 電腦（x64）。 |
| 傳輸線與帳號 | USB 傳輸線與 Apple 帳號。電腦開啟 Poki Setup 時可自動續簽免費 7 天簽署，也可在 Poki 內登入續簽。 |
| 連線 | 將 `10.7.0.1` 路由回 iPhone 的本地 VPN 應用程式（LocalDevVPN、Karing 或 Shadowrocket）。 |
| 模型帳號 | ChatGPT Plus/Pro 登入、API 金鑰（Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter、OpenCode Go）或 OpenAI 相容服務。 |

- 完整安裝細節、更新、常見問題、已知限制與路線圖：[Poki iPhone 使用指南](docs/iphone-guide.md)
- 版本變更紀錄：[CHANGELOG.md](CHANGELOG.md)
- 代理程式安裝技能與桌面工具：[install-poki 技能](skills/install-poki/SKILL.md) 與 [Poki Setup](desktop/README.md)
- 測試驗證、平台限制與發佈通道：[驗證與限制](docs/verification.md) 與 [發佈通道](docs/release-channels.md)
- 早期電腦端連線工具（已停止更新）：[Poki MCP 與 Poki Agent](docs/poki-mcp.md)

</details>

## 社群

- **提問與交流：** 歡迎加入 [GitHub Discussions](https://github.com/JosssphZhou/poki/discussions)。
- **問題回報與建議：** 請前往 [GitHub Issues](https://github.com/JosssphZhou/poki/issues)。
- **參與貢獻：** 請先閱讀 [CONTRIBUTING.md](CONTRIBUTING.md)。

### 共創者

<!-- CO-CREATOR:START -->
<p align="center">
  <a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=320" width="160" height="160" alt="ZhehanZhang"/><br /><b>ZhehanZhang</b></a><br />
  Poki 偉大的共同創造者。
</p>
<!-- CO-CREATOR:END -->

### 核心貢獻者

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />提交了 Poki 的第一個問題 <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>：在 iOS 18.6.2 上截圖正常，輔助功能和觸控不可用，哪些能用哪些不能寫得很清楚。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/14">#14</a> 讓 Poki 能在路由器上執行，Mac 關機時也能透過 Telegram 操作 iPhone；<a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>、<a href="https://github.com/JosssphZhou/poki/pull/17">#17</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a> 隨後跟進。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> 中回報 macOS 27.2 上 usbmuxd 列不出任何 iPhone；Poki 現在會直接說明這一點，以及輔助程式為何提前停止（<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> 查明實體 iPhone 點按慢的原因，隨後的修正讓點按快了約三分之一。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/16">#16</a> 把 Poki 移植到 Linux，並在實體 iPhone 上透過 USB、區域網路和 Tailscale 驗證；README 現已指向該移植版。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> 把實體 iPhone 觸控失敗追查到缺少 display service；現在 Poki 會說明沒有送出任何輸入，並指向 prepare-device。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />修正了損壞的路由快取中斷無關 Agent 任務的問題（<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>、<a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>），隨後在 <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a> 讓 Agent 重用操作後已讀到的畫面。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> 回報 iMessage 任務不會被自然語言的停止請求打斷；現在 Poki 會回覆任務途中的訊息，並提示使用 /stop。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> 中重現了兩個 Agent 缺陷，隨後合併了七項修正和測試修整，從已取消的輸入鎖（<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>）到無效的觸控座標（<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> 修正了 iPhone 區域網路位址變更後 RemotePairing 連線失效的問題（<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>）；實體 iPhone 重新連線只花了 768 毫秒。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> 和 <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a> 中實地測試了 iPhone 應用，涵蓋行動網路和 Windows，促成了首次設定需要 Wi-Fi 的說明（<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>）；還回報了 <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> 修正了 Windows 主機經 RemotePairing 連線時每次點按都失敗的問題；修正後 5 次點按全部成功。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> 透過 Tailscale 在實體 iPhone 上做了一次保險條款核對；這份報告推動了更清楚的 USB 錯誤訊息，以及依工作階段切換連線方式。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />錄製了 Poki 操作實體 iPhone 的示範影片，讓新訪客在安裝之前就能看到它能做什麼。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/68">#68</a> 中把 OpenCode Go 加為 iPhone 應用的模型帳號，附獨立的鑰匙圈憑證和獨立的模型選擇。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> 中提供了 Runner 閒置約 25 分鐘後配對失敗的完整時間線；設定頁現在會指向回環和配對檢查（<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />讓批次呼叫在裝置不明確時給出提示而不是當機（<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>），並新增 POKI_MCP_DEVICE（<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>）和可選的逐任務核准（<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />修正配對設定把人帶到錯誤設定頁面的問題，開發者模式和 UI 自動化步驟現在會開啟正確的頁面（<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> 中修正讀取畫面超過呼叫期限的問題，並為持續變慢的 Runner 回應補上回歸測試。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Ryanwu316"><img src="https://avatars.githubusercontent.com/u/49024277?v=4&size=240" width="120" height="120" alt="Ryanwu316"/><br /><sub><b>Ryanwu316</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/354">#354</a> 為 iPhone Duo 加入雙 App 工作區，任務在旋轉時會等待，並在同一組 App 上繼續。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/soloface"><img src="https://avatars.githubusercontent.com/u/62548950?v=4&size=240" width="120" height="120" alt="soloface"/><br /><sub><b>soloface</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/311">#311</a> 查明手機顯示在線卻回傳 MCP 503 錯誤的原因是中繼重新連線缺陷，並附上可重現的測試和修補。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/whiteluw"><img src="https://avatars.githubusercontent.com/u/86720151?v=4&size=240" width="120" height="120" alt="whiteluw"/><br /><sub><b>whiteluw</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/326">#326</a> 修正 iPhone 上三維小熊初始化時的閃退。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/cs50Mu"><img src="https://avatars.githubusercontent.com/u/4456781?v=4&size=240" width="120" height="120" alt="cs50Mu"/><br /><sub><b>cs50Mu</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/issues/362">#362</a> 發現 Poki Setup 的 macOS 安裝檔只能在 Apple 晶片上執行；隨後的通用版本也能在 Intel Mac 上執行。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mgkvibez"><img src="https://avatars.githubusercontent.com/u/198796435?v=4&size=240" width="120" height="120" alt="mgkvibez"/><br /><sub><b>mgkvibez</b></sub></a><br />在 <a href="https://github.com/JosssphZhou/poki/pull/380">#380</a> 新增一個測試，確保付款判斷先於傳送訊息判斷，因此 Mail 裡的 “Send money” 這類按鈕仍需先審批。</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

<details>
<summary>特別貢獻者、感謝牆與 Star History</summary>

### 特別貢獻者

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />為 0.4.0 改版提供完整的介面設計，涵蓋對話、即時動態、設定與首次使用流程（<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>, <a href="https://github.com/JosssphZhou/poki/pull/256">#256</a>, <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>），為新介面提供了方向。</td>
    </tr>
  </tbody>
</table>

### 感謝牆

感謝每一位提交過 Issue 或 Pull Request 的朋友，你們的回報與修正讓 Poki 變得更好。

<!-- THANKS-WALL:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=160" width="80" height="80" alt="ZhehanZhang"/><br /><sub><b>ZhehanZhang</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=160" width="80" height="80" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/cs50Mu"><img src="https://avatars.githubusercontent.com/u/4456781?v=4&size=160" width="80" height="80" alt="cs50Mu"/><br /><sub><b>cs50Mu</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=160" width="80" height="80" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=160" width="80" height="80" alt="edge369"/><br /><sub><b>edge369</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=160" width="80" height="80" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=160" width="80" height="80" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=160" width="80" height="80" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=160" width="80" height="80" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/htx996"><img src="https://avatars.githubusercontent.com/u/95217139?v=4&size=160" width="80" height="80" alt="htx996"/><br /><sub><b>htx996</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=160" width="80" height="80" alt="igc110"/><br /><sub><b>igc110</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/iTry"><img src="https://avatars.githubusercontent.com/u/1381960?v=4&size=160" width="80" height="80" alt="iTry"/><br /><sub><b>iTry</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=160" width="80" height="80" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/kilingzhang"><img src="https://avatars.githubusercontent.com/u/17439300?v=4&size=160" width="80" height="80" alt="kilingzhang"/><br /><sub><b>kilingzhang</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=160" width="80" height="80" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/lunar-me"><img src="https://avatars.githubusercontent.com/u/275556969?v=4&size=160" width="80" height="80" alt="lunar-me"/><br /><sub><b>lunar-me</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=160" width="80" height="80" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=160" width="80" height="80" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/mgkvibez"><img src="https://avatars.githubusercontent.com/u/198796435?v=4&size=160" width="80" height="80" alt="mgkvibez"/><br /><sub><b>mgkvibez</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/oasis979559-alt"><img src="https://avatars.githubusercontent.com/u/295108220?v=4&size=160" width="80" height="80" alt="oasis979559-alt"/><br /><sub><b>oasis979559-alt</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=160" width="80" height="80" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=160" width="80" height="80" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=160" width="80" height="80" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Ryanwu316"><img src="https://avatars.githubusercontent.com/u/49024277?v=4&size=160" width="80" height="80" alt="Ryanwu316"/><br /><sub><b>Ryanwu316</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=160" width="80" height="80" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=160" width="80" height="80" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/soloface"><img src="https://avatars.githubusercontent.com/u/62548950?v=4&size=160" width="80" height="80" alt="soloface"/><br /><sub><b>soloface</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/wanghao-SunSky"><img src="https://avatars.githubusercontent.com/u/73684879?v=4&size=160" width="80" height="80" alt="wanghao-SunSky"/><br /><sub><b>wanghao-SunSky</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/whiteluw"><img src="https://avatars.githubusercontent.com/u/86720151?v=4&size=160" width="80" height="80" alt="whiteluw"/><br /><sub><b>whiteluw</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/windywendyday"><img src="https://avatars.githubusercontent.com/u/65647922?v=4&size=160" width="80" height="80" alt="windywendyday"/><br /><sub><b>windywendyday</b></sub></a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="20%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=160" width="80" height="80" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=160" width="80" height="80" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/zcyoung2000"><img src="https://avatars.githubusercontent.com/u/62181891?v=4&size=160" width="80" height="80" alt="zcyoung2000"/><br /><sub><b>zcyoung2000</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=160" width="80" height="80" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a></td>
      <td align="center" valign="top" width="20%"><a href="https://github.com/zqy5608"><img src="https://avatars.githubusercontent.com/u/14949471?v=4&size=160" width="80" height="80" alt="zqy5608"/><br /><sub><b>zqy5608</b></sub></a></td>
    </tr>
  </tbody>
</table>
<!-- THANKS-WALL:END -->

### Star History

<a href="https://www.star-history.com/?repos=JosssphZhou%2Fpoki&type=date&legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&theme=dark&legend=top-left">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
    <img alt="Star History chart" src="https://api.star-history.com/chart?repos=JosssphZhou/poki&type=date&legend=top-left">
  </picture>
</a>

</details>

依據 [AGPL-3.0-only](LICENSE) 開源。品牌素材受 [BRAND.md](BRAND.md) 規範。詳見 [Poki iPhone 使用指南](docs/iphone-guide.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 與 [免責聲明](docs/iphone-guide.md#disclaimer)。
