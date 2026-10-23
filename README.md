# PS5Plus

PS5Plus is a [KytyPS5](https://github.com/KytyPS5/KytyPS5) build with local improvements. It is
developed on macOS, merged with upstream nightly, and tested on g913 through Fenrir's EmuDeck
streaming environment.

## Layout

| Path | Purpose |
|------|---------|
| `KytyPS5/` | Submodule: [jefflouisma/KytyPS5](https://github.com/jefflouisma/KytyPS5), branch `ps5plus` |
| `scripts/build-macos.sh` | Build and run upstream's unit tests on this Mac |
| `scripts/validate-g913.sh` | Publish `ps5plus`, wait for its Linux release, and activate it on g913 |
| `scripts/nightly-sync.sh` | Merge upstream into `ps5plus`, verify it on this Mac, and publish |
| `scripts/install-nightly.sh` | Install the nightly LaunchAgent |
| `scripts/upstream-ci.py` | Read build targets, tests, apt packages and Qt version from upstream CI |
| `.github/workflows/release.yml` | Build, test and release the Linux package on every push to `main` |

The fork has two branches. `main` mirrors upstream exactly. `ps5plus` is upstream plus PS5Plus
changes, so `main...ps5plus` shows every local change. Keep upstream pull requests on topic
branches cut from `main`; the upstream project closes broad or unfocused PRs.

The submodule has an `upstream` remote for KytyPS5/KytyPS5. A fresh clone needs it added:

```sh
git clone --recurse-submodules https://github.com/jefflouisma/PS5Plus.git
git -C PS5Plus/KytyPS5 remote add upstream https://github.com/KytyPS5/KytyPS5.git
git -C PS5Plus/KytyPS5 switch ps5plus
```

## Development loop

1. Commit changes on `ps5plus` in `KytyPS5/` (or merge a topic branch into it).
2. Run `scripts/build-macos.sh`. It builds an x86_64 `kyty_emulator` that runs under Rosetta 2
   and runs the same unit tests as upstream's macOS CI. The Qt launcher is skipped because Fenrir
   starts the emulator directly. Build output and ccache live under `/Volumes/4TB_Drive/tmp/ps5plus`.
3. Run `scripts/validate-g913.sh`. It requires clean trees and then:
   - pushes `ps5plus` to the fork and commits the submodule pointer to PS5Plus `main`;
   - waits for CI to build, test and release `PS5Plus-<date>-<commit>`;
   - has Fenrir stage that release and queue activation. Activation waits for running Moonlight
     sessions to close.
4. In Moonlight, open **EmuDeck** and launch a game from **Sony PlayStation 5 (PS5Plus)**.

Each validated build is also a GitHub release, so its binary always matches published source.

## Nightly upstream merge

`scripts/install-nightly.sh` installs a LaunchAgent that runs `nightly-sync.sh` at 03:00. It:

1. skips with a notification if either repository has uncommitted changes, is on another branch,
   has unpushed `ps5plus` commits, or has diverged from GitHub;
2. fast-forwards the fork's `main` to upstream;
3. merges `upstream/main` into `ps5plus` in the submodule;
4. builds and tests on this Mac (`PS5PLUS_SKIP_BUILD=1` skips this);
5. pushes `ps5plus`, commits the new submodule pointer, and pushes PS5Plus `main`.

A merge conflict is aborted and reported. A failed build keeps the merge on a local
`nightly/failed-<date>-<upstream>` branch and leaves `ps5plus` unchanged. Nothing is published
in either case. Logs are in `/Volumes/4TB_Drive/tmp/ps5plus/logs/nightly-<date>.log`.

Run it immediately with `launchctl kickstart gui/$(id -u)/com.jefflouisma.ps5plus.nightly`.

## Fenrir integration

Fenrir's package manager treats PS5Plus like KytyPS5 but as a separate `ps5plus` component. It
checks this repository's latest release every six hours. It verifies the tarball against its
GitHub SHA-256 digest and checks the emulator's command-line interface. A version activates only
when you choose **Update** at `http://192.168.1.221:47989/updates`, or when `validate-g913.sh`
does it for you. The previous three versions are retained for rollback.

EmuDeck lists the same `fenrir-games/ps5` titles under **Sony PlayStation 5 (PS5Plus)**. The
`ps5plus` launcher uses the selected PS5Plus build. Its guest data and saves are in
`~/.local/share/ps5plus`, separate from KytyPS5's, so an experimental build cannot damage KytyPS5
saves. Emulator logs are written to `/Volumes/4TB_Drive/tmp/ps5plus/logs` in the session pod.

## God of War Ragnarök (PPSA08332)

Upstream KytyPS5 shows a black screen in Ragnarök (KytyPS5 issue #546). `ps5plus` adds the open
upstream pull requests the game needs and the fixes below. With them it boots, plays the opening
cutscene, and is controllable through the sled ride, the quick-time events and the first fight on
g913 (RTX 5080, NVIDIA 615.71).

Merged upstream pull requests: #1118, #1152, #1165, #1199, #1200, #1211, #1254, #1255, #1281,
#1282, #1284, #1285, #1289, #1294, #1295, #1307, #1308, #1311, #1456, #1491, #1503, #1506,
#1791, #1821 and #1828. The others linked from the issue were already upstream, superseded
(#1482 by #1791) or unrelated. #1288 conflicts with upstream's GPU indirect-draw path, and
PS5Plus fixes that path separately.

PS5Plus changes:

| Commit | Change |
|--------|--------|
| `85f47a33` | PlayGo: a dump without chunk metadata reports every chunk as installed, so the game no longer waits forever for its first frame. |
| `4b3672ab`, `349f7d19` | Texture cache: keep up to four dynamic-resolution siblings of a render target instead of recreating them every frame. |
| `651db272` | Shader: allow PC-relative buffer descriptors in programs that use `s_swappc`. |
| `4c14b72b` | Shader: on 32-lane hosts (NVIDIA) skip the ordered-append rank wait, which stalled the GPU for minutes. |
| `8166ea03` | Shader: resource tracking follows loop inductions split across congruent Phis. |
| `807e6e76` | Renderer: index buffers are bound with `INDEX_BUFFER_SIZE` (`VK_KHR_maintenance5`), so indices past it read as 0 as on the hardware. |
| `1ed88c44` | Shader: a BDA page miss tests its fault bit before setting it, so a missing page no longer serializes a whole draw. |

The last two fix the NVIDIA device loss (`Xid 109, CTX SWITCH TIMEOUT` in `kern.log`) in the
opening cutscene. Its particle draws read past their index buffers, and lit particles spent
seconds per draw contending on one fault-bitmap word.

Fenrir starts Ragnarök with `--tessellation`, set in homelab's
`images/emudeck/config/title-options`.

Known issues:

- The first run after an emulator update compiles pipelines with freezes of up to about 100 s,
  and a quick-time event can fail during one. Later runs reuse the pipeline caches.
- Some particle effects in the opening (snow and sparks) draw as screen-wide streaks.
- The frame rate is 10–40 FPS.
- After a death, **Restart from Checkpoint** may need a second Cross press once its loading
  finishes.

The merged pull requests change areas upstream is still revising. When upstream merges them, or
other changes that touch them, the nightly merge may conflict and stop with a notification.
Resolve it by merging `upstream/main` into `ps5plus` by hand, preferring upstream's version of
anything it has merged.

## License

KytyPS5 is GPL-2.0. Releases are built from the submodule commit named in each release's notes.
