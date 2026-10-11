# Connected test checklist and pilot steps

The automated tests run real TLS sockets, real phone sync engines and a real local cloud
Worker on one PC (`docs/PROGRESS.md`). They are **not** physical-device tests. Before a café
pilot, run this list on the **actual Windows PC, phones, tablet, Wi-Fi and printers**, and also
`docs/MANUAL_TEST_CHECKLIST.md` (offline features). Mark each check **passed / failed / not
run** with evidence (screenshot, order/receipt number, time, device model).

Record: POS PC model + Windows version, phone/tablet models + Android versions, router model,
CaféDesk Online version on every device, printer models.

## A. Setup

| # | Check | Steps | Expected | Result | Evidence |
|---|---|---|---|---|---|
| A1 | Both apps side by side | Install offline CaféDesk and CaféDesk Online on the same Android phone and the same PC. | Two apps; each opens its own data; neither changes the other. | not run | |
| A2 | Turn on phones | POS: Settings → Connected devices → turn on phone connections. | Windows asks to allow the app; after *Allow* (Private network) the screen shows "On", the PC's address and port. | not run | |
| A3 | Public network profile | Switch the PC's network to *Public*, try to pair. | Phone cannot connect (expected); switching back to *Private* fixes it. | not run | |
| A4 | Pair waiter phone | Pair a phone as Waiter by scanning the QR. | Paired within seconds; appears in the device list. | not run | |
| A5 | Pair with pasted text | Pair the tablet as Kitchen by pasting the pairing text. | Paired. | not run | |
| A6 | Expired / reused code | Wait 10 minutes, scan an old QR; scan a used QR on another phone. | Both refused with a clear message. | not run | |
| A7 | Sign in | Waiter signs in on the phone; kitchen user on the tablet; a waiter tries the tablet. | First two work; the waiter is refused on the kitchen display. | not run | |

## B. Ordering on the café Wi-Fi

| # | Check | Steps | Expected | Result | Evidence |
|---|---|---|---|---|---|
| B1 | Table order | Waiter: table T1 → items with a variant, add-on and note → Send. | "Accepted by the POS"; POS shows T1 occupied with the order; kitchen tablet sounds once and shows the ticket; one KOT prints. | not run | |
| B2 | Two waiters, one table | Two phones open the same free table and send at the same moment. | One order; the other phone offers "Add to order #…". | not run | |
| B3 | Additions | Add items to T1 from the phone. | New kitchen ticket with only the new items. | not run | |
| B4 | Cancel a sent item | Reduce an item the kitchen already has. | Owner password needed; correction ticket with reason. | not run | |
| B5 | Price change | Change an item's price on the POS while a phone has a draft; send. | Phone shows the new price and asks before sending. | not run | |
| B6 | Kitchen flow | Tablet: Start → Ready. | POS and waiter phone show the new status; no second alarm. | not run | |
| B7 | Kitchen reconnect | Turn the tablet's Wi-Fi off and on. | Board comes back; old tickets do not sound again; tickets created meanwhile sound once. | not run | |
| B8 | Payment stays on the POS | Pay T1 on the POS. | Bill and receipt as usual; the phone shows the order closed and cannot change it. | not run | |

## C. Outages (the important part)

| # | Check | Steps | Expected | Result | Evidence |
|---|---|---|---|---|---|
| C1 | Internet down | Unplug the router's internet; keep Wi-Fi. Repeat B1–B6. | Everything works. | not run | |
| C2 | Phone off Wi-Fi, no cloud | Turn off the phone's Wi-Fi; send an order. | "Saved on this phone — waiting for the POS"; sent once when Wi-Fi is back; no duplicate. | not run | |
| C3 | POS closed | Close CaféDesk Online on the PC; send from a phone; reopen the POS. | Phone banner says not connected; the order is sent once after the POS opens. | not run | |
| C4 | Phone app killed | Send while the POS is closed, force-stop the phone app, reopen both. | The order is still there and is sent once. | not run | |
| C5 | Over 30 minutes | Send while the POS is closed; reopen it after 31 minutes. | The phone holds the order for review ("Check before sending again"); nothing reaches the kitchen by itself. | not run | |
| C6 | PC address changes | Give the PC a new IP address (router). | Phones show not connected (expected; reserve the PC's IP). Re-pairing fixes it. | not run | |
| C7 | Remove a phone | Remove a paired phone on the POS while it is in use. | The phone is disconnected at once and says it was removed. | not run | |

## D. Cloud relay (deployed at `https://cafedesk-online.growlineecommerce.workers.dev`; codes: `docs/CLOUDFLARE_SETUP.md` §8)

| # | Check | Steps | Expected | Result | Evidence |
|---|---|---|---|---|---|
| D1 | Connect the cloud | Connected devices → Cloud relay → address + enrollment code. | "Connected"; sales copied up to #… | not run | |
| D2 | Phone on mobile data | Phone on mobile data sends an order. | Accepted through the cloud; kitchen and printer as in B1. | not run | |
| D3 | POS offline from the cloud | Unplug the POS PC's internet; phone on mobile data sends. | "Waiting in the cloud — the POS has not answered yet"; accepted once when the internet is back (within 30 minutes). | not run | |
| D4 | Cloud reports | Compare the cloud report for today with the POS dashboard. | Same totals; the report says how current it is. | not run | |

## E. Restore drill

| # | Check | Steps | Expected | Result | Evidence |
|---|---|---|---|---|---|
| E1 | Restore with phones | Back up; make a sale; send an order from a phone with the POS closed; restore the backup. | Connected devices shows "This POS was restored"; phones cannot connect; the POS bills normally. | not run | |
| E2 | Reconnect | Choose *Reconnect devices*; staff sign in again on the phones. | Phones reload; the order from before the restore is held for review, not sent; with a cloud, cloud reports match the restored POS. | not run | |

## Pilot steps

1. Install on the café's own PC (code-signed build — Smart App Control blocks unsigned apps),
   set up the restaurant, printers and staff accounts as in the offline app.
2. Reserve the PC's IP address in the router, set the network profile to *Private*, set sleep
   to *Never* (`docs/PAIRING_AND_SECURITY.md` §7).
3. Pair one waiter phone and one kitchen tablet. Run sections A–C with the owner present, before
   opening hours.
4. First service: one waiter on the phone, everyone else as usual on the POS. Keep the KOT
   printer on as a backup to the kitchen display.
5. After the shift: compare the POS dashboard and the printed KOTs with what the phones showed;
   note any confusing message for the waiters.
6. If the owner wants waiters off the Wi-Fi or off-site reports: issue an enrollment code for the
   café (`docs/CLOUDFLARE_SETUP.md` §8), connect the POS to the deployed cloud, then run section D.
7. Practise section E once on a copy of the data before relying on restores.
