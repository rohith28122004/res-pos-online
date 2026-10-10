# Printer setup

CaféDesk prints to **ESC/POS-compatible** thermal printers with **58 mm or 80 mm** paper.
Compatibility depends on the printer model and its firmware/driver; there is no promise that
every thermal printer works. Test with **Print sample** before going live. **Billing never
depends on a printer**: a sale is saved first; printing happens afterwards from a durable queue.

## Supported connections

| Platform | Connection | How it works | Status |
|---|---|---|---|
| Android | Bluetooth Classic (SPP/RFCOMM) | Kotlin plugin `BluetoothPrinterPlugin.kt`; printer must be **paired in Android settings** first | implemented, hardware validation pending |
| Android | LAN / Wi-Fi (TCP, usually port 9100) | `TcpTransport` (dart:io socket) | implemented, tested against a local socket only |
| Windows | Installed printer — RAW | ESC/POS bytes sent through the Windows spooler (`OpenPrinter` / `StartDocPrinter` `RAW` / `WritePrinter`) via dart:ffi | implemented, hardware validation pending |
| Windows | Installed printer — driver rendered | receipt rendered to a 1-bit image and drawn with GDI (`StretchDIBits`) on the queue's device context; for drivers that reject RAW | implemented, hardware validation pending |
| Windows | LAN / Wi-Fi (TCP 9100) | same as Android | implemented, tested against a local socket only |

Not supported in v1: BLE-only printers, vendor-proprietary protocols, USB on Android,
Bluetooth on Windows (pair it as a Windows printer and use RAW/driver mode instead, if the
vendor driver supports it — unverified).

## Settings per printer

* **Prints**: receipts, kitchen tickets, or both. A receipt printer and a KOT printer can be
  different devices.
* **Paper**: 58 mm (default 384 dots, 32 characters) or 80 mm (576 dots, 48 characters). Adjust
  dots/characters if your model differs (check its manual or self-test page).
* **Print mode**:
  * *Text, image when needed* (default): fast code-page text; switches to an image when the
    receipt contains characters the code page cannot print (₹ symbol in names, Tamil, Hindi…)
  * *Text only*: never images; a receipt with unsupported characters **fails with a clear
    message** instead of printing "?"
  * *Always image*: every receipt as an image (prints ₹ on totals; slower, larger data)
* **Code page**: PC437 (default, universal) or WPC1252. In text mode the rupee sign is
  printed as **INR**.
* **Cutter**: none / partial / full. **Blank lines before cut**.
* **Cash drawer pulse**: off by default. Turn on only if a drawer is wired to the printer's
  drawer port. It fires only after original receipts (never copies).
* **Timeout** (connect/write), default 8 s.

## Android Bluetooth

1. Turn the printer on; pair it in Android **Settings → Bluetooth** (PIN often 0000 or 1234).
2. In CaféDesk: Settings → Printers → Add printer → Connection: Bluetooth Classic.
3. Allow **Nearby devices** when asked (Android 12+). If you deny it, CaféDesk explains how
   to allow it in app settings. Older Android versions need no runtime prompt.
4. Choose the printer from the paired list → **Test connection** → **Print sample**.

If the printer is off or out of range the job is marked **Failed — not sent** (safe to retry).
If the link drops while sending, the job is **Unknown — check printer**.

## Windows USB printer

1. Install the vendor's Windows driver so the printer appears in Windows **Printers & scanners**.
2. Settings → Printers → Add printer → Connection: *Windows printer — RAW ESC/POS*; pick the
   queue → **Print sample**.
3. If nothing prints or garbage prints, edit the printer and switch to *Windows printer —
   driver rendered*, set the paper width in the driver preferences, and try again.

## LAN printer

1. Print the printer's self-test page to find its IP address; give it a fixed IP/DHCP
   reservation on your router.
2. Add printer → Connection: Network → IP and port (9100) → **Test connection** → **Print sample**.
   Works on a local network with no internet.

## Job states

| State | Meaning | What to do |
|---|---|---|
| Waiting / Sending | in the queue / being sent | — |
| Sent to printer | bytes reached the printer connection or the Windows spooler. **Not proof that paper came out** (paper out, cover open…) | check the slip |
| Failed — not sent | could not connect / open the printer; nothing was sent | fix the printer, tap **Retry** |
| Unknown — check printer | the connection broke while sending, or the app closed mid-print | look at the printer: **It printed** or **Reprint** (marked REPRINT) |
| Held for review | jobs restored from a backup | **Release** or cancel |

Staff reprints from Bills are always marked **COPY**. Uncertain jobs are never resent
automatically, and the app does not claim exactly-once physical printing.

## Compatibility matrix

Only physically verified rows may be marked "physically verified". A software fake or local
socket validates logic only.

| Platform | Model | Connection | Paper | Encoding / mode | Cutter | Test date | Status |
|---|---|---|---|---|---|---|---|
| any | (software fake) | queue logic | 58/80 | text + raster | — | 2026-10-10 | simulated (unit tests) |
| Windows (dev PC) | loopback TCP socket | TCP | — | ESC/POS bytes | — | 2026-10-10 | simulated (bytes received intact) |
| Android | — | Bluetooth Classic | — | — | — | — | unverified (no hardware) |
| Windows | — | USB spooler RAW | — | — | — | — | unverified (no hardware) |
| Windows | — | USB driver rendered | — | — | — | — | unverified (no hardware) |
| Android / Windows | — | LAN TCP 9100 | — | — | — | — | unverified (no hardware) |

Add a row for every printer you test with the manual checklist in
`docs/MANUAL_TEST_CHECKLIST.md` (58/80 mm long names, ₹ / INR, cut, out-of-paper,
power-off mid-job, reprint marking).
