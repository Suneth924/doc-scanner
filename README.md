# DocScanner

An iPhone document scanner that sends scans to a Mac, a Windows PC, or a NAS.

## Features (v0.1)

- **Scan:** Apple's document camera finds page edges, straightens the page and lets you drag the corners. Multi-page scans are supported, and you can add pages later.
- **Enhance:** Original, Enhanced, Greyscale and Black & White filters (Core Image).
- **Library:** grid of scans with rename, delete and add pages.
- **Export:** multi-page PDF (A4 width) or JPEG per page.
- **Send to a Mac:** Share › AirDrop.
- **Send to a Windows PC (or any computer):** Wi‑Fi Transfer. The app runs a small web server and shows an address like `http://192.168.1.20:8080`. Open it in a browser on the PC and click a scan to download its PDF. It also lists your Tailscale address (`100.x.x.x`), so it works from anywhere on your tailnet.
- **Send to a NAS:** in the Files app, choose Connect to Server and enter `smb://<nas-address>` once. After that, Share › Save to Files › your NAS.

## Build and run

You need a Mac with Xcode 15 or later and an iPhone running iOS 17 or later. The document camera does not work in the Simulator.

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
  Models/    ScanDocument and ScanStore (saves scans to the app's Documents folder)
  Services/  ImageEnhancer, PDFExporter, TransferServer (HTTP over Network.framework)
  Views/     Library, document detail, camera wrapper, share sheet, Wi‑Fi Transfer
project.yml  XcodeGen spec that generates the Xcode project
```

## Next ideas

- Text recognition (OCR) with Vision so PDFs are searchable
- Uploading from the PC to the phone through the same web page
- Password-protected PDFs
