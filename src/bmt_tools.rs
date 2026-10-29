//! BMT Remote background tools (ScreenConnect's Backstage and Commands).
//!
//! An enrolled, installed BMT Remote waits on remote.bmtech.co.uk for commands
//! a technician queues from the console (process and service lists, event
//! logs, installed software, system info, a command terminal). Each command is
//! a PowerShell or CMD script built by the console; it runs here as SYSTEM with
//! a time limit and the output is posted back. The wait is a long poll the
//! server answers as soon as a command is queued, so tools feel immediate.
//!
//! The machine proves itself with its company token, its ID and its own random
//! agent key (the console trusts the first key it sees and keeps only a hash).

use hbb_common::{
    config::Config,
    log,
    rand::{distributions::Alphanumeric, rngs::OsRng, Rng},
    tokio,
};
use std::time::Duration;

const WAIT_URL: &str = "https://remote.bmtech.co.uk/api/agent/wait";
const RESULT_URL: &str = "https://remote.bmtech.co.uk/api/agent/result";
const OPT_KEY: &str = "bmt-agent-key";
/// Set by bmt_enrol: the enrolment token, and the token this machine enrolled with.
const OPT_TOKEN: &str = "bmt-enrol-token";
const OPT_ENROLLED: &str = "bmt-enrolled-token";
const MAX_OUTPUT: usize = 1_000_000;

struct Command {
    id: i64,
    shell: String,
    script: String,
    timeout: u64,
}

pub fn start() {
    if !crate::platform::is_installed() {
        return;
    }
    let spawned = std::thread::Builder::new()
        .name("bmt-tools".into())
        .spawn(|| {
            let rt = match tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
            {
                Ok(rt) => rt,
                Err(e) => {
                    log::error!("bmt tools: no runtime: {e}");
                    return;
                }
            };
            rt.block_on(run());
        });
    if let Err(e) = spawned {
        log::error!("bmt tools: could not start: {e}");
    }
}

fn agent_key() -> String {
    let key = Config::get_option(OPT_KEY);
    if key.len() >= 32 {
        return key;
    }
    let key: String = OsRng
        .sample_iter(&Alphanumeric)
        .take(48)
        .map(char::from)
        .collect();
    Config::set_option(OPT_KEY.into(), key.clone());
    key
}

async fn run() {
    loop {
        let token = Config::get_option(OPT_TOKEN).trim().to_owned();
        let id = Config::get_id();
        if token.is_empty() || id.is_empty() || Config::get_option(OPT_ENROLLED) != token {
            tokio::time::sleep(Duration::from_secs(30)).await;
            continue;
        }
        match wait(&token, &id).await {
            Ok(Some(cmd)) => {
                let (shell, script, timeout) = (cmd.shell.clone(), cmd.script.clone(), cmd.timeout);
                let outcome =
                    tokio::task::spawn_blocking(move || execute(&shell, &script, timeout)).await;
                let (exit, output, timed_out) = outcome.unwrap_or_else(|e| {
                    (None, format!("BMT Remote could not run this command: {e}"), false)
                });
                if let Err(e) = report(&token, &id, cmd.id, exit, &output, timed_out).await {
                    log::warn!("bmt tools: result for {} not sent: {e}", cmd.id);
                }
            }
            Ok(None) => {}
            Err(e) => {
                hbb_common::throttled_log!(Duration::from_secs(600), warn, "bmt tools: {e}");
                tokio::time::sleep(Duration::from_secs(30)).await;
            }
        }
    }
}

fn credentials(token: &str, id: &str) -> serde_json::Value {
    serde_json::json!({ "token": token, "id": id, "key": agent_key() })
}

async fn wait(token: &str, id: &str) -> Result<Option<Command>, String> {
    let (status, body) = crate::common::post_request_with_status(
        WAIT_URL.into(),
        credentials(token, id).to_string(),
        "Content-Type: application/json",
    )
    .await
    .map_err(|e| e.to_string())?;
    match status {
        204 => Ok(None),
        200 => {
            let v: serde_json::Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
            let c = &v["cmd"];
            match (c["id"].as_i64(), c["script"].as_str()) {
                (Some(id), Some(script)) => Ok(Some(Command {
                    id,
                    shell: c["shell"].as_str().unwrap_or("powershell").to_owned(),
                    script: script.to_owned(),
                    timeout: c["timeout"].as_u64().unwrap_or(120).clamp(5, 900),
                })),
                _ => Ok(None),
            }
        }
        s => Err(format!("wait returned {s}")),
    }
}

async fn report(
    token: &str,
    id: &str,
    cmd: i64,
    exit: Option<i32>,
    output: &str,
    timed_out: bool,
) -> Result<(), String> {
    let mut body = credentials(token, id);
    body["cmd"] = cmd.into();
    body["exit"] = exit.into();
    body["output"] = output.into();
    body["timedOut"] = timed_out.into();
    match crate::common::post_request_with_status(
        RESULT_URL.into(),
        body.to_string(),
        "Content-Type: application/json",
    )
    .await
    .map_err(|e| e.to_string())?
    .0
    {
        204 | 200 => Ok(()),
        s => Err(format!("result returned {s}")),
    }
}

/// Runs one script as this service's user (SYSTEM) and returns the exit code,
/// the combined output and whether it was stopped for running too long.
fn execute(shell: &str, script: &str, timeout: u64) -> (Option<i32>, String, bool) {
    use std::{io::Read, os::windows::process::CommandExt, process::Stdio};
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let base = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into());
    let nonce: String = OsRng
        .sample_iter(&Alphanumeric)
        .take(12)
        .map(char::from)
        .collect();
    let (ext, text) = if shell == "cmd" {
        ("cmd", format!("@echo off\r\n{}\r\n", script.replace('\n', "\r\n")))
    } else {
        (
            "ps1",
            format!("[Console]::OutputEncoding = [Text.Encoding]::UTF8\n{script}\n"),
        )
    };
    let file = std::path::Path::new(&base)
        .join("Temp")
        .join(format!("bmt-tool-{nonce}.{ext}"));
    // A BOM so Windows PowerShell 5 reads the script as UTF-8.
    let bytes = if ext == "ps1" {
        [&[0xEF, 0xBB, 0xBF][..], text.as_bytes()].concat()
    } else {
        text.into_bytes()
    };
    if let Err(e) = std::fs::write(&file, bytes) {
        return (None, format!("BMT Remote could not write the script: {e}"), false);
    }

    let mut command = if ext == "cmd" {
        let mut c = std::process::Command::new("cmd.exe");
        c.arg("/d").arg("/c").arg(&file);
        c
    } else {
        let mut c = std::process::Command::new("powershell.exe");
        c.args(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"])
            .arg(&file);
        c
    };
    let spawned = command
        .current_dir(&base)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .creation_flags(CREATE_NO_WINDOW)
        .spawn();
    let mut child = match spawned {
        Ok(c) => c,
        Err(e) => {
            std::fs::remove_file(&file).ok();
            return (None, format!("BMT Remote could not start {shell}: {e}"), false);
        }
    };
    let pipe = |r: Option<Box<dyn Read + Send>>| {
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            if let Some(mut r) = r {
                r.by_ref().take(MAX_OUTPUT as u64 + 1).read_to_end(&mut buf).ok();
            }
            buf
        })
    };
    let out = pipe(child.stdout.take().map(|s| Box::new(s) as Box<dyn Read + Send>));
    let err = pipe(child.stderr.take().map(|s| Box::new(s) as Box<dyn Read + Send>));

    let deadline = std::time::Instant::now() + Duration::from_secs(timeout);
    let mut timed_out = false;
    let exit = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status.code(),
            Ok(None) if std::time::Instant::now() >= deadline => {
                timed_out = true;
                // The whole tree, so a script's own children don't keep running.
                std::process::Command::new("taskkill")
                    .args(["/T", "/F", "/PID", &child.id().to_string()])
                    .creation_flags(CREATE_NO_WINDOW)
                    .status()
                    .ok();
                child.kill().ok();
                break child.wait().ok().and_then(|s| s.code());
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(100)),
            Err(e) => {
                log::warn!("bmt tools: waiting for the script failed: {e}");
                break None;
            }
        }
    };
    let stdout = out.join().unwrap_or_default();
    let stderr = err.join().unwrap_or_default();
    std::fs::remove_file(&file).ok();

    let mut output = String::from_utf8_lossy(&stdout).into_owned();
    let stderr = String::from_utf8_lossy(&stderr);
    if !stderr.trim().is_empty() {
        if !output.is_empty() && !output.ends_with('\n') {
            output.push('\n');
        }
        output.push_str(&stderr);
    }
    if output.len() > MAX_OUTPUT {
        let mut cut = MAX_OUTPUT;
        while !output.is_char_boundary(cut) {
            cut -= 1;
        }
        output.truncate(cut);
        output.push_str("\n[output cut at 1 MB]");
    }
    if timed_out {
        output.push_str(&format!("\n[stopped after {timeout} seconds]"));
    }
    (exit, output, timed_out)
}
