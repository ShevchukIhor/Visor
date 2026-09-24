# Visor — dApp Store Listing Metadata
# Скопіюй ці значення у Publisher Portal (publish.solanamobile.com)

> **Чому формулювання саме такі.** Publisher Policy вимагає, щоб dApp, який
> робить медичні або health-твердження, ці твердження **обґрунтовував** і мав
> відповідні дисклеймери. Тому опис описує те, **що застосунок робить**
> (стимули, завдання, таймери), а не те, що він нібито **лікує**. Формулювань
> штибу «reduces eye strain» чи «sharper eyes» тут свідомо немає: вони
> недоказові й це типова причина відмови.

## App Name (назва)
Visor

## Subtitle (<= 50 символів)
Gabor-patch games and guided eye exercises

(42 символи — в межах ліміту)

## Description (коротке поле «In a short paragraph, describe your app»)
Visor is an offline vision-training app built around Gabor patches — the
striped stimuli used in vision research to study how we tell fine detail
apart. Find the one matching pattern in grids from 3x3 to 6x6 across four
difficulty levels, where every card differs from the target by a single
controlled parameter: orientation, spatial frequency, or phase. Eight
guided eye-movement drills round it out, each on a fixed 30/60/120-second
timer. Your streak and scores stay in on-device storage — no accounts, no
ads, no trackers. Visor is a training tool, not a medical device, and does
not diagnose or treat any eye condition.

## Long Description
Visor is a vision-training app built around Gabor patches — the striped,
softly-faded targets used in vision research to study how we tell fine
visual detail apart. No paywall, no accounts, no ads.

WHAT YOU GET

Gabor Patch Game: find the one matching pattern in a 3x3 to 6x6 grid.
Every distractor differs from the target by a single controlled parameter
— orientation, spatial frequency, or phase — so the task rewards genuine
discrimination rather than guessing.

Four difficulty levels: Easy (3x3) through Expert (6x6). Each level
narrows the difference between the target and its distractors, and Expert
also lowers contrast.

Eye Exercises: eight guided movement drills — convergence, near-far focus
cycles paced like a breath, wide focus shifting, saccadic jumps, smooth
pursuit, figure-8 tracking, peripheral awareness, and drifting Gabor orbs.
Every drill runs on a fixed timer you choose (30/60/120s), never endlessly.

Progress: streak, today-counter and best score, kept in on-device SQLite.
Training data stays on your device and is not uploaded anywhere; Android
backup is switched off for the app.

Daily reminders: one nudge a day, and only on days you have not trained
yet — never after a completed session. The reminder is re-armed after a
reboot.

Tipping: entirely optional. If the app was useful, a tip (SOL or SKR) can
be sent from the About screen via Seed Vault. Visor never handles your
keys — you review and approve the transaction in the wallet.

Visor is built for Solana Seeker (Android, ARM64) and works offline. The
only time it uses the network is when you choose to send a tip: it then
queries public Solana RPC endpoints, which see your wallet's public
address, as with any Solana wallet.

IMPORTANT

Visor is a training tool, not a medical device. It does not diagnose,
treat, cure or prevent any eye condition, and nothing in it is medical
advice. If you have persistent eye pain, double vision, sudden vision
changes, or any other concerning symptom, see a qualified eye-care
professional.

## Publisher Portal — full form values
| Field | Value |
|-------|-------|
| dApp Name (<= 25) | Visor |
| Package Name | com.visor.app |
| Subtitle (<= 50) | Gabor-patch games and guided eye exercises |
| Description | (see Description above) |
| dApp Icon 512x512 | assets/icon_512.png |
| Banner 1200x600 | visor-assets/banner_1200x600.png |
| Graphic 1200x1200 | visor-assets/graphic_1200x1200.png |
| Preview images (min 4, 1080x1920 portrait) | uploaded to the portal draft |
| Headline (<= 50) | Train your eyes, not just your streak |
| Languages | English |
| Countries | All countries |
| App Website | https://visor-mobile.pages.dev/ |
| Contact Email | env5150@proton.me |
| Support Email | env5150@proton.me |
| Terms of Use | https://visor-mobile.pages.dev/terms.html |
| Privacy Policy | https://visor-mobile.pages.dev/privacy.html |

## Publisher profile (окремо від лістингу застосунку)
| Field | Value |
|-------|-------|
| Publisher Website | https://shevchukihor.github.io/ |

⚠️ Усі поля, які бачить рецензент, ведуть на власні HTML-сторінки, а не на
github.com (перевірено: усі віддають 200).

## Category (категорія у dApp Store)
Lifestyle

## Tags / keywords (для пошуку)
gabor patch, vision training, eye exercises, visual discrimination,
focus drills, psychophysics

## Release / APK
| | |
|---|---|
| Версія | 0.3.2 (`versionCode` 6) |
| Підпис | `CN=Ihor Shevchuk, OU=Mobile, O=ShevchukIhor, C=UA`, RSA 4096 |
| Відбиток сертифіката | `a9881d7e613f1a3a25527e1169a760adc8bb5c0c58887fa7815d6334698f1493` |
| sha256 APK | `1109d762f650b343e4841758d55529e5126431e9fa5c8252e6d8c18d9cee620f` |

> Подавати APK **файлом**, не посиланням: портал не може завантажити асет
> GitHub release через CORS, а невдала подача займає слот версії назавжди.

⚠️ Кожне оновлення в dApp Store потребує **вищого `versionCode`** і підпису
**тим самим** ключем. Втрата keystore = неможливість оновити застосунок.

## Media specs (для довідки)
- Icon: 512x512px (required)
- Banner: 1200x600px (required)
- Graphic: 1200x1200px
- Preview images: jpg/png/webp, до 3MB, 1080x1920 (portrait) або 1920x1080 (landscape)
- Preview video: mp4, до 30MB, 720px+ (1080p recommended)

## Чек-лист перед подачею
- [x] APK підписаний окремим релізним ключем (не тим, що для Google Play)
- [x] Icon / Banner / Graphic точних розмірів
- [x] Privacy Policy і Terms доступні за публічними URL
- [x] Privacy Policy описує мережеві запити до Solana RPC
- [x] Медичний дисклеймер: у застосунку, у TERMS.md і в описі лістингу
- [x] Скріншоти (мін. 4, 1080x1920) завантажені в драфт
- [ ] Publisher-гаманець із ~0.2 SOL на ArDrive та мінт (потрібен для **всіх**
      майбутніх подач цього застосунку)
- [ ] KYC/KYB пройдено в порталі
- [ ] Під час подачі підтверджено **кожен** запит на підпис
- [ ] У порталі стоять актуальні **Subtitle і Description** з цього файлу
- [ ] **Publisher Website** веде на портфоліо, не на github.com
- [ ] APK подано **файлом**, не посиланням
