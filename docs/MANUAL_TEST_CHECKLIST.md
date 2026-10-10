# Manual acceptance checklist

A release is ready for a café pilot only after the **actual target printer and devices** pass
this list. Mark each check **passed / failed / not run** with evidence (photo of the slip,
screenshot, receipt number, date, device model).

Record: device model + OS version, CaféDesk version, printer model + connection + paper width.

| # | Check | Steps | Expected | Result | Evidence |
|---|---|---|---|---|---|
| 1 | Airplane-mode billing | Turn on airplane mode (LAN printer: Wi-Fi on, no internet). Take a takeaway and a dine-in order, pay cash and UPI. | Orders, bills, KOT and receipts work; nothing asks for internet. | not run | |
| 2 | Restart during ordering | Add items to an order, force-stop the app (Android) / end task (Windows), reopen. | The open order and its items are still there; nothing duplicated. | not run | |
| 3 | Reboot after sale | Complete a sale, reboot the device immediately, reopen. | The bill exists in Bills and in the dashboard; receipt number not reused. | not run | |
| 4 | Bluetooth permission denial (Android 12+) | Add a Bluetooth printer, deny "Nearby devices"; then deny with "don't ask again". | Clear explanation; app keeps working; settings link explains how to allow. | not run | |
| 5 | Printer out of paper | Remove paper, make a sale. | Bill saved. Job shows Sent / Failed / Unknown honestly; after loading paper staff can retry or confirm. No silent duplicate. | not run | |
| 6 | Printer disconnected / off | Turn the printer off, make a sale, then turn it on. | Job **Failed — not sent**; Retry prints it once as the original. | not run | |
| 7 | Power off mid-print | Turn the printer off while a long receipt prints. | Job **Unknown — check printer**; Reprint is marked REPRINT. | not run | |
| 8 | 58 mm long names | Item with a very long name, modifiers and a note on a 58 mm printer. | Text wraps cleanly, amounts aligned, nothing cut off. | not run | |
| 9 | 80 mm long names | Same on 80 mm. | As above with 48 columns. | not run | |
| 10 | Rupee / scripts | Item named in Tamil with ₹ in a note; printer in "Text, image when needed". | Prints correctly as an image; in "Text only" the job fails with a clear message (no "?"). | not run | |
| 11 | Split tender | Bill ₹500: UPI ₹300 + cash ₹200 received ₹500. | Change ₹300 shown and printed; dashboard counts UPI 300, cash 200. | not run | |
| 12 | Partial refund | Refund 1 of 2 items from an earlier bill with the owner password. | Refund receipt prints; original bill unchanged; dashboard shows refund on today's date. | not run | |
| 13 | Overnight cutoff | Cutoff 04:00. Make a sale at 01:30. | Counted in the previous business day in dashboard and ledger. | not run | |
| 14 | Backup restoration | Back up, make another sale, restore the backup. | Pre-restore backup created; restored data shown; next receipt number continues after the highest used; print jobs held. | not run | |
| 15 | Cross-platform restore | Back up on Android, restore on Windows (or the reverse). | All bills, refunds, expenses and shifts present; reports match. | not run | |
| 16 | Clean Windows machine | Copy the release folder (or installer) to a PC without Flutter/VS; run CaféDesk.exe. | Starts; no missing DLL errors; setup works. With Smart App Control on, an unsigned build is blocked — must be code-signed. | not run | |
| 17 | KOT flow | Send to kitchen, add more, send again, reduce a sent item with the owner password. | Second KOT has only new items; correction ticket printed with reason. | not run | |
| 18 | Shift close | Open with float, sales, cash out, drawer expense, close with counted cash. | Expected cash = float + cash sales − cash refunds + in − out − drawer expenses; variance shown. | not run | |
| 19 | Inactivity lock | Leave idle for the lock timeout. | Lock screen; open order intact after unlocking. | not run | |
| 20 | Second instance (Windows) | Start CaféDesk twice. | Second window says it is already open. | not run | |

## Performance (record device + numbers)

| Scenario | Target | Device | Measured | Result |
|---|---|---|---|---|
| Load menu, 1,000 items | feels immediate | Dev PC (Win 11, i7-1185G7, 16 GB) — `tool/perf_benchmark.dart`, database layer | 24 ms load; 4 searches < 5 ms total | passed (desktop, DB layer only) |
| Create order + 2 adds / reload with pricing / checkout (50,000-bill DB) | feels immediate | same | 53 ms / 13 ms / 35 ms | passed (desktop, DB layer only) |
| Dashboard one day / one month (12,927 bills) / 120 days (50,000 bills) | usable | same | 30 ms / 452 ms / 1,646 ms | passed (desktop, DB layer only) |
| Same scenarios on the café's Android device (UI included) | feels immediate / usable | | | not run |
| Same scenarios on the café's Windows PC (UI included) | feels immediate / usable | | | not run |

The dev-PC numbers exclude Flutter rendering and come from a fast laptop; measure on the real
pilot devices before relying on them.

Use `dart run tool/perf_benchmark.dart` (database-level timings) and Flutter DevTools on a profile
build to measure; write the device model and timings here instead of claiming them.
