# Installing Lumen (testers)

Lumen is a photo editor for Mac with AI auto-enhance, portrait retouching and RAW editing. This is a test build.

## What you need
- A Mac with **macOS 14 (Sonoma) or newer**. Apple silicon (M1–M4) and Intel Macs both work.
- About 150 MB of free space, plus room for your photos.
- An internet connection for the install and for updates.

## Install (one step)

1. Open **Terminal**: press `⌘ Space`, type `Terminal`, press Return.
2. Copy this line, paste it into Terminal, and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/Fred-In-tech/lumen/main/install.sh | bash
```

3. Wait for "Lumen … is installed, with automatic updates." Lumen opens by itself. It now lives in your **Applications** folder like any other app.

If you're asked for a token, the project is private at the moment. Ask Freddy to send you the token version of the command.

## Updates happen by themselves
- Lumen checks for a new version when you log in and every 6 hours.
- A new version installs while Lumen is **closed**. If Lumen is open, it waits until you quit it.
- Your photos and edits are kept across updates.
- To update right away, run the install line again.

## First use
1. Click **Import** and pick some photos. JPEG, PNG, HEIC and camera RAW files (Canon, Nikon, Sony, Fujifilm and more) all work.
2. Click a photo to open it. The editor starts in **Auto**:
   1. **Enhance** fixes light and colour.
   2. **Auto Retouch** cleans up skin, eyes and teeth.
   3. **Looks** applies a style.
3. Switch to **Manual** at the top for every slider, plus masks, remove, crop and presets.
4. Hold `\` to see the before photo. Press `I` for the photo's camera details.
5. Click **Export** to save your edited photo.

The "Describe an edit" box needs an AI server that isn't part of this test build, so it uses a basic offline edit instead.

## If something goes wrong
- **"lumen can't be opened" / "unidentified developer":** run the install line again; it clears this. Or right-click Lumen in Applications, choose **Open**, then **Open** again.
- **Nothing happens after the command:** check your internet connection and run the line again.
- **Updates seem stuck:** see `~/Library/Application Support/Lumen/updater/update.log`, or just run the install line again.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/Fred-In-tech/lumen/main/install.sh | bash -s -- --uninstall
```

This removes the app and the auto-updater. Your photo library stays in `~/Library/Containers/com.fvm.lumen` until you delete that folder.

## Sending feedback
Tell Freddy what you edited, what looked wrong, and which Mac you're on (Apple menu → About This Mac). A screenshot helps a lot.
