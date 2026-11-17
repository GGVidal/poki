//! GrandSlam Authentication: Apple ID sign-in with SRP, two-factor, and the Xcode app token.
//!
//! Protocol as in SideStore's icloud-auth (MPL-2.0) and Dadoum's Sideloader (GPL-3.0), written
//! again here in Rust against the plist shapes those projects document.
use super::anisette::{Headers as Anisette, Provider};
use super::srp;
use crate::{Error, Result};
use aes_gcm::aead::{Aead, Payload};
use aes_gcm::KeyInit;
use base64::Engine;
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

const GS_SERVICE: &str = "https://gsa.apple.com/grandslam/GsService2";
const TRUSTED_DEVICE: &str = "https://gsa.apple.com/auth/verify/trusteddevice";
const VALIDATE: &str = "https://gsa.apple.com/grandslam/GsService2/validate";
const AUTH_INFO: &str = "https://gsa.apple.com/auth";
const SMS_START: &str = "https://gsa.apple.com/auth/verify/phone/";
const SMS_CODE: &str = "https://gsa.apple.com/auth/verify/phone/securitycode";
const GSA_AGENT: &str = "akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0";

#[derive(Debug, Clone)]
pub(crate) struct Endpoints {
    pub gs_service: String,
    pub trusted_device: String,
    pub validate: String,
    pub auth_info: String,
    pub sms_start: String,
    pub sms_code: String,
}

impl Endpoints {
    pub fn apple() -> Self {
        Self {
            gs_service: GS_SERVICE.into(),
            trusted_device: TRUSTED_DEVICE.into(),
            validate: VALIDATE.into(),
            auth_info: AUTH_INFO.into(),
            sms_start: SMS_START.into(),
            sms_code: SMS_CODE.into(),
        }
    }

    #[cfg(test)]
    pub fn local(base: &str) -> Self {
        Self {
            gs_service: format!("{base}/grandslam/GsService2"),
            trusted_device: format!("{base}/auth/verify/trusteddevice"),
            validate: format!("{base}/grandslam/GsService2/validate"),
            auth_info: format!("{base}/auth"),
            sms_start: format!("{base}{}", SMS_START.trim_start_matches("https://gsa.apple.com")),
            sms_code: format!("{base}/auth/verify/phone/securitycode"),
        }
    }
}

/// What a sign-in leaves behind. `gs_idms_token` + `adsid` identify the session to Apple;
/// `sk`/`c` let us ask for app tokens again without the password.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
    pub apple_id: String,
    pub adsid: String,
    pub gs_idms_token: String,
    pub first_name: String,
    pub last_name: String,
    #[serde(with = "b64")]
    pub sk: Vec<u8>,
    #[serde(with = "b64")]
    pub c: Vec<u8>,
}

mod b64 {
    use base64::Engine;
    use serde::{Deserialize, Deserializer, Serializer};
    pub fn serialize<S: Serializer>(v: &Vec<u8>, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&base64::engine::general_purpose::STANDARD.encode(v))
    }
    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<u8>, D::Error> {
        let s = String::deserialize(d)?;
        base64::engine::general_purpose::STANDARD.decode(s).map_err(serde::de::Error::custom)
    }
}

/// A token for one app (we only ever ask for Xcode's).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppToken {
    pub app: String,
    pub token: String,
    /// Unix seconds.
    pub expires_at: i64,
}

impl AppToken {
    pub fn valid_for(&self, secs: i64) -> bool { self.expires_at - time::OffsetDateTime::now_utc().unix_timestamp() > secs }
}

/// How the sign-in ended.
#[derive(Debug)]
pub enum Outcome {
    SignedIn(Session),
    /// Apple wants a second factor. Keep the [`Pending`] and call `trusted_device_code` or `sms_code`.
    NeedsCode(Pending),
}

/// A sign-in waiting for the 2FA code. Serializable so the command line can finish it in a
/// second run (`poki-setup login --code`); it is kept in the keychain, never in a file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pending {
    pub apple_id: String,
    password: String,
    session: Session,
    pub via: Factor,
    /// The trusted phone number Apple texted (its id in Apple's list), for an SMS sign-in.
    phone_id: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Factor {
    TrustedDevice,
    Sms,
}

pub struct Client {
    http: reqwest::Client,
    anisette: Provider,
    endpoints: Endpoints,
}

type HmacSha256 = Hmac<Sha256>;

fn dict<'a>(v: &'a plist::Value, key: &str) -> Option<&'a plist::Value> { v.as_dictionary()?.get(key) }
fn s<'a>(v: &'a plist::Value, key: &str) -> Option<&'a str> { dict(v, key)?.as_string() }
fn data<'a>(v: &'a plist::Value, key: &str) -> Option<&'a [u8]> { dict(v, key)?.as_data() }

struct Status {
    ec: i64,
    em: String,
    hsc: i64,
    au: Option<String>,
}

fn status(response: &plist::Value) -> Status {
    let st = dict(response, "Status");
    let int = |k: &str| st.and_then(|s| dict(s, k)).and_then(|v| v.as_signed_integer()).unwrap_or(0);
    Status {
        ec: int("ec"),
        em: st.and_then(|s0| s(s0, "em")).unwrap_or("").to_string(),
        hsc: int("hsc"),
        au: st.and_then(|s0| s(s0, "au")).map(|a| a.to_string()),
    }
}

fn apple_error(st: &Status) -> Error {
    tracing::warn!("Apple sign-in status ec={} hsc={} em={:?}", st.ec, st.hsc, st.em);
    let text = match st.ec {
        -20101 | -22406 | -20970 => "Apple ID or password is wrong.".to_string(),
        -20209 | -20751 => "This Apple ID is locked. Unlock it at iforgot.apple.com and try again.".to_string(),
        -22421 => "Apple refused the sign-in from this computer's identity (anisette). Try again in a minute, or choose another anisette server in Settings.".to_string(),
        -23782 => "Apple refused the Mac identity Poki signs in with (it asks for macOS 10.13 or later). Update Poki and Poki Setup to the latest version, then try again.".to_string(),
        -20283 => "Apple asked for a passcode or trusted device that this computer cannot provide. Enable two-factor authentication on this Apple ID and try again.".to_string(),
        _ if st.em.is_empty() => format!("Apple's sign-in failed with code {}.", st.ec),
        _ => st.em.clone(),
    };
    Error::apple(st.ec, text)
}

impl Client {
    pub fn new(anisette: Provider) -> Result<Client> { Self::with_endpoints(anisette, Endpoints::apple()) }

    pub(crate) fn with_endpoints(anisette: Provider, endpoints: Endpoints) -> Result<Client> {
        Ok(Client { http: super::http_client()?, anisette, endpoints })
    }

    pub fn anisette(&mut self) -> &mut Provider { &mut self.anisette }

    async fn gs_request(&self, headers: &Anisette, request: plist::Dictionary) -> Result<plist::Value> {
        let mut header = plist::Dictionary::new();
        header.insert("Version".into(), "1.0.1".into());
        let mut root = plist::Dictionary::new();
        root.insert("Header".into(), plist::Value::Dictionary(header));
        root.insert("Request".into(), plist::Value::Dictionary(request));
        let mut body = Vec::new();
        plist::to_writer_xml(&mut body, &plist::Value::Dictionary(root))?;
        let res = self
            .http
            .post(&self.endpoints.gs_service)
            .header("Content-Type", "text/x-xml-plist")
            .header("Accept", "*/*")
            .header("User-Agent", headers.get("User-Agent").unwrap_or(GSA_AGENT))
            .header("X-MMe-Client-Info", headers.get("X-Mme-Client-Info").unwrap_or(""))
            .body(body)
            .send()
            .await?;
        if res.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
            return Err(rate_limited());
        }
        let res = res.error_for_status()?.bytes().await?;
        let v: plist::Value = plist::from_bytes(&res)?;
        dict(&v, "Response").cloned().ok_or_else(|| Error::msg("Apple's sign-in service gave an answer without a Response"))
    }

    /// Signs in. Returns `NeedsCode` when Apple wants a second factor.
    ///
    /// When Apple refuses the anisette identity (-80045/-80046) the next fallback server is tried.
    /// That is a different "Mac" to Apple, so it is only done here, before any code was asked for.
    pub async fn sign_in(&mut self, apple_id: &str, password: &str) -> Result<Outcome> {
        loop {
            match self.sign_in_once(apple_id, password).await {
                Err(Error::Apple { code: -80045, .. }) | Err(Error::Apple { code: -80046, .. }) if self.anisette.rotate() => continue,
                other => return other,
            }
        }
    }

    async fn sign_in_once(&mut self, apple_id: &str, password: &str) -> Result<Outcome> {
        let anisette = self.anisette.headers().await?;
        let mut client = srp::Client::new();

        let mut init = plist::Dictionary::new();
        init.insert("A2k".into(), plist::Value::Data(client.a_pub.clone()));
        init.insert("cpd".into(), plist::Value::Dictionary(anisette.cpd()));
        init.insert("o".into(), "init".into());
        init.insert("ps".into(), plist::Value::Array(vec!["s2k".into(), "s2k_fo".into()]));
        init.insert("u".into(), apple_id.into());
        let r1 = self.gs_request(&anisette, init).await?;
        let st = status(&r1);
        if st.ec != 0 {
            return Err(apple_error(&st));
        }
        let sp = s(&r1, "sp").unwrap_or("s2k");
        let salt = data(&r1, "s").ok_or_else(|| Error::msg("sign-in: no salt"))?.to_vec();
        let iterations = dict(&r1, "i").and_then(|v| v.as_signed_integer()).ok_or_else(|| Error::msg("sign-in: no iteration count"))? as u32;
        let b_pub = data(&r1, "B").ok_or_else(|| Error::msg("sign-in: no B"))?.to_vec();
        let cookie = data(&r1, "c").map(|c| c.to_vec()).or_else(|| s(&r1, "c").map(|c| c.as_bytes().to_vec())).unwrap_or_default();
        let c_value = dict(&r1, "c").cloned().unwrap_or(plist::Value::String(String::new()));

        let derived = srp::Client::derive_password(password, &salt, iterations, sp == "s2k_fo");
        let m1 = client.process(apple_id, &derived, &salt, &b_pub).map_err(Error::msg)?;
        let _ = cookie;

        let mut complete = plist::Dictionary::new();
        complete.insert("c".into(), c_value);
        complete.insert("M1".into(), plist::Value::Data(m1));
        complete.insert("cpd".into(), plist::Value::Dictionary(anisette.cpd()));
        complete.insert("o".into(), "complete".into());
        complete.insert("u".into(), apple_id.into());
        let r2 = self.gs_request(&anisette, complete).await?;
        let st = status(&r2);
        if st.ec != 0 {
            return Err(apple_error(&st));
        }
        let m2 = data(&r2, "M2").ok_or_else(|| Error::msg("sign-in: no M2"))?;
        if !client.verify_server(m2) {
            return Err(Error::msg("Apple's sign-in answer did not verify (M2 mismatch). Check the clock on this computer and try again."));
        }
        let spd = data(&r2, "spd").ok_or_else(|| Error::msg("sign-in: no spd"))?;
        let spd = decrypt_spd(client.key(), spd)?;
        let session = Session {
            apple_id: apple_id.to_string(),
            adsid: s(&spd, "adsid").unwrap_or("").to_string(),
            gs_idms_token: s(&spd, "GsIdmsToken").unwrap_or("").to_string(),
            first_name: s(&spd, "fn").unwrap_or("").to_string(),
            last_name: s(&spd, "ln").unwrap_or("").to_string(),
            sk: data(&spd, "sk").unwrap_or(&[]).to_vec(),
            c: data(&spd, "c").unwrap_or(&[]).to_vec(),
        };
        if session.adsid.is_empty() || session.gs_idms_token.is_empty() {
            return Err(Error::msg("Apple's sign-in answer had no account token."));
        }
        tracing::info!("sign-in answered hsc {} au {:?}", st.hsc, st.au);
        let pending = |via: Factor, phone_id: u64, session: Session| Pending { apple_id: apple_id.into(), password: password.into(), session, via, phone_id };
        match next_step(st.hsc, st.au.as_deref()) {
            Step::SignedIn => Ok(Outcome::SignedIn(session)),
            // Since October 2026 Apple can answer 409 with no `au` and push the code to the
            // person's devices by itself (SideStore's SideSign #5, AltSign #59). Asking for another
            // push would replace the code already on the way, so only wait for it.
            Step::CodeAlreadySent => {
                tracing::info!("Apple sent the code to the trusted devices by itself (hsc 409, no au)");
                Ok(Outcome::NeedsCode(pending(Factor::TrustedDevice, 0, session)))
            }
            // One code per attempt: a push to the person's Apple devices first, a text only when
            // no device took it. Apple turns text codes away for this client more and more (HTTP
            // 403), and each new request can replace the code sent before it.
            Step::AskForCode => match self.start_trusted_device(&session).await {
                Ok(()) => Ok(Outcome::NeedsCode(pending(Factor::TrustedDevice, 0, session))),
                Err(e) if is_rate_limit(&e) => Err(e),
                Err(e) => {
                    tracing::warn!("trusted-device code not sent, texting it instead: {e}");
                    match self.start_sms(&session).await {
                        Ok(phone_id) => Ok(Outcome::NeedsCode(pending(Factor::Sms, phone_id, session))),
                        Err(sms) if is_rate_limit(&sms) => Err(sms),
                        // Nothing was sent, but a code made on a device (Settings > [name] >
                        // Sign-In & Security > Get Verification Code) is still checked the same way.
                        Err(sms) => {
                            tracing::warn!("SMS code not sent either, waiting for a code made on a device: {sms}");
                            Ok(Outcome::NeedsCode(pending(Factor::TrustedDevice, 0, session)))
                        }
                    }
                }
            },
            // Apple marks the account as needing attention (most often two-factor authentication is
            // not turned on, or new terms wait). The session is complete, so go on as Sideloader and
            // AltSign do; only a session without the app-token keys cannot be used.
            Step::Repair if !session.sk.is_empty() && !session.c.is_empty() => {
                tracing::warn!("Apple asked to repair the account (au repair); continuing with the session");
                Ok(Outcome::SignedIn(session))
            }
            Step::Repair => Err(Error::NeedsPerson("Apple wants something on this Apple Account fixed before it can be used here. Sign in at account.apple.com, turn on two-factor authentication and accept any new terms, then sign in again.".into())),
            Step::Unsupported(other) => Err(Error::msg(format!("Apple asked for a verification step this app does not support ({other})."))),
        }
    }

    fn twofa_request(&self, rb: reqwest::RequestBuilder, session: &Session, anisette: &Anisette) -> reqwest::RequestBuilder {
        self.twofa_request_as(rb, session, anisette, "text/x-xml-plist")
    }

    /// The 2FA headers with one Content-Type and Accept (`kind`). The SMS endpoints speak JSON; a
    /// request that carries both the plist and the JSON type is turned away (HTTP 405).
    fn twofa_request_as(&self, rb: reqwest::RequestBuilder, session: &Session, anisette: &Anisette, kind: &str) -> reqwest::RequestBuilder {
        let identity = base64::engine::general_purpose::STANDARD.encode(format!("{}:{}", session.adsid, session.gs_idms_token));
        let mut rb = rb
            .header("X-Apple-Identity-Token", identity)
            .header("X-Apple-App-Info", super::XCODE_APP_ID)
            .header("X-Xcode-Version", super::XCODE_VERSION)
            .header("Content-Type", kind)
            .header("Accept", kind)
            .header("Accept-Language", "en-us")
            .header("User-Agent", "Xcode");
        for (k, v) in &anisette.map {
            if k.eq_ignore_ascii_case("User-Agent") {
                continue;
            }
            rb = rb.header(k.as_str(), v.as_str());
        }
        if let Some(loc) = anisette.map.get("X-Apple-Locale") {
            rb = rb.header("Loc", loc.as_str());
        }
        rb
    }

    /// Asks Apple to show a code on the person's Apple devices. Apple can answer 200 with an error
    /// inside the plist, so that is read too.
    async fn start_trusted_device(&mut self, session: &Session) -> Result<()> {
        let anisette = self.anisette.headers().await?;
        let res = self.twofa_request(self.http.get(&self.endpoints.trusted_device), session, &anisette).send().await?;
        let status = res.status();
        let bytes = res.bytes().await.unwrap_or_default();
        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            return Err(rate_limited());
        }
        if !status.is_success() {
            return Err(Error::msg(format!("Apple could not send a code to your devices (HTTP {status}). Try again, or get a code on a device: Settings > [your name] > Sign-In & Security > Two-Factor Authentication > Get Verification Code.")));
        }
        if let Ok(v) = plist::from_bytes::<plist::Value>(&bytes) {
            let ec = dict(&v, "ec").and_then(|e| e.as_signed_integer()).unwrap_or(0);
            if ec != 0 {
                return Err(Error::apple(ec, format!("Apple could not send a code to your devices: {} ({ec}).", s(&v, "em").unwrap_or("no reason given"))));
            }
        }
        tracing::info!("trusted-device code requested (HTTP {status}, {} bytes)", bytes.len());
        Ok(())
    }

    /// Asks Apple to text a code. First reads the account's trusted phone numbers (GET /auth, which
    /// also opens the verification on Apple's side), then asks for the text to the first one.
    /// Returns the phone number's id, which the code is checked against.
    async fn start_sms(&mut self, session: &Session) -> Result<u64> {
        let anisette = self.anisette.headers().await?;
        let mut phone_id = 1u64;
        let mut already_sent = false;
        if let Ok(res) = self.twofa_request_as(self.http.get(&self.endpoints.auth_info), session, &anisette, "application/json").send().await {
            // 201: Apple has texted the code already (SideStore reads it the same way).
            already_sent = res.status().as_u16() == 201;
            tracing::info!("2FA info answered HTTP {}", res.status());
            if let Ok(v) = res.json::<serde_json::Value>().await {
                if let Some(id) = first_phone_id(&v) {
                    phone_id = id;
                }
            }
        }
        if already_sent {
            return Ok(phone_id);
        }
        let body = serde_json::json!({ "phoneNumber": { "id": phone_id }, "mode": "sms" });
        let mut last = None;
        // PUT is what Apple's own clients send; POST is tried when PUT is turned away.
        for method in [reqwest::Method::PUT, reqwest::Method::POST] {
            let res = self
                .twofa_request_as(self.http.request(method.clone(), &self.endpoints.sms_start), session, &anisette, "application/json")
                .body(body.to_string())
                .send()
                .await?;
            if res.status().is_success() {
                tracing::info!("SMS code requested ({method}, HTTP {})", res.status());
                return Ok(phone_id);
            }
            tracing::warn!("SMS request {method} answered {}", res.status());
            if res.status() == reqwest::StatusCode::TOO_MANY_REQUESTS {
                return Err(rate_limited());
            }
            last = Some(res.status());
            if res.status() != reqwest::StatusCode::METHOD_NOT_ALLOWED {
                break;
            }
        }
        Err(Error::msg(format!(
            "Apple could not text a code to your phone number (HTTP {}). Use a code from one of your Apple devices instead: on an iPhone, iPad or Mac signed in to this Apple Account, open Settings > [your name] > Sign-In & Security > Two-Factor Authentication > Get Verification Code.",
            last.map(|s| s.to_string()).unwrap_or_default()
        )))
    }

    async fn check_device_code(&self, pending: &Pending, anisette: &Anisette, code: &str) -> Result<()> {
        let res = self.twofa_request(self.http.get(&self.endpoints.validate), &pending.session, anisette).header("security-code", code).send().await?;
        let status = res.status().as_u16();
        let bytes = res.bytes().await?;
        device_code_answer(status, &bytes)
    }

    async fn check_sms_code(&self, pending: &Pending, anisette: &Anisette, code: &str) -> Result<()> {
        let body = serde_json::json!({ "phoneNumber": { "id": pending.phone_id }, "securityCode": { "code": code }, "mode": "sms" });
        let res = self
            .twofa_request_as(self.http.post(&self.endpoints.sms_code), &pending.session, anisette, "application/json")
            .body(body.to_string())
            .send()
            .await?;
        sms_code_answer(res.status().as_u16())
    }

    /// Finishes a 2FA sign-in with the code the person typed.
    pub async fn finish(&mut self, pending: Pending, code: &str) -> Result<Session> {
        let code = code.trim();
        if code.len() != 6 || !code.chars().all(|c| c.is_ascii_digit()) {
            return Err(Error::NeedsPerson("The code is six digits.".into()));
        }
        let anisette = self.anisette.headers().await?;
        // A code can come from either place (Apple may push and text); check the one that was
        // asked for first, then the other.
        let first = match pending.via {
            Factor::TrustedDevice => self.check_device_code(&pending, &anisette, code).await,
            Factor::Sms => self.check_sms_code(&pending, &anisette, code).await,
        };
        if let Err(first) = first {
            let second = match pending.via {
                Factor::TrustedDevice if pending.phone_id != 0 => self.check_sms_code(&pending, &anisette, code).await,
                Factor::TrustedDevice => Err(first),
                Factor::Sms => self.check_device_code(&pending, &anisette, code).await.map_err(|_| first),
            };
            second?;
        }
        // Sign in again: this identity is trusted now and Apple hands out the full session. It must
        // be the same anisette identity the code was checked with, so there is no move to another
        // server here: a new "Mac" would be asked for a new code.
        match self.sign_in_once(&pending.apple_id, &pending.password).await? {
            Outcome::SignedIn(s) => Ok(s),
            Outcome::NeedsCode(_) => Err(Error::NeedsPerson("Apple took the code but asked for a new one when Poki signed in again. Wait for the new code and enter it, or sign in again in a few minutes.".into())),
        }
    }

    /// The app token for Xcode's services, which the developer portal wants.
    pub async fn xcode_token(&mut self, session: &Session) -> Result<AppToken> {
        self.app_token(session, super::XCODE_APP_ID).await
    }

    pub async fn app_token(&mut self, session: &Session, app: &str) -> Result<AppToken> {
        let anisette = self.anisette.headers().await?;
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&session.sk).map_err(|_| Error::msg("session key is empty; sign in again"))?;
        mac.update(b"apptokens");
        mac.update(session.adsid.as_bytes());
        mac.update(app.as_bytes());
        let checksum = mac.finalize().into_bytes().to_vec();
        let mut req = plist::Dictionary::new();
        req.insert("app".into(), plist::Value::Array(vec![app.into()]));
        req.insert("c".into(), plist::Value::Data(session.c.clone()));
        req.insert("checksum".into(), plist::Value::Data(checksum));
        req.insert("cpd".into(), plist::Value::Dictionary(anisette.cpd()));
        req.insert("o".into(), "apptokens".into());
        req.insert("t".into(), session.gs_idms_token.clone().into());
        req.insert("u".into(), session.adsid.clone().into());
        let r = self.gs_request(&anisette, req).await?;
        let st = status(&r);
        if st.ec != 0 {
            return Err(match st.ec {
                -20101 | -22406 | -21212 => Error::NeedsPerson("Your Apple session has expired. Sign in again.".into()),
                _ => apple_error(&st),
            });
        }
        let et = data(&r, "et").ok_or_else(|| Error::msg("Apple gave no app token"))?;
        let tokens = decrypt_gcm(&session.sk, et)?;
        let entry = dict(&tokens, "t").and_then(|t| dict(t, app)).ok_or_else(|| Error::msg("Apple's app token answer had no Xcode token"))?;
        let token = s(entry, "token").ok_or_else(|| Error::msg("app token without a token"))?.to_string();
        let expiry = dict(entry, "expiry").and_then(|e| e.as_signed_integer()).unwrap_or(0);
        // Apple sends milliseconds since 1970.
        let expires_at = if expiry > 10_000_000_000 { expiry / 1000 } else { expiry };
        Ok(AppToken { app: app.to_string(), token, expires_at })
    }
}

/// What a finished password step asks for next.
#[derive(Debug, PartialEq, Eq)]
enum Step<'a> {
    SignedIn,
    /// 409 with no `au`: Apple pushed a code to the trusted devices on its own.
    CodeAlreadySent,
    /// `trustedDeviceSecondaryAuth` or `secondaryAuth`: ask for one code.
    AskForCode,
    /// `repair`: Apple wants the account fixed (often two-factor authentication turned on).
    Repair,
    Unsupported(&'a str),
}

fn next_step(hsc: i64, au: Option<&str>) -> Step<'_> {
    match au {
        Some("trustedDeviceSecondaryAuth") | Some("secondaryAuth") => Step::AskForCode,
        Some("repair") => Step::Repair,
        Some(other) => Step::Unsupported(other),
        None if hsc == 409 => Step::CodeAlreadySent,
        None => Step::SignedIn,
    }
}

const RATE_LIMITED: &str = "Apple has had too many sign-in attempts or codes for this Apple Account. Wait about an hour before you sign in again, because each new try asks Apple for another code.";

fn rate_limited() -> Error { Error::NeedsPerson(RATE_LIMITED.into()) }

fn is_rate_limit(e: &Error) -> bool { matches!(e, Error::NeedsPerson(m) if m == RATE_LIMITED) }

/// Reads Apple's answer to a device code. Only an answer that says `ec` 0 (at the top or under
/// `Status`) counts as accepted; an error page or an empty answer is not.
fn device_code_answer(status: u16, bytes: &[u8]) -> Result<()> {
    if status == 429 {
        return Err(rate_limited());
    }
    let v = plist::from_bytes::<plist::Value>(bytes).ok();
    let ec_of = |d: &plist::Value| dict(d, "ec").and_then(|e| e.as_signed_integer());
    let ec = v.as_ref().and_then(|v| ec_of(v).or_else(|| dict(v, "Status").and_then(ec_of)));
    let em = v.as_ref().and_then(|v| s(v, "em").or_else(|| dict(v, "Status").and_then(|st| s(st, "em")))).unwrap_or("");
    match ec {
        Some(0) if (200..300).contains(&status) => Ok(()),
        Some(-21669) => Err(Error::NeedsPerson("That code was not right. Try again.".into())),
        Some(0) | None => Err(Error::msg(format!("Apple's answer to the code could not be read (HTTP {status}). Try the code again, or sign in again."))),
        Some(ec) => Err(Error::apple(ec, if em.is_empty() { format!("Apple rejected the code ({ec}).") } else { em.to_string() })),
    }
}

/// Reads Apple's answer to a texted code from its HTTP status.
fn sms_code_answer(status: u16) -> Result<()> {
    match status {
        200..=299 => Ok(()),
        429 => Err(rate_limited()),
        403 => Err(Error::NeedsPerson("Apple turned away text-message codes for this sign-in. Use a code from one of your Apple devices instead. On a device signed in to this Apple Account, open Settings > [your name] > Sign-In & Security > Get Verification Code.".into())),
        _ => Err(Error::NeedsPerson("That code was not right. Try again.".into())),
    }
}

fn decrypt_spd(key: &[u8], spd: &[u8]) -> Result<plist::Value> {
    use aes::cipher::{BlockDecryptMut, KeyIvInit};
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key).unwrap();
    mac.update(b"extra data key:");
    let k = mac.finalize().into_bytes();
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key).unwrap();
    mac.update(b"extra data iv:");
    let iv = mac.finalize().into_bytes();
    let dec = cbc::Decryptor::<aes::Aes256>::new_from_slices(&k, &iv[..16]).map_err(|_| Error::msg("spd key"))?;
    let plain = dec.decrypt_padded_vec_mut::<aes::cipher::block_padding::Pkcs7>(spd).map_err(|_| Error::msg("Apple's session data did not decrypt. Check the password and try again."))?;
    Ok(plist::from_bytes(&plain)?)
}

fn decrypt_gcm(sk: &[u8], et: &[u8]) -> Result<plist::Value> {
    // "XYZ" | 16-byte IV | ciphertext | 16-byte tag, AES-256-GCM with the header as AAD.
    use aes_gcm::aead::generic_array::{GenericArray, typenum::U16};
    if et.len() < 3 + 16 + 16 || &et[..3] != b"XYZ" {
        return Err(Error::msg("Apple's app token has an unknown shape"));
    }
    let cipher = aes_gcm::AesGcm::<aes::Aes256, U16>::new_from_slice(sk).map_err(|_| Error::msg("session key length"))?;
    let plain = cipher
        .decrypt(GenericArray::from_slice(&et[3..19]), Payload { msg: &et[19..], aad: b"XYZ" })
        .map_err(|_| Error::msg("Apple's app token did not decrypt. Sign in again."))?;
    Ok(plist::from_bytes(&plain)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn authentication_request_values_never_enter_trace_events() {
        use std::sync::{Arc, atomic::{AtomicUsize, Ordering}};
        use tracing::{Event, Metadata, Subscriber, field::{Field, Visit}, span::{Attributes, Id, Record}};

        const CANARY: &str = "synthetic-private-request-value";
        struct TraceCapture { events: Arc<AtomicUsize>, leaks: Arc<AtomicUsize> }
        impl Visit for TraceCapture {
            fn record_debug(&mut self, _: &Field, value: &dyn std::fmt::Debug) {
                if format!("{value:?}").contains(CANARY) {
                    self.leaks.fetch_add(1, Ordering::SeqCst);
                }
            }
        }
        impl Subscriber for TraceCapture {
            fn enabled(&self, _: &Metadata<'_>) -> bool { true }
            fn new_span(&self, _: &Attributes<'_>) -> Id { Id::from_u64(1) }
            fn record(&self, _: &Id, _: &Record<'_>) {}
            fn record_follows_from(&self, _: &Id, _: &Id) {}
            fn event(&self, event: &Event<'_>) {
                self.events.fetch_add(1, Ordering::SeqCst);
                event.record(&mut TraceCapture { events: self.events.clone(), leaks: self.leaks.clone() });
            }
            fn enter(&self, _: &Id) {}
            fn exit(&self, _: &Id) {}
        }
        let events = Arc::new(AtomicUsize::new(0));
        let leaks = Arc::new(AtomicUsize::new(0));
        let capture = TraceCapture { events: events.clone(), leaks: leaks.clone() };
        tracing::subscriber::with_default(capture, || {
            tracing::trace!("trace capture enabled");
            let runtime = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            runtime.block_on(async {
                let client = Client::new(Provider::new(super::super::anisette::Source::System)).unwrap();
                // Invalid HTTP headers fail before any network I/O, after request serialization.
                let headers = Anisette {
                    map: [("User-Agent".into(), "invalid\nheader".into())].into(),
                    made_at: std::time::Instant::now(),
                };
                let mut request = plist::Dictionary::new();
                request.insert("test-value".into(), CANARY.into());
                let error = client.gs_request(&headers, request).await.unwrap_err();
                assert!(error.to_string().contains("builder error"));
            });
        });
        assert!(events.load(Ordering::SeqCst) > 0, "TRACE must be enabled for this check");
        assert_eq!(leaks.load(Ordering::SeqCst), 0, "authentication request value reached a trace event");
    }

    #[test]
    fn spd_round_trip() {
        use aes::cipher::{BlockEncryptMut, KeyIvInit};
        let key = [7u8; 32];
        let mut d = plist::Dictionary::new();
        d.insert("adsid".into(), "000-1".into());
        let mut plain = Vec::new();
        plist::to_writer_xml(&mut plain, &plist::Value::Dictionary(d)).unwrap();
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&key).unwrap();
        mac.update(b"extra data key:");
        let k = mac.finalize().into_bytes();
        let mut mac = <HmacSha256 as Mac>::new_from_slice(&key).unwrap();
        mac.update(b"extra data iv:");
        let iv = mac.finalize().into_bytes();
        let enc = cbc::Encryptor::<aes::Aes256>::new_from_slices(&k, &iv[..16]).unwrap();
        let ct = enc.encrypt_padded_vec_mut::<aes::cipher::block_padding::Pkcs7>(&plain);
        let v = decrypt_spd(&key, &ct).unwrap();
        assert_eq!(s(&v, "adsid"), Some("000-1"));
    }

    #[test]
    fn gcm_round_trip_16_byte_iv() {
        use aes_gcm::aead::generic_array::typenum::U16;
        let sk = [3u8; 32];
        let mut t = plist::Dictionary::new();
        let mut app = plist::Dictionary::new();
        app.insert("token".into(), "tok".into());
        app.insert("expiry".into(), plist::Value::Integer(1_800_000_000_000i64.into()));
        t.insert(super::super::XCODE_APP_ID.into(), plist::Value::Dictionary(app));
        let mut root = plist::Dictionary::new();
        root.insert("t".into(), plist::Value::Dictionary(t));
        let mut plain = Vec::new();
        plist::to_writer_xml(&mut plain, &plist::Value::Dictionary(root)).unwrap();
        let c = aes_gcm::AesGcm::<aes::Aes256, U16>::new_from_slice(&sk).unwrap();
        let iv = [9u8; 16];
        let ct = c.encrypt(aes_gcm::aead::generic_array::GenericArray::from_slice(&iv), Payload { msg: &plain, aad: b"XYZ" }).unwrap();
        let mut et = b"XYZ".to_vec();
        et.extend_from_slice(&iv);
        et.extend_from_slice(&ct);
        let v = decrypt_gcm(&sk, &et).unwrap();
        assert_eq!(s(dict(dict(&v, "t").unwrap(), super::super::XCODE_APP_ID).unwrap(), "token"), Some("tok"));
    }
}

/// The id of the trusted phone number to text: the one Apple marks for SMS, else the first.
fn first_phone_id(v: &serde_json::Value) -> Option<u64> {
    let phones = v.get("trustedPhoneNumbers").and_then(|p| p.as_array())?;
    let pick = phones.iter().find(|p| p.get("pushMode").and_then(|m| m.as_str()) == Some("sms")).or_else(|| phones.first())?;
    pick.get("id").and_then(|i| i.as_u64())
}

#[cfg(test)]
mod sms_tests {
    #[test]
    fn picks_the_sms_phone() {
        let v = serde_json::json!({ "trustedPhoneNumbers": [ { "id": 3, "pushMode": "voice" }, { "id": 7, "pushMode": "sms" } ] });
        assert_eq!(super::first_phone_id(&v), Some(7));
        assert_eq!(super::first_phone_id(&serde_json::json!({ "trustedPhoneNumbers": [ { "id": 2 } ] })), Some(2));
        assert_eq!(super::first_phone_id(&serde_json::json!({})), None);
    }
}

#[cfg(test)]
mod step_tests {
    use super::*;

    #[test]
    fn a_409_without_au_waits_for_the_code_apple_pushed() {
        assert_eq!(next_step(409, None), Step::CodeAlreadySent);
        assert_eq!(next_step(200, None), Step::SignedIn);
        assert_eq!(next_step(0, None), Step::SignedIn);
        assert_eq!(next_step(409, Some("trustedDeviceSecondaryAuth")), Step::AskForCode);
        assert_eq!(next_step(409, Some("secondaryAuth")), Step::AskForCode);
        assert_eq!(next_step(409, Some("repair")), Step::Repair);
        assert_eq!(next_step(409, Some("somethingNew")), Step::Unsupported("somethingNew"));
    }

    fn answer(d: plist::Dictionary) -> Vec<u8> {
        let mut out = Vec::new();
        plist::to_writer_xml(&mut out, &plist::Value::Dictionary(d)).unwrap();
        out
    }

    #[test]
    fn a_device_code_counts_only_with_an_explicit_ec_0() {
        let mut ok = plist::Dictionary::new();
        ok.insert("ec".into(), 0.into());
        assert!(device_code_answer(200, &answer(ok.clone())).is_ok());
        let mut nested = plist::Dictionary::new();
        nested.insert("Status".into(), plist::Value::Dictionary(ok.clone()));
        assert!(device_code_answer(200, &answer(nested)).is_ok());
        assert!(device_code_answer(503, &answer(ok)).is_err());
        assert!(device_code_answer(200, b"<html>Service Unavailable</html>").is_err());
        assert!(device_code_answer(200, &answer(plist::Dictionary::new())).is_err());
        let mut wrong = plist::Dictionary::new();
        wrong.insert("ec".into(), (-21669).into());
        assert!(matches!(device_code_answer(400, &answer(wrong)), Err(Error::NeedsPerson(_))));
        assert!(is_rate_limit(&device_code_answer(429, b"").unwrap_err()));
    }

    #[test]
    fn a_texted_code_reports_why_it_was_turned_away() {
        assert!(sms_code_answer(200).is_ok());
        assert!(is_rate_limit(&sms_code_answer(429).unwrap_err()));
        assert!(sms_code_answer(403).unwrap_err().to_string().contains("Get Verification Code"));
        assert!(sms_code_answer(400).unwrap_err().to_string().contains("not right"));
    }
}

#[cfg(test)]
mod rate_limit_regressions {
    use super::*;
    use crate::apple::anisette::Source;
    use crate::apple::store;
    use crate::setup::Signer;
    use std::collections::HashMap;
    use std::sync::{Arc, Mutex};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[derive(Clone, Default)]
    struct Counts {
        srp_init: usize,
        srp_complete: usize,
        apptokens: usize,
        trusted_device_push: usize,
        sms_auth_info: usize,
        sms_send: usize,
        sms_send_with_slash: usize,
        device_validate: usize,
        sms_validate: usize,
    }

    #[derive(Clone)]
    struct MockBehavior {
        apple_id: String,
        password: String,
        hsc: i64,
        au: Option<String>,
        include_session_keys_on_409: bool,
        trusted_device_status: u16,
        sms_auth_status: u16,
        sms_send_status: u16,
        accepted_code: String,
        apptokens_status: u16,
        apptokens_ec: i64,
    }

    impl Default for MockBehavior {
        fn default() -> Self {
            Self {
                apple_id: "person@example.com".into(),
                password: "correct-horse-battery".into(),
                hsc: 409,
                au: Some("trustedDeviceSecondaryAuth".into()),
                include_session_keys_on_409: true,
                trusted_device_status: 200,
                sms_auth_status: 200,
                sms_send_status: 200,
                accepted_code: "654321".into(),
                apptokens_status: 200,
                apptokens_ec: 0,
            }
        }
    }

    struct MockGsa {
        base_url: String,
        counts: Arc<Mutex<Counts>>,
        _behavior: Arc<Mutex<MockBehavior>>,
    }

    fn plist_xml(d: plist::Dictionary) -> Vec<u8> {
        let mut out = Vec::new();
        plist::to_writer_xml(&mut out, &plist::Value::Dictionary(d)).unwrap();
        out
    }

    fn gs_response(mut resp: plist::Dictionary, ec: i64, hsc: i64, au: Option<&str>) -> Vec<u8> {
        let mut st = plist::Dictionary::new();
        st.insert("ec".into(), ec.into());
        st.insert("hsc".into(), hsc.into());
        if let Some(au) = au {
            st.insert("au".into(), au.into());
        }
        resp.insert("Status".into(), plist::Value::Dictionary(st));
        let mut root = plist::Dictionary::new();
        root.insert("Response".into(), plist::Value::Dictionary(resp));
        plist_xml(root)
    }

    fn encrypt_spd_for_test(srp_key: &[u8], include_keys: bool) -> Vec<u8> {
        use aes::cipher::{BlockEncryptMut, KeyIvInit};
        let mut spd = plist::Dictionary::new();
        spd.insert("adsid".into(), "000123-abc".into());
        spd.insert("GsIdmsToken".into(), "idms-tok-1".into());
        spd.insert("fn".into(), "Test".into());
        spd.insert("ln".into(), "Person".into());
        if include_keys {
            spd.insert("sk".into(), plist::Value::Data(vec![7u8; 32]));
            spd.insert("c".into(), plist::Value::Data(b"cookie-bytes".to_vec()));
        }
        let plain = plist_xml(spd);
        let mut mac = <HmacSha256 as Mac>::new_from_slice(srp_key).unwrap();
        mac.update(b"extra data key:");
        let k = mac.finalize().into_bytes();
        let mut mac = <HmacSha256 as Mac>::new_from_slice(srp_key).unwrap();
        mac.update(b"extra data iv:");
        let iv = mac.finalize().into_bytes();
        let enc = cbc::Encryptor::<aes::Aes256>::new_from_slices(&k, &iv[..16]).unwrap();
        enc.encrypt_padded_vec_mut::<aes::cipher::block_padding::Pkcs7>(&plain)
    }

    fn encrypt_apptoken_for_test(sk: &[u8]) -> Vec<u8> {
        use aes_gcm::aead::generic_array::typenum::U16;
        let mut app = plist::Dictionary::new();
        app.insert("token".into(), "xcode-auth-token-ok".into());
        let future_ms = (time::OffsetDateTime::now_utc().unix_timestamp() + 7200) * 1000;
        app.insert("expiry".into(), plist::Value::Integer(future_ms.into()));
        let mut t = plist::Dictionary::new();
        t.insert(super::super::XCODE_APP_ID.into(), plist::Value::Dictionary(app));
        let mut root = plist::Dictionary::new();
        root.insert("t".into(), plist::Value::Dictionary(t));
        let plain = plist_xml(root);
        let cipher = aes_gcm::AesGcm::<aes::Aes256, U16>::new_from_slice(sk).unwrap();
        let iv = [5u8; 16];
        let ct = cipher.encrypt(aes_gcm::aead::generic_array::GenericArray::from_slice(&iv), Payload { msg: &plain, aad: b"XYZ" }).unwrap();
        let mut et = b"XYZ".to_vec();
        et.extend_from_slice(&iv);
        et.extend_from_slice(&ct);
        et
    }

    async fn start_mock_gsa(initial: MockBehavior) -> MockGsa {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let counts = Arc::new(Mutex::new(Counts::default()));
        let behavior = Arc::new(Mutex::new(initial));
        let last_a_pub: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));

        let counts_bg = counts.clone();
        let behavior_bg = behavior.clone();
        let last_a_bg = last_a_pub.clone();
        tokio::spawn(async move {
            while let Ok((mut stream, _)) = listener.accept().await {
                let counts = counts_bg.clone();
                let behavior = behavior_bg.clone();
                let last_a = last_a_bg.clone();
                tokio::spawn(async move {
                    let mut buf = Vec::new();
                    let mut tmp = [0u8; 4096];
                    let header_end = loop {
                        let n = match stream.read(&mut tmp).await {
                            Ok(0) | Err(_) => return,
                            Ok(n) => n,
                        };
                        buf.extend_from_slice(&tmp[..n]);
                        if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                            break pos + 4;
                        }
                    };
                    let head = String::from_utf8_lossy(&buf[..header_end]).to_string();
                    let mut lines = head.lines();
                    let req_line = lines.next().unwrap_or("");
                    let mut parts = req_line.split_whitespace();
                    let method = parts.next().unwrap_or("");
                    let path = parts.next().unwrap_or("");
                    let mut headers = HashMap::new();
                    for line in lines {
                        if let Some((k, v)) = line.split_once(':') {
                            headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
                        }
                    }
                    let content_len: usize = headers.get("content-length").and_then(|s| s.parse().ok()).unwrap_or(0);
                    while buf.len() < header_end + content_len {
                        let n = match stream.read(&mut tmp).await {
                            Ok(0) | Err(_) => break,
                            Ok(n) => n,
                        };
                        buf.extend_from_slice(&tmp[..n]);
                    }
                    let body = &buf[header_end..buf.len().min(header_end + content_len)];

                    let (status, content_type, resp_body) = {
                        let b = behavior.lock().unwrap().clone();
                        match (method, path) {
                            ("POST", "/grandslam/GsService2") => {
                                let root: plist::Value = plist::from_bytes(body).unwrap();
                                let req = dict(&root, "Request").unwrap();
                                let op = s(req, "o").unwrap_or("");
                                let srp_srv = srp::TestServer::new(&b.apple_id, &b.password);
                                match op {
                                    "init" => {
                                        counts.lock().unwrap().srp_init += 1;
                                        *last_a.lock().unwrap() = data(req, "A2k").unwrap().to_vec();
                                        let mut r = plist::Dictionary::new();
                                        r.insert("sp".into(), "s2k".into());
                                        r.insert("s".into(), plist::Value::Data(srp_srv.salt));
                                        r.insert("i".into(), plist::Value::Integer((srp_srv.iterations as i64).into()));
                                        r.insert("B".into(), plist::Value::Data(srp_srv.b_pub));
                                        r.insert("c".into(), "srv-c".into());
                                        (200u16, "text/x-xml-plist", gs_response(r, 0, 200, None))
                                    }
                                    "complete" => {
                                        counts.lock().unwrap().srp_complete += 1;
                                        let a_pub = last_a.lock().unwrap().clone();
                                        let m1 = data(req, "M1").unwrap();
                                        if let Some((key, m2)) = srp_srv.verify_and_m2(&a_pub, m1) {
                                            let mut r = plist::Dictionary::new();
                                            r.insert("M2".into(), plist::Value::Data(m2));
                                            let include_keys = b.hsc != 409 || b.include_session_keys_on_409;
                                            r.insert("spd".into(), plist::Value::Data(encrypt_spd_for_test(&key, include_keys)));
                                            (200, "text/x-xml-plist", gs_response(r, 0, b.hsc, b.au.as_deref()))
                                        } else {
                                            (200, "text/x-xml-plist", gs_response(plist::Dictionary::new(), -22406, 200, None))
                                        }
                                    }
                                    "apptokens" => {
                                        counts.lock().unwrap().apptokens += 1;
                                        if b.apptokens_status != 200 {
                                            (b.apptokens_status, "text/plain", b"rate limited".to_vec())
                                        } else if b.apptokens_ec != 0 {
                                            (200, "text/x-xml-plist", gs_response(plist::Dictionary::new(), b.apptokens_ec, 200, None))
                                        } else {
                                            let mut r = plist::Dictionary::new();
                                            r.insert("et".into(), plist::Value::Data(encrypt_apptoken_for_test(&[7u8; 32])));
                                            (200, "text/x-xml-plist", gs_response(r, 0, 200, None))
                                        }
                                    }
                                    _ => (400, "text/plain", b"bad op".to_vec()),
                                }
                            }
                            ("GET", "/auth/verify/trusteddevice") => {
                                counts.lock().unwrap().trusted_device_push += 1;
                                let mut d = plist::Dictionary::new();
                                d.insert("ec".into(), 0.into());
                                (b.trusted_device_status, "text/x-xml-plist", plist_xml(d))
                            }
                            ("GET", "/auth") => {
                                counts.lock().unwrap().sms_auth_info += 1;
                                let j = serde_json::json!({ "trustedPhoneNumbers": [{ "id": 1, "pushMode": "sms" }] });
                                (b.sms_auth_status, "application/json", j.to_string().into_bytes())
                            }
                            ("PUT" | "POST", "/auth/verify/phone/") => {
                                let mut c = counts.lock().unwrap();
                                c.sms_send += 1;
                                c.sms_send_with_slash += 1;
                                if method == "PUT" {
                                    (405, "application/json", b"{}".to_vec())
                                } else {
                                    (b.sms_send_status, "application/json", b"{}".to_vec())
                                }
                            }
                            ("PUT", "/auth/verify/phone") => {
                                counts.lock().unwrap().sms_send += 1;
                                (b.sms_send_status, "application/json", b"{}".to_vec())
                            }
                            ("GET", "/grandslam/GsService2/validate") => {
                                counts.lock().unwrap().device_validate += 1;
                                let code = headers.get("security-code").cloned().unwrap_or_default();
                                let mut d = plist::Dictionary::new();
                                if code == b.accepted_code {
                                    d.insert("ec".into(), 0.into());
                                    (200, "text/x-xml-plist", plist_xml(d))
                                } else {
                                    d.insert("ec".into(), (-21669).into());
                                    d.insert("em".into(), "Incorrect verification code.".into());
                                    (400, "text/x-xml-plist", plist_xml(d))
                                }
                            }
                            ("POST", "/auth/verify/phone/securitycode") => {
                                counts.lock().unwrap().sms_validate += 1;
                                let v: serde_json::Value = serde_json::from_slice(body).unwrap_or_default();
                                let code = v.get("securityCode").and_then(|s| s.get("code")).and_then(|c| c.as_str()).unwrap_or("");
                                if code == b.accepted_code {
                                    (200, "application/json", b"{}".to_vec())
                                } else {
                                    let err = serde_json::json!({
                                        "serviceErrors": [{ "code": "-21669", "title": "Incorrect Code", "message": "Incorrect verification code." }]
                                    });
                                    (400, "application/json", err.to_string().into_bytes())
                                }
                            }
                            _ => (404, "text/plain", b"not found".to_vec()),
                        }
                    };

                    let reason = match status {
                        200 => "OK",
                        201 => "Created",
                        400 => "Bad Request",
                        403 => "Forbidden",
                        405 => "Method Not Allowed",
                        429 => "Too Many Requests",
                        503 => "Service Unavailable",
                        _ => "Error",
                    };
                    let head = format!(
                        "HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        resp_body.len()
                    );
                    let _ = stream.write_all(head.as_bytes()).await;
                    let _ = stream.write_all(&resp_body).await;
                });
            }
        });

        MockGsa { base_url: format!("http://{addr}"), counts, _behavior: behavior }
    }

    fn test_client(base_url: &str) -> Client {
        let headers = Anisette {
            map: HashMap::from([
                ("X-Apple-I-MD".into(), "otp-1".into()),
                ("X-Apple-I-MD-M".into(), "mid-1".into()),
                ("X-Apple-I-MD-LU".into(), "lu-1".into()),
                ("X-Apple-I-MD-RINFO".into(), "17106176".into()),
                ("X-Mme-Device-Id".into(), "DEV-1".into()),
                ("X-Mme-Client-Info".into(), "<Mac15,7> <macOS;27.0;26A5378j> <com.apple.AuthKit/1 (com.apple.akd/1.0)>".into()),
                ("User-Agent".into(), "akd/1.0 CFNetwork/811.5.4".into()),
                ("X-Apple-I-Client-Time".into(), "2026-11-17T08:00:00Z".into()),
                ("X-Apple-Locale".into(), "en_US".into()),
                ("X-Apple-I-TimeZone".into(), "UTC".into()),
            ]),
            made_at: std::time::Instant::now(),
        };
        let provider = Provider::for_test(Source::Remote { url: "https://new.ani.sidestore.io".into() }, headers);
        Client::with_endpoints(provider, Endpoints::local(base_url)).unwrap()
    }

    fn run_in_vault<F: std::future::Future<Output = ()>>(f: F) {
        let vault = Arc::new(crate::vault::memory::Memory::default());
        store::with_test_vault(vault, || {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap();
            rt.block_on(f);
        });
    }

    #[test]
    fn one_code_per_sign_in_without_cross_channel_fallback() {
        run_in_vault(async {
            // 1) trustedDeviceSecondaryAuth failure must NOT fall back to SMS and request a second code.
            let mock = start_mock_gsa(MockBehavior {
                trusted_device_status: 500,
                ..MockBehavior::default()
            })
            .await;
            let mut client = test_client(&mock.base_url);
            let res = client.sign_in("person@example.com", "correct-horse-battery").await;
            assert!(res.is_err(), "failed trusted-device push must report error rather than silently texting");
            let c = mock.counts.lock().unwrap().clone();
            assert_eq!(c.trusted_device_push, 1, "at most 1 trusted-device code request");
            assert_eq!(c.sms_auth_info + c.sms_send, 0, "must never fall back to SMS after trusted-device failure");

            // 2) secondaryAuth must request SMS directly without hitting trusteddevice or trailing-slash PUT+POST.
            let mock_sms = start_mock_gsa(MockBehavior {
                au: Some("secondaryAuth".into()),
                ..MockBehavior::default()
            })
            .await;
            let mut client_sms = test_client(&mock_sms.base_url);
            let out = client_sms.sign_in("person@example.com", "correct-horse-battery").await.unwrap();
            assert!(matches!(out, Outcome::NeedsCode(ref p) if p.via == Factor::Sms));
            let c_sms = mock_sms.counts.lock().unwrap().clone();
            assert_eq!(c_sms.trusted_device_push, 0, "secondaryAuth must not request a trusted-device push first");
            assert_eq!(c_sms.sms_send_with_slash, 0, "SMS endpoint must not use trailing slash");
            assert_eq!(c_sms.sms_send, 1, "secondaryAuth must send exactly 1 SMS request");
        });
    }

    #[test]
    fn no_new_code_request_before_user_enters_code() {
        run_in_vault(async {
            let mock = start_mock_gsa(MockBehavior {
                apptokens_ec: -22406,
                ..MockBehavior::default()
            })
            .await;
            let mut signer = Signer::for_test(test_client(&mock.base_url)).unwrap();
            signer.account.session = Some(Session {
                apple_id: "person@example.com".into(),
                adsid: "000123-abc".into(),
                gs_idms_token: "expired-tok".into(),
                first_name: "Test".into(),
                last_name: "Person".into(),
                sk: vec![7u8; 32],
                c: b"cookie-bytes".to_vec(),
            });
            signer.account.password = Some("correct-horse-battery".into());
            store::save(&signer.account).unwrap();

            let p1 = signer.sign_in("person@example.com", "correct-horse-battery", true).await.unwrap().expect("needs code");
            assert_eq!(mock.counts.lock().unwrap().srp_complete, 1);
            assert_eq!(mock.counts.lock().unwrap().trusted_device_push, 1);

            // Retrying sign_in or background token() before the code is entered must reuse the pending session.
            let p2 = signer.sign_in("person@example.com", "correct-horse-battery", true).await.unwrap().expect("reused pending");
            assert_eq!(p1.session.gs_idms_token, p2.session.gs_idms_token);
            let tok_err = signer.token().await.unwrap_err();
            assert!(matches!(tok_err, Error::NeedsCode(_)), "background token() while waiting for code must return NeedsCode without re-signing in");
            assert_eq!(mock.counts.lock().unwrap().srp_complete, 1, "must not run SRP again while waiting for code");
            assert_eq!(mock.counts.lock().unwrap().trusted_device_push, 1, "must not ask Apple for another code while waiting");
        });
    }

    #[test]
    fn verified_code_uses_session_directly_without_second_sign_in() {
        run_in_vault(async {
            let mock = start_mock_gsa(MockBehavior::default()).await;
            let mut signer = Signer::for_test(test_client(&mock.base_url)).unwrap();
            let pending = signer.sign_in("person@example.com", "correct-horse-battery", true).await.unwrap().expect("needs code");
            assert_eq!(mock.counts.lock().unwrap().srp_complete, 1);
            assert_eq!(mock.counts.lock().unwrap().trusted_device_push, 1);

            signer.finish_sign_in(pending, "654321").await.unwrap();
            let c = mock.counts.lock().unwrap().clone();
            assert_eq!(c.device_validate, 1, "validated code once");
            assert_eq!(c.srp_complete, 1, "must use the session directly and NOT call sign_in_once a second time");
            assert_eq!(c.trusted_device_push, 1, "total codes requested in one sign-in must be 1");

            let token = signer.token().await.unwrap();
            assert_eq!(token.token, "xcode-auth-token-ok");
        });
    }

    #[test]
    fn keyless_409_session_never_requests_second_code_after_validation() {
        run_in_vault(async {
            let mock = start_mock_gsa(MockBehavior {
                include_session_keys_on_409: false,
                ..MockBehavior::default()
            })
            .await;
            let mut signer = Signer::for_test(test_client(&mock.base_url)).unwrap();
            let pending = signer.sign_in("person@example.com", "correct-horse-battery", true).await.unwrap().expect("needs code");
            assert_eq!(mock.counts.lock().unwrap().trusted_device_push, 1);

            // Even when the initial 409 omitted sk/c and the server answers 409 again on exchange,
            // Poki must NEVER call trusted_device_push or sms_send a second time.
            let _ = signer.finish_sign_in(pending, "654321").await;
            let c = mock.counts.lock().unwrap().clone();
            assert_eq!(c.trusted_device_push, 1, "must never ask for a second device push after code validation");
            assert_eq!(c.sms_auth_info + c.sms_send, 0, "must never ask for an SMS code after code validation");
        });
    }

    #[test]
    fn wrong_code_reuses_same_pending_session_and_warns_after_two_failures() {
        run_in_vault(async {
            let mock = start_mock_gsa(MockBehavior {
                au: Some("secondaryAuth".into()),
                ..MockBehavior::default()
            })
            .await;
            let mut signer = Signer::for_test(test_client(&mock.base_url)).unwrap();
            let pending = signer.sign_in("person@example.com", "correct-horse-battery", true).await.unwrap().expect("needs code");
            assert_eq!(mock.counts.lock().unwrap().sms_send, 1);

            // 1st wrong code: no new sign-in, no double-hit on device_validate, tells user to enter newest code.
            let e1 = signer.finish_sign_in(pending.clone(), "000000").await.unwrap_err().to_string();
            assert!(e1.to_lowercase().contains("newest") || e1.to_lowercase().contains("latest"), "expected newest-code hint, got: {e1}");
            assert_eq!(mock.counts.lock().unwrap().device_validate, 0, "wrong SMS code must not also hit device validate");
            assert_eq!(mock.counts.lock().unwrap().srp_complete, 1);
            assert_eq!(mock.counts.lock().unwrap().sms_send, 1);

            // 2nd wrong code: warns user to pause and wait a few minutes to avoid account lockout.
            let e2 = signer.finish_sign_in(pending.clone(), "111111").await.unwrap_err().to_string();
            assert!(e2.to_lowercase().contains("wait") && e2.to_lowercase().contains("lock"), "expected wait/lock warning after 2 failures, got: {e2}");
            assert_eq!(mock.counts.lock().unwrap().srp_complete, 1);
            assert_eq!(mock.counts.lock().unwrap().sms_send, 1);

            // Right code on the same pending session succeeds without ever requesting another code.
            signer.finish_sign_in(pending, "654321").await.unwrap();
            assert_eq!(mock.counts.lock().unwrap().srp_complete, 1);
            assert_eq!(mock.counts.lock().unwrap().sms_send, 1);
        });
    }

    #[test]
    fn rate_limit_stops_immediately_without_auto_retry() {
        run_in_vault(async {
            let mock = start_mock_gsa(MockBehavior {
                apptokens_status: 429,
                ..MockBehavior::default()
            })
            .await;
            let mut signer = Signer::for_test(test_client(&mock.base_url)).unwrap();
            signer.account.session = Some(Session {
                apple_id: "person@example.com".into(),
                adsid: "000123-abc".into(),
                gs_idms_token: "valid-tok".into(),
                first_name: "Test".into(),
                last_name: "Person".into(),
                sk: vec![7u8; 32],
                c: b"cookie-bytes".to_vec(),
            });
            signer.account.password = Some("correct-horse-battery".into());
            store::save(&signer.account).unwrap();

            // When xcode_token returns HTTP 429, Signer::token() must stop immediately and NOT fall back to sign_in!
            let err = signer.token().await.unwrap_err();
            assert!(is_rate_limit(&err), "expected rate-limit error, got: {err}");
            let c = mock.counts.lock().unwrap().clone();
            assert_eq!(c.apptokens, 1);
            assert_eq!(c.srp_init + c.srp_complete + c.trusted_device_push, 0, "rate limit on apptokens must never trigger sign_in or ask for a code");

            // Immediate retry during cooldown must also stop before sending any new HTTP request to Apple.
            let err2 = signer.sign_in("person@example.com", "correct-horse-battery", true).await.unwrap_err();
            assert!(is_rate_limit(&err2), "expected cooldown to block immediate retry, got: {err2}");
            let c2 = mock.counts.lock().unwrap().clone();
            assert_eq!(c2.apptokens, 1);
            assert_eq!(c2.srp_init + c2.srp_complete + c2.trusted_device_push, 0);
        });
    }
}
