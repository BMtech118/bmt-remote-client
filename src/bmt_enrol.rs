//! BMT Remote unattended access (ScreenConnect "Access" style).
//!
//! An installed BMT Remote is enrolled with a company's token, set by the
//! installer or NinjaOne as `--option bmt-enrol-token <TOKEN>`. The service
//! then gives itself a strong random permanent password, accepts connections by
//! password only (no Accept prompt; nobody may be at the machine), and reports
//! the password once to remote.bmtech.co.uk, which stores it encrypted for the
//! technician console. After that it checks in every minute so the console can
//! show the machine online. If the server no longer knows the machine (removed
//! from the console, or a new token), a fresh password is made and reported.
//!
//! Runs only in the installed service.

use hbb_common::{
    config::Config,
    log,
    rand::{distributions::Alphanumeric, rngs::OsRng, Rng},
    tokio,
};
use std::time::Duration;

const ENROL_URL: &str = "https://remote.bmtech.co.uk/api/enrol";
const OPT_TOKEN: &str = "bmt-enrol-token";
/// The token this machine last enrolled with; a different token re-enrols.
const OPT_ENROLLED: &str = "bmt-enrolled-token";

pub fn start() {
    if !crate::platform::is_installed() {
        return;
    }
    std::thread::spawn(|| {
        let rt = match tokio::runtime::Builder::new_current_thread().enable_all().build() {
            Ok(rt) => rt,
            Err(e) => {
                log::error!("bmt enrol: no runtime: {e}");
                return;
            }
        };
        rt.block_on(run());
    });
}

async fn run() {
    loop {
        let token = Config::get_option(OPT_TOKEN);
        if !token.trim().is_empty() {
            if let Err(e) = tick(token.trim()).await {
                log::warn!("bmt enrol: {e}");
            }
        }
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

async fn tick(token: &str) -> Result<(), String> {
    let id = Config::get_id();
    if id.is_empty() {
        return Ok(());
    }
    let enrolled = Config::get_option(OPT_ENROLLED) == token;
    if enrolled {
        match post(token, &id, None).await? {
            200 => return Ok(()),
            // The console no longer knows this machine: enrol it again.
            404 => {}
            410 | 403 => return Err("enrolment token revoked".into()),
            s => return Err(format!("check-in returned {s}")),
        }
    }
    let password: String = OsRng
        .sample_iter(&Alphanumeric)
        .take(24)
        .map(char::from)
        .collect();
    if !Config::set_permanent_password(&password) {
        return Err("could not set the access password".into());
    }
    Config::set_option("approve-mode".into(), "password".into());
    Config::set_option(
        "verification-method".into(),
        "use-permanent-password".into(),
    );
    match post(token, &id, Some(&password)).await? {
        200 => {
            Config::set_option(OPT_ENROLLED.into(), token.into());
            log::info!("bmt enrol: enrolled {id}");
            Ok(())
        }
        s => Err(format!("enrolment returned {s}")),
    }
}

async fn post(token: &str, id: &str, password: Option<&str>) -> Result<u16, String> {
    let mut body = serde_json::json!({
        "token": token,
        "id": id,
        "hostname": crate::common::hostname(),
        "os": std::env::consts::OS,
        "user": crate::platform::get_active_username(),
        "version": crate::VERSION,
    });
    if let Some(p) = password {
        body["password"] = p.into();
    }
    crate::common::post_request_with_status(
        ENROL_URL.into(),
        body.to_string(),
        "Content-Type: application/json",
    )
    .await
    .map(|(status, _)| status)
    .map_err(|e| e.to_string())
}
