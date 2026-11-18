<p align="center">
  <img src="docs/images/poki-icon.png" width="64" height="64" alt="Poki icon">
</p>

<h1 align="center">Poki は、あなたと同じように iPhone を使う</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="500" alt="Poki 公式サイトのトップページのアニメーション">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | 日本語 | <a href="README.ko.md">한국어</a> | <a href="README.es.md">Español</a><br>
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
  <strong>Poki が役に立ったら、★ Star をクリックしてプロジェクトを応援してください。</strong>
</p>

## Poki とは

Poki は、あなたの代わりに iPhone 全体を操作するオープンソースの iPhone エージェントです。Poki アプリは iPhone 本体で直接動作し、画面を読み取って実際のアプリ内でタップ、文字入力、スクロールを行います。モデルアカウントはご自身のものを使用し、支払い、削除、ウォレット内の操作は常にあなたの確認を求めます。

## なぜ Poki か

- **日常の用事を複数のアプリを行き来せずに済ませる。** チャットで頼むか、アクションボタンの長押しや Siri から呼び出すだけで、内蔵ブラウザでの調べもの、明日の天気の確認、メモの作成を任せられます。iPhone Duo では Split View で 2 つのアプリを並べて操作できます。
- **繰り返しの手順をタップや音声ですぐ実行。** 毎回同じ操作をしなくても、ホーム画面の記憶済みルーティンをタップするか、音声会話で話しかけるだけで進められます。各ステップの状況は Dynamic Island に表示されます。
- **パソコンをつけっぱなしにせず実機を自動化。** Mac または Windows PC から一度インストールすれば、その後の作業にパソコンは不要です。承認が必要な操作では、ロック画面や Dynamic Island で一時停止して確認を求めます。

## 使い方

### iPhone に Poki をインストールする

1. **Mac または Windows PC から一度インストールする。** iPhone を USB で接続してロックを解除し（無料の Apple Account で構いません）、Claude Code や Codex などのエージェントに次を伝えます。

   ```text
   Install Poki on my iPhone from https://github.com/JosssphZhou/poki
   ```

   あるいは [GitHub Releases](https://github.com/JosssphZhou/poki/releases) から macOS 版（`.dmg`）または Windows 版（`.exe`）の Poki Setup をダウンロードして案内どおりに進めます。
2. **接続設定とモデルアカウントを追加する。** iOS の指示に従って「信頼」、デベロッパモード、オートメーションモードを有効にし、`10.7.0.1` を iPhone にルーティングするローカル VPN アプリ（無料の LocalDevVPN など）を設定します。続けて ChatGPT Plus/Pro でサインインするか、Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter、OpenCode Go の API キー、または OpenAI 互換サーバーを登録します。
3. **最初のタスクを実行する。** Poki を開いて以下を送信します。

   ```text
   Create a new note in Notes titled "Poki Demo" with these three lines: Milk, Eggs, Coffee. Open the note when finished. Leave existing notes unchanged.
   ```

   完了後にメモアプリを開き、「Poki Demo」というタイトルと 3 行の本文が作成されていることを確認します。

<details>
<summary>動作要件、アップデート方法、よくある質問、ガイド一覧</summary>

| 項目 | 要件 |
| --- | --- |
| iPhone | iOS 18 以降（iPhone XS、XR、SE 第 2 世代以降、iPadOS 18 以降）。実機テストは iOS 27 で確認済みです。 |
| パソコン | macOS 14 以降の Mac（エージェント導入には Node.js 24 以降）、または Apple Devices / iTunes を導入した Windows PC（x64）。 |
| ケーブルとアカウント | USB データケーブルと Apple Account。無料アカウントの 7 日間署名は Poki Setup または Poki アプリ内で更新できます。 |
| 接続 | `10.7.0.1` を iPhone に戻すローカル VPN アプリ（LocalDevVPN、Karing、Shadowrocket）。 |
| モデルアカウント | ChatGPT Plus/Pro サインイン、API キー（Anthropic、OpenAI、Gemini、DeepSeek、OpenRouter、OpenCode Go）、または OpenAI 互換サーバー。 |

- 詳細なインストール手順、更新方法、FAQ、既知の制限、ロードマップ：[Poki iPhone アプリガイド](docs/iphone-guide.md)
- バージョン履歴：[CHANGELOG.md](CHANGELOG.md)
- エージェント用スキルとデスクトップアプリ：[install-poki スキル](skills/install-poki/SKILL.md) / [Poki Setup](desktop/README.md)
- 検証結果、制限事項、リリースチャネル：[検証と制限](docs/verification.md) / [リリースチャネル](docs/release-channels.md)
- 従来のパソコン連携ツール（更新終了）：[Poki MCP と Poki Agent](docs/poki-mcp.md)

</details>

## コミュニティ

- **質問やアイデアの共有：** [GitHub Discussions](https://github.com/JosssphZhou/poki/discussions) にご参加ください。
- **バグ報告や機能リクエスト：** [GitHub Issues](https://github.com/JosssphZhou/poki/issues) からお寄せください。
- **コントリビュート：** [CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

### 共同創造者

<!-- CO-CREATOR:START -->
<p align="center">
  <a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=320" width="160" height="160" alt="ZhehanZhang"/><br /><b>ZhehanZhang</b></a><br />
  Poki の偉大な共同創造者。
</p>
<!-- CO-CREATOR:END -->

### コアコントリビューター

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />Poki 最初の issue <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a> を報告。iOS 18.6.2 でスクリーンショットは動き、アクセシビリティとタッチは動かないことを、切り分けてわかりやすく書いてくれました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/14">#14</a> で Poki をルーター上で動かせるようにし、Mac の電源がオフでも Telegram から iPhone を操作できます。<a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>、<a href="https://github.com/JosssphZhou/poki/pull/17">#17</a>、<a href="https://github.com/JosssphZhou/poki/issues/19">#19</a> が続きました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> で macOS 27.2 の usbmuxd が iPhone を一覧に出さないことを報告。Poki はそれを明確に伝え、ヘルパーが早く止まる理由も示すようになりました（<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> で実機 iPhone のタップが遅い原因を突き止め、その後の修正でタップが約 3 分の 1 速くなりました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/16">#16</a> で Poki を Linux に移植し、実機 iPhone で USB、LAN、Tailscale 経由の動作を確認しました。README はこの移植版を案内しています。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> で実機 iPhone のタッチ失敗の原因が display service の欠如にあると突き止めました。Poki は何も送信されなかったことを伝え、prepare-device を案内します。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />壊れたキャッシュ済みルートが無関係な Agent タスクを中断させる問題を修正し（<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>、<a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>）、続く <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a> で操作後に読み取った画面を Agent が再利用できるようにしました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> で、自然言語の停止リクエストでは iMessage のタスクが止まらないことを報告しました。Poki はタスク中のメッセージに返信し、/stop を案内するようになりました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> と <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> で Agent の 2 つの不具合を再現し、その後、キャンセル済みの入力ロック（<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>）から無効なタッチ座標（<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>）まで、7 件の修正とテスト修整をマージしました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />iPhone の LAN アドレスが変わると RemotePairing 接続が切れる問題（<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>）を <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> で修正しました。実機では 768 ミリ秒で再接続できました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> と <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a> でモバイル通信と Windows から iPhone アプリを実機テストし、初回セットアップに Wi-Fi が必要という説明（<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>）につながりました。<a href="https://github.com/JosssphZhou/poki/issues/162">#162</a> も報告。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />Windows ホストから RemotePairing 接続でタップが毎回失敗する問題を <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> で修正しました。修正後は 5 回中 5 回のタップが成功しました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> で Tailscale 経由の実機 iPhone を使い、保険約款の確認を行いました。この報告が、USB のより分かりやすいエラーと、セッションごとの接続方式の切り替えにつながっています。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />Poki が実機 iPhone を操作するデモ動画を制作し、新しい訪問者がインストール前に何ができるかを確認できるようにしました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/68">#68</a> で OpenCode Go を iPhone アプリのモデルアカウントとして追加。専用の Keychain 認証情報と独立したモデル選択を備えています。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> で Runner が約 25 分の待機後にペアリングに失敗する経過を詳しく記録。Setup は Loopback と Pairing の確認を案内するようになりました（<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>）。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />バッチ呼び出しがデバイス不明時にクラッシュせず知らせるようにし（<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>）、POKI_MCP_DEVICE（<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>）とタスクごとの任意の承認ゲート（<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>）を追加しました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />ペアリング設定が誤った設定ページへ誘導する問題を修正し、開発者モードと UI オートメーションの手順が正しいページを開くようになりました（<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>）。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> で画面読み取りが呼び出しの期限を超える問題を修正し、常に遅い Runner 応答に対する回帰テストも追加しました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Ryanwu316"><img src="https://avatars.githubusercontent.com/u/49024277?v=4&size=240" width="120" height="120" alt="Ryanwu316"/><br /><sub><b>Ryanwu316</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/354">#354</a> で iPhone Duo に 2 つのアプリのワークスペースを追加し、回転中もタスクが待機して同じアプリの組み合わせで再開するようにしました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/soloface"><img src="https://avatars.githubusercontent.com/u/62548950?v=4&size=240" width="120" height="120" alt="soloface"/><br /><sub><b>soloface</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/311">#311</a> で、電話がオンライン表示なのに MCP が 503 を返す原因がリレーの再接続の不具合だと突き止め、再現テストとパッチを添えました。</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/whiteluw"><img src="https://avatars.githubusercontent.com/u/86720151?v=4&size=240" width="120" height="120" alt="whiteluw"/><br /><sub><b>whiteluw</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/326">#326</a> で iPhone の 3D クマの初期化時に発生するクラッシュを修正しました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/cs50Mu"><img src="https://avatars.githubusercontent.com/u/4456781?v=4&size=240" width="120" height="120" alt="cs50Mu"/><br /><sub><b>cs50Mu</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/362">#362</a> で、Poki Setup の macOS 版が Apple シリコンでしか動かないことを見つけ、その後のユニバーサルビルドで Intel Mac でも動くようになりました。</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mgkvibez"><img src="https://avatars.githubusercontent.com/u/198796435?v=4&size=240" width="120" height="120" alt="mgkvibez"/><br /><sub><b>mgkvibez</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/380">#380</a> で、支払いの判定をメッセージ送信の判定より先に行う順序を守るテストを追加し、Mail の “Send money” のようなボタンでも承認が必要なままになります。</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

<details>
<summary>特別な貢献者、スペシャルサンクス、Star History</summary>

### 特別な貢献者

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />0.4.0 の刷新に向け、チャット、ライブアクティビティ、設定、初回起動の一式の画面デザインを提供しました（<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>, <a href="https://github.com/JosssphZhou/poki/pull/256">#256</a>, <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>）。新しいインターフェースの方向性に反映されています。</td>
    </tr>
  </tbody>
</table>

### スペシャルサンクス

Issue や Pull Request を寄せてくださった皆さまに感謝いたします。皆さまのご報告と修正が Poki をより良くしています。

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

[AGPL-3.0-only](LICENSE) ライセンスで公開しています。ブランド素材の扱いは [BRAND.md](BRAND.md) をご覧ください。詳細は [Poki iPhone アプリガイド](docs/iphone-guide.md)、[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)、[免責事項](docs/iphone-guide.md#disclaimer) にあります。
