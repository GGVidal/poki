//! The phones this computer set up, and when each needs Poki signed again. A free team's
//! profile lasts 7 days; a paid team's a year. Renewal is due with 2 days left.
use crate::{Result, paths};
use serde::{Deserialize, Serialize};

pub const RENEW_WITH_DAYS_LEFT: i64 = 2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Record {
    pub udid: String,
    pub phone_name: String,
    pub ios: String,
    pub apple_id: String,
    pub team_id: String,
    pub team_name: String,
    pub team_is_free: bool,
    pub bundle_id: String,
    pub app_group: String,
    pub version: String,
    pub build: String,
    pub release_tag: String,
    /// Unix seconds.
    pub signed_at: i64,
    pub profile_expires_at: i64,
    pub last_checked_at: Option<i64>,
    pub last_error: Option<String>,
    /// The phone's last known Wi-Fi address, for renewals without the cable.
    pub wifi_address: Option<String>,
    pub pairing_handed_off: bool,
    /// Set when the device has a test build from GitHub Actions instead of a release.
    #[cfg(feature = "device")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub test_build: Option<crate::devbuilds::BuildRef>,
}

impl Record {
    pub fn days_left(&self) -> i64 { (self.profile_expires_at - now()) / 86_400 }
    pub fn is_due(&self) -> bool { self.days_left() <= RENEW_WITH_DAYS_LEFT }
    pub fn is_expired(&self) -> bool { self.profile_expires_at <= now() }
}

pub fn now() -> i64 { time::OffsetDateTime::now_utc().unix_timestamp() }

fn path() -> Result<std::path::PathBuf> { Ok(paths::state_dir()?.join("phones.json")) }

pub fn all() -> Result<Vec<Record>> {
    Ok(std::fs::read_to_string(path()?).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default())
}

pub fn get(udid: &str) -> Result<Option<Record>> { Ok(all()?.into_iter().find(|r| r.udid == udid)) }

pub fn put(record: Record) -> Result<()> {
    let mut list = all()?;
    list.retain(|r| r.udid != record.udid);
    list.push(record);
    list.sort_by(|a, b| a.phone_name.cmp(&b.phone_name));
    std::fs::write(path()?, serde_json::to_vec_pretty(&list)?)?;
    Ok(())
}

pub fn remove(udid: &str) -> Result<()> {
    let mut list = all()?;
    list.retain(|r| r.udid != udid);
    std::fs::write(path()?, serde_json::to_vec_pretty(&list)?)?;
    Ok(())
}

pub fn note_check(udid: &str, error: Option<String>) -> Result<()> {
    if let Some(mut r) = get(udid)? {
        r.last_checked_at = Some(now());
        r.last_error = error;
        put(r)?;
    }
    Ok(())
}

pub fn due() -> Result<Vec<Record>> { Ok(all()?.into_iter().filter(|r| r.is_due()).collect()) }

/// How renewals treat the build on the phone.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenewalPrefs {
    /// A renewal of a release build signs the newest release instead (an update). Off, it signs the
    /// build that is on again. Test builds are always signed again, whatever this says.
    #[serde(default = "yes")]
    pub update_on_renew: bool,
}

fn yes() -> bool { true }

impl Default for RenewalPrefs {
    fn default() -> Self { RenewalPrefs { update_on_renew: true } }
}

fn prefs_path() -> Result<std::path::PathBuf> { Ok(paths::state_dir()?.join("renewals.json")) }

pub fn renewal_prefs() -> RenewalPrefs {
    prefs_path().ok().and_then(|p| std::fs::read(p).ok()).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}

pub fn set_renewal_prefs(prefs: &RenewalPrefs) -> Result<()> {
    std::fs::write(prefs_path()?, serde_json::to_vec_pretty(prefs)?)?;
    Ok(())
}

/// The unsigned build this computer last put on a phone, kept so a renewal can sign the same build
/// again (a test build or an IPA chosen by hand is not on any release to fetch again).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct KeptBuild {
    pub version: String,
    pub build: String,
    pub ipa: std::path::PathBuf,
    pub signing_zip: Option<std::path::PathBuf>,
}

fn kept_dir(udid: &str) -> Result<std::path::PathBuf> {
    let safe: String = udid.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-').collect();
    Ok(paths::state_dir()?.join("kept").join(safe))
}

/// Keeps a copy of the unsigned IPA (and its signing zip) that was just installed on `udid`.
pub fn keep_build(udid: &str, version: &str, build: &str, ipa: &std::path::Path, signing_zip: Option<&std::path::Path>) -> Result<KeptBuild> {
    let dir = kept_dir(udid)?;
    std::fs::create_dir_all(&dir)?;
    let kept_ipa = dir.join("Poki.ipa");
    let kept_zip = dir.join("Poki-signing.zip");
    if ipa != kept_ipa {
        let part = dir.join("Poki.ipa.part");
        std::fs::copy(ipa, &part)?;
        std::fs::rename(&part, &kept_ipa)?;
    }
    match signing_zip {
        Some(z) if z != kept_zip => {
            std::fs::copy(z, &kept_zip)?;
        }
        Some(_) => {}
        None => {
            let _ = std::fs::remove_file(&kept_zip);
        }
    }
    let kept = KeptBuild { version: version.into(), build: build.into(), ipa: kept_ipa, signing_zip: signing_zip.map(|_| kept_zip) };
    std::fs::write(dir.join("kept.json"), serde_json::to_vec_pretty(&kept)?)?;
    Ok(kept)
}

/// The build kept for `udid`, when its files are still there.
pub fn kept_build(udid: &str) -> Option<KeptBuild> {
    let dir = kept_dir(udid).ok()?;
    let kept: KeptBuild = serde_json::from_slice(&std::fs::read(dir.join("kept.json")).ok()?).ok()?;
    (kept.ipa.is_file() && kept.signing_zip.as_ref().is_none_or(|z| z.is_file())).then_some(kept)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn due_and_store() {
        let (_lock, _dir) = crate::paths::test_home();
        let mk = |udid: &str, days: i64| Record {
            udid: udid.into(),
            phone_name: "Phone".into(),
            ios: "26.1".into(),
            apple_id: "a@b".into(),
            team_id: "T".into(),
            team_name: "T".into(),
            team_is_free: true,
            bundle_id: "nz.zheha.poki.T".into(),
            app_group: "group.nz.zheha.poki.T".into(),
            version: "0.2.7".into(),
            build: "70".into(),
            release_tag: "ios-v0.2.7".into(),
            signed_at: now(),
            profile_expires_at: now() + days * 86_400,
            last_checked_at: None,
            last_error: None,
            wifi_address: None,
            pairing_handed_off: false,
            #[cfg(feature = "device")]
            test_build: None,
        };
        put(mk("A", 7)).unwrap();
        put(mk("B", 1)).unwrap();
        assert_eq!(all().unwrap().len(), 2);
        let d = due().unwrap();
        assert_eq!(d.len(), 1);
        assert_eq!(d[0].udid, "B");
        remove("A").unwrap();
        assert_eq!(all().unwrap().len(), 1);
    }

    #[test]
    fn keeps_the_installed_build_and_the_renewal_choice() {
        let (_lock, dir) = crate::paths::test_home();
        assert!(renewal_prefs().update_on_renew);
        set_renewal_prefs(&RenewalPrefs { update_on_renew: false }).unwrap();
        assert!(!renewal_prefs().update_on_renew);

        assert!(kept_build("U1").is_none());
        let ipa = dir.path().join("Poki-unsigned.ipa");
        std::fs::write(&ipa, b"ipa").unwrap();
        let zip = dir.path().join("Poki-signing.zip");
        std::fs::write(&zip, b"zip").unwrap();
        let kept = keep_build("U1", "0.4.5", "50", &ipa, Some(&zip)).unwrap();
        assert_eq!(kept_build("U1"), Some(kept.clone()));
        assert_eq!(std::fs::read(&kept.ipa).unwrap(), b"ipa");
        // Signing the kept copy again keeps it, and a build without a signing zip drops the old zip.
        let again = keep_build("U1", "0.4.5", "50", &kept.ipa, None).unwrap();
        assert_eq!(again.signing_zip, None);
        assert_eq!(std::fs::read(&again.ipa).unwrap(), b"ipa");
        std::fs::remove_file(&again.ipa).unwrap();
        assert!(kept_build("U1").is_none());
    }
}
