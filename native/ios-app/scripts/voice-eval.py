#!/usr/bin/env python3
"""Live voice eval: plays spoken Chinese into a real Realtime session over WebRTC, as the phone's
microphone does, with the session the voice bridge mints (bin/voice-bridge.mjs: the same instructions,
tools and turn detection as VoiceDirect.swift), and checks what the model did. The client does what
VoiceModel does: it turns the session's speech detection off from the start of each answer until its
audio has played, and closes wait_for_user without asking for an answer. The tools are stubbed: they
answer in English, as Poki's often do.

The scenarios are the spoken acceptance sentences for the live voice, with the iPhone in Chinese:

  open         打开微信: one word (好), open_app with 微信, the result in Chinese
  scroll       打开微信, then 往下翻一下: run_task, no translation, nothing in English
  hello        给文件传输助手发个hello: one sentence that names 文件传输助手, run_task in the same turn,
               without waiting for a yes
  stop         停 while that task runs: stop_task
  backchannel  嗯 0.3 s into Poki's answer: the answer plays to its end, is not said again, nothing in English
and two more from a talk on a physical iPhone:
  start_blip   a short English sound as the talk opens, then 帮我打开我的微信: every answer in Chinese
  flip         打开微信, then 稍微翻一下: run_task (scroll), not a translation

Speech comes from macOS `say` (Tingting, Samantha) through ffmpeg; nothing is played aloud. Needs
`pip install aiortc aiohttp`, Node for the bridge and an OpenAI API key:

    OPENAI_API_KEY=... python3 native/ios-app/scripts/voice-eval.py [--scenario all] [--runs 4]

A scenario passes when every run does. Exit status 1 when any scenario fails.
"""
import argparse, asyncio, fractions, json, os, re, subprocess, sys, tempfile, time

import aiohttp
import av
from aiortc import MediaStreamTrack, RTCPeerConnection, RTCSessionDescription

RATE = 48000
FRAME = 960
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
CLIPS = {
    "it": ("Samantha", "it"),
    "open_mine": ("Tingting", "帮我打开我的微信"),
    "open": ("Tingting", "打开微信"),
    "look": ("Tingting", "看一下我这个界面有什么内容"),
    "scroll": ("Tingting", "往下翻一下"),
    "flip": ("Tingting", "稍微翻一下"),
    "hello": ("Tingting", "给文件传输助手发个hello"),
    "stop": ("Tingting", "停"),
    "en": ("Tingting", "嗯"),
}
LOOK = ("app: WeChat\nelements (9):\n 1 Other \"Chats\" [0,54,402,44]\n 2 Button \"Search\" [306,58,40,44]\n"
        " 3 Cell \"Family group, unread, [6 messages] Mom: ok, 13:42\" [0,353,402,72]\n 4 Cell \"Official Accounts, unread, [6]\" [0,425,402,72]\n"
        " 5 Cell \"Alex, [Voice] 11\\\", 13:37\" [0,497,402,72]\n 6 Button \"Chats\" [0,800,100,74]\n 7 Button \"Contacts\" [100,800,100,74]\n"
        " 8 Button \"Discover\" [200,800,100,74]\n 9 Button \"Me\" [300,800,100,74]")
OPENED = "launch com.tencent.xin\napp: WeChat\nelements (3):\n 1 Other \"Chats\" [0,54,402,44]\n 2 Button \"Search\" [306,58,40,44]\n 3 Button \"Me\" [300,800,100,74]"
TASK = "result: done: the task is finished.\nPoki said: Done."
STOPPED = "result: stopped by the user."


def make_clips(folder):
    for name, (voice, text) in CLIPS.items():
        aiff = os.path.join(folder, f"{name}.aiff")
        subprocess.run(["say", "-v", voice, "-o", aiff, text], check=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", aiff, "-ac", "1", "-ar", str(RATE), "-f", "s16le",
                        os.path.join(folder, f"{name}.pcm")], check=True)


class Mic(MediaStreamTrack):
    """Silence, except for the clips handed to say(), in real time."""
    kind = "audio"

    def __init__(self):
        super().__init__()
        self.queue = bytearray()
        self.pts = 0
        self.start = None

    def say(self, pcm):
        self.queue += pcm

    async def recv(self):
        self.start = self.start or time.monotonic()
        wait = self.start + self.pts / RATE - time.monotonic()
        if wait > 0:
            await asyncio.sleep(wait)
        chunk = bytes(self.queue[:FRAME * 2]).ljust(FRAME * 2, b"\0")
        del self.queue[:FRAME * 2]
        frame = av.AudioFrame(format="s16", layout="mono", samples=FRAME)
        frame.planes[0].update(chunk)
        frame.sample_rate, frame.pts, frame.time_base = RATE, self.pts, fractions.Fraction(1, RATE)
        self.pts += FRAME
        return frame


def chinese(text):
    han = len(re.findall(r"[一-鿿]", text))
    return han > 0 and han >= len(re.findall(r"[A-Za-z]", text)) / 3


class Talk:
    def __init__(self, secret, clips):
        self.secret, self.clips = secret, clips
        self.t0 = time.monotonic()
        self.mic = Mic()
        self.log, self.calls, self.replies = [], [], []
        self.args = {}
        self.events = 0
        self.speaking = False
        self.turn_detection = None
        self.deaf = False
        self.active = None
        self.played = False
        self.stopped = asyncio.Event()
        self.task_takes = 1.5
        self.cleared = self.cancelled = self.outputs = self.replied_after_output = 0

    def note(self, text):
        self.log.append(f"{time.monotonic() - self.t0:6.2f} {text}")

    def send(self, event):
        self.channel.send(json.dumps(event))

    def say(self, clip):
        with open(os.path.join(self.clips, f"{clip}.pcm"), "rb") as f:
            self.mic.say(f.read())

    async def until(self, test, timeout=20):
        end = time.monotonic() + timeout
        while time.monotonic() < end and not test():
            await asyncio.sleep(0.05)
        return test()

    async def quiet(self, settle=1.5, timeout=30):
        """Until nothing has happened for `settle` seconds and Poki is not speaking."""
        end, last, seen = time.monotonic() + timeout, time.monotonic(), self.events
        while time.monotonic() < end:
            await asyncio.sleep(0.1)
            if self.events != seen or self.speaking:
                seen, last = self.events, time.monotonic()
            elif time.monotonic() - last > settle:
                return

    def english(self):
        return [x for x in self.replies if x.strip() and not chinese(x)]

    def hear(self, on):
        """VoiceModel.hear: speech detection off while Poki answers, back on after."""
        if self.deaf != on or self.turn_detection is None:
            return
        self.deaf = not on
        self.send({"type": "session.update", "session": {"type": "realtime", "audio": {"input": {"turn_detection": self.turn_detection if on else None}}}})

    def on_event(self, e):
        self.events += 1
        t = e.get("type", "")
        if t == "session.created":
            self.turn_detection = e.get("session", {}).get("audio", {}).get("input", {}).get("turn_detection")
            self.note("session created")
        elif t == "session.updated":
            turn = e.get("session", {}).get("audio", {}).get("input", {}).get("turn_detection")
            self.note(f"speech detection {'on' if turn else 'off'}")
        elif t == "input_audio_buffer.speech_started":
            self.note("speech started")
        elif t == "input_audio_buffer.speech_stopped":
            self.note("speech stopped")
        elif t == "conversation.item.input_audio_transcription.completed":
            self.note(f"heard: {e.get('transcript', '').strip()}")
        elif t == "response.created":
            self.active, self.played = e.get("response", {}).get("id"), False
            self.hear(False)
        elif t == "response.done":
            response = e.get("response", {})
            self.cancelled += response.get("status") == "cancelled"
            if response.get("id") == self.active:
                self.active = None
            spoke = any(item.get("type") == "message" for item in response.get("output", []))
            if not spoke or self.played:
                self.hear(True)
            self.note(f"response {response.get('status')}")
        elif t == "output_audio_buffer.started":
            self.speaking = True
            self.note("audio started")
        elif t in ("output_audio_buffer.stopped", "output_audio_buffer.cleared"):
            self.speaking, self.played = False, True
            self.cleared += t.endswith("cleared")
            if self.active is None:
                self.hear(True)
            self.note(f"audio {t.split('.')[-1]}")
        elif t == "response.output_audio_transcript.done":
            self.replies.append(e.get("transcript", ""))
            self.replied_after_output += self.outputs > 0
            self.note(f"said: {e.get('transcript', '')}")
        elif t == "response.output_item.done" and e.get("item", {}).get("type") == "function_call":
            item = e["item"]
            self.calls.append(item.get("name"))
            self.args.setdefault(item.get("name"), []).append(item.get("arguments"))
            self.note(f"call {item.get('name')} {item.get('arguments')}")
            asyncio.get_event_loop().create_task(self.answer(item))
        elif t == "error":
            self.note(f"error: {e.get('error', {}).get('message')}")

    async def answer(self, item):
        name = item.get("name")
        if name == "run_task":
            try:
                await asyncio.wait_for(self.stopped.wait(), self.task_takes)
                output = STOPPED
            except asyncio.TimeoutError:
                output = TASK
        else:
            if name == "stop_task":
                self.stopped.set()
            await asyncio.sleep({"look": 0.8, "open_app": 1.0}.get(name, 0))
            output = {"look": LOOK, "open_app": OPENED, "stop_task": "stopped"}.get(name, "ok")
        self.send({"type": "conversation.item.create", "item": {"type": "function_call_output", "call_id": item["call_id"], "output": output}})
        self.outputs += 1
        if name != "wait_for_user":
            # As VoiceModel.flush: one response at a time.
            await self.until(lambda: self.active is None, timeout=10)
            self.send({"type": "response.create"})

    async def connect(self):
        self.pc = RTCPeerConnection()
        self.pc.addTrack(self.mic)
        self.channel = self.pc.createDataChannel("oai-events")
        created = asyncio.Event()

        @self.channel.on("message")
        def message(raw):
            event = json.loads(raw)
            if event.get("type") == "session.created":
                created.set()
            self.on_event(event)

        @self.pc.on("track")
        def track(remote):
            async def drain():
                try:
                    while True:
                        await remote.recv()
                except Exception:
                    pass
            asyncio.get_event_loop().create_task(drain())

        await self.pc.setLocalDescription(await self.pc.createOffer())
        async with aiohttp.ClientSession() as http:
            async with http.post("https://api.openai.com/v1/realtime/calls", data=self.pc.localDescription.sdp,
                                 headers={"Authorization": f"Bearer {self.secret}", "Content-Type": "application/sdp"}) as r:
                answer = await r.text()
                if r.status >= 300:
                    raise RuntimeError(f"realtime/calls answered {r.status}: {answer[:200]}")
        await self.pc.setRemoteDescription(RTCSessionDescription(sdp=answer, type="answer"))
        await asyncio.wait_for(created.wait(), 15)


async def opened(t, clip="open"):
    t.say(clip)
    await t.until(lambda: t.outputs > 0 and t.replied_after_output > 0)
    await t.quiet()


async def open_wechat(t):
    await opened(t)
    first = t.replies[0] if t.replies else ""
    ok = (t.calls[:1] == ["open_app"] and "微信" in (t.args["open_app"][0] or "") and len(re.sub(r"\W", "", first)) <= 3
          and t.replied_after_output > 0 and not t.english())
    return ok, {"calls": t.calls, "said": t.replies, "english": t.english()}


async def then(t, clip):
    await opened(t)
    calls, said = len(t.calls), len(t.replies)
    t.say(clip)
    await t.until(lambda: len(t.calls) > calls)
    await t.quiet(settle=2.5)
    later = t.calls[calls:]
    return "run_task" in later and not t.english(), {"calls": later, "said": t.replies[said:], "english": t.english()}


async def hello(t):
    t.task_takes = 4
    t.say("hello")
    await t.until(lambda: "run_task" in t.calls)
    restated = [x for x in t.replies if "文件传输助手" in x]
    task = (t.args.get("run_task") or [""])[0] or ""
    await t.until(lambda: t.replied_after_output > 0)
    await t.quiet()
    ok = bool(restated) and "文件传输助手" in task and "hello" in task.lower() and not t.english()
    return ok, {"task": task, "said": t.replies, "english": t.english()}


async def stop(t):
    t.task_takes = 30
    t.say("hello")
    await t.until(lambda: "run_task" in t.calls)
    await t.until(lambda: not t.speaking and t.active is None, timeout=10)
    await asyncio.sleep(1)
    t.say("stop")
    stopped = await t.until(lambda: "stop_task" in t.calls, timeout=8)
    await t.quiet()
    return stopped and not t.english(), {"calls": t.calls, "said": t.replies, "english": t.english()}


async def start_blip(t):
    t.say("it")
    await t.quiet()
    await opened(t, "open_mine")
    return any(c in ("open_app", "run_task") for c in t.calls) and not t.english(), {"calls": t.calls, "said": t.replies, "english": t.english()}


async def backchannel(t):
    t.say("look")
    await t.until(lambda: t.outputs > 0)
    await t.until(lambda: t.speaking and t.replied_after_output == 0)
    await asyncio.sleep(0.3)
    t.say("en")
    await t.quiet(settle=2.5)
    ok = t.cleared == 0 and t.cancelled == 0 and t.replied_after_output == 1 and not t.english()
    return ok, {"said": t.replies, "english": t.english(), "cleared": t.cleared, "cancelled": t.cancelled}


SCENARIOS = {
    "open": open_wechat,
    "scroll": lambda t: then(t, "scroll"),
    "hello": hello,
    "stop": stop,
    "backchannel": backchannel,
    "start_blip": start_blip,
    "flip": lambda t: then(t, "flip"),
}


async def bridge(root, language):
    """A voice bridge from `root`, and a function that mints one session's client secret from it."""
    state = tempfile.mkdtemp(prefix="voice-eval-")
    proc = await asyncio.create_subprocess_exec("node", os.path.join(root, "bin/voice-bridge.mjs"), "--port", "0", "--host", "127.0.0.1",
                                                env={**os.environ, "POKI_MCP_STATE_DIR": state},
                                                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    port = json.loads(await proc.stdout.readline())["port"]
    with open(os.path.join(state, "voice-bridge.json")) as f:
        secret = json.load(f)["secret"]

    async def mint():
        async with aiohttp.ClientSession() as http:
            async with http.get(f"http://127.0.0.1:{port}/voice/{secret}/token?language={language}") as r:
                body = await r.json()
                if r.status != 200:
                    raise RuntimeError(f"the bridge answered {r.status}: {body.get('error')}")
                return body["value"]
    return proc, mint


async def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--scenario", default="all", choices=["all", *SCENARIOS])
    p.add_argument("--runs", type=int, default=4)
    p.add_argument("--language", default="zh-Hans-CN", help="the iPhone's language")
    p.add_argument("--root", default=ROOT, help="the checkout whose voice bridge mints the sessions")
    p.add_argument("--out", help="write every run's log here as JSON")
    a = p.parse_args()
    if not os.environ.get("OPENAI_API_KEY"):
        sys.exit("Set OPENAI_API_KEY.")
    names = list(SCENARIOS) if a.scenario == "all" else [a.scenario]
    clips = tempfile.mkdtemp(prefix="voice-eval-clips-")
    make_clips(clips)
    proc, mint = await bridge(a.root, a.language)
    report, failed = {}, []
    try:
        for name in names:
            runs = []
            for n in range(a.runs):
                t = Talk(None, clips)
                try:
                    t.secret = await mint()
                    await t.connect()
                    ok, detail = await SCENARIOS[name](t)
                except Exception as error:
                    ok, detail = False, {"error": repr(error)}
                finally:
                    if hasattr(t, "pc"):
                        await t.pc.close()
                runs.append({"ok": ok, **detail, "log": t.log})
                print(f"--- {name} {n + 1}: {'pass' if ok else 'FAIL'}", *t.log, f"    {json.dumps(detail, ensure_ascii=False)}", sep="\n    ", flush=True)
            passed = sum(r["ok"] for r in runs)
            print(f"=== {name}: {passed}/{a.runs}", flush=True)
            report[name] = runs
            if passed < a.runs:
                failed.append(name)
    finally:
        proc.terminate()
        await proc.wait()
    if a.out:
        with open(a.out, "w") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
    print("failed: " + ", ".join(failed) if failed else "all passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    asyncio.run(main())
