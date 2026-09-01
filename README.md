# Cfx Server (Windows) on Wine, for Pterodactyl

This repository builds a Docker image that can run the Windows build of the Cfx server
(the FiveM for GTA V Enhanced server, `cfx-server.exe`) on a Linux machine, using Wine.
It also contains a Pterodactyl egg, which is the file you import into your panel so you
can create servers that use this image.

Wine is a compatibility layer. It lets a program that was built for Windows run on Linux
without a Windows licence and without a virtual machine. This image pins Wine to version
**11.16**, so every server you create behaves exactly the same, and nothing changes under
you when a new Wine release comes out.

## How the server files are put together

The Cfx depot publishes the server in named channels. Think of a channel as a download
slot that always points at the newest build of one particular variant.

This egg installs from two channels at the same time.

1. Everything comes from the `main` channel, which is the normal Enhanced server.
2. Then the whole `coreclr_server` folder is thrown away and reinstalled from the
   `csharp_improvements` channel.

`coreclr_server` is the folder that holds the .NET runtime and the C# libraries the
server uses to run C# resources. Replacing just that folder means you get the regular
server, but with the C# side coming from the experimental build.

Both channels are read from the public depot API, for example
`https://depot.cfx.re/public/p/fxserver_gen9/u/main`, which returns a download link, a
build number and a SHA256 checksum. The installer checks that checksum before it unpacks
anything, so a half finished or corrupted download cannot quietly become a broken server.

## What is in this repository

| File | What it does |
| --- | --- |
| `Dockerfile` | Builds the image. Debian with Wine 11.16 pinned, plus a `container` user, which is the account Pterodactyl expects. |
| `entrypoint.sh` | Runs inside the container on every boot. Creates the Wine prefix the first time, then runs your startup command. |
| `scripts/install.sh` | The install script the panel runs once, when you create or reinstall a server. Downloads and unpacks the server. |
| `egg-cfx-server-wine.template.json` | The egg without the install script, and without a real image name in it. |
| `scripts/render-egg.py` | Glues `install.sh` into the template and fills in your GitHub account name. |
| `egg-cfx-server-wine.json` | The finished egg. This is the file you import into Pterodactyl. |
| `.github/workflows/build.yml` | Builds and publishes the image on every commit. |
| `.github/workflows/cleanup.yml` | Deletes old image versions so your GitHub package storage stays small. |

The install script lives in its own `.sh` file rather than being pasted inside the egg
JSON, because a shell script buried in a JSON string is painful to read and impossible to
check. The render step puts it into the JSON for you.

## Setting it up on GitHub

1. Create a new repository on GitHub and push these files to a branch called `main`.
2. The `build` workflow runs on its own. It builds the image and pushes it to the GitHub
   Container Registry as `ghcr.io/YOUR-ACCOUNT/cfx-server-wine`.
3. **Make the package public.** This is the one step GitHub does not let a workflow do for
   you. Go to your profile, open the **Packages** tab, click `cfx-server-wine`, then
   **Package settings**, scroll to **Danger Zone** and choose **Change visibility**, then
   **Public**. If you skip this, your Pterodactyl node cannot pull the image, because it
   has no GitHub login.
4. On that same settings page, check that the package is linked to this repository. That
   link is what lets the cleanup workflow delete old versions using the built in token.

After the first successful run, the workflow commits `egg-cfx-server-wine.json` back to the
repository with your real account name filled in. From then on, the copy in the repository
is always the correct, ready to import one.

## Importing the egg into Pterodactyl

1. Download `egg-cfx-server-wine.json` from this repository.
2. In the panel, go to **Admin**, then **Nests**, then **Import Egg**, and upload the file.
   Put it in whichever nest you like.
3. Create a server using it. The install runs on its own and takes a couple of minutes,
   most of which is downloading roughly 80 MB of server files.

### Settings the egg gives you

| Setting | Default | Meaning |
| --- | --- | --- |
| Server channel | `main` | Depot channel for the server itself. |
| C# runtime channel | `csharp_improvements` | Depot channel that `coreclr_server` is taken from. |
| Download default resources | `1` | On a fresh install, also fetch the standard cfx-server-data resources, so the server actually boots into something. |
| License key | empty | Your key from https://portal.cfx.re/. It is written into `server.cfg` only when the installer creates that file. |
| Virtual display | `0` | Starts a fake screen (Xvfb) before the server. The Cfx server is a console program and does not need one, so leave this off unless something you added asks for a desktop. |

The startup command is exactly `wine cfx-server.exe +exec server.cfg`.

The panel rewrites the two `endpoint_add_tcp` and `endpoint_add_udp` lines in `server.cfg`
on every boot, so the port always matches the allocation you gave the server in the panel.

To stop the server, the panel sends `quit` to the console, which is the clean way to shut a
Cfx server down.

## Updating

Because both depot channels always point at their newest build, updating the server is just
a **Reinstall** in the panel. Your `resources` folder and your `server.cfg` are left alone.
Only the server binaries and `coreclr_server` are replaced.

To change the Wine version, edit `WINE_VERSION` in `Dockerfile` and in
`.github/workflows/build.yml`, then commit. Available versions are listed at
https://dl.winehq.org/wine-builds/debian/dists/trixie/. If you pick a version that does not
exist for Debian trixie, the build fails immediately with an apt error, so a typo cannot
produce a broken image.

## Image tags and keeping storage tidy

Every push to `main` publishes these tags.

- `latest`, which always points at the newest build.
- `wine11.16`, which points at the newest build of that Wine version.
- `wine11.16-20260901-42`, a fixed tag with the date and the workflow run number. Use one of
  these in the egg if you ever want a server pinned to an exact image.

Right after a successful build, the cleanup workflow runs. It removes every untagged image
version, which is the leftover rubbish that builds up as tags move to newer images, and then
keeps only the newest 5 versions and deletes the rest. It also runs on its own on the first
of every month, and you can start it by hand from the **Actions** tab if you want to clean up
with a different number.

Deleting a version can only be undone by rebuilding, so the workflow is deliberately careful.
It never touches whatever `latest` points at, and both delete steps are marked
`continue-on-error`, so a cleanup problem can never fail a build that already succeeded.

If cleanup reports a permission error, your account is set up so the automatic token cannot
delete packages. Create a personal access token with the `delete:packages` scope, add it to
the repository as a secret named `GHCR_CLEANUP_TOKEN`, and the workflow picks it up on its
own.

## Things worth knowing

**The first boot is slow.** Wine has to build its prefix, which is a folder that pretends to
be a Windows installation. That happens once, takes about half a minute, and is stored in
`/home/container/.wine`, so it survives restarts. The console tells you when it is happening.

**The image is large**, around 1.5 GB, because the official Wine packages include both the
64 bit and the 32 bit halves of Wine. Your node downloads it once.

**The console line the panel waits for** is `Started resource`, which the server prints as it
starts each resource. This matters more than it sounds. Most FiveM eggs wait for a line
saying `Authenticating...`, and that text simply does not exist in the Enhanced server, so an
egg copied from elsewhere leaves your server stuck on "Starting" forever.

**System resources.** The Enhanced server ships only `chat` and `txadmin` inside itself.
Everything else, including `mapmanager` and `spawnmanager`, comes from cfx-server-data, which
is why the installer offers to download it.
