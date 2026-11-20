//! Stateless USB setup wizard state machine.
use crate::{Error, Progress, Reporter, Result, device, keeper};
use std::sync::{Arc, atomic::{AtomicBool, Ordering}};
use serde::{Deserialize, Serialize};
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WizardState {
    DeviceDisconnected,
    DeviceUntrusted,
    DeveloperModeOff,
    AccountSignedOut,
    ReadyToInstall,
    SigningFailed,
    InstallFailed,
    DdiUnmounted,
    AppUntrusted,
    PokiNotStarted,
    AutomationPending,
    Completed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FailureStage {
    Sign,
    Install,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WizardFailure {
    pub kind: String,
    pub stage: FailureStage,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UsbPhoneView {
    pub udid: String,
    pub name: String,
    pub product_type: String,
    pub ios: String,
    pub paired: bool,
    pub developer_mode: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InstalledPokiView {
    pub bundle_id: String,
    pub version: String,
    pub build: String,
    pub profile_validated: Option<bool>,
    pub team_is_free: bool,
    pub expires_at: Option<i64>,
    pub expired: bool,
}

#[derive(Debug, Clone, Default)]
pub struct WizardProbe {
    pub phone: Option<UsbPhoneView>,
    pub account_signed_in: bool,
    pub installed: Option<InstalledPokiView>,
    pub ddi_mounted: bool,
    pub poki_started: bool,
    pub automation_ready: bool,
    pub failure: Option<WizardFailure>,
}

pub fn evaluate(probe: &WizardProbe) -> WizardState {
    let Some(phone) = &probe.phone else { return WizardState::DeviceDisconnected };
    if !phone.paired { return WizardState::DeviceUntrusted; }
    if phone.developer_mode == Some(false) { return WizardState::DeveloperModeOff; }
    if let Some(app) = probe.installed.as_ref().filter(|app| !app.expired) {
        if !probe.ddi_mounted { return WizardState::DdiUnmounted; }
        if probe.poki_started {
            return if probe.automation_ready { WizardState::Completed } else { WizardState::AutomationPending };
        }
        if app.profile_validated == Some(false) || (app.profile_validated.is_none() && app.team_is_free) {
            return WizardState::AppUntrusted;
        }
        return WizardState::PokiNotStarted;
    }
    if !probe.account_signed_in { return WizardState::AccountSignedOut; }
    match probe.failure.as_ref().map(|failure| failure.stage) {
        Some(FailureStage::Sign) => WizardState::SigningFailed,
        Some(FailureStage::Install) => WizardState::InstallFailed,
        _ => WizardState::ReadyToInstall,
    }
}

#[derive(Debug, Serialize)]
pub struct Snapshot {
    pub state: WizardState,
    pub usb_phones: Vec<UsbPhoneView>,
    pub selected_udid: Option<String>,
    pub installed: Option<InstalledPokiView>,
    pub failure: Option<WizardFailure>,
}

#[derive(Default)]
pub struct Attempts(tokio::sync::Mutex<Option<(String, WizardFailure)>>);

impl Attempts {
    pub async fn remember(&self, udid: String, stage: FailureStage, kind: &str, message: &str) {
        *self.0.lock().await = Some((udid, WizardFailure { stage, kind: kind.to_owned(), message: message.to_owned() }));
    }

    pub async fn clear(&self) { *self.0.lock().await = None; }

    pub async fn inspect(&self, udid: Option<&str>, account_signed_in: bool) -> Result<Snapshot> {
        let failure = self.0.lock().await.clone();
        inspect(udid, account_signed_in, failure).await
    }
}

pub fn install_reporter(reporter: Reporter) -> (Reporter, impl Fn() -> FailureStage) {
    let installing = Arc::new(AtomicBool::new(false));
    let flag = installing.clone();
    let reporter = Reporter::new(move |progress| {
        if let Progress::Step { id, .. } = &progress
            && matches!(id.as_str(), "install" | "profiles" | "pairing_file" | "ddi" | "mount")
        {
            flag.store(true, Ordering::Relaxed);
        }
        reporter.emit(progress);
    });
    (reporter, move || if installing.load(Ordering::Relaxed) { FailureStage::Install } else { FailureStage::Sign })
}

pub async fn usb_phone(udid: &str) -> Result<device::Phone> {
    device::Phone::list().await?.into_iter().find(|phone| phone.is_usb() && phone.udid == udid)
        .ok_or_else(|| Error::device("Connect that iPhone with a USB cable and unlock it."))
}

#[derive(Deserialize)]
struct Hello {
    schema: String,
    version: String,
    build: String,
    at: String,
    #[serde(default)]
    ui_automation_ready: bool,
}

impl Hello {
    fn matches(&self, app: &InstalledPokiView, signed_at: Option<i64>) -> bool {
        self.schema == "poki.hello/1" && self.version == app.version && self.build == app.build
            && signed_at.is_none_or(|signed| {
                use time::{OffsetDateTime, format_description::well_known::Rfc3339};
                OffsetDateTime::parse(&self.at, &Rfc3339).is_ok_and(|at| at.unix_timestamp() >= signed)
            })
    }
}

/// Read the device's state anew. A saved signing record is metadata for an app that still exists.
async fn inspect(udid: Option<&str>, account_signed_in: bool, failure: Option<(String, WizardFailure)>) -> Result<Snapshot> {
    let phones: Vec<_> = device::Phone::list().await?.into_iter().filter(device::Phone::is_usb).collect();
    let selected = udid.and_then(|udid| phones.iter().find(|phone| phone.udid == udid))
        .or_else(|| phones.first());
    let failure = failure.filter(|(udid, _)| selected.is_some_and(|p| p.udid == *udid)).map(|(_, failure)| failure);
    let mut probe = WizardProbe { account_signed_in, failure, ..Default::default() };
    let mut usb_phones = Vec::with_capacity(phones.len());
    for phone in &phones {
        let facts = tokio::time::timeout(Duration::from_secs(3), device::info::read(phone)).await.ok().and_then(Result::ok);
        let view = UsbPhoneView {
            udid: phone.udid.clone(),
            name: facts.as_ref().map(|f| f.name.clone()).unwrap_or_default(),
            product_type: facts.as_ref().map(|f| f.product_type.clone()).unwrap_or_default(),
            ios: facts.as_ref().map(|f| f.ios.clone()).unwrap_or_default(),
            paired: facts.as_ref().is_some_and(|f| f.paired_with_this_computer),
            developer_mode: facts.and_then(|f| f.developer_mode),
        };
        if selected.is_some_and(|selected| selected.udid == phone.udid) {
            probe.phone = Some(view.clone());
        }
        usb_phones.push(view);
    }
    if let Some(phone) = selected.filter(|_| probe.phone.as_ref().is_some_and(|p| p.paired && p.developer_mode != Some(false))) {
        let record = keeper::get(&phone.udid)?;
        let apps = tokio::time::timeout(Duration::from_secs(8), device::install::find_apps(phone, crate::POKI_BUNDLE_ID))
            .await.map_err(|_| Error::device("Unlock the iPhone to check whether Poki is installed."))??;
        let app = record.as_ref().and_then(|r| apps.iter().find(|app| app.bundle_id == r.bundle_id)).or_else(|| apps.first());
        if let Some(app) = app {
            let record = record.as_ref().filter(|r| r.bundle_id == app.bundle_id && r.build == app.build);
            let installed = InstalledPokiView {
                bundle_id: app.bundle_id.clone(),
                version: app.version.clone(),
                build: app.build.clone(),
                profile_validated: app.profile_validated,
                team_is_free: record.is_none_or(|r| r.team_is_free),
                expires_at: record.map(|r| r.profile_expires_at),
                expired: record.is_some_and(|r| r.is_expired()),
            };
            if !installed.expired {
                probe.ddi_mounted = device::ddi::mounted(phone).await?;
                if probe.ddi_mounted {
                    let path = "Documents/PokiSetup/poki-hello.json";
                    let hello = tokio::time::timeout(Duration::from_secs(4), device::container::read_file(phone, &app.bundle_id, path)).await
                        .ok().and_then(Result::ok).and_then(|data| serde_json::from_slice::<Hello>(&data).ok());
                    if let Some(hello) = hello.filter(|hello| hello.matches(&installed, record.map(|r| r.signed_at))) {
                        probe.poki_started = true;
                        probe.automation_ready = hello.ui_automation_ready;
                    }
                }
            }
            probe.installed = Some(installed);
        }
    }
    Ok(Snapshot {
        state: evaluate(&probe),
        usb_phones,
        selected_udid: selected.map(|phone| phone.udid.clone()),
        installed: probe.installed,
        failure: probe.failure,
    })
}

pub async fn pair(udid: &str, reporter: &Reporter) -> Result<()> {
    device::pairing::pair(&usb_phone(udid).await?, reporter, Duration::from_secs(90)).await.map(|_| ())
}

pub async fn reveal_developer_mode(udid: &str) -> Result<()> {
    device::devmode::reveal(&usb_phone(udid).await?).await
}

pub async fn mount(udid: &str, reporter: &Reporter) -> Result<()> {
    let phone = usb_phone(udid).await?;
    device::pairing::pair(&phone, reporter, Duration::from_secs(90)).await?;
    device::ddi::mount(&phone, reporter).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn base_phone(paired: bool, developer_mode: Option<bool>) -> UsbPhoneView {
        UsbPhoneView {
            udid: "00008130-TEST".into(),
            name: "iPhone".into(),
            product_type: "iPhone17,1".into(),
            ios: "27.0".into(),
            paired,
            developer_mode,
        }
    }

    fn installed(profile_validated: Option<bool>, expired: bool) -> InstalledPokiView {
        InstalledPokiView {
            bundle_id: "nz.zheha.poki.TEAM1".into(),
            version: "0.4.4".into(),
            build: "1683".into(),
            profile_validated,
            team_is_free: true,
            expires_at: Some(1_900_000_000),
            expired,
        }
    }

    #[test]
    fn wizard_state_machine_evaluates_all_states_and_recovers_after_unplug_and_reboot() {
        assert_eq!(evaluate(&WizardProbe::default()), WizardState::DeviceDisconnected);

        let untrusted = WizardProbe { phone: Some(base_phone(false, None)), ..Default::default() };
        assert_eq!(evaluate(&untrusted), WizardState::DeviceUntrusted);

        let dev_off = WizardProbe { phone: Some(base_phone(true, Some(false))), ..Default::default() };
        assert_eq!(evaluate(&dev_off), WizardState::DeveloperModeOff);

        let signed_out = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: false,
            ..Default::default()
        };
        assert_eq!(evaluate(&signed_out), WizardState::AccountSignedOut);

        let ready = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: true,
            ..Default::default()
        };
        assert_eq!(evaluate(&ready), WizardState::ReadyToInstall);

        let sign_err = WizardProbe {
            failure: Some(WizardFailure {
                kind: "not_enough_app_ids".into(),
                stage: FailureStage::Sign,
                message: "Not enough available app IDs".into(),
            }),
            ..ready.clone()
        };
        assert_eq!(evaluate(&sign_err), WizardState::SigningFailed);

        let install_err = WizardProbe {
            failure: Some(WizardFailure {
                kind: "device".into(),
                stage: FailureStage::Install,
                message: "Install failed".into(),
            }),
            ..ready.clone()
        };
        assert_eq!(evaluate(&install_err), WizardState::InstallFailed);

        // Reboot recovery: Poki is already installed and non-expired, account is even signed out,
        // but reboot cleared /System/Developer so DDI is unmounted -> must go to DdiUnmounted, NOT AccountSignedOut!
        let after_reboot = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: false,
            installed: Some(installed(Some(true), false)),
            ddi_mounted: false,
            poki_started: true,
            automation_ready: true,
            failure: None,
        };
        assert_eq!(evaluate(&after_reboot), WizardState::DdiUnmounted);

        let app_untrusted = WizardProbe {
            phone: Some(base_phone(true, Some(true))),
            account_signed_in: true,
            installed: Some(installed(Some(false), false)),
            ddi_mounted: true,
            poki_started: false,
            ..Default::default()
        };
        assert_eq!(evaluate(&app_untrusted), WizardState::AppUntrusted);

        let not_started = WizardProbe {
            installed: Some(installed(Some(true), false)),
            ..app_untrusted.clone()
        };
        assert_eq!(evaluate(&not_started), WizardState::PokiNotStarted);

        let opened = WizardProbe { poki_started: true, ..not_started };
        assert_eq!(evaluate(&opened), WizardState::AutomationPending);
        let done = WizardProbe { automation_ready: true, ..opened };
        assert_eq!(evaluate(&done), WizardState::Completed);
    }
}
