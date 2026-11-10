use std::{
    net::SocketAddr,
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::{
    Router,
    body::Bytes,
    extract::{
        State, WebSocketUpgrade,
        ws::{CloseFrame, Message, Utf8Bytes, WebSocket},
    },
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Redirect},
    routing::get,
};
use serde::{Deserialize, Serialize};
use tokio::{
    net::TcpListener,
    sync::watch,
    time::{Instant, MissedTickBehavior, interval, sleep_until, timeout},
};

use super::{DT, Game};

#[derive(Clone, Copy, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Command {
    Input {
        round: u32,
        angle: f32,
        power: f32,
        fire: bool,
    },
    Restart {
        round: u32,
    },
}

#[derive(Clone, Copy)]
struct Controls {
    angle: f32,
    power: f32,
    fire: bool,
}

impl From<super::Cannon> for Controls {
    fn from(cannon: super::Cannon) -> Self {
        Self {
            angle: cannon.angle,
            power: cannon.power,
            fire: false,
        }
    }
}

struct Room {
    game: Game,
    seats: [Option<Controls>; 2],
    round: u32,
}

impl Room {
    fn new() -> Self {
        Self {
            game: Game::new(seed(), 1),
            seats: [None; 2],
            round: 0,
        }
    }

    fn players(&self) -> usize {
        self.seats.iter().flatten().count()
    }

    fn command(&mut self, player: usize, command: Command) {
        match command {
            Command::Input {
                round,
                angle,
                power,
                fire,
            } if round == self.round
                && self.players() == 2
                && angle.is_finite()
                && power.is_finite() =>
            {
                if let Some(input) = &mut self.seats[player] {
                    input.angle = angle;
                    input.power = power;
                    input.fire |= fire;
                }
            }
            Command::Restart { round } if player == 0 && round == self.round => {
                self.round = self.round.wrapping_add(1);
                self.game = Game::new(seed(), self.game.revision.wrapping_add(1));
                for (seat, cannon) in self.seats.iter_mut().zip(self.game.cannons) {
                    if seat.is_some() {
                        *seat = Some(cannon.into());
                    }
                }
            }
            _ => {}
        }
    }

    fn step(&mut self) {
        if self.players() != 2 {
            return;
        }
        for (index, seat) in self.seats.iter_mut().enumerate() {
            if let Some(input) = seat {
                self.game.input(
                    index,
                    input.angle,
                    input.power,
                    std::mem::take(&mut input.fire),
                );
            }
        }
        self.game.step();
    }
}

fn seed() -> u32 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u32
}

#[derive(Serialize)]
struct Snapshot {
    protocol: u32,
    tick: u32,
    round: u32,
    players: usize,
    result: i32,
    revision: u32,
    cannons: [[f32; 7]; 2],
    shots: Vec<[f32; 2]>,
    drop: Option<[f32; 3]>,
    warning: f32,
}

struct Frame {
    json: Utf8Bytes,
    terrain: Bytes,
    revision: u32,
}

impl Frame {
    fn capture(room: &Room, previous: Option<&Frame>) -> Self {
        let game = &room.game;
        let snapshot = Snapshot {
            protocol: 1,
            tick: game.tick,
            round: room.round,
            players: room.players(),
            result: game.result,
            revision: game.revision,
            cannons: game.cannons.map(|c| c.view()),
            shots: game.shots.iter().map(|s| [s.x, s.y]).collect(),
            drop: game.drop.map(|d| [d.kind as f32, d.x, d.y]),
            warning: game.drop_warning_x(),
        };
        let terrain = previous
            .filter(|frame| frame.revision == game.revision)
            .map_or_else(
                || encode_terrain(&game.cells),
                |frame| frame.terrain.clone(),
            );
        Self {
            json: serde_json::to_string(&snapshot)
                .expect("valid simulation snapshot")
                .into(),
            terrain,
            revision: game.revision,
        }
    }
}

// Terrain has long runs of identical cells. Fall back to raw bytes if it
// becomes too fragmented for runs to save bandwidth.
fn encode_terrain(cells: &[u8]) -> Bytes {
    let mut runs = vec![1];
    for row in cells.chunk_by(|left, right| left == right) {
        for run in row.chunks(u8::MAX as usize) {
            runs.extend_from_slice(&[run.len() as u8, run[0]]);
        }
        if runs.len() >= cells.len() + 1 {
            let mut raw = Vec::with_capacity(cells.len() + 1);
            raw.push(0);
            raw.extend_from_slice(cells);
            return raw.into();
        }
    }
    runs.into()
}

#[derive(Clone)]
struct App {
    room: Arc<Mutex<Room>>,
    frames: watch::Sender<Arc<Frame>>,
}

struct Seat {
    room: Arc<Mutex<Room>>,
    player: usize,
}

impl Drop for Seat {
    fn drop(&mut self) {
        let mut room = self.room.lock().unwrap();
        room.seats[self.player] = None;
        for input in room.seats.iter_mut().flatten() {
            input.fire = false;
        }
    }
}

async fn upgrade(
    State(app): State<App>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    if let Some(origin) = headers.get(header::ORIGIN) {
        let host = headers
            .get(header::HOST)
            .and_then(|value| value.to_str().ok());
        let origin_host = origin
            .to_str()
            .ok()
            .and_then(|value| value.strip_prefix("http://"));
        let same_host = origin_host
            .zip(host)
            .is_some_and(|(origin, host)| origin.eq_ignore_ascii_case(host));
        // Unreal's native WebSocket library omits the port in Origin. Browser
        // WebSocket clients cannot set this custom upgrade header.
        let native = headers
            .get("x-cannon-hill-native")
            .is_some_and(|value| value == "1")
            && host
                .and_then(|value| value.parse::<axum::http::uri::Authority>().ok())
                .zip(origin_host)
                .is_some_and(|(host, origin)| origin.eq_ignore_ascii_case(host.host()));
        if !same_host && !native {
            return StatusCode::FORBIDDEN.into_response();
        }
    }
    ws.max_message_size(1024)
        .max_frame_size(1024)
        .on_upgrade(move |socket| connect(app, socket))
        .into_response()
}

async fn send(socket: &mut WebSocket, message: Message) -> bool {
    matches!(
        timeout(Duration::from_secs(3), socket.send(message)).await,
        Ok(Ok(()))
    )
}

async fn connect(app: App, mut socket: WebSocket) {
    let seat = {
        let mut room = app.room.lock().unwrap();
        room.seats.iter().position(Option::is_none).map(|player| {
            room.seats[player] = Some(room.game.cannons[player].into());
            Seat {
                room: app.room.clone(),
                player,
            }
        })
    };
    let Some(seat) = seat else {
        let _ = send(
            &mut socket,
            Message::Close(Some(CloseFrame {
                code: 1008,
                reason: "Partie voll".into(),
            })),
        )
        .await;
        return;
    };
    let mut frames = app.frames.subscribe();
    let welcome = Message::Text(format!(r#"{{"protocol":1,"player":{}}}"#, seat.player).into());
    if !send(&mut socket, welcome).await {
        return;
    }

    let mut last_revision = None;
    let mut heartbeat = interval(Duration::from_secs(5));
    let mut deadline = Instant::now() + Duration::from_secs(20);
    loop {
        tokio::select! {
            received = socket.recv() => match received {
                Some(Ok(Message::Text(data))) => {
                    deadline = Instant::now() + Duration::from_secs(20);
                    if let Ok(command) = serde_json::from_str::<Command>(&data) {
                        app.room.lock().unwrap().command(seat.player, command);
                    }
                }
                Some(Ok(Message::Pong(_))) => deadline = Instant::now() + Duration::from_secs(20),
                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                _ => {}
            },
            frame_ready = frames.changed() => {
                if frame_ready.is_err() { break; }
                let frame = frames.borrow_and_update().clone();
                if last_revision != Some(frame.revision) {
                    if !send(&mut socket, Message::Binary(frame.terrain.clone())).await { break; }
                    last_revision = Some(frame.revision);
                }
                if !send(&mut socket, Message::Text(frame.json.clone())).await { break; }
            },
            _ = heartbeat.tick() => {
                if !send(&mut socket, Message::Ping(Bytes::new())).await { break; }
            }
            _ = sleep_until(deadline) => break,
        }
    }
}

pub async fn run(address: SocketAddr, dist: PathBuf) -> Result<(), Box<dyn std::error::Error>> {
    let html = Bytes::from(std::fs::read(dist.join("index.html"))?);
    let js = Bytes::from(std::fs::read(dist.join("app.js"))?);
    let wasm = Bytes::from(std::fs::read(dist.join("cannon_hill_web.wasm"))?);
    let room = Room::new();
    let (frames, _) = watch::channel(Arc::new(Frame::capture(&room, None)));
    let app = App {
        room: Arc::new(Mutex::new(room)),
        frames,
    };
    let simulation = app.clone();
    let listener = TcpListener::bind(address).await?;
    let local = listener.local_addr()?;
    let router = Router::new()
        .route(
            "/",
            get(|| async { Redirect::temporary("/index.html?lan=1") }),
        )
        .route(
            "/index.html",
            get(
                move || async move { ([(header::CONTENT_TYPE, "text/html; charset=utf-8")], html) },
            ),
        )
        .route(
            "/app.js",
            get(move || async move {
                (
                    [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
                    js,
                )
            }),
        )
        .route(
            "/cannon_hill_web.wasm",
            get(move || async move { ([(header::CONTENT_TYPE, "application/wasm")], wasm) }),
        )
        .route("/ws", get(upgrade))
        .with_state(app);
    tokio::spawn(async move {
        let mut timer = interval(Duration::from_secs_f64(f64::from(DT)));
        timer.set_missed_tick_behavior(MissedTickBehavior::Skip);
        let mut publish = false;
        loop {
            timer.tick().await;
            let mut room = simulation.room.lock().unwrap();
            room.step();
            publish = !publish;
            if publish && !simulation.frames.is_closed() {
                let frame = Frame::capture(&room, Some(&simulation.frames.borrow()));
                simulation.frames.send_replace(Arc::new(frame));
            }
        }
    });
    println!("LAN bereit auf http://{local}");
    axum::serve(listener, router).await?;
    Ok(())
}
