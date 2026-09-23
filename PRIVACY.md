# Visor — Privacy Policy

**Effective: September 23, 2026**

Visor is a vision-training application for Solana Seeker. This policy explains how your data is handled.

## What we collect

**Nothing.** Visor does not collect, transmit, or store any personal information.

- No accounts, no login, no email, no identifiers.
- No analytics, no tracking, no telemetry, no crash reporters.
- No third-party SDKs that collect data.

## Where your data lives

All app data — your training sessions, streak, best score, and reminder settings — is stored **locally** in on-device SQLite. It never leaves your device and is never uploaded to any server. Visor does not store a wallet address at all.

Android's Auto Backup is **disabled** for Visor, so this data is not copied to your Google Drive or transferred to a new device.

## Optional tipping via Seed Vault

Tipping is entirely optional. Visor never handles your keys, seed phrase, or wallet contents: the transaction is built on your device and handed to Seed Vault (the on-device Mobile Wallet Adapter), where you review and approve it yourself.

## Network access

Visor makes network requests in exactly one situation: **when you send a tip.** To build a valid Solana transaction, the app queries public Solana RPC endpoints — currently `api.mainnet-beta.solana.com` and `solana-rpc.publicnode.com` — for a recent blockhash and to check whether your wallet holds enough to cover the tip.

Those requests include **your wallet's public address**, which the RPC provider can see along with your IP address, as with any Solana wallet or block explorer. We do not operate these endpoints and do not receive the requests ourselves. Public addresses and transactions on Solana are public by nature.

If you never send a tip, Visor makes no network requests at all.

## Third parties

Visor contains no analytics, advertising, or tracking SDKs. The only third parties that ever see anything are the public Solana RPC endpoints described above, and only when you choose to tip.

## Children

Visor does not collect data from anyone, including children.

## Changes

If this policy changes, the updated version will be published with the app.

## Contact

For privacy questions, contact **env5150@proton.me**.