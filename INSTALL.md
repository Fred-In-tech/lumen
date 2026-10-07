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
1. Click **Import** and pick the photos of one shoot. JPEG, PNG, HEIC and camera RAW files (Canon, Nikon, Sony, Fujifilm and more) all work. Lumen asks where they go: a **new project** (the name is filled in from the shoot's date and first file; change it if you like), a project you already have, or **Unsorted**. You can also drag photos onto a project on the Home screen.
2. Each project shows five steps: **Import → Cull → Edit → Retouch → Export**, and a button for the next one (for example "Cull 120 photos"). **Smart Cull** suggests picks and rejects; press `P` to pick and `X` to reject yourself.
3. Click a photo to open it. The editor starts in **Auto**:
   1. **Enhance** fixes light and colour.
   2. **Auto Retouch** cleans up skin, eyes and teeth.
   3. **Looks** applies a style.
   The strip at the bottom and the arrow keys move through the photos of that project only.
4. Switch to **Manual** at the top for every slider, plus masks, remove, crop and presets. Hold `\` to see the before photo. Press `I` for the photo's camera details.
5. Click **Export picks** on the project page (or **Export** in the editor) to save your photos. Pick a preset (Web, Full size JPEG, Print TIFF 16-bit, Instagram) or set format, size, sharpening, file name and an optional watermark yourself, then **Save as preset**.
6. Home shows your shoots in progress, this week's numbers and the looks you can give a whole project. Your photos from before projects are in **Unsorted** (and in **All photos**): select some and use **Move to…** to put them in a project. Add your name in **Settings** and Home greets you by it.

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
