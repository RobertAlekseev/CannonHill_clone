use std::{net::SocketAddr, path::PathBuf};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = std::env::args().skip(1);
    let address: SocketAddr = args
        .next()
        .unwrap_or_else(|| "127.0.0.1:8000".into())
        .parse()?;
    let dist = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("dist"));
    cannon_hill_web::server::run(address, dist).await
}
