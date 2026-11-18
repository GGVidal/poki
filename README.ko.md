<p align="center">
  <img src="docs/images/poki-icon.png" width="64" height="64" alt="Poki icon">
</p>

<h1 align="center">Poki는 당신의 iPhone을 당신처럼 씁니다</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="500" alt="Poki 공식 웹사이트 홈페이지 애니메이션">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | <a href="README.ja.md">日本語</a> | 한국어 | <a href="README.es.md">Español</a><br>
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
  <strong>Poki가 도움이 되었다면 ★ Star를 클릭해 프로젝트를 응원해 주세요.</strong>
</p>

## Poki란 무엇인가요

Poki는 사용자를 대신해 iPhone 전체를 조작하는 오픈소스 iPhone 에이전트입니다. Poki 앱은 iPhone에서 직접 실행되며, 사용자의 모델 계정으로 화면을 읽고 실제 앱에서 탭, 입력, 스크롤을 수행합니다. 승인 방식은 직접 선택할 수 있으며 결제, 삭제, Wallet 작업은 항상 확인을 받습니다.

## 왜 Poki인가요

- **일상적인 작업을 위해 여러 앱을 번갈아 누를 필요가 없습니다.** 채팅으로 부탁하거나 동작 버튼을 길게 누르고 Siri를 호출해 내장 브라우저 검색, 내일 날씨 확인, 메모 작성을 맡길 수 있습니다. iPhone Duo에서는 Split View로 두 앱을 나란히 조작합니다.
- **반복 작업을 탭 한 번이나 음성으로 실행합니다.** 매일 같은 단계를 되풀이하는 대신 홈 화면에 기억된 루틴을 탭하거나 음성 대화를 시작하세요. 각 단계의 진행 상황은 Dynamic Island에 표시됩니다.
- **컴퓨터를 켜 두지 않고도 실제 iPhone을 자동화합니다.** Mac이나 Windows PC에서 한 번 설치하면 컴퓨터 없이 iPhone 단독으로 실행되며, 승인이 필요한 단계에서는 잠금 화면이나 Dynamic Island에서 멈추고 확인을 기다립니다.

## 사용 방법

### iPhone에 Poki 설치하기

1. **Mac 또는 Windows PC에서 한 번 설치합니다.** USB 케이블로 iPhone을 연결하고 잠금을 해제한 뒤(무료 Apple 계정 가능), Claude Code나 Codex 같은 코딩 에이전트에게 아래 문장을 전달하세요.

   ```text
   Install Poki on my iPhone from https://github.com/JosssphZhou/poki
   ```

   또는 [GitHub Releases](https://github.com/JosssphZhou/poki/releases)에서 macOS용(`.dmg`) 또는 Windows용(`.exe`) Poki Setup을 내려받아 안내를 따르세요.
2. **연결과 모델 계정을 설정합니다.** iOS 안내에 따라 신뢰, 개발자 모드, 자동화 모드를 켜고 `10.7.0.1`을 iPhone으로 라우팅하는 로컬 VPN 앱(예: 무료 LocalDevVPN)을 설치합니다. 이어서 ChatGPT Plus/Pro로 로그인하거나 Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, OpenCode Go API 키 또는 OpenAI 호환 서버를 등록하세요.
3. **첫 작업을 실행합니다.** Poki를 열고 다음 메시지를 보냅니다.

   ```text
   Create a new note in Notes titled "Poki Demo" with these three lines: Milk, Eggs, Coffee. Open the note when finished. Leave existing notes unchanged.
   ```

   완료 후 메모 앱을 열어 "Poki Demo" 메모가 세 줄의 내용과 함께 생성되었는지 확인하세요.

<details>
<summary>요구 사항, 업데이트, 자주 묻는 질문 및 가이드</summary>

| 항목 | 요구 사항 |
| --- | --- |
| iPhone | iOS 18 이상(iPhone XS, XR, SE 2세대 이상 및 iPadOS 18+). 실제 기기 테스트는 iOS 27에서 진행했습니다. |
| 컴퓨터 | macOS 14+ Mac(에이전트 설치 시 Node.js 24+ 필요) 또는 Apple Devices / iTunes가 설치된 Windows PC(x64). |
| 케이블 및 계정 | USB 데이터 케이블과 Apple 계정. 무료 계정의 7일 서명은 Poki Setup이나 Poki 앱에서 갱신할 수 있습니다. |
| 연결 | `10.7.0.1`을 iPhone으로 돌려보내는 로컬 VPN 앱(LocalDevVPN, Karing, Shadowrocket). |
| 모델 계정 | ChatGPT Plus/Pro 로그인, API 키(Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, OpenCode Go) 또는 OpenAI 호환 서버. |

- 전체 설치 안내, 업데이트, FAQ, 알려진 제한 및 로드맵: [Poki iPhone 앱 가이드](docs/iphone-guide.md)
- 버전별 변경 사항: [CHANGELOG.md](CHANGELOG.md)
- 에이전트 설치 스킬 및 데스크톱 도우미: [install-poki 스킬](skills/install-poki/SKILL.md) 및 [Poki Setup](desktop/README.md)
- 검증 기록, 제한 사항 및 릴리스 채널: [검증 및 제한](docs/verification.md) 및 [릴리스 채널](docs/release-channels.md)
- 기존 컴퓨터 연동 도구(업데이트 중단): [Poki MCP 및 Poki Agent](docs/poki-mcp.md)

</details>

## 커뮤니티

- **질문 및 아이디어:** [GitHub Discussions](https://github.com/JosssphZhou/poki/discussions)에 참여해 주세요.
- **버그 제보 및 기능 제안:** [GitHub Issues](https://github.com/JosssphZhou/poki/issues)에 올려 주세요.
- **코드 기여:** [CONTRIBUTING.md](CONTRIBUTING.md)를 참고해 주세요.

### 공동 창작자

<!-- CO-CREATOR:START -->
<p align="center">
  <a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=320" width="160" height="160" alt="ZhehanZhang"/><br /><b>ZhehanZhang</b></a><br />
  Poki의 위대한 공동 창작자.
</p>
<!-- CO-CREATOR:END -->

### 핵심 기여자

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />Poki의 첫 번째 이슈 <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>을 올렸습니다. iOS 18.6.2에서 스크린샷은 되고 손쉬운 사용과 터치는 안 된다는 점을 명확히 나누어 적어 주었습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/14">#14</a>에서 Poki를 라우터에서 실행할 수 있게 만들어 Mac이 꺼져 있어도 Telegram으로 iPhone을 조작할 수 있게 했고, <a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>, <a href="https://github.com/JosssphZhou/poki/pull/17">#17</a>, <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a>가 이어졌습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/6">#6</a>에서 macOS 27.2의 usbmuxd가 iPhone을 목록에 보이지 않는 문제를 보고했습니다. 이제 Poki는 이를 분명히 알리고 도우미가 일찍 멈춘 이유도 알려 줍니다(<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>).</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/10">#10</a>에서 실제 iPhone의 탭이 느린 원인을 찾아냈고, 이후 수정으로 탭이 약 3분의 1 빨라졌습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/16">#16</a>에서 Poki를 Linux로 포팅해 실제 iPhone에서 USB, LAN, Tailscale 연결을 검증했고, README는 이 포팅 버전을 안내합니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/18">#18</a>에서 실제 iPhone의 터치 실패 원인이 display service 누락임을 밝혀냈고, 이제 Poki는 아무것도 전송되지 않았다고 알리며 prepare-device를 안내합니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />손상된 캐시 경로가 관련 없는 Agent 작업을 중단시키는 문제를 고쳤고(<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>, <a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>), 이어 <a href="https://github.com/JosssphZhou/poki/pull/37">#37</a>에서 Agent가 동작 후 읽은 화면을 재사용하게 했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/25">#25</a>에서 자연어 중지 요청으로는 iMessage 작업이 멈추지 않는다고 보고했고, 이제 Poki는 작업 도중 받은 메시지에 답하며 /stop을 안내합니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/27">#27</a>과 <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a>에서 Agent 버그 두 건을 재현한 뒤, 취소된 입력 잠금(<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>)부터 잘못된 터치 좌표(<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>)까지 수정과 테스트 정비 일곱 건을 병합했습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />iPhone의 LAN 주소가 바뀌면 끊기던 RemotePairing 연결(<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>)을 <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a>에서 고쳤고, 실제 iPhone은 768ms 만에 다시 연결되었습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/35">#35</a>와 <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a>에서 모바일 데이터와 Windows로 iPhone 앱을 실기기 테스트했고, 첫 설정에 Wi-Fi가 필요하다는 안내(<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>)로 이어졌습니다. <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>도 보고했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />Windows 호스트에서 RemotePairing으로 연결할 때 탭이 매번 실패하던 문제를 <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a>에서 고쳤고, 수정 후 5번 중 5번의 탭이 성공했습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/42">#42</a>에서 Tailscale로 연결한 실제 iPhone으로 보험 약관을 확인했고, 이 보고가 더 알기 쉬운 USB 오류와 세션별 연결 방식 전환 작업으로 이어졌습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />Poki가 실제 iPhone을 조작하는 데모 영상을 제작해, 새 방문자가 설치하기 전에 무엇을 할 수 있는지 볼 수 있게 했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/68">#68</a>에서 OpenCode Go를 iPhone 앱의 모델 계정으로 추가했습니다. 전용 키체인 자격 증명과 독립된 모델 선택을 갖추고 있습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/69">#69</a>에서 Runner가 약 25분 유휴 후 페어링에 실패하는 과정을 상세히 기록했습니다. 이제 Setup은 Loopback과 Pairing 확인을 안내합니다(<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />배치 호출이 기기가 모호할 때 충돌하지 않고 알려 주도록 했고(<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>), POKI_MCP_DEVICE(<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>)와 작업별 선택적 승인 단계(<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>)를 추가했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />페어링 설정이 잘못된 설정 페이지로 안내하던 문제를 고쳐, 개발자 모드와 UI 자동화 단계가 이제 올바른 페이지를 엽니다(<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>).</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/139">#139</a>에서 화면 읽기가 호출 기한을 넘기던 문제를 고쳤고, 계속 느린 Runner 응답에 대한 회귀 테스트도 추가했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Ryanwu316"><img src="https://avatars.githubusercontent.com/u/49024277?v=4&size=240" width="120" height="120" alt="Ryanwu316"/><br /><sub><b>Ryanwu316</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/354">#354</a>에서 iPhone Duo에 두 앱 작업 공간을 추가해, 화면을 돌리는 동안 작업이 기다렸다가 같은 앱 쌍에서 이어지도록 했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/soloface"><img src="https://avatars.githubusercontent.com/u/62548950?v=4&size=240" width="120" height="120" alt="soloface"/><br /><sub><b>soloface</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/311">#311</a>에서 휴대폰이 온라인으로 표시되는데도 MCP가 503을 반환하는 원인이 릴레이 재연결 결함임을 찾아내고, 재현 테스트와 패치를 함께 제공했습니다.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/whiteluw"><img src="https://avatars.githubusercontent.com/u/86720151?v=4&size=240" width="120" height="120" alt="whiteluw"/><br /><sub><b>whiteluw</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/326">#326</a>에서 iPhone의 3D 곰 초기화 중 발생하는 충돌을 수정했습니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/cs50Mu"><img src="https://avatars.githubusercontent.com/u/4456781?v=4&size=240" width="120" height="120" alt="cs50Mu"/><br /><sub><b>cs50Mu</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/issues/362">#362</a>에서 Poki Setup의 macOS 설치 파일이 Apple 실리콘에서만 실행된다는 것을 찾아냈고, 이후의 유니버설 빌드는 Intel Mac에서도 실행됩니다.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mgkvibez"><img src="https://avatars.githubusercontent.com/u/198796435?v=4&size=240" width="120" height="120" alt="mgkvibez"/><br /><sub><b>mgkvibez</b></sub></a><br /><a href="https://github.com/JosssphZhou/poki/pull/380">#380</a>에서 결제 판단이 메시지 전송 판단보다 먼저 이루어지도록 지키는 테스트를 추가해, Mail의 “Send money” 같은 버튼도 계속 승인을 먼저 받습니다.</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

<details>
<summary>특별 기여자, 고마운 분들 및 Star History</summary>

### 특별 기여자

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />0.4.0 개편을 위해 채팅, 실시간 현황, 설정, 첫 실행 과정을 포함한 전체 인터페이스 디자인을 제공했습니다(<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>, <a href="https://github.com/JosssphZhou/poki/pull/256">#256</a>, <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>). 새 인터페이스의 방향을 잡는 데 기여했습니다.</td>
    </tr>
  </tbody>
</table>

### 고마운 분들

Issue나 Pull Request를 남겨 주신 모든 분께 감사드리며, 여러분의 제보와 수정 덕분에 Poki가 더 좋아지고 있습니다.

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

[AGPL-3.0-only](LICENSE) 라이선스로 공개됩니다. 브랜드 자산 규정은 [BRAND.md](BRAND.md)를 따릅니다. 자세한 내용은 [Poki iPhone 앱 가이드](docs/iphone-guide.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [면책 조항](docs/iphone-guide.md#disclaimer)을 참고하세요.
