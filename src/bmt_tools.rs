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
const TERM_URL: &str = "wss://remote.bmtech.co.uk/api/agent/term/";
const MAX_OUTPUT: usize = 6_000_000;
/// Agent-side WebSocket frames start with one type byte.
const FRAME_DATA: u8 = 0;
const FRAME_CONTROL: u8 = 1;

struct Command {
    id: i64,
    shell: String,
    script: String,
    timeout: u64,
}

enum Job {
    Command(Command),
    Terminal { sid: String, shell: String, cols: u16, rows: u16 },
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
            Ok(Some(Job::Terminal { sid, shell, cols, rows })) => {
                let (token, id) = (token.clone(), id.clone());
                tokio::spawn(async move {
                    if let Err(e) = terminal(&token, &id, &sid, &shell, cols, rows).await {
                        log::warn!("bmt tools: terminal ended: {e}");
                    }
                });
            }
            Ok(Some(Job::Command(cmd))) => {
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

async fn wait(token: &str, id: &str) -> Result<Option<Job>, String> {
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
            let t = &v["term"];
            if let Some(sid) = t["sid"].as_str() {
                return Ok(Some(Job::Terminal {
                    sid: sid.to_owned(),
                    shell: t["shell"].as_str().unwrap_or("powershell").to_owned(),
                    cols: t["cols"].as_u64().unwrap_or(120).clamp(20, 400) as u16,
                    rows: t["rows"].as_u64().unwrap_or(30).clamp(5, 200) as u16,
                }));
            }
            let c = &v["cmd"];
            match (c["id"].as_i64(), c["script"].as_str()) {
                (Some(id), Some(script)) => Ok(Some(Job::Command(Command {
                    id,
                    shell: c["shell"].as_str().unwrap_or("powershell").to_owned(),
                    script: script.to_owned(),
                    timeout: c["timeout"].as_u64().unwrap_or(120).clamp(5, 900),
                }))),
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
    if shell == "screenshot" {
        return screenshot();
    }

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

/// A live shell for the console: PowerShell or CMD as SYSTEM in a ConPTY,
/// relayed over a WebSocket. Frames carry a type byte (data or JSON control).
async fn terminal(token: &str, id: &str, sid: &str, shell: &str, cols: u16, rows: u16) -> Result<(), String> {
    use hbb_common::{bytes::Bytes, websocket::WsFramedStream};
    use portable_pty::{CommandBuilder, PtySize};
    use std::io::{Read, Write};

    let mut ws = WsFramedStream::new(format!("{TERM_URL}{sid}"), None, None, 15_000)
        .await
        .map_err(|e| e.to_string())?;
    ws.set_raw();
    let hello = [&[FRAME_CONTROL][..], credentials(token, id).to_string().as_bytes()].concat();
    ws.send_bytes(Bytes::from(hello)).await.map_err(|e| e.to_string())?;

    let pair = portable_pty::native_pty_system()
        .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
        .map_err(|e| e.to_string())?;
    let program = if shell == "cmd" { "cmd.exe" } else { "powershell.exe" };
    let mut cmd = CommandBuilder::new(program);
    if program == "powershell.exe" {
        cmd.arg("-NoLogo");
    }
    cmd.cwd(std::env::var("SystemRoot").map(|r| format!("{r}\\System32")).unwrap_or_else(|_| "C:\\Windows\\System32".into()));
    let mut child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    drop(pair.slave);
    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let mut writer = pair.master.take_writer().map_err(|e| e.to_string())?;

    let (out_tx, mut out_rx) = tokio::sync::mpsc::channel::<Vec<u8>>(64);
    std::thread::spawn(move || {
        let mut buf = [0u8; 16 * 1024];
        loop {
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if out_tx.blocking_send(buf[..n].to_vec()).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let (in_tx, in_rx) = std::sync::mpsc::channel::<Vec<u8>>();
    std::thread::spawn(move || {
        while let Ok(data) = in_rx.recv() {
            if writer.write_all(&data).and_then(|_| writer.flush()).is_err() {
                break;
            }
        }
    });

    log::info!("bmt tools: terminal {sid} opened ({program})");
    loop {
        tokio::select! {
            msg = ws.next() => {
                let Some(Ok(frame)) = msg else { break };
                match frame.first() {
                    Some(&FRAME_DATA) => {
                        if in_tx.send(frame[1..].to_vec()).is_err() {
                            break;
                        }
                    }
                    Some(&FRAME_CONTROL) => {
                        let v: serde_json::Value = serde_json::from_slice(&frame[1..]).unwrap_or_default();
                        if let (Some(c), Some(r)) = (v["r"][0].as_u64(), v["r"][1].as_u64()) {
                            pair.master
                                .resize(PtySize { rows: r.clamp(5, 200) as u16, cols: c.clamp(20, 400) as u16, pixel_width: 0, pixel_height: 0 })
                                .ok();
                        }
                    }
                    _ => {}
                }
            }
            out = out_rx.recv() => {
                match out {
                    Some(data) => {
                        let frame = [&[FRAME_DATA][..], &data].concat();
                        if ws.send_bytes(Bytes::from(frame)).await.is_err() {
                            break;
                        }
                    }
                    None => {
                        let code = child.wait().ok().map(|s| s.exit_code());
                        let bye = [&[FRAME_CONTROL][..], serde_json::json!({ "x": code }).to_string().as_bytes()].concat();
                        ws.send_bytes(Bytes::from(bye)).await.ok();
                        break;
                    }
                }
            }
        }
    }
    child.kill().ok();
    log::info!("bmt tools: terminal {sid} closed");
    Ok(())
}

/// Screenshot tool: the service can't see the user's desktop from session 0,
/// so it starts `BMT-Remote.exe --bmt-screenshot <base>` in the signed-in
/// session and returns the JPEGs it writes as base64 JSON.
fn screenshot() -> (Option<i32>, String, bool) {
    let base_dir = std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into());
    let nonce: String = OsRng.sample_iter(&Alphanumeric).take(12).map(char::from).collect();
    let base = std::path::Path::new(&base_dir).join("Temp").join(format!("bmt-shot-{nonce}"));
    let base_s = base.to_string_lossy().into_owned();
    let fail = |m: String| (Some(1), serde_json::json!({ "error": m }).to_string(), false);
    let exe = match std::env::current_exe() {
        Ok(e) => e,
        Err(e) => return fail(format!("BMT Remote could not find itself: {e}")),
    };
    if let Err(e) = crate::platform::windows::run_exe_in_cur_session(&exe.to_string_lossy(), vec!["--bmt-screenshot", &base_s], false) {
        return fail(format!("Nobody is signed in, or the screen couldn't be reached: {e}"));
    }
    let done = format!("{base_s}.done");
    let err = format!("{base_s}.err");
    let deadline = std::time::Instant::now() + Duration::from_secs(20);
    while std::time::Instant::now() < deadline && !std::path::Path::new(&done).exists() && !std::path::Path::new(&err).exists() {
        std::thread::sleep(Duration::from_millis(150));
    }
    let cleanup = || {
        for i in 0..16 {
            std::fs::remove_file(format!("{base_s}-{i}.jpg")).ok();
        }
        std::fs::remove_file(&done).ok();
        std::fs::remove_file(&err).ok();
    };
    if let Ok(m) = std::fs::read_to_string(&err) {
        cleanup();
        return fail(format!("The screen couldn't be captured (locked or disconnected?): {}", m.trim()));
    }
    let Ok(sizes) = std::fs::read_to_string(&done) else {
        cleanup();
        return fail("The screen capture did not finish in time.".into());
    };
    let mut screens = Vec::new();
    for (i, line) in sizes.lines().enumerate() {
        let (w, h) = line.split_once('x').unwrap_or(("0", "0"));
        if let Ok(bytes) = std::fs::read(format!("{base_s}-{i}.jpg")) {
            use hbb_common::base64::Engine;
            screens.push(serde_json::json!({
                "W": w.trim().parse::<u32>().unwrap_or(0),
                "H": h.trim().parse::<u32>().unwrap_or(0),
                "Data": hbb_common::base64::engine::general_purpose::STANDARD.encode(bytes),
            }));
        }
    }
    cleanup();
    let user = crate::platform::get_active_username();
    (Some(0), serde_json::json!({ "User": user, "At": hbb_common::chrono::Local::now().to_rfc3339(), "Screens": screens }).to_string(), false)
}

/// `--bmt-screenshot <base>`, run in the signed-in user's session: captures
/// every display at full resolution and writes <base>-N.jpg plus <base>.done
/// listing each size, or <base>.err with the reason.
pub fn capture_screens(base: &str) -> i32 {
    use scrap::{Capturer, Display, Frame, TraitCapturer, TraitPixelBuffer};
    let result = (|| -> Result<Vec<(usize, usize)>, String> {
        let displays = Display::all().map_err(|e| e.to_string())?;
        if displays.is_empty() {
            return Err("no displays".into());
        }
        let mut sizes = Vec::new();
        for (i, display) in displays.into_iter().enumerate() {
            let mut cap = Capturer::new(display).map_err(|e| e.to_string())?;
            let (w, h) = (cap.width(), cap.height());
            let mut rgb: Option<Vec<u8>> = None;
            for attempt in 0..40 {
                if attempt == 20 {
                    cap.set_gdi();
                }
                match cap.frame(Duration::from_millis(100)) {
                    Ok(Frame::PixelBuffer(pb)) if !pb.data().is_empty() => {
                        let stride = pb.stride().first().copied().unwrap_or(w * 4);
                        let data = pb.data();
                        let mut out = Vec::with_capacity(w * h * 3);
                        for y in 0..h {
                            let row = &data[y * stride..y * stride + w * 4];
                            for px in row.chunks_exact(4) {
                                out.extend_from_slice(&[px[2], px[1], px[0]]);
                            }
                        }
                        rgb = Some(out);
                        break;
                    }
                    Ok(_) => {}
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                    Err(e) => return Err(e.to_string()),
                }
            }
            let rgb = rgb.ok_or("no frame from the screen")?;
            let file = std::fs::File::create(format!("{base}-{i}.jpg")).map_err(|e| e.to_string())?;
            let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(std::io::BufWriter::new(file), 90);
            enc.encode(&rgb, w as u32, h as u32, image::ColorType::Rgb8).map_err(|e| e.to_string())?;
            sizes.push((w, h));
        }
        Ok(sizes)
    })();
    match result {
        Ok(sizes) => {
            let list: Vec<String> = sizes.iter().map(|(w, h)| format!("{w}x{h}")).collect();
            std::fs::write(format!("{base}.done"), list.join("\n")).ok();
            0
        }
        Err(e) => {
            std::fs::write(format!("{base}.err"), e).ok();
            1
        }
    }
}
