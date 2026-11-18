// A stand-in for Tauri's bridge so the page can be looked at in a plain browser (VITE_MOCK=1).
// Nothing here ships: main.tsx imports it only in that mode.
const params = new URLSearchParams(location.search);
const os = params.get("os") ?? "windows";
const scenario = params.get("scenario") ?? "ready";
const langParam = params.get("lang");
if (langParam === "en" || langParam === "zh-Hans") {
  localStorage.setItem("lang", langParam);
  document.documentElement.dataset.lang = langParam;
}

const now = Math.floor(Date.now() / 1000);
const facts = {
  udid: "00008150-000829EA2183C01C",
  name: "iPhone",
  product_type: "iPhone18,1",
  ios: "27.0",
  build: "23B81",
  developer_mode: scenario !== "devmode_off",
  paired_with_this_computer: scenario !== "untrusted",
  can_pair_on_device: true,
  wifi_address: "192.168.1.23",
};
const record = {
  udid: facts.udid,
  phone_name: facts.name,
  ios: "27.0",
  apple_id: "user@example.com",
  team_id: "ABCDE12345",
  team_name: "Personal Team",
  team_is_free: true,
  bundle_id: "nz.zheha.poki.ABCDE12345",
  version: "0.4.4",
  build: "1683",
  release_tag: "app-0.4.4-beta.1",
  signed_at: now - 300,
  profile_expires_at: now + 86400 * 7,
  last_error: null,
  pairing_handed_off: true,
};

function buildWizardSnapshot() {
  const usbPhone = {
    udid: facts.udid,
    name: facts.name,
    product_type: facts.product_type,
    ios: facts.ios,
    paired: facts.paired_with_this_computer,
    developer_mode: facts.paired_with_this_computer ? facts.developer_mode : null,
  };
  const usbmuxdMissingMsg =
    os === "windows"
      ? "Poki Setup cannot reach the iPhone service. Install Apple Devices from the Microsoft Store (or iTunes from apple.com), then plug the iPhone in again."
      : "Poki Setup cannot reach usbmuxd, which macOS starts when an iPhone is plugged in. Plug the iPhone in with a data cable and unlock it.";

  if (scenario === "usbmuxd_missing") {
    return {
      state: "device_disconnected",
      usbmuxd_unavailable: true,
      usb_phones: [],
      selected_udid: null,
      account_signed_in: false,
      account_apple_id: null,
      installed: null,
      ddi_mounted: false,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: { kind: "usbmuxd", stage: "usbmuxd", message: usbmuxdMissingMsg },
    };
  }
  if (scenario === "disconnected") {
    return {
      state: "device_disconnected",
      usbmuxd_unavailable: false,
      usb_phones: [],
      selected_udid: null,
      account_signed_in: false,
      account_apple_id: null,
      installed: null,
      ddi_mounted: false,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "untrusted") {
    return {
      state: "device_untrusted",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: false,
      account_apple_id: null,
      installed: null,
      ddi_mounted: false,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "devmode_off") {
    return {
      state: "developer_mode_off",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: false,
      account_apple_id: null,
      installed: null,
      ddi_mounted: false,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "signed_out") {
    return {
      state: "account_signed_out",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: false,
      account_apple_id: null,
      installed: null,
      ddi_mounted: false,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "ddi_unmounted") {
    return {
      state: "ddi_unmounted",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: true,
      account_apple_id: record.apple_id,
      installed: { bundle_id: record.bundle_id, version: record.version, build: record.build, profile_validated: true, team_is_free: true, expires_at: record.profile_expires_at, expired: false },
      ddi_mounted: false,
      poki_started: true,
      poki_accepts_model_key: true,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "app_untrusted") {
    return {
      state: "app_untrusted",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: true,
      account_apple_id: record.apple_id,
      installed: { bundle_id: record.bundle_id, version: record.version, build: record.build, profile_validated: false, team_is_free: true, expires_at: record.profile_expires_at, expired: false },
      ddi_mounted: true,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: false,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "poki_not_started") {
    return {
      state: "poki_not_started",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: true,
      account_apple_id: record.apple_id,
      installed: { bundle_id: record.bundle_id, version: record.version, build: record.build, profile_validated: true, team_is_free: true, expires_at: record.profile_expires_at, expired: false },
      ddi_mounted: true,
      poki_started: false,
      poki_accepts_model_key: false,
      model_key_queued: true,
      model_key_imported_provider: null,
      failure: null,
    };
  }
  if (scenario === "completed") {
    return {
      state: "completed",
      usbmuxd_unavailable: false,
      usb_phones: [usbPhone],
      selected_udid: usbPhone.udid,
      account_signed_in: true,
      account_apple_id: record.apple_id,
      installed: { bundle_id: record.bundle_id, version: record.version, build: record.build, profile_validated: true, team_is_free: true, expires_at: record.profile_expires_at, expired: false },
      ddi_mounted: true,
      poki_started: true,
      poki_accepts_model_key: true,
      model_key_queued: false,
      model_key_imported_provider: "openai",
      failure: null,
    };
  }
  return {
    state: "ready_to_install",
    usbmuxd_unavailable: false,
    usb_phones: [usbPhone],
    selected_udid: usbPhone.udid,
    account_signed_in: true,
    account_apple_id: record.apple_id,
    installed: null,
    ddi_mounted: false,
    poki_started: false,
    poki_accepts_model_key: false,
    model_key_queued: false,
    model_key_imported_provider: null,
    failure: null,
  };
}

const answers: Record<string, unknown> = {
  app_info: { version: "0.2.4", os, arch: "x86_64", data_dir: "~/Library/Application Support/nz.zheha.poki-setup", can_use_system_anisette: os === "macos" },
  wizard_state: buildWizardSnapshot(),
  phones:
    scenario === "usbmuxd_missing" || scenario === "disconnected"
      ? []
      : [{ phone: { udid: facts.udid, link: { kind: "usb" } }, facts, error: null, record: scenario === "ready" ? null : record }],
  account: {
    signed_in: scenario !== "signed_out" && scenario !== "usbmuxd_missing",
    apple_id: "user@example.com",
    name: "Personal Team",
    team_id: "ABCDE12345",
    password_kept: true,
    anisette: os === "macos" ? { kind: "system" } : { kind: "remote", url: "https://ani.sidestore.io" },
    pending_factor: null,
  },
  teams: [{ team_id: "ABCDE12345", name: "Personal Team", kind: "Individual", is_free: true }],
  records: [record],
  send_model_key: { sent: scenario === "completed", queued: scenario !== "completed" },
  clear_wizard_failure: null,
  relay_state: null,
  connectors: [],
  connector_snippets: [],
  agent_prompt: "You are setting up Poki on my iPhone with Poki Setup's command line tool.",
  check_update: { current: "0.2.4-1683", latest: "0.2.4-1683", url: null, newer: false, source: "r2", source_notice: null, channel: "beta" },
  install_update: { path: "", relaunching: false },
  channels: [
    { id: "stable", title: "Stable", selected: false, latest: null },
    { id: "beta", title: "Beta", selected: true, latest: { tag: "app-0.4.4-beta.1", version: "0.4.4", build: "1683", published_at: "", ipa_name: "Poki-external-0.4.4-1683.ipa", source: "r2", source_notice: null, channel: "beta" } },
  ],
  qr_svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#fff"/></svg>',
};

(window as unknown as { __TAURI_INTERNALS__: unknown }).__TAURI_INTERNALS__ = {
  invoke: async (cmd: string) => {
    if (scenario === "usbmuxd_missing" && cmd === "phones") {
      throw {
        kind: "usbmuxd",
        message:
          "Poki Setup cannot reach the iPhone service. Install Apple Devices from the Microsoft Store (or iTunes from apple.com), then plug the iPhone in again.",
      };
    }
    return cmd.startsWith("plugin:") ? 1 : (answers[cmd] ?? null);
  },
  transformCallback: () => Math.floor(Math.random() * 1e9),
  metadata: { currentWindow: { label: "main" }, currentWebview: { label: "main" } },
  convertFileSrc: (p: string) => p,
};
export {};
