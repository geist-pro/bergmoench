//! Anki's own sync server, for testing Kartei's sync against a local machine.
//! SYNC_USER1=user:pass SYNC_BASE=/tmp/kartei-sync SYNC_PORT=8080 cargo run --release --example syncserver
fn main() {
    anki::log::set_global_logger(None).ok();
    let err = anki::sync::http_server::SimpleServer::run();
    eprintln!("sync server stopped: {err}");
    std::process::exit(1);
}
