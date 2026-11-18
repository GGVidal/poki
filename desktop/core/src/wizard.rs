//! Stateless USB setup wizard state machine.
use serde::{Deserialize, Serialize};

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
    Completed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FailureStage {
    Usbmuxd,
    Sign,
    Install,
    Ddi,
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
    pub usbmuxd_unavailable: bool,
    pub phone: Option<UsbPhoneView>,
    pub account_signed_in: bool,
    pub installed: Option<InstalledPokiView>,
    pub ddi_mounted: bool,
    pub poki_started: bool,
    pub failure: Option<WizardFailure>,
}

pub fn evaluate(_probe: &WizardProbe) -> WizardState {
    WizardState::DeviceDisconnected
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
            failure: None,
            usbmuxd_unavailable: false,
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

        let done = WizardProbe { poki_started: true, ..not_started.clone() };
        assert_eq!(evaluate(&done), WizardState::Completed);
    }
}
