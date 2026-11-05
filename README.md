# DocScanner

An iPhone document scanner that sends scans to a Mac, a Windows PC, or a NAS.

## Features (v0.1)

- **Scan:** a custom camera outlines the page live as you aim. Edge detection combines Vision's document-segmentation model (robust on busy or low-contrast backgrounds) with its rectangle detector (precise corners), then runs again on the full-resolution photo. Multi-page scans are supported, and you can add pages later or import photos.
- **Adjust edges:** after each capture, drag the four corners or the edges to fit the page exactly; a magnifier shows what's under your finger. Auto re-runs detection and Full Page resets the crop. The uncropped photo is kept, so you can re-adjust any page later from the scan's crop button.
- **Enhance:** Original, Enhanced, Greyscale and Black & White filters (Core Image).
- **Library:** grid of scans with rename, delete and add pages.
- **Export:** multi-page PDF (A4 width) or JPEG per page.
- **Send to a Mac:** Share › AirDrop.
- **Send to a Windows PC (or any computer):** Wi‑Fi Transfer. The app runs a small web server and shows an address like `http://192.168.1.20:8080`. Open it in a browser on the PC and click a scan to download its PDF. It also lists your Tailscale address (`100.x.x.x`), so it works from anywhere on your tailnet.
- **Send to a NAS:** in the Files app, choose Connect to Server and enter `smb://<nas-address>` once. After that, Share › Save to Files › your NAS.

## Build and run

You need a Mac with Xcode 15 or later and an iPhone running iOS 17 or later. The camera does not work in the Simulator, but Import from Photos does, so you can try edge detection there.

```sh
brew install xcodegen
xcodegen generate
open DocScanner.xcodeproj
```

In Xcode, choose your Apple ID team under Signing & Capabilities, plug in your iPhone, and press Run. A free Apple ID works for installing on your own phone.

The first time you use Wi‑Fi Transfer, iOS asks for Local Network permission. Allow it.

## Project layout

```
DocScanner/
  App/       app entry point
  Models/    ScanDocument, Quad (crop corners) and ScanStore (saves scans to the app's Documents folder)
  Services/  EdgeDetector (Vision), PerspectiveCorrector, CameraController (AVFoundation),
             ImageEnhancer, PDFExporter, TransferServer (HTTP over Network.framework)
  Views/     Library, document detail, share sheet, Wi‑Fi Transfer
  Views/Scanner/  scanning screen, live preview overlay, corner editor
project.yml  XcodeGen spec that generates the Xcode project
```

## Next ideas

- Text recognition (OCR) with Vision so PDFs are searchable
- Uploading from the PC to the phone through the same web page
- Password-protected PDFs
