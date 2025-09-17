use anyhow::{Context, Result};
use std::fs::File;
use std::io;
use std::time::Duration;

/// Download a URL to a string with a timeout (in seconds).
pub fn get_to_string(url: &str, user_agent: &str, timeout_secs: u64) -> Result<String> {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(timeout_secs))
        .build();
    let resp = agent.get(url).set("User-Agent", user_agent).call();
    if let Err(err) = &resp { return Err(anyhow::anyhow!(err.to_string())); }
    let resp = resp.unwrap();
    let code = resp.status();
    if !(200..=299).contains(&code) { return Err(anyhow::anyhow!(format!("HTTP {}", code))); }
    let text = resp.into_string().context("reading body")?;
    Ok(text)
}

/// Download a URL to a file path (atomic via .tmp rename) with timeout.
pub fn get_to_file(url: &str, path: &str, user_agent: &str, timeout_secs: u64) -> Result<()> {
    let agent = ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(timeout_secs))
        .build();
    let resp = agent.get(url).set("User-Agent", user_agent).call();
    if let Err(err) = &resp { return Err(anyhow::anyhow!(err.to_string())); }
    let resp = resp.unwrap();
    let code = resp.status();
    if !(200..=299).contains(&code) { return Err(anyhow::anyhow!(format!("HTTP {}", code))); }
    let tmp = format!("{}.tmp", path);
    let mut f = File::create(&tmp).with_context(|| format!("open {}", tmp))?;
    io::copy(&mut resp.into_reader(), &mut f).context("writing file")?;
    drop(f);
    std::fs::rename(&tmp, path).with_context(|| format!("rename {} -> {}", tmp, path))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::thread;
    use tiny_http::{Response, Server};

    fn spawn_server() -> (String, thread::JoinHandle<()>) {
        // Bind to an OS-assigned free port
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let url = format!("http://{}", addr);
        drop(listener);
        let server = Server::http(addr).unwrap();
        let handle = thread::spawn(move || {
            if let Some(rq) = server.incoming_requests().next() {
                let path = rq.url().to_string();
                if path == "/hello" {
                    let _ = rq.respond(Response::from_string("world"));
                } else {
                    let _ = rq.respond(Response::empty(404));
                }
            }
        });
        (url, handle)
    }

    #[test]
    fn string_and_file() {
        let (base, h) = spawn_server();
        let text = get_to_string(&format!("{}/hello", base), "QHTL", 5).unwrap();
        assert_eq!(text, "world");

        let (base2, h2) = spawn_server();
        let tmpdir = tempfile::tempdir().unwrap();
        let path = tmpdir.path().join("out.txt");
        get_to_file(&format!("{}/hello", base2), path.to_str().unwrap(), "QHTL", 5).unwrap();
        let data = std::fs::read_to_string(&path).unwrap();
        assert_eq!(data, "world");
        h.join().unwrap();
        h2.join().unwrap();
    }
}
