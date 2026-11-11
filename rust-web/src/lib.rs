use std::cell::RefCell;

#[cfg(all(feature = "lan", not(target_arch = "wasm32")))]
pub mod server;

#[cfg(not(feature = "bench-large"))]
const MAP_SCALE: usize = 1;
#[cfg(feature = "bench-large")]
const MAP_SCALE: usize = 4;
const W: usize = 240 * MAP_SCALE;
const H: usize = 128 * MAP_SCALE;
const DT: f32 = 1.0 / 30.0;
const GRAVITY: f32 = 39.24;
// Power 55 (the default) reaches the opposite cannon on flat ground at 45°.
const MUZZLE_SCALE: f32 = 1.45;
const DRIVE_SPEED: f32 = 14.0;
// Highest step (in cells) a cannon can climb while driving.
const MAX_CLIMB: f32 = 2.5;
const MAX_HP: i32 = 1000;
const DROP_INTERVAL: u32 = 150;
const BUFF_TICKS: u32 = 240;

#[derive(Clone, Copy)]
struct Cannon {
    x: f32,
    y: f32,
    vy: f32,
    angle: f32,
    power: f32,
    drive: f32,
    hp: i32,
    cooldown: u32,
    shield: u32,
    rapid: u32,
}

impl Cannon {
    fn view(&self) -> [f32; 7] {
        [
            self.x,
            self.y,
            self.angle,
            self.power,
            self.hp as f32,
            self.shield as f32 * DT,
            self.rapid as f32 * DT,
        ]
    }

    fn new(x: f32) -> Self {
        Self {
            x,
            y: 0.0,
            vy: 0.0,
            angle: 45.0,
            power: 55.0,
            drive: 0.0,
            hp: MAX_HP,
            cooldown: 0,
            shield: 0,
            rapid: 0,
        }
    }
}

#[derive(Clone, Copy)]
struct Shot {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    owner: usize,
    age: u32,
}

#[derive(Clone, Copy)]
struct Drop {
    x: f32,
    y: f32,
    kind: u32,
}

struct Game {
    cells: [u8; W * H],
    sand_active: bool,
    cannons: [Cannon; 2],
    shots: Vec<Shot>,
    drop: Option<Drop>,
    tick: u32,
    revision: u32,
    rng: u32,
    // -2: playing, -1: draw, otherwise winner index.
    result: i32,
}

fn distance_sq(x: f32, y: f32) -> f32 {
    x * x + y * y
}

fn next_seed(mut seed: u32) -> u32 {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    seed
}

impl Game {
    fn new(seed: u32, revision: u32) -> Self {
        let mut game = Self {
            cells: [0; W * H],
            sand_active: true,
            cannons: [
                Cannon::new(40.0 * MAP_SCALE as f32),
                Cannon::new(200.0 * MAP_SCALE as f32),
            ],
            shots: Vec::new(),
            drop: None,
            tick: 0,
            revision,
            rng: seed.max(1),
            result: -2,
        };
        for x in 0..W {
            let x_wave = x as f32 / MAP_SCALE as f32;
            let height = 81.0 + 10.0 * (x_wave * 0.035).sin() + 5.0 * (x_wave * 0.081).sin();
            let top = (height * MAP_SCALE as f32) as usize;
            for y in top..H {
                game.cells[y * W + x] = if y >= H - 4 { 2 } else { 1 };
            }
        }
        for i in 0..2 {
            let x = game.cannons[i].x as i32;
            game.cannons[i].y = game.floor_at(x, 0) as f32;
        }
        game
    }

    fn solid(&self, x: i32, y: i32) -> bool {
        x >= 0
            && x < W as i32
            && y >= 0
            && y < H as i32
            && self.cells[y as usize * W + x as usize] != 0
    }

    fn floor_at(&self, x: i32, start: i32) -> i32 {
        (start.max(0)..H as i32)
            .find(|&y| self.solid(x - 3, y) || self.solid(x + 3, y))
            .unwrap_or(H as i32 - 4)
            - 3
    }

    fn next_random(&mut self) -> u32 {
        self.rng = next_seed(self.rng);
        self.rng
    }

    fn drop_warning_x(&self) -> f32 {
        if self.result == -2 && self.tick % DROP_INTERVAL >= DROP_INTERVAL - 30 {
            ((96 + next_seed(self.rng) % 49) as usize * MAP_SCALE) as f32
        } else {
            -1.0
        }
    }

    fn drive(&mut self, player: usize, direction: f32) {
        if let Some(cannon) = self.cannons.get_mut(player) {
            cannon.drive = if direction.is_finite() {
                direction.clamp(-1.0, 1.0)
            } else {
                0.0
            };
        }
    }

    fn move_cannon(&mut self, i: usize) {
        let c = self.cannons[i];
        if c.drive == 0.0 || c.hp <= 0 || self.result != -2 || c.vy != 0.0 {
            return;
        }
        let x = (c.x + c.drive * DRIVE_SPEED * DT).clamp(4.0, (W - 5) as f32);
        let floor = self.floor_at(x as i32, (c.y - MAX_CLIMB - 1.0).max(0.0) as i32) as f32;
        if floor < c.y - MAX_CLIMB {
            return;
        }
        let c = &mut self.cannons[i];
        c.x = x;
        c.y = c.y.min(floor);
    }

    fn input(&mut self, player: usize, angle: f32, power: f32, fire: bool) {
        if self.result != -2 || !angle.is_finite() || !power.is_finite() {
            return;
        }
        let Some(cannon) = self.cannons.get_mut(player) else {
            return;
        };
        cannon.angle = angle.clamp(5.0, 85.0);
        cannon.power = power.clamp(15.0, 90.0);
        if !fire || cannon.cooldown > 0 || self.shots.len() >= 32 {
            return;
        }
        let angle = cannon.angle.to_radians();
        let dx = angle.cos() * if player == 0 { 1.0 } else { -1.0 };
        let dy = -angle.sin();
        self.shots.push(Shot {
            x: cannon.x + 7.0 * dx,
            y: cannon.y - 1.0 + 7.0 * dy,
            vx: dx * cannon.power * MUZZLE_SCALE,
            vy: dy * cannon.power * MUZZLE_SCALE,
            owner: player,
            age: 0,
        });
        cannon.cooldown = if cannon.rapid > 0 { 11 } else { 21 };
    }

    fn settle(&mut self) {
        if !self.sand_active && !cfg!(feature = "bench-full-scan") {
            return;
        }
        let mut changed = false;
        for y in (0..H - 1).rev() {
            for scan in 0..W {
                let x = if self.tick % 2 == 0 {
                    scan
                } else {
                    W - 1 - scan
                };
                let index = y * W + x;
                if self.cells[index] != 1 {
                    continue;
                }
                let below = index + W;
                let mut target = below;
                if self.cells[below] != 0 {
                    let side = if (self.tick as usize + x + y) % 2 == 0 {
                        1
                    } else {
                        -1
                    };
                    let Some(diagonal) = [side, -side]
                        .into_iter()
                        .map(|offset| x as i32 + offset)
                        .find(|&nx| {
                            nx >= 0 && nx < W as i32 && self.cells[(y + 1) * W + nx as usize] == 0
                        })
                    else {
                        continue;
                    };
                    target = (y + 1) * W + diagonal as usize;
                }
                self.cells[index] = 0;
                self.cells[target] = 1;
                changed = true;
            }
        }
        // A pass without movement proves that no grain has a free destination.
        // Alternating the scan order cannot change that until terrain is removed.
        self.sand_active = changed;
        if changed {
            self.revision = self.revision.wrapping_add(1);
        }
    }

    fn explode(&mut self, x: f32, y: f32, direct: Option<usize>) {
        let mut changed = false;
        for row in ((y - 10.0) as i32).max(0)..=((y + 10.0) as i32).min(H as i32 - 1) {
            for column in ((x - 10.0) as i32).max(0)..=((x + 10.0) as i32).min(W as i32 - 1) {
                let cell = &mut self.cells[row as usize * W + column as usize];
                if *cell == 1 && distance_sq(x - column as f32, y - row as f32) < 100.0 {
                    *cell = 0;
                    changed = true;
                }
            }
        }
        if changed {
            self.sand_active = true;
            self.revision = self.revision.wrapping_add(1);
        }
        for (i, c) in self.cannons.iter_mut().enumerate() {
            let distance = (distance_sq(c.x - x, c.y - y).sqrt() - 4.0).max(0.0);
            let damage = if direct == Some(i) {
                200.0
            } else {
                200.0 * (1.0 - distance / 14.0).max(0.0)
            };
            let shield = if c.shield > 0 { 0.5 } else { 1.0 };
            c.hp = (c.hp - (damage * shield).round() as i32).max(0);
        }
    }

    fn step(&mut self) {
        self.tick = self.tick.wrapping_add(1);
        self.settle();
        for i in 0..2 {
            self.move_cannon(i);
            let c = self.cannons[i];
            let floor = self.floor_at(c.x as i32, (c.y + 2.0) as i32) as f32;
            let c = &mut self.cannons[i];
            c.cooldown = c.cooldown.saturating_sub(1);
            c.shield = c.shield.saturating_sub(1);
            c.rapid = c.rapid.saturating_sub(1);
            c.vy += GRAVITY * DT;
            c.y += c.vy * DT;
            if c.y >= floor {
                c.y = floor;
                c.vy = 0.0;
            }
        }
        if self.result != -2 {
            return;
        }
        if self.tick % DROP_INTERVAL == 0 {
            self.drop = Some(Drop {
                x: ((96 + self.next_random() % 49) as usize * MAP_SCALE) as f32,
                y: 4.0,
                kind: self.next_random() % 3,
            });
        }
        if let Some(mut drop) = self.drop {
            drop.y += 19.0 * DT;
            self.drop =
                (drop.y < H as f32 && !self.solid(drop.x as i32, drop.y as i32)).then_some(drop);
        }
        for i in (0..self.shots.len()).rev() {
            let mut shot = self.shots[i];
            if self.advance_shot(&mut shot) {
                self.shots[i] = shot;
            } else {
                self.shots.remove(i);
            }
        }
        self.result = match (self.cannons[0].hp > 0, self.cannons[1].hp > 0) {
            (true, true) => -2,
            (true, false) => 0,
            (false, true) => 1,
            (false, false) => -1,
        };
        if self.result != -2 {
            self.shots.clear();
            self.drop = None;
        }
    }

    fn advance_shot(&mut self, shot: &mut Shot) -> bool {
        shot.age += 1;
        shot.vy += GRAVITY * DT;
        let count = (distance_sq(shot.vx, shot.vy).sqrt() * DT * 2.0)
            .ceil()
            .max(1.0) as u32;
        for _ in 0..count {
            shot.x += shot.vx * DT / count as f32;
            shot.y += shot.vy * DT / count as f32;
            if let Some(drop) = self.drop {
                if distance_sq(shot.x - drop.x, shot.y - drop.y) <= 25.0 {
                    let c = &mut self.cannons[shot.owner];
                    if c.hp > 0 {
                        match drop.kind {
                            0 => c.hp = (c.hp + 150).min(MAX_HP),
                            1 => c.shield = BUFF_TICKS,
                            _ => c.rapid = BUFF_TICKS,
                        }
                    }
                    self.drop = None;
                    return false;
                }
            }
            let direct = self
                .cannons
                .iter()
                .position(|c| c.hp > 0 && distance_sq(shot.x - c.x, shot.y - c.y) <= 16.0);
            if direct.is_some() || self.solid(shot.x.floor() as i32, shot.y.floor() as i32) {
                self.explode(shot.x, shot.y, direct);
                return false;
            }
        }
        shot.age < 360 && shot.x >= 0.0 && shot.x < W as f32 && shot.y < H as f32
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn drop_warning_x() -> f32 {
    GAME.with_borrow(Game::drop_warning_x)
}

thread_local! { static GAME: RefCell<Game> = RefCell::new(Game::new(1, 1)); }

// The browser adapter reads the fixed-size terrain buffer from Wasm memory.
#[unsafe(no_mangle)]
pub extern "C" fn terrain_ptr() -> *const u8 {
    GAME.with_borrow(|g| g.cells.as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn terrain_revision() -> u32 {
    GAME.with_borrow(|g| g.revision)
}

#[unsafe(no_mangle)]
pub extern "C" fn reset(seed: u32) {
    GAME.with_borrow_mut(|g| *g = Game::new(seed, g.revision.wrapping_add(1)));
}

#[unsafe(no_mangle)]
pub extern "C" fn input(player: usize, angle: f32, power: f32, fire: u32) {
    GAME.with_borrow_mut(|g| g.input(player, angle, power, fire != 0));
}

#[unsafe(no_mangle)]
pub extern "C" fn drive(player: usize, direction: f32) {
    GAME.with_borrow_mut(|g| g.drive(player, direction));
}

#[unsafe(no_mangle)]
pub extern "C" fn step() {
    GAME.with_borrow_mut(Game::step);
}

#[unsafe(no_mangle)]
pub extern "C" fn result() -> i32 {
    GAME.with_borrow(|g| g.result)
}

#[unsafe(no_mangle)]
pub extern "C" fn cannon(player: usize, field: u32) -> f32 {
    GAME.with_borrow(|g| {
        let Some(c) = g.cannons.get(player) else {
            return 0.0;
        };
        c.view().get(field as usize).copied().unwrap_or(0.0)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn shot_count() -> usize {
    GAME.with_borrow(|g| g.shots.len())
}

#[unsafe(no_mangle)]
pub extern "C" fn shot(index: usize, axis: u32) -> f32 {
    GAME.with_borrow(|g| {
        g.shots
            .get(index)
            .map_or(0.0, |s| if axis == 0 { s.x } else { s.y })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn drop_state(field: u32) -> f32 {
    GAME.with_borrow(|g| {
        g.drop.map_or(-1.0, |d| match field {
            0 => d.kind as f32,
            1 => d.x,
            _ => d.y,
        })
    })
}

// Only exposed in dedicated benchmark builds. Keeps real projectiles in flight
// near the center without changing the normal firing rules or cooldowns.
#[cfg(feature = "bench")]
#[unsafe(no_mangle)]
pub extern "C" fn bench_fill_shots() {
    GAME.with_borrow_mut(|g| {
        for index in g.shots.len()..32 {
            let slot = (g.tick as usize * 7 + index * 13) % 49;
            g.shots.push(Shot {
                x: ((96 + slot) * MAP_SCALE) as f32,
                y: (40 + index % 5 * 4) as f32,
                vx: if index % 2 == 0 { 9.0 } else { -9.0 },
                vy: -20.0,
                owner: index % 2,
                age: 0,
            });
        }
    });
}

#[cfg(feature = "bench")]
#[unsafe(no_mangle)]
pub extern "C" fn bench_map_scale() -> usize {
    MAP_SCALE
}
