# Setup & Verification Todo

## 1. Install Node.js (if not installed)
```bash
brew install node
# or: https://nodejs.org
```

## 2. Install server dependencies & verify signaling
```bash
cd server
npm install
node signaling-server.js &
npm test
```

Expected output: all 10 assertions pass.

## 3. Create Xcode project
- Open Xcode → File → New → Project → iOS → App
- Product name: `BodyMotionApp`
- Interface: SwiftUI, Language: Swift
- Save into `capstone_app/BodyMotionApp/`

## 4. Add WebRTC package dependency
- File → Add Package Dependencies
- Search: `https://github.com/stasel/WebRTC.git`
- Select `WebRTC` target, click Add Package

## 5. Add source files to Xcode
- Drag all `.swift` files from `BodyMotionApp/Sources/` into the Xcode project navigator
- Ensure "Copy items if needed" is unchecked (they're already in the right place)
- Check all targets

## 6. Update Info.plist
Add camera usage description:
```
NSCameraUsageDescription = "Camera is used to capture body motion for gesture recognition"
```

## 7. Build & run on iPhone
- Connect iPhone via USB
- Select device in scheme menu
- Product → Run (⌘R)
- Grant camera permission when prompted

## 8. Test end-to-end
1. Start signaling server: `cd server && node signaling-server.js`
2. Open app on iPhone
3. Go to Settings tab, enter server IP + port
4. Switch to Capture tab — verify camera shows with skeleton overlay
5. Verify status bar shows "Connected"

## 9. (Optional) Expose server via Tailscale Funnel
```bash
tailscale funnel 3000
```
Use the Tailscale-provided URL as the server IP in app settings.
