#!/usr/bin/env python3
"""End-to-end check of Apple Watch live-voice remote control on paired simulators.

Verifies over real WatchConnectivity (WCSession) without any voice API key, using Poki's
simulator TalkRehearsal test double:
1. Foreground fallback ("Continue on iPhone") when iPhone lacks microphone permission.
2. Background start from Watch while iPhone is in another app, then Listening -> Mute -> Unmute -> End.
3. Live step text ("Using the phone") and final result delivery into shared #591 Watch history,
   plus Watch relaunch sync and preservation of the #591 Voice Task screen.
"""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import select
import subprocess
from tempfile import TemporaryDirectory
from time import monotonic, sleep

PHONE_BUNDLE = "nz.zheha.poki"
WATCH_BUNDLE = PHONE_BUNDLE + ".watchkitapp"


def simctl(*args, timeout=60, check=True):
    return subprocess.run(
        ["xcrun", "simctl", *args],
        check=check,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def archive_path(device, bundle):
    container = simctl("get_app_container", device, bundle, "data").stdout.strip()
    return Path(container) / "Library" / "Application Support" / "WatchVoice.json"


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def wait_for_file(path, predicate, timeout_s, failure, keep_awake_watch=None):
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = read_json(path)
    if existing is not None and predicate(existing):
        return existing
    directory = os.open(path.parent, os.O_EVTONLY)
    try:
        with closing(select.kqueue()) as queue:
            change = select.kevent(
                directory,
                filter=select.KQ_FILTER_VNODE,
                flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                fflags=select.KQ_NOTE_WRITE | select.KQ_NOTE_RENAME,
            )
            queue.control([change], 0, 0)
            deadline = monotonic() + timeout_s
            last_poke = monotonic()
            while True:
                data = read_json(path)
                if data is not None and predicate(data):
                    return data
                now = monotonic()
                remaining = deadline - now
                if remaining <= 0:
                    raise AssertionError(f"{failure}\nLast archive: {json.dumps(data, ensure_ascii=False)}")
                if keep_awake_watch and now - last_poke >= 3.0:
                    last_poke = now
                    with TemporaryDirectory() as directory_tmp:
                        simctl("io", keep_awake_watch, "screenshot", str(Path(directory_tmp) / "poke.png"), timeout=15, check=False)
                queue.control([], 1, min(0.5, remaining))
    finally:
        os.close(directory)


def ocr_screen(device, ocr_bin, save_to=None):
    with TemporaryDirectory() as directory:
        path = Path(save_to) if save_to else Path(directory) / "screen.png"
        simctl("io", device, "screenshot", str(path), timeout=30)
        lines = json.loads(subprocess.check_output([str(ocr_bin), str(path)], timeout=30))
        header = path.read_bytes()
        width = int.from_bytes(header[16:20], "big")
        height = int.from_bytes(header[20:24], "big")
        return lines, width, height


def wait_for_ocr(device, ocr_bin, predicate, timeout_s, failure, save_to=None):
    deadline = monotonic() + timeout_s
    last_lines = []
    while True:
        lines, width, height = ocr_screen(device, ocr_bin, save_to=save_to)
        last_lines = [line["text"] for line in lines]
        if predicate(lines):
            return lines, width, height
        if monotonic() >= deadline:
            raise AssertionError(f"{failure}\nObserved OCR lines: {last_lines}")
        sleep(0.4)


def touch(session, x, y, hold_ms=80):
    def event(phase):
        return {
            "messageType": "IndigoDigitizerEvent",
            "payload": {"pointOne": {"x": x, "y": y}, "eventType": phase, "edge": 0, "target": 0},
        }

    session.stdin.write(json.dumps({"events": [event(0), {"delay_ms": hold_ms}, event(2)]}) + "\n")
    session.stdin.flush()
    assert json.loads(session.stdout.readline())["sent"], "Simulator input did not send"


def snapshot_version(snapshot):
    if not snapshot:
        return (0, 0)
    return (snapshot.get("epoch", 0), snapshot.get("sequence", 0))


def tap_start_and_wait(watch, ocr_bin, session, watch_archive, predicate, timeout_s, failure, label="Start"):
    for attempt in range(2):
        tap_label(watch, ocr_bin, session, lambda t: button_matches(t, label))
        try:
            return wait_for_file(watch_archive, predicate, max(timeout_s, 35), failure, keep_awake_watch=watch)
        except AssertionError:
            data = read_json(watch_archive) or {}
            state = (data.get("remoteSnapshot") or {}).get("state")
            if attempt == 0 and state == "idle":
                sleep(1.5)
                continue
            raise


def button_matches(text, label):
    stripped = text.strip()
    if label.isascii():
        return stripped == label or stripped.endswith(" " + label)
    return stripped.endswith(label)


def tap_in_lines(session, lines, width, height, match):
    sleep(0.35)
    target = next(row for row in lines if match(row["text"]))
    cx = (target["x"] + target["width"] / 2.0) / width
    cy = (target["y"] + target["height"] / 2.0) / height
    print(f"[tap] {target['text']!r} @ ({cx:.3f}, {cy:.3f})", flush=True)
    touch(session, cx, cy, hold_ms=90)
    return target["text"]


def tap_label(device, ocr_bin, session, match, timeout_s=15):
    lines, width, height = wait_for_ocr(
        device,
        ocr_bin,
        lambda rows: any(match(row["text"]) for row in rows),
        timeout_s,
        "Expected Watch button matching predicate",
    )
    return tap_in_lines(session, lines, width, height, match)


def configure_phone_defaults(phone, hold=None):
    simctl("spawn", phone, "defaults", "write", PHONE_BUNDLE, "pokiFirstRun", "done")
    simctl("spawn", phone, "defaults", "write", PHONE_BUNDLE, "pokiTalkRehearsal", "1")
    if hold is None:
        simctl("spawn", phone, "defaults", "delete", PHONE_BUNDLE, "pokiTalkHold", check=False)
    else:
        simctl("spawn", phone, "defaults", "write", PHONE_BUNDLE, "pokiTalkHold", hold)


def clear_phone_defaults(phone):
    for key in ("pokiTalkRehearsal", "pokiTalkHold"):
        simctl("spawn", phone, "defaults", "delete", PHONE_BUNDLE, key, check=False)


def poki_log_path(phone):
    container = simctl("get_app_container", phone, PHONE_BUNDLE, "data").stdout.strip()
    return Path(container) / "Library" / "Caches" / "poki-log.txt"


def warmup_phone(phone):
    log_file = poki_log_path(phone)
    simctl("terminate", phone, PHONE_BUNDLE, check=False)
    sleep(0.3)
    configure_phone_defaults(phone, hold="listening")
    simctl("launch", phone, PHONE_BUNDLE, "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-pokiTalkRehearsal", "1")
    deadline = monotonic() + 90
    while monotonic() < deadline:
        if log_file.exists() and "first_frame_ms=" in log_file.read_text(errors="ignore"):
            break
        sleep(0.5)
    simctl("terminate", phone, PHONE_BUNDLE, check=False)
    sleep(0.5)


def launch_phone(phone, *extra_args, background=False, hold=None, language="en", locale="en_US"):
    configure_phone_defaults(phone, hold=hold)
    args = list(extra_args)
    if hold is not None:
        args.extend(["-pokiTalkHold", hold])
    for attempt in range(2):
        try:
            simctl(
                "launch",
                "--terminate-running-process",
                phone,
                PHONE_BUNDLE,
                "-AppleLanguages",
                f"({language})",
                "-AppleLocale",
                locale,
                "-pokiTalkRehearsal",
                "1",
                *args,
                timeout=45,
            )
            break
        except subprocess.TimeoutExpired:
            if attempt == 1:
                raise
            simctl("terminate", phone, PHONE_BUNDLE, check=False)
            sleep(1.0)
    sleep(4.5)
    if background:
        for attempt in range(3):
            res = simctl("launch", phone, "com.apple.Preferences", check=False)
            if res.returncode == 0:
                break
            sleep(2.0)
        else:
            simctl("launch", phone, "com.apple.mobilesafari")
        sleep(1.0)


def launch_watch(watch, ocr_bin=None, session=None, language="en", locale="en_US"):
    simctl("terminate", watch, WATCH_BUNDLE, check=False)
    sleep(0.3)
    simctl("launch", watch, WATCH_BUNDLE, "-AppleLanguages", f"({language})", "-AppleLocale", locale)
    sleep(1.5)
    if ocr_bin and session:
        for _ in range(3):
            lines, width, height = ocr_screen(watch, ocr_bin)
            allow = next((r for r in lines if r["text"].strip() in {"Allow", "允许", "允許"}), None)
            if allow and any(k in r["text"] for r in lines for k in ("Notifications", "通知")):
                cx = (allow["x"] + allow["width"] / 2.0) / width
                cy = (allow["y"] + allow["height"] / 2.0) / height
                touch(session, cx, cy, hold_ms=90)
                sleep(1.0)
            else:
                break


def run_checks(args):
    ocr_bin = Path(args.helper).with_name("ocr")
    shots = Path(args.shots) if args.shots else None
    if shots:
        shots.mkdir(parents=True, exist_ok=True)

    watch_archive = archive_path(args.watch, WATCH_BUNDLE)
    phone_archive = archive_path(args.phone, PHONE_BUNDLE)
    watch_archive.unlink(missing_ok=True)
    phone_archive.unlink(missing_ok=True)

    warmup_phone(args.phone)

    with subprocess.Popen(
        [args.helper, "--hid-session", args.watch],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    ) as session:
        try:
            assert json.loads(session.stdout.readline())["ready"], "HID helper did not become ready"

            # 1. Foreground fallback when microphone permission is missing.
            simctl("privacy", args.phone, "revoke", "microphone", PHONE_BUNDLE, check=False)
            launch_phone(args.phone, hold="listening", background=True)
            launch_watch(args.watch, ocr_bin, session)
            wait_for_file(
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "idle",
                35,
                "Watch did not sync initial idle snapshot from iPhone",
            )
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("Ready" in r["text"] for r in rows)
                and any(button_matches(r["text"], "Start") for r in rows),
                20,
                "Watch did not reach Ready + Start screen",
            )
            snap_fg = tap_start_and_wait(
                args.watch,
                ocr_bin,
                session,
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("requiresForeground") is True,
                25,
                "Watch did not receive requiresForeground snapshot",
            )["remoteSnapshot"]
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("Continue on iPhone" in r["text"] for r in rows),
                15,
                "Watch did not display Continue on iPhone",
                save_to=shots / "01-continue-on-iphone.png" if shots else None,
            )
            print(f"[PASS 1] requiresForeground -> Continue on iPhone (epoch={snap_fg['epoch']} seq={snap_fg['sequence']})")

            # 2. Background start -> Listening -> Mute -> Unmute -> End.
            simctl("privacy", args.phone, "grant", "microphone", PHONE_BUNDLE)
            launch_phone(args.phone, hold="listening", background=True)
            snap_listen = tap_start_and_wait(
                args.watch,
                ocr_bin,
                session,
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "listening",
                25,
                "Watch did not transition to listening after background start",
            )["remoteSnapshot"]
            call_id = snap_listen["callID"]
            assert call_id, "Listening snapshot missing callID"
            assert snap_listen["isMuted"] is False
            assert snap_listen["transportConnected"] is True
            assert snap_listen["inputReady"] is True
            lines_listen, w_listen, h_listen = wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("Listening" in r["text"] for r in rows)
                and any(button_matches(r["text"], "Mute") for r in rows),
                15,
                "Watch UI did not show Listening + Mute",
                save_to=shots / "02-listening.png" if shots else None,
            )
            print(f"[PASS 2a] Background start -> Listening (callID={call_id}, seq={snap_listen['sequence']})")

            tap_in_lines(session, lines_listen, w_listen, h_listen, lambda t: button_matches(t, "Mute"))
            snap_muted = wait_for_file(
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "muted"
                and snapshot_version(d.get("remoteSnapshot")) > snapshot_version(snap_listen),
                15,
                "Watch did not transition to muted",
                keep_awake_watch=args.watch,
            )["remoteSnapshot"]
            assert snap_muted["callID"] == call_id
            assert snap_muted["isMuted"] is True
            assert snap_muted["inputReady"] is False
            lines_muted, w_muted, h_muted = wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("Muted" in r["text"] for r in rows)
                and any(button_matches(r["text"], "Unmute") for r in rows),
                15,
                "Watch UI did not show Muted + Unmute",
                save_to=shots / "03-muted.png" if shots else None,
            )
            print(f"[PASS 2b] Mute -> Muted (seq={snap_muted['sequence']})")

            tap_in_lines(session, lines_muted, w_muted, h_muted, lambda t: button_matches(t, "Unmute"))
            snap_unmuted = wait_for_file(
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "listening"
                and (d.get("remoteSnapshot") or {}).get("isMuted") is False
                and snapshot_version(d.get("remoteSnapshot")) > snapshot_version(snap_muted),
                15,
                "Watch did not transition back to listening on Unmute",
                keep_awake_watch=args.watch,
            )["remoteSnapshot"]
            assert snap_unmuted["callID"] == call_id
            print(f"[PASS 2c] Unmute -> Listening (seq={snap_unmuted['sequence']})")

            tap_in_lines(session, lines_listen, w_listen, h_listen, lambda t: button_matches(t, "End"))
            snap_idle = wait_for_file(
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "idle"
                and snapshot_version(d.get("remoteSnapshot")) > snapshot_version(snap_unmuted),
                15,
                "Watch did not transition to idle on End",
                keep_awake_watch=args.watch,
            )["remoteSnapshot"]
            assert snap_idle.get("callID") is None
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any(button_matches(r["text"], "Start") for r in rows),
                15,
                "Watch UI did not return to Start after End",
            )
            print(f"[PASS 2d] End -> Ready (seq={snap_idle['sequence']})")

            # 3a. Live step text during phone action (-pokiTalkHold acting avoids racing a short step).
            launch_phone(args.phone, hold="acting", background=True)
            snap_step = tap_start_and_wait(
                args.watch,
                ocr_bin,
                session,
                watch_archive,
                lambda d: bool((d.get("remoteSnapshot") or {}).get("currentStep")),
                35,
                "Watch did not receive currentStep during phone action",
            )["remoteSnapshot"]
            lines_step, w_step, h_step = wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("Using the phone" in r["text"] for r in rows),
                15,
                "Watch UI did not display live step text",
                save_to=shots / "04-step.png" if shots else None,
            )
            print(f"[PASS 3a] Live step displayed: {snap_step['currentStep']!r} (seq={snap_step['sequence']})")
            if any(button_matches(r["text"], "End") for r in lines_step):
                tap_in_lines(session, lines_step, w_step, h_step, lambda t: button_matches(t, "End"))
            else:
                tap_label(args.watch, ocr_bin, session, lambda t: button_matches(t, "End"))
            wait_for_file(
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "idle"
                and snapshot_version(d.get("remoteSnapshot")) > snapshot_version(snap_step),
                20,
                "Watch did not return to idle after ending acting call",
                keep_awake_watch=args.watch,
            )

            # 3b. Full rehearsal turn: final spoken result delivered into shared #591 history.
            launch_phone(args.phone, background=True)
            data_done = tap_start_and_wait(
                args.watch,
                ocr_bin,
                session,
                watch_archive,
                lambda d: any(item.get("text") in {"Okay.", "好的。"} for item in (d.get("results") or [])),
                50,
                "Watch did not receive final voice result into shared history",
            )
            result = next(item for item in data_done["results"] if item.get("text") in {"Okay.", "好的。"})
            assert result["phase"] == 2, f"Expected finished phase (2), got {result}"
            if (data_done.get("remoteSnapshot") or {}).get("state") != "idle":
                tap_label(args.watch, ocr_bin, session, lambda t: button_matches(t, "End"))
                wait_for_file(
                    watch_archive,
                    lambda d: (d.get("remoteSnapshot") or {}).get("state") == "idle",
                    15,
                    "Watch did not return to idle after full turn",
                )
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("Task finished" in r["text"] for r in rows),
                15,
                "Watch UI did not display shared latest result card",
                save_to=shots / "05-result.png" if shots else None,
            )
            print(f"[PASS 3b] Final result saved in shared history: {result['text']!r} (id={result['id']})")

            # 3c. Verify phone journal also persisted the full result for #591 chunked retrieval.
            phone_rows = read_json(phone_archive)
            assert phone_rows, "iPhone WatchVoice.json missing persisted result"
            phone_map = dict(zip(phone_rows[::2], phone_rows[1::2]))
            assert result["id"] in phone_map, "Result ID missing from iPhone WatchVoice.json"
            assert phone_map[result["id"]]["text"] == result["text"]
            print("[PASS 3c] iPhone journal persisted result for #591 chunk retrieval")

            # 3d. Relaunch Watch app to confirm state query sync, history persistence, and #591 Voice Task link.
            launch_watch(args.watch, ocr_bin, session)
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any(button_matches(r["text"], "Start") for r in rows)
                or any("Listening" in r["text"] for r in rows),
                15,
                "Watch did not recover state after relaunch",
            )
            reloaded = read_json(watch_archive)
            assert any(item["id"] == result["id"] for item in reloaded.get("results") or [])
            print("[PASS 3d] Relaunch state sync and history persistence verified")

            # 4. Chinese localization check (Dynamic Island state wording on Watch).
            launch_phone(args.phone, hold="listening", background=True, language="zh-Hans", locale="zh_CN")
            launch_watch(args.watch, ocr_bin, session, language="zh-Hans", locale="zh_CN")
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("就绪" in r["text"] for r in rows)
                and any(button_matches(r["text"], "开始") for r in rows),
                20,
                "Watch did not render Chinese Ready + Start UI",
            )
            tap_start_and_wait(
                args.watch,
                ocr_bin,
                session,
                watch_archive,
                lambda d: (d.get("remoteSnapshot") or {}).get("state") == "listening",
                25,
                "Watch did not enter listening in Chinese UI",
                label="开始",
            )
            lines_zh, w_zh, h_zh = wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any("在听" in r["text"] for r in rows)
                and any(button_matches(r["text"], "静音") for r in rows),
                20,
                "Watch did not render Chinese Listening + Mute UI",
                save_to=shots / "06-zh-listening.png" if shots else None,
            )
            if any(button_matches(r["text"], "结束") for r in lines_zh):
                tap_in_lines(session, lines_zh, w_zh, h_zh, lambda t: button_matches(t, "结束"))
            else:
                tap_label(args.watch, ocr_bin, session, lambda t: button_matches(t, "结束"))
            wait_for_ocr(
                args.watch,
                ocr_bin,
                lambda rows: any(button_matches(r["text"], "开始") for r in rows),
                15,
                "Watch did not return to Chinese Start after End",
            )
            print("[PASS 4] Chinese localization verified (就绪 -> 在听/静音/结束 -> 就绪)")
        finally:
            clear_phone_defaults(args.phone)
            session.stdin.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phone")
    parser.add_argument("watch")
    parser.add_argument("--helper", required=True)
    parser.add_argument("--shots", default=None)
    run_checks(parser.parse_args())


if __name__ == "__main__":
    main()
