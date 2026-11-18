import { useEffect, useRef, useState } from "react";
import {
  api,
  failureKind,
  failureText,
  onProgress,
  type Account,
  type AppInfo,
  type Handoff,
  type PhoneRow,
  type WizardSnapshot,
  type WizardStateId,
} from "../api";
import { ErrorCard, normalizePlatform } from "../ErrorCard";
import { t } from "../i18n";
import { Capsule, Card, Field, Pill, Qr, Steps, Toggle, useInterval, useSteps } from "../ui";

const STEPS = [
  { id: "phone", title: "Phone" },
  { id: "pair", title: "Pairing" },
  { id: "devmode", title: "Developer Mode" },
  { id: "account", title: "Account" },
  { id: "release", title: "Release" },
  { id: "sign", title: "Signing" },
  { id: "install", title: "Install" },
  { id: "pairing_file", title: "Pairing file" },
  { id: "ddi", title: "Developer disk image" },
  { id: "mount", title: "Mounting" },
];

const PROVIDERS = [
  { id: "openai", label: "OpenAI" },
  { id: "anthropic", label: "Anthropic" },
  { id: "gemini", label: "Gemini" },
  { id: "deepseek", label: "DeepSeek" },
  { id: "openrouter", label: "OpenRouter" },
];

function stateSummary(state: WizardStateId): {
  badge: string;
  tone: "" | "ok" | "bad" | "warn";
  heading: string;
  instruction: string;
} {
  switch (state) {
    case "device_disconnected":
      return {
        badge: t("Device not connected"),
        tone: "warn",
        heading: t("Device not connected"),
        instruction: t("Connect your iPhone to this computer with a USB data cable and unlock the screen."),
      };
    case "device_untrusted":
      return {
        badge: t("Device not trusted"),
        tone: "warn",
        heading: t("Device not trusted"),
        instruction: t("Unlock your iPhone, tap Trust on the prompt, and enter your iPhone passcode. Poki Setup continues automatically."),
      };
    case "developer_mode_off":
      return {
        badge: t("Developer Mode is off"),
        tone: "warn",
        heading: t("Developer Mode is off"),
        instruction: t("On your iPhone, open Settings > Privacy & Security > Developer Mode, turn it on and restart. After unlocking, tap Turn On."),
      };
    case "account_signed_out":
      return {
        badge: t("Apple Account not signed in"),
        tone: "warn",
        heading: t("Apple Account not signed in"),
        instruction: t("Sign in with your Apple Account (a free account works) to sign and install Poki."),
      };
    case "ready_to_install":
      return {
        badge: t("Ready to install"),
        tone: "ok",
        heading: t("Ready to install"),
        instruction: t("Click Install Poki below. Poki Setup signs Poki, installs it over USB, and mounts the developer disk image automatically."),
      };
    case "signing_failed":
      return {
        badge: t("Signing failed"),
        tone: "bad",
        heading: t("Signing failed"),
        instruction: t("Sign in with your Apple Account (a free account works) to sign and install Poki."),
      };
    case "install_failed":
      return {
        badge: t("Installation failed"),
        tone: "bad",
        heading: t("Installation failed"),
        instruction: t("Connect your iPhone to this computer with a USB data cable and unlock the screen."),
      };
    case "ddi_unmounted":
      return {
        badge: t("Developer disk image needs restore"),
        tone: "warn",
        heading: t("Developer disk image needs restore"),
        instruction: t("Your iPhone restarted, which clears the developer disk image. Keep the USB cable connected and restore it in one click (no re-signing needed)."),
      };
    case "app_untrusted":
      return {
        badge: t("Trust developer certificate on iPhone"),
        tone: "warn",
        heading: t("Trust developer certificate on iPhone"),
        instruction: t("On your iPhone, open Settings > General > VPN & Device Management, tap your Apple Account under Developer App, and tap Trust."),
      };
    case "poki_not_started":
      return {
        badge: t("Open Poki on your iPhone"),
        tone: "warn",
        heading: t("Open Poki on your iPhone"),
        instruction: t("Tap Poki on your iPhone Home Screen, enable UI Automation when prompted, and enter your iPhone passcode once."),
      };
    case "completed":
      return {
        badge: t("Poki is ready"),
        tone: "ok",
        heading: t("Poki is ready"),
        instruction: t("Poki is installed, the developer disk image is mounted, and no VPN or loopback is needed. You can unplug the USB cable and send your first task in Poki."),
      };
  }
}

export default function Setup({ goAccount }: { goAccount: () => void }) {
  const [appInfo, setAppInfo] = useState<AppInfo | null>(null);
  const [wizard, setWizard] = useState<WizardSnapshot | null>(null);
  const [rows, setRows] = useState<PhoneRow[] | null>(null);
  const [listError, setListError] = useState<{ kind: string; text: string } | null>(null);
  const [account, setAccount] = useState<Account | null>(null);
  const [running, setRunning] = useState(false);
  const [busyAction, setBusyAction] = useState<"" | "pair" | "devmode" | "ddi" | "signin" | "key">("");
  const [actionError, setActionError] = useState<{ kind: string; text: string } | null>(null);
  const [certQuestion, setCertQuestion] = useState(false);
  const [result, setResult] = useState<{ notes: string[]; handoff: Handoff | null; name: string; version: string } | null>(null);
  const { steps, apply, fail, reset } = useSteps(STEPS);
  const [chosen, setChosen] = useState<string | null>(null);
  const [localIpa, setLocalIpa] = useState<string | null>(null);

  const [appleId, setAppleId] = useState("");
  const [applePassword, setApplePassword] = useState("");
  const [keepSignedIn, setKeepSignedIn] = useState(true);
  const [factorCode, setFactorCode] = useState("");

  const [modelProvider, setModelProvider] = useState("openai");
  const [modelSecret, setModelSecret] = useState("");
  const [modelStatus, setModelStatus] = useState<string | null>(null);
  const autoPairedUdid = useRef<string | null>(null);
  const autoRevealedDevmodeUdid = useRef<string | null>(null);

  useEffect(() => {
    api.appInfo().then(setAppInfo).catch(() => {});
  }, []);

  const refresh = () => {
    api
      .wizardState(chosen)
      .then((snap) => {
        setWizard(snap);
        if (snap.usbmuxd_unavailable && snap.failure) {
          setListError({ kind: snap.failure.kind, text: snap.failure.message });
        } else {
          setListError(null);
        }
      })
      .catch((e) => {
        setListError({ kind: failureKind(e), text: failureText(e) });
      });
    api
      .phones()
      .then((r) => {
        setRows(r);
      })
      .catch((e) => {
        setRows([]);
        setListError({ kind: failureKind(e), text: failureText(e) });
      });
    api.account().then(setAccount).catch(() => {});
  };

  useInterval(() => {
    if (running || busyAction !== "") return;
    refresh();
  }, 2500, [running, busyAction, chosen]);

  useEffect(() => {
    const unInstall = onProgress("install", apply);
    const unDdi = onProgress("ddi", apply);
    return () => {
      unInstall.then((f) => f());
      unDdi.then((f) => f());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const selectedUdid = wizard?.selected_udid ?? chosen ?? rows?.find((r) => r.phone.link.kind === "usb")?.phone.udid ?? null;
  const usbPhone =
    wizard?.usb_phones.find((p) => p.udid === selectedUdid) ??
    wizard?.usb_phones[0] ??
    null;
  const phoneRow = rows?.find((r) => r.phone.udid === (usbPhone?.udid ?? selectedUdid)) ?? null;

  useEffect(() => {
    if (!wizard || running || busyAction !== "") return;
    if (wizard.state === "device_untrusted" && usbPhone && autoPairedUdid.current !== usbPhone.udid) {
      autoPairedUdid.current = usbPhone.udid;
      void runPair(usbPhone.udid);
    }
    if (wizard.state === "developer_mode_off" && usbPhone && autoRevealedDevmodeUdid.current !== usbPhone.udid) {
      autoRevealedDevmodeUdid.current = usbPhone.udid;
      void runDevmode(usbPhone.udid);
    }
    if (wizard.state === "device_disconnected") {
      autoPairedUdid.current = null;
      autoRevealedDevmodeUdid.current = null;
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [wizard?.state, usbPhone?.udid]);

  const pickIpa = async () => {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const f = await open({ multiple: false, filters: [{ name: "IPA", extensions: ["ipa"] }] });
    setLocalIpa((f as string | null) ?? null);
  };

  const runPair = async (udid: string) => {
    setBusyAction("pair");
    setActionError(null);
    try {
      await api.pair(udid);
      refresh();
    } catch (e) {
      setActionError({ kind: failureKind(e), text: failureText(e) });
    } finally {
      setBusyAction("");
    }
  };

  const runDevmode = async (udid: string) => {
    setBusyAction("devmode");
    setActionError(null);
    try {
      await api.devmode(udid);
      refresh();
    } catch (e) {
      setActionError({ kind: failureKind(e), text: failureText(e) });
    } finally {
      setBusyAction("");
    }
  };

  const runMountDdi = async (udid: string) => {
    setBusyAction("ddi");
    setActionError(null);
    try {
      await api.mountDdi(udid);
      refresh();
    } catch (e) {
      setActionError({ kind: failureKind(e), text: failureText(e) });
    } finally {
      setBusyAction("");
    }
  };

  const submitSignIn = async (ev: React.FormEvent) => {
    ev.preventDefault();
    if (!appleId.trim() || !applePassword) return;
    setBusyAction("signin");
    setActionError(null);
    try {
      await api.signIn(appleId.trim(), applePassword, keepSignedIn);
      setApplePassword("");
      refresh();
    } catch (e) {
      setActionError({ kind: failureKind(e), text: failureText(e) });
    } finally {
      setBusyAction("");
    }
  };

  const submitFactorCode = async (ev: React.FormEvent) => {
    ev.preventDefault();
    if (factorCode.trim().length !== 6) return;
    setBusyAction("signin");
    setActionError(null);
    try {
      await api.finishSignIn(factorCode.trim());
      setFactorCode("");
      refresh();
    } catch (e) {
      setActionError({ kind: failureKind(e), text: failureText(e) });
    } finally {
      setBusyAction("");
    }
  };

  const queueOrSendModelKey = async (udid: string) => {
    const trimmed = modelSecret.trim();
    if (!trimmed) return;
    setBusyAction("key");
    setActionError(null);
    try {
      const delivery = await api.sendModelKey(udid, modelProvider, trimmed);
      setModelSecret("");
      setModelStatus(
        delivery.sent
          ? t("Model key sealed and delivered to Poki.")
          : t("Model key queued in memory; it will be sealed automatically as soon as you open Poki on the iPhone."),
      );
      refresh();
    } catch (e) {
      setActionError({ kind: failureKind(e), text: failureText(e) });
    } finally {
      setBusyAction("");
    }
  };

  const start = async () => {
    const udid = usbPhone?.udid ?? selectedUdid;
    if (!udid) return;
    setRunning(true);
    setActionError(null);
    setResult(null);
    setCertQuestion(false);
    reset();
    try {
      await api.clearWizardFailure(udid);
      if (modelSecret.trim()) {
        const delivery = await api.sendModelKey(udid, modelProvider, modelSecret.trim());
        setModelSecret("");
        setModelStatus(
          delivery.sent
            ? t("Model key sealed and delivered to Poki.")
            : t("Model key queued in memory; it will be sealed automatically as soon as you open Poki on the iPhone."),
        );
      }
      const r = await api.install(udid, false, localIpa);
      setResult({ notes: r.notes, handoff: r.handoff, name: r.record.phone_name, version: r.record.version });
      refresh();
    } catch (e) {
      const text = failureText(e);
      const kind = failureKind(e);
      fail(text);
      setActionError({ kind, text });
      setCertQuestion(kind === "certificate_limit");
      refresh();
    } finally {
      setRunning(false);
    }
  };

  const platform = normalizePlatform(appInfo?.os);
  const anisetteUrl =
    account?.anisette.kind === "remote" ? account.anisette.url : "https://ani.sidestore.io";

  const currentState: WizardStateId =
    wizard?.state ??
    (!usbPhone && !phoneRow
      ? "device_disconnected"
      : (usbPhone ? !usbPhone.paired : !phoneRow?.facts?.paired_with_this_computer)
        ? "device_untrusted"
        : (usbPhone ? usbPhone.developer_mode === false : phoneRow?.facts?.developer_mode === false)
          ? "developer_mode_off"
          : !account?.signed_in
            ? "account_signed_out"
            : "ready_to_install");

  const summary = stateSummary(currentState);
  const activeFailure =
    wizard?.failure ??
    (listError ? { kind: listError.kind, stage: "usbmuxd" as const, message: listError.text } : null) ??
    (actionError ? { kind: actionError.kind, stage: "install" as const, message: actionError.text } : null);

  return (
    <>
      <div className="hero" style={{ marginBottom: 20 }}>
        <img className="bear" src="/icon.png" alt="" />
        <div>
          <h1>{t("Set up Poki on this iPhone")}</h1>
          <p className="page-sub" style={{ margin: 0 }}>
            {t("Connect the iPhone with a cable to set it up; this works on every iOS version.")}
          </p>
        </div>
      </div>

      <Card className="wizard-card">
        <div className="row between" style={{ marginBottom: 8 }}>
          <span className="muted small">{t("Current step")}</span>
          <span data-testid="wizard-state-pill">
            <Pill tone={summary.tone}>{summary.badge}</Pill>
          </span>
        </div>
        <h2 style={{ marginBottom: 6 }} data-testid="wizard-heading">
          {summary.heading}
        </h2>
        <p style={{ margin: 0 }} data-testid="wizard-instruction">
          {summary.instruction}
        </p>

        {wizard && wizard.usb_phones.length > 1 && (
          <div className="seg" style={{ marginTop: 12 }}>
            {wizard.usb_phones.map((p) => (
              <button
                key={p.udid}
                className={usbPhone?.udid === p.udid ? "on" : ""}
                onClick={() => setChosen(p.udid)}
              >
                {p.name || p.udid.slice(0, 8)}
              </button>
            ))}
          </div>
        )}

        {usbPhone && (
          <>
            <div className="hair" />
            <div className="row between wrap">
              <div className="grow">
                <strong>{usbPhone.name || t("Phone")}</strong>
                <div className="muted small">
                  {usbPhone.product_type} (iOS {usbPhone.ios})
                  {wizard?.installed && !wizard.installed.expired && (
                    <>, {t("Poki is installed.")} {wizard.installed.version}</>
                  )}
                </div>
              </div>
              <Pill tone={usbPhone.paired ? "ok" : "warn"}>
                {t(usbPhone.paired ? "paired" : "not paired")}
              </Pill>
              {usbPhone.developer_mode !== null && (
                <Pill tone={usbPhone.developer_mode ? "ok" : "warn"}>
                  {t("Developer Mode")} {t(usbPhone.developer_mode ? "on" : "off")}
                </Pill>
              )}
            </div>
          </>
        )}

        {currentState === "device_untrusted" && usbPhone && (
          <div style={{ marginTop: 12 }}>
            <Capsule onClick={() => runPair(usbPhone.udid)} disabled={busyAction === "pair"}>
              {busyAction === "pair" ? t("Pairing…") : t("Pair now")}
            </Capsule>
          </div>
        )}

        {currentState === "developer_mode_off" && usbPhone && (
          <div style={{ marginTop: 12 }}>
            <Capsule onClick={() => runDevmode(usbPhone.udid)} disabled={busyAction === "devmode"}>
              {busyAction === "devmode" ? t("Waiting for Developer Mode…") : t("Turn on Developer Mode")}
            </Capsule>
          </div>
        )}

        {currentState === "ddi_unmounted" && usbPhone && (
          <div style={{ marginTop: 12 }}>
            <Capsule onClick={() => runMountDdi(usbPhone.udid)} disabled={busyAction === "ddi"}>
              {busyAction === "ddi" ? t("Restoring…") : t("Restore developer disk image")}
            </Capsule>
          </div>
        )}

        {currentState === "account_signed_out" && (
          <>
            <div className="hair" />
            {account?.pending_factor ? (
              <form className="stack" onSubmit={submitFactorCode}>
                <Field label={t("Verification code")}>
                  <input
                    className="input"
                    inputMode="numeric"
                    maxLength={6}
                    placeholder="123456"
                    value={factorCode}
                    onChange={(ev) => setFactorCode(ev.target.value.replace(/\D/g, "").slice(0, 6))}
                  />
                </Field>
                <div className="row between">
                  <span className="muted small">
                    {t(
                      account.pending_factor === "sms"
                        ? "Apple sent a code by text message."
                        : "Apple sent a code to your devices.",
                    )}
                  </span>
                  <Capsule type="submit" disabled={factorCode.length !== 6 || busyAction === "signin"}>
                    {busyAction === "signin" ? t("Signing in…") : t("Verify & Continue")}
                  </Capsule>
                </div>
              </form>
            ) : (
              <form className="stack" onSubmit={submitSignIn}>
                <div className="grid2">
                  <Field label={t("Apple Account email")}>
                    <input
                      className="input"
                      type="email"
                      placeholder="name@example.com"
                      value={appleId}
                      onChange={(ev) => setAppleId(ev.target.value)}
                    />
                  </Field>
                  <Field label={t("Password")}>
                    <input
                      className="input"
                      type="password"
                      value={applePassword}
                      onChange={(ev) => setApplePassword(ev.target.value)}
                    />
                  </Field>
                </div>
                <div className="row between wrap">
                  <Toggle
                    on={keepSignedIn}
                    onChange={setKeepSignedIn}
                    label={t("Keep me signed in for weekly renewal")}
                  />
                  <div className="row">
                    <Capsule kind="ghost" sm onClick={goAccount}>
                      {t("Apple ID")}
                    </Capsule>
                    <Capsule
                      type="submit"
                      disabled={!appleId.trim() || !applePassword || busyAction === "signin"}
                    >
                      {busyAction === "signin" ? t("Signing in…") : t("Sign in")}
                    </Capsule>
                  </div>
                </div>
              </form>
            )}
          </>
        )}

        {(currentState === "ready_to_install" ||
          currentState === "signing_failed" ||
          currentState === "install_failed") &&
          usbPhone && (
            <>
              <div className="hair" />
              <div className="row between wrap">
                <span className="muted small grow">
                  {account?.name ?? account?.apple_id ?? wizard?.account_apple_id ?? ""}
                  {account?.team_id ? ` (${t("Team")} ${account.team_id})` : ""}
                </span>
                <span className="muted small">
                  {localIpa ? localIpa.split(/[\\/]/).pop() : t("Latest release")}
                </span>
                <Capsule
                  kind="ghost"
                  sm
                  onClick={localIpa ? () => setLocalIpa(null) : pickIpa}
                  disabled={running}
                >
                  {localIpa ? t("Use the latest release") : t("Use an IPA file…")}
                </Capsule>
                <Capsule onClick={start} disabled={running}>
                  {running
                    ? t("Setting up…")
                    : currentState === "signing_failed" || currentState === "install_failed"
                      ? t("Try again")
                      : t("Install Poki")}
                </Capsule>
              </div>
            </>
          )}
      </Card>

      {activeFailure && (
        <Card>
          <ErrorCard
            title={
              activeFailure.kind === "usbmuxd"
                ? t("Apple driver missing")
                : currentState === "signing_failed"
                  ? t("Signing failed")
                  : currentState === "install_failed"
                    ? t("Installation failed")
                    : undefined
            }
            kind={activeFailure.kind}
            message={activeFailure.message}
            platform={platform}
            anisetteServer={anisetteUrl}
            onDismiss={
              activeFailure.kind === "usbmuxd"
                ? undefined
                : () => {
                    setActionError(null);
                    if (usbPhone) void api.clearWizardFailure(usbPhone.udid).then(refresh);
                  }
            }
          />
          {certQuestion && !running && (
            <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
              <Capsule
                kind="danger"
                onClick={async () => {
                  try {
                    await api.approveCertificateReplacement();
                    await start();
                  } catch (e) {
                    setActionError({ kind: failureKind(e), text: failureText(e) });
                  }
                }}
              >
                {t("Replace Certificate")}
              </Capsule>
              <Capsule kind="ghost" onClick={() => setCertQuestion(false)}>
                {t("Cancel")}
              </Capsule>
            </div>
          )}
        </Card>
      )}

      {usbPhone &&
        (currentState === "ready_to_install" ||
          currentState === "app_untrusted" ||
          currentState === "poki_not_started" ||
          currentState === "completed") && (
          <Card>
            <h2>{t("Optional: Model API key")}</h2>
            <p className="muted small" style={{ marginTop: 0, marginBottom: 10 }}>
              {t(
                "Paste an API key to seal it to your iPhone's Secure Enclave over USB. You can also sign in with ChatGPT inside Poki instead.",
              )}
            </p>
            <div className="row wrap">
              <select
                className="input"
                style={{ width: 150 }}
                value={modelProvider}
                onChange={(ev) => setModelProvider(ev.target.value)}
              >
                {PROVIDERS.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.label}
                  </option>
                ))}
              </select>
              <input
                className="input grow"
                type="password"
                placeholder={t("API key (optional)")}
                value={modelSecret}
                onChange={(ev) => setModelSecret(ev.target.value)}
              />
              {currentState !== "ready_to_install" && (
                <Capsule
                  kind="ghost"
                  onClick={() => queueOrSendModelKey(usbPhone.udid)}
                  disabled={!modelSecret.trim() || busyAction === "key"}
                >
                  {busyAction === "key" ? t("Sending…") : t("Send key to Poki")}
                </Capsule>
              )}
            </div>
            {(modelStatus || wizard?.model_key_imported_provider || wizard?.model_key_queued) && (
              <p className="muted small" style={{ marginTop: 8, marginBottom: 0 }}>
                {wizard?.model_key_imported_provider
                  ? `${t("Model key sealed and delivered to Poki.")} (${wizard.model_key_imported_provider})`
                  : modelStatus ??
                    t(
                      "Model key queued in memory; it will be sealed automatically as soon as you open Poki on the iPhone.",
                    )}
              </p>
            )}
          </Card>
        )}

      {(running || steps.some((s) => s.state !== "todo")) && (
        <Card>
          <Steps steps={steps} />
        </Card>
      )}

      {result && (
        <Card white>
          <h2>{t("Done")}</h2>
          <p style={{ margin: "0 0 8px" }}>
            Poki {result.version} ({result.name})
          </p>
          <p style={{ margin: "0 0 6px" }}>
            1. {t("On your iPhone, open Settings > General > VPN & Device Management, tap your Apple Account under Developer App, and tap Trust.")}
          </p>
          <p style={{ margin: 0 }}>
            2. {t("Tap Poki on your iPhone Home Screen, enable UI Automation when prompted, and enter your iPhone passcode once.")}
          </p>
          {result.notes.map((n, i) => (
            <p key={i} className="muted small" style={{ margin: "6px 0 0" }}>
              {n}
            </p>
          ))}
          {result.handoff && (
            <div className="row" style={{ marginTop: 14, alignItems: "flex-start" }}>
              <Qr svg={result.handoff.qr_svg} />
              <div className="grow">
                <p style={{ marginTop: 0 }}>
                  {t("Scan this with the iPhone's Camera (same Wi-Fi). Poki opens and takes the pairing file.")}
                </p>
                <code className="small" style={{ userSelect: "text" }}>
                  {result.handoff.link}
                </code>
              </div>
            </div>
          )}
        </Card>
      )}
    </>
  );
}
