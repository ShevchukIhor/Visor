# Visor

**Vision training for Solana Seeker — Gabor patch games and guided eye exercises. No paywall. No accounts. Works fully offline.**

Visor trains your visual cortex, not just your eyes. It uses Gabor patches — the sinusoidal grating stimuli that neuroscience uses to probe V1 neurons — and turns them into a discrimination game with controlled difficulty.

## Features

- **Gabor Patch Game** — find the matching pattern in a 3×3 to 6×6 grid. Each card differs by a *single* controlled parameter (orientation, spatial frequency, or phase), so the brain learns to discriminate real visual detail instead of guessing at noise.
- **Four difficulty levels** — Easy (3×3) through Expert (6×6), each tightening the discrimination threshold the way neurophysiology research does.
- **Eight eye exercises** — convergence, near-far cycles, focus shifting, saccadic jumps, smooth pursuit, figure-8 tracking, peripheral awareness, and 3D floating orbs. Every exercise runs on a set timer (30 / 60 / 120 s), not indefinitely.
- **On-device progress** — streak, today-counter, and best score, stored locally in SQLite. Your data never leaves the phone.
- **Seed Vault (optional)** — link your training profile to a Solana wallet via Mobile Wallet Adapter. Training works fully offline without it.
- **Daily reminders** — fire exactly once, only on days you haven't trained. Alarms use exact scheduling and survive reboot.

## Architecture

| Layer | Technology |
|-------|-----------|
| UI | Flutter (Dark theme, Material 3) |
| Gabor engine | Custom pixel-buffer rendering in `CustomPainter` |
| Storage | SQLite via `sqflite` |
| Wallet | Solana Mobile Wallet Adapter (`clientlib-ktx`) |
| Reminders | Native `AlarmManager` + `BootReceiver` |

## Gabor patch generation

The core stimulus is computed from the standard Gabor formula:

```
G(x, y) = exp(-(x'² + γ·y'²) / 2σ²) · cos(2π·f·x' + φ)

x' = x·cosθ + y·sinθ
y' = -x·sinθ + y·cosθ
```

Each parameter maps to one dimension the brain must discriminate:

- `θ` — orientation (primary dimension for the grid game)
- `f` — spatial frequency (stripe fineness)
- `σ` — Gaussian envelope size
- `φ` — phase
- `γ` — aspect ratio

Difficulty increases by reducing the angular/contrast difference between the target and decoys, mirroring how V1 neurons are probed.

## Get Started

```bash
flutter pub get
flutter build apk --release
```

The release APK is signed with a dedicated key (see `android/key.properties`, kept out of version control).

## Device Requirements

- Android (Solana Seeker is the target device — ARM64)
- `minSdk` per Flutter default; `targetSdk` 36

## License

See [LICENSE](LICENSE).

## Privacy

Visor collects nothing. All data (sessions, streak, wallet association) is stored locally in on-device SQLite. There is no network telemetry, no analytics, and no account required.