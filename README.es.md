<p align="center">
  <img src="docs/images/poki-icon.png" width="64" height="64" alt="Poki icon">
</p>

<h1 align="center">Poki usa tu iPhone como lo harías tú</h1>

<p align="center">
  <img src="docs/images/poki-home.gif" width="500" alt="Animación de la página de inicio del sitio web de Poki">
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | <a href="README.ja.md">日本語</a> | <a href="README.ko.md">한국어</a> | Español<br>
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
  <strong>Si Poki te resulta útil, haz clic en ★ Star para apoyar el proyecto.</strong>
</p>

## Qué es Poki

Poki es un agente de código abierto para iPhone que opera todo tu iPhone por ti. La app Poki funciona directamente en el propio iPhone, lee la pantalla y toca, escribe y desplaza contenido en apps reales usando tu propia cuenta de modelo. Tú eliges cómo pide permiso; los pagos, las eliminaciones y las acciones en Wallet siempre piden confirmación.

## Por qué Poki

- **Evita saltar entre apps para tareas cotidianas.** Pide ayuda a Poki en el chat, mantén pulsado el botón de Acción o usa Siri para buscar en el navegador integrado, consultar el tiempo o crear una nota. En iPhone Duo, Poki trabaja en dos apps a la vez en Vista dividida.
- **Ejecuta rutinas repetidas con un toque o con la voz.** En lugar de repetir los mismos pasos cada día, abre una rutina guardada desde la pantalla de inicio o inicia una charla por voz mientras la Dynamic Island muestra cada paso.
- **Automatiza tu teléfono real sin dejar un ordenador encendido.** Tras instalarlo una vez desde Mac o Windows, Poki funciona de forma independiente en el iPhone y se detiene en la pantalla bloqueada o en la Dynamic Island cuando hace falta tu aprobación.

## Cómo usarlo

### Instala Poki en tu iPhone

1. **Instala una vez desde un Mac o PC con Windows.** Conecta y desbloquea tu iPhone por USB (sirve una cuenta gratuita de Apple) y envía a tu agente de código, como Claude Code o Codex:

   ```text
   Install Poki on my iPhone from https://github.com/JosssphZhou/poki
   ```

   También puedes descargar [Poki Setup](https://github.com/JosssphZhou/poki/releases) para macOS (`.dmg`) o Windows (`.exe`) y seguir la ventana.
2. **Conecta y añade tu cuenta de modelo.** Acepta **Confiar**, activa el Modo desarrollador y el Modo de automatización cuando iOS lo pida, instala una app VPN local que enrute `10.7.0.1` al propio iPhone (como LocalDevVPN, gratuita) e inicia sesión con ChatGPT Plus o Pro, o pega una clave API (Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, OpenCode Go o un servidor compatible con OpenAI).
3. **Ejecuta tu primera tarea.** Abre Poki y envía:

   ```text
   Create a new note in Notes titled "Poki Demo" with these three lines: Milk, Eggs, Coffee. Open the note when finished. Leave existing notes unchanged.
   ```

   Abre Notas después para confirmar que existe "Poki Demo" con esas tres líneas.

<details>
<summary>Requisitos, actualizaciones, preguntas frecuentes y guías</summary>

| Elemento | Requisito |
| --- | --- |
| iPhone | iOS 18 o posterior (iPhone XS, XR, SE 2.ª gen. o posterior; también iPadOS 18+). Probado en iPhones físicos con iOS 27. |
| Ordenador | Mac con macOS 14+ (Node.js 24+ para instalación con agente) o PC Windows (x64) con Apple Devices o iTunes. |
| Cable y cuenta | Cable de datos USB y cuenta de Apple. Poki Setup renueva firmas gratuitas de 7 días mientras está abierto, o inicia sesión dentro de Poki. |
| Conexión | App VPN local que enrute `10.7.0.1` de vuelta al iPhone (LocalDevVPN, Karing o Shadowrocket). |
| Cuenta de modelo | Sesión de ChatGPT Plus/Pro, clave API (Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, OpenCode Go) o servidor compatible con OpenAI. |

- Instalación completa, actualizaciones, preguntas frecuentes, límites y hoja de ruta: [Guía de Poki para iPhone](docs/iphone-guide.md)
- Registro de cambios: [CHANGELOG.md](CHANGELOG.md)
- Skill para agentes y asistente de escritorio: [skill install-poki](skills/install-poki/SKILL.md) y [Poki Setup](desktop/README.md)
- Verificación, límites y canales de publicación: [Verificación](docs/verification.md) y [Canales de publicación](docs/release-channels.md)
- Herramientas anteriores desde ordenador (sin nuevas actualizaciones): [Poki MCP y Poki Agent](docs/poki-mcp.md)

</details>

## Comunidad

- **Dudas e ideas:** Únete a [GitHub Discussions](https://github.com/JosssphZhou/poki/discussions).
- **Errores y sugerencias:** Abre un issue en [GitHub Issues](https://github.com/JosssphZhou/poki/issues).
- **Contribuir:** Consulta [CONTRIBUTING.md](CONTRIBUTING.md).

### Cocreador

<!-- CO-CREATOR:START -->
<p align="center">
  <a href="https://github.com/ZhehanZhang"><img src="https://avatars.githubusercontent.com/u/67270559?v=4&size=320" width="160" height="160" alt="ZhehanZhang"/><br /><b>ZhehanZhang</b></a><br />
  El gran cocreador de Poki.
</p>
<!-- CO-CREATOR:END -->

### Colaboradores principales

<!-- CORE-CONTRIBUTORS:START -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/makirqi-alt"><img src="https://avatars.githubusercontent.com/u/295395617?v=4&size=240" width="120" height="120" alt="makirqi-alt"/><br /><sub><b>makirqi-alt</b></sub></a><br />Abrió el primer issue de Poki, <a href="https://github.com/JosssphZhou/poki/issues/1">#1</a>, en iOS 18.6.2: las capturas funcionaban, la accesibilidad y el toque no, y la separación clara lo hizo fácil de seguir.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/edge369"><img src="https://avatars.githubusercontent.com/u/63720633?v=4&size=240" width="120" height="120" alt="edge369"/><br /><sub><b>edge369</b></sub></a><br />Hizo que Poki funcionara en un router en <a href="https://github.com/JosssphZhou/poki/pull/14">#14</a>, de modo que Telegram controla el iPhone con el Mac apagado; siguieron <a href="https://github.com/JosssphZhou/poki/pull/15">#15</a>, <a href="https://github.com/JosssphZhou/poki/pull/17">#17</a> y <a href="https://github.com/JosssphZhou/poki/issues/19">#19</a>.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mawenhao1028"><img src="https://avatars.githubusercontent.com/u/70818670?v=4&size=240" width="120" height="120" alt="mawenhao1028"/><br /><sub><b>mawenhao1028</b></sub></a><br />Informó en <a href="https://github.com/JosssphZhou/poki/issues/6">#6</a> de que usbmuxd no listaba ningún iPhone en macOS 27.2; ahora Poki lo dice con claridad y explica por qué un ayudante se detiene antes de tiempo (<a href="https://github.com/JosssphZhou/poki/issues/59">#59</a>).</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/igc110"><img src="https://avatars.githubusercontent.com/u/241411380?v=4&size=240" width="120" height="120" alt="igc110"/><br /><sub><b>igc110</b></sub></a><br />Descubrió en <a href="https://github.com/JosssphZhou/poki/issues/10">#10</a> por qué los toques en un iPhone físico eran lentos; la corrección posterior los hizo alrededor de un tercio más rápidos.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/carrotciallo"><img src="https://avatars.githubusercontent.com/u/69567867?v=4&size=240" width="120" height="120" alt="carrotciallo"/><br /><sub><b>carrotciallo</b></sub></a><br />Portó Poki a Linux y lo probó en un iPhone físico por USB, LAN y Tailscale en <a href="https://github.com/JosssphZhou/poki/issues/16">#16</a>; el README ahora lo enlaza.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/guangtouge82"><img src="https://avatars.githubusercontent.com/u/269691899?v=4&size=240" width="120" height="120" alt="guangtouge82"/><br /><sub><b>guangtouge82</b></sub></a><br />Rastreó en <a href="https://github.com/JosssphZhou/poki/issues/18">#18</a> los toques fallidos de un iPhone físico hasta la falta de display service; ahora Poki indica que no se envió nada y apunta a prepare-device.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Dreaminmaster"><img src="https://avatars.githubusercontent.com/u/189544503?v=4&size=240" width="120" height="120" alt="Dreaminmaster"/><br /><sub><b>Dreaminmaster</b></sub></a><br />Corrigió una ruta en caché corrupta que abortaba tareas del Agent sin relación (<a href="https://github.com/JosssphZhou/poki/issues/21">#21</a>, <a href="https://github.com/JosssphZhou/poki/pull/22">#22</a>) y después hizo que el Agent reutilice la pantalla ya leída tras cada acción (<a href="https://github.com/JosssphZhou/poki/pull/37">#37</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/PeterKingXu1s"><img src="https://avatars.githubusercontent.com/u/89392314?v=4&size=240" width="120" height="120" alt="PeterKingXu1s"/><br /><sub><b>PeterKingXu1s</b></sub></a><br />Reportó en <a href="https://github.com/JosssphZhou/poki/issues/25">#25</a> que una petición de detener en lenguaje natural no interrumpía una tarea de iMessage; ahora Poki responde a los mensajes enviados durante la tarea y señala /stop.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/ScottH1122"><img src="https://avatars.githubusercontent.com/u/142722955?v=4&size=240" width="120" height="120" alt="ScottH1122"/><br /><sub><b>ScottH1122</b></sub></a><br />Reprodujo dos errores del Agent en <a href="https://github.com/JosssphZhou/poki/issues/27">#27</a> y <a href="https://github.com/JosssphZhou/poki/issues/28">#28</a> y luego fusionó siete correcciones y arreglos de pruebas, desde bloqueos de entrada cancelados (<a href="https://github.com/JosssphZhou/poki/pull/102">#102</a>) hasta coordenadas táctiles no válidas (<a href="https://github.com/JosssphZhou/poki/pull/136">#136</a>).</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/jiahuipaung"><img src="https://avatars.githubusercontent.com/u/70688286?v=4&size=240" width="120" height="120" alt="jiahuipaung"/><br /><sub><b>jiahuipaung</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/34">#34</a> una conexión RemotePairing que fallaba al cambiar la dirección LAN del iPhone (<a href="https://github.com/JosssphZhou/poki/issues/30">#30</a>); un iPhone real se reconectó en 768 ms.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Zeno6898"><img src="https://avatars.githubusercontent.com/u/229920081?v=4&size=240" width="120" height="120" alt="Zeno6898"/><br /><sub><b>Zeno6898</b></sub></a><br />Probó la app de iPhone con datos móviles y desde Windows en <a href="https://github.com/JosssphZhou/poki/issues/35">#35</a> y <a href="https://github.com/JosssphZhou/poki/issues/40">#40</a>, lo que dio lugar a la nota sobre Wi-Fi en la primera configuración (<a href="https://github.com/JosssphZhou/poki/issues/138">#138</a>); también informó de <a href="https://github.com/JosssphZhou/poki/issues/162">#162</a>.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/scy7796"><img src="https://avatars.githubusercontent.com/u/282529358?v=4&size=240" width="120" height="120" alt="scy7796"/><br /><sub><b>scy7796</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/39">#39</a> los toques que fallaban siempre por RemotePairing desde un host Windows; después, 5 de 5 toques funcionaron.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/foshanfm"><img src="https://avatars.githubusercontent.com/u/24779370?v=4&size=240" width="120" height="120" alt="foshanfm"/><br /><sub><b>foshanfm</b></sub></a><br />Hizo en <a href="https://github.com/JosssphZhou/poki/issues/42">#42</a> una comprobación de condiciones de seguros en un iPhone real por Tailscale; su informe orientó errores USB más claros y un cambio de transporte por sesión.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/xiaweiyi713"><img src="https://avatars.githubusercontent.com/u/208608622?v=4&size=240" width="120" height="120" alt="xiaweiyi713"/><br /><sub><b>xiaweiyi713</b></sub></a><br />Grabó vídeos de demostración de Poki controlando un iPhone real, para que los visitantes nuevos vean qué hace antes de instalar nada.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/fucknima"><img src="https://avatars.githubusercontent.com/u/18666223?v=4&size=240" width="120" height="120" alt="f&#42;&#42;&#42;&#42;&#42;&#42;&#42;"/><br /><sub><b>f&#42;&#42;&#42;&#42;&#42;&#42;&#42;</b></sub></a><br />Añadió OpenCode Go como cuenta de modelo en la app de iPhone en <a href="https://github.com/JosssphZhou/poki/pull/68">#68</a>, con su propia credencial en el llavero y una elección de modelo independiente.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/owensn951954688"><img src="https://avatars.githubusercontent.com/u/312761798?v=4&size=240" width="120" height="120" alt="owensn951954688"/><br /><sub><b>owensn951954688</b></sub></a><br />Aportó en <a href="https://github.com/JosssphZhou/poki/issues/69">#69</a> la cronología completa de un fallo de emparejamiento del Runner tras 25 minutos de inactividad; Setup ahora remite a Loopback y Pairing (<a href="https://github.com/JosssphZhou/poki/issues/70">#70</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/kira-ariaki"><img src="https://avatars.githubusercontent.com/u/257352493?v=4&size=240" width="120" height="120" alt="kira-ariaki"/><br /><sub><b>kira-ariaki</b></sub></a><br />Hizo que las llamadas por lotes avisen de un dispositivo ambiguo en vez de fallar (<a href="https://github.com/JosssphZhou/poki/pull/74">#74</a>) y añadió POKI_MCP_DEVICE (<a href="https://github.com/JosssphZhou/poki/pull/75">#75</a>) y una aprobación opcional por tarea (<a href="https://github.com/JosssphZhou/poki/pull/77">#77</a>).</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Purelite"><img src="https://avatars.githubusercontent.com/u/9334469?v=4&size=240" width="120" height="120" alt="Purelite"/><br /><sub><b>Purelite</b></sub></a><br />Corrigió que la configuración del emparejamiento llevara a la página de Ajustes equivocada; los pasos de Modo desarrollador y automatización de UI ahora abren la correcta (<a href="https://github.com/JosssphZhou/poki/pull/137">#137</a>).</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/heyallencao"><img src="https://avatars.githubusercontent.com/u/258265534?v=4&size=240" width="120" height="120" alt="heyallencao"/><br /><sub><b>heyallencao</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/139">#139</a> las lecturas de pantalla que superaban el plazo de la llamada, con una prueba de regresión para respuestas del Runner constantemente lentas.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/Ryanwu316"><img src="https://avatars.githubusercontent.com/u/49024277?v=4&size=240" width="120" height="120" alt="Ryanwu316"/><br /><sub><b>Ryanwu316</b></sub></a><br />Añadió en <a href="https://github.com/JosssphZhou/poki/pull/354">#354</a> los espacios de trabajo con dos apps en el iPhone Duo: la tarea espera durante la rotación y continúa en el mismo par de apps.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/soloface"><img src="https://avatars.githubusercontent.com/u/62548950?v=4&size=240" width="120" height="120" alt="soloface"/><br /><sub><b>soloface</b></sub></a><br />Descubrió en <a href="https://github.com/JosssphZhou/poki/issues/311">#311</a> que los errores 503 de MCP con el teléfono en línea venían de un fallo de reconexión del relé, y aportó una prueba que lo reproduce y un parche.</td>
    </tr>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/whiteluw"><img src="https://avatars.githubusercontent.com/u/86720151?v=4&size=240" width="120" height="120" alt="whiteluw"/><br /><sub><b>whiteluw</b></sub></a><br />Corrigió en <a href="https://github.com/JosssphZhou/poki/pull/326">#326</a> un fallo al inicializar el oso 3D en el iPhone.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/cs50Mu"><img src="https://avatars.githubusercontent.com/u/4456781?v=4&size=240" width="120" height="120" alt="cs50Mu"/><br /><sub><b>cs50Mu</b></sub></a><br />Descubrió en <a href="https://github.com/JosssphZhou/poki/issues/362">#362</a> que la descarga de Poki Setup para macOS solo funcionaba en Apple silicon; la compilación universal posterior también funciona en Mac con Intel.</td>
      <td align="center" valign="top" width="33%"><a href="https://github.com/mgkvibez"><img src="https://avatars.githubusercontent.com/u/198796435?v=4&size=240" width="120" height="120" alt="mgkvibez"/><br /><sub><b>mgkvibez</b></sub></a><br />Añadió en <a href="https://github.com/JosssphZhou/poki/pull/380">#380</a> una prueba que mantiene la comprobación de pagos antes que la de envío de mensajes, de modo que un botón “Send money” en Mail sigue pidiendo aprobación.</td>
    </tr>
  </tbody>
</table>
<!-- CORE-CONTRIBUTORS:END -->

<details>
<summary>Colaboradores especiales, menciones y Star History</summary>

### Colaboradores especiales

<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="33%"><a href="https://github.com/yulunRyanw"><img src="https://avatars.githubusercontent.com/u/216360668?v=4&size=240" width="120" height="120" alt="yulunRyanw"/><br /><sub><b>yulunRyanw</b></sub></a><br />Aportó un conjunto completo de diseños para la renovación de 0.4.0, incluidos el chat, las actividades en directo, los ajustes y el primer inicio (<a href="https://github.com/JosssphZhou/poki/pull/250">#250</a>, <a href="https://github.com/JosssphZhou/poki/pull/256">#256</a>, <a href="https://github.com/JosssphZhou/poki/pull/268">#268</a>); ayudaron a definir la nueva interfaz.</td>
    </tr>
  </tbody>
</table>

### Menciones especiales

Gracias a todas las personas que han abierto un issue o un pull request; sus reportes y correcciones hacen que Poki sea cada vez mejor.

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

Código abierto bajo [AGPL-3.0-only](LICENSE). Los recursos de marca se rigen por [BRAND.md](BRAND.md). Consulta [Guía de Poki para iPhone](docs/iphone-guide.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) y el [Descargo de responsabilidad](docs/iphone-guide.md#disclaimer).
