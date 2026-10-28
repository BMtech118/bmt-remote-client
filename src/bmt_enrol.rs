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
//!
//! The same service also runs support sessions where the customer accepted
//! at the start: the session download, run as administrator, installs BMT
//! Remote and sets `bmt-session-code`. The service then takes a random access
//! password, sends it with its session check-in so the technician connects
//! without a prompt (also after a restart), and uninstalls itself when the
//! technician ends the session.

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

const CHECKIN_URL: &str = "https://remote.bmtech.co.uk/api/checkin";
/// Set by the session download after it installs BMT Remote for a session.
pub const OPT_SESSION: &str = "bmt-session-code";
/// The session code whose access password the server has.
const OPT_SESSION_REPORTED: &str = "bmt-session-reported";

/// Where the session download leaves the session code for the service.
#[cfg(windows)]
fn session_file() -> std::path::PathBuf {
    let base = std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".into());
    std::path::Path::new(&base)
        .join(crate::get_app_name())
        .join("bmt-session-code")
}

#[cfg(windows)]
pub fn write_session_file(code: &str) -> Result<(), String> {
    let path = session_file();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    std::fs::write(&path, code).map_err(|e| e.to_string())
}

/// A session code left by the session download, taken once.
fn take_session_file() -> Option<String> {
    #[cfg(windows)]
    {
        let path = session_file();
        let code = std::fs::read_to_string(&path).ok()?.trim().to_uppercase();
        std::fs::remove_file(&path).ok();
        if code.len() == 6 {
            return Some(code);
        }
    }
    None
}

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
        if let Some(code) = take_session_file() {
            Config::set_option(OPT_SESSION.into(), code);
        }
        let code = Config::get_option(OPT_SESSION);
        let mut wait = 60;
        if !code.trim().is_empty() {
            match session_tick(code.trim()).await {
                Ok(()) => {}
                Err(e) => {
                    log::warn!("bmt session: {e}");
                    // Not reported yet (just installed, or the network is still
                    // coming up after a restart): try again soon.
                    wait = 10;
                }
            }
        }
        tokio::time::sleep(Duration::from_secs(wait)).await;
    }
}

/// One support-session check-in. The first one after install sends the
/// access password; later ones are the heartbeat the console shows as
/// "Ready to connect".
async fn session_tick(code: &str) -> Result<(), String> {
    let id = Config::get_id();
    if id.is_empty() {
        return Err("no ID yet".into());
    }
    let mut body = serde_json::json!({ "code": code, "id": id, "hb": 1 });
    let reporting = Config::get_option(OPT_SESSION_REPORTED) != code;
    if reporting {
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
        body["password"] = password.into();
    }
    let (status, reply) = crate::common::post_request_with_status(
        CHECKIN_URL.into(),
        body.to_string(),
        "Content-Type: application/json",
    )
    .await
    .map_err(|e| e.to_string())?;
    match status {
        200 => {
            open_chat_if_new(&reply);
            if reporting {
                Config::set_option(OPT_SESSION_REPORTED.into(), code.into());
                log::info!("bmt session: {code} ready on {id}");
            }
            Ok(())
        }
        // The technician ended the session (or it expired): remove BMT Remote.
        404 | 410 => {
            log::info!("bmt session: {code} ended, uninstalling");
            end_session();
            Ok(())
        }
        s => Err(format!("check-in returned {s}")),
    }
}

/// Uninstalls BMT Remote after a support session. The uninstall stops this
/// service, so it runs as its own detached process.
fn end_session() {
    Config::set_option(OPT_SESSION.into(), "".into());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const DETACHED_PROCESS: u32 = 0x0000_0008;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
        const CREATE_BREAKAWAY_FROM_JOB: u32 = 0x0100_0000;
        match std::env::current_exe() {
            Ok(exe) => {
                if let Err(e) = std::process::Command::new(exe)
                    .arg("--uninstall")
                    .creation_flags(DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_BREAKAWAY_FROM_JOB)
                    .spawn()
                {
                    log::error!("bmt session: could not start the uninstall: {e}");
                }
            }
            Err(e) => log::error!("bmt session: no exe path: {e}"),
        }
    }
}

async fn tick(token: &str) -> Result<(), String> {
    let id = Config::get_id();
    if id.is_empty() {
        return Ok(());
    }
    let enrolled = Config::get_option(OPT_ENROLLED) == token;
    if enrolled {
        let (status, body) = post(token, &id, None).await?;
        match status {
            200 => {
                open_chat_if_new(&body);
                return Ok(());
            }
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
    match post(token, &id, Some(&password)).await?.0 {
        200 => {
            Config::set_option(OPT_ENROLLED.into(), token.into());
            log::info!("bmt enrol: enrolled {id}");
            Ok(())
        }
        s => Err(format!("enrolment returned {s}")),
    }
}

async fn post(token: &str, id: &str, password: Option<&str>) -> Result<(u16, String), String> {
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
    .map_err(|e| e.to_string())
}

/// The last console message this machine has opened the chat window for.
const OPT_CHAT_SEEN: &str = "bmt-chat-seen";

/// A check-in reply carries the conversation token and the newest technician
/// message id; a newer message opens the chat window for the signed-in user.
fn open_chat_if_new(body: &str) {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(body) else {
        return;
    };
    let (Some(token), Some(last)) = (v["chat"]["t"].as_str(), v["chat"]["last"].as_i64()) else {
        return;
    };
    let seen = Config::get_option(OPT_CHAT_SEEN).parse::<i64>().unwrap_or(0);
    if last <= seen {
        return;
    }
    #[cfg(windows)]
    match crate::platform::run_as_user(vec!["--bmt-chat", token]) {
        Ok(_) => Config::set_option(OPT_CHAT_SEEN.into(), last.to_string()),
        Err(e) => log::warn!("bmt chat: could not open the chat window: {e}"),
    }
}

/// True if this user's chat window is already open, so a second launch quits.
#[cfg(windows)]
pub fn chat_window_running() -> bool {
    use std::os::windows::ffi::OsStrExt;
    let name: Vec<u16> = std::ffi::OsStr::new("Local\\BMTRemoteChat")
        .encode_wide()
        .chain(Some(0))
        .collect();
    // The handle is deliberately kept for the life of the chat window.
    let handle = unsafe { winapi::um::synchapi::CreateMutexW(std::ptr::null_mut(), 0, name.as_ptr()) };
    !handle.is_null() && std::io::Error::last_os_error().raw_os_error() == Some(183)
}
