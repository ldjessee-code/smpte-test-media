# SMPTE Test Media Generator

Public FFmpeg scripts that synthesize SMPTE bars, line-up tones, motion loops, and encoder-stress clips. No bitmap assets. MIT license. Copyright stays in [LICENSE](LICENSE) on every redistribution.

A session started in this repo loads this file. A session started somewhere else does not. The shared path for those sessions is TheCourt, below.

## This repo

- Root on the Mac: `/Volumes/SeagatePortable/ios_projects/smpte-test-media`
- Public GitHub: `ldjessee-code/smpte-test-media`
- The Seagate path is not on Dropbox. PC-NorCal cannot write this tree unless that drive is mounted there.
- Read [README.md](README.md) and [docs/STANDARDS.md](docs/STANDARDS.md) before changing a generator. Standards notes are engineering references, not a claim of broadcast certification.
- Scripts: `generate_test_media.sh` (H.264, supported), `generate_test_media_prores_hd.sh` (ProRes 422 HQ, supported; macOS uses `prores_videotoolbox`), `generate_test_media_hevc_hd.sh` (HEVC, prototype), `generate_test_media.py` (seeded noise, stdlib only). `load_config.sh` reads the local config.
- `test-media.conf` and `PUBLISH.md` are gitignored. Copy `test-media.conf.example` for local paths. Generated trees (`output/`, `output-prores-hd/`, `output-hevc-hd/`) and media extensions stay untracked.
- Do not commit or push unless asked. Anything committed here is public.

## How TrueEyed Jack uses this

The iOS app does not vendor these scripts. QA copies live only on the machine that generated them, usually:

`/Volumes/SeagatePortable/ios_projects/mobilevideocompressor/test-clips/`

That folder is gitignored in the app repo. A pointer README is at `mobilevideocompressor/scripts/test-media/README.md`. Product decisions (presets, store copy, in-app bars and tone) stay in the app repo and in `iOS-App-Business-Docs`. This repo stays a standalone generator.

`smpte-test-media_old/` next to this folder is an older local snapshot with no GitHub remote. Edit this tree.

## TheCourt, for files in and out

Dropbox folder, shared with Grok Bot on the PC:

- Mac: `/Volumes/SeagatePortable/Dropbox/TheCourt`
- Court name: `/TheCourt/`
- Contract: `AGENTS.md` in that folder. Read it before adding or moving court files. If a folder README disagrees with it, the Court `AGENTS.md` wins.
- A new file can show as 0 bytes on this Mac until Dropbox hydrates it. Open it before treating it as empty.

Use it when this session needs the PC (Playwright, a signed-in browser, a Grok Bot), or when another agent needs to leave something for this session.

- Ask or handoff: `/TheCourt/inbox-md/yyyyMMdd-HHmm_topic.md` (top-level markdown only). Six lines: Goal / Paths / Decisions / Limits / Open questions / Next gate. The phone opens the newest file, so write that note last.
- Finished reading for Doug: `/TheCourt/outbox/`
- True Eyed Jack research already filed under `/TheCourt/business/` belongs to the company, not in this public repo. Generator notes that are safe to publish can be filed here. Private QA results go to the app repo or `/TheCourt/business/`.
- Do not move, rename, or delete court files you did not create. No secrets, tokens, or cookies.

## If you were started elsewhere and the task says to drop a file here

Write it on the Mac at:

`/Volumes/SeagatePortable/ios_projects/smpte-test-media`

If you are on the PC and that path is not mounted, do not invent a second generator tree under Dropbox. Leave the file in `/TheCourt/outbox/` and drop the `inbox-md` note with that path. This session files it into the repo from there. Remember the remote is public before you commit.
