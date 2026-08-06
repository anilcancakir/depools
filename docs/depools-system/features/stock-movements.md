# Stock movements: taking out and putting in

The two most frequent actions in the product. A cafe does them dozens of times a day, a household several times a week, and every number the app computes afterwards is derived from them. So the design constraint is not completeness, it is that a correct entry has to be faster than not bothering.

## The shape both sheets share

**Nothing starts unanswered.** Every field opens with a value already in it, and the user's job is to disagree rather than to fill. The common case is two taps: open the sheet, confirm.

**Every inference states its basis.** The suggested location says "burada 2 parti var", the suggested date says "raf ömründen (5 gün)". D29 forbids asking for what can be inferred, but an inference that does not admit it is how a wrong value silently becomes the input to a forecast. Naming the basis is also what makes the AI suggestion trustworthy the first time a user disagrees with it.

**The outcome is visible before the commit.** "Sonra: 2 adet + 250 ml". Same principle as the filter sheet's result count: a user about to empty their last carton should see that before they lose it, not after.

**Nothing is disabled that could be preselected.** A disabled primary button in a sheet usually means the sheet asked a question it could have answered.

## Taking stock out

| Field | Default | Why |
|---|---|---|
| Reason | Tüketildi | The only one forecasting counts |
| Lot | FEFO: the open one, else the earliest expiring | Waste prevention, and it is the one the user is holding |
| Amount | The first offered option | Removes the empty state entirely |

**Reason comes first, not last.** It changes what the numbers mean: forecasting sums consumption and excludes waste, and the waste metric is a filter on this field. Asking last also invites leaving it on the default, which would log every thrown-out carton as demand and have the app recommend buying more of what the user keeps wasting.

The reason list is short and closed for the same reason. Free text would make both metrics uncomputable, and a longer list would make the most frequent action slower.

**FEFO prefers the open lot** over a merely-earlier printed date, because an opened container is already on a shorter clock than anything sealed (D27). That is also the physical answer: the opened carton is the one at the front of the fridge. The choice stays visible and changeable, because an automatic default that cannot be overridden is how a user ends up fighting the app when they took the carton from the back.

**Consuming part of a sealed unit opens it, without asking.** Taking 500 ml from a sealed 1 lt carton produces an open lot with 500 ml left and starts its after-opening clock. The user never says "I am opening this"; they say what they used and the state follows (D13, D29).

But **the button that will do it says so** ("kartonu açar"). A silent state change that shortens an expiry from a week to three days is exactly what a user needs to see coming, and discovering it afterwards means the app told them the opposite of the truth.

The offered amounts differ by lot state, which is the point:

| Selected lot | Offers |
|---|---|
| Open, 500 ml left | 250 ml, 500 ml (hepsi) |
| Sealed 1 lt carton | 1 adet, 500 ml (opens it) |
| No content declared | Whole units only |

A bag of nails goes out in whole nails, so a product with no content declaration is never offered a fraction.

## Putting stock in

| Field | Default | Basis shown |
|---|---|---|
| Amount | 1 unit, plus a "hedefe tamamla" offer | The gap to `par_level` |
| Location | The one already holding the most of this product | "burada N parti var" |
| Expiry | Today plus the shelf life | "raf ömründen (N gün)" |

**"Hedefe tamamla" is offered only when it differs from the everyday amounts.** The gap to target is what a user restocking actually wants and the number they would otherwise work out at the shelf, but offering it beside an identical "2 adet" is a duplicate rather than a shortcut.

**The location suggestion is the affinity model's UI.** `location-assignment.md` ranks co-location affinity first, and the fixture stands in for it with "the location already holding the most of this product", so the screen is designed against the right shape of answer. Whether the real model's confidence should gate the suggestion is open.

**No expiry field appears for a product that declares no shelf life.** Inventing a date input for a box of screws is how a form gets long enough to be abandoned, and it is also the food-app framing D2 warns against.

**Adding stock is never disabled**, unlike taking it out. Any level is valid, including from zero: that is how a depleted product comes back.

## What is not designed yet

- **Moving stock between locations.** The header action exists and does nothing. It is a paired movement in the ledger (out of one location, into another) and it needs the same lot picker.
- **Undo.** The ledger is append-only, so an undo is a compensating movement rather than a delete. Whether the sheet offers one immediately after a commit, and for how long, is open.
- **Bulk entry.** A receipt scan produces many lines at once and cannot go through a sheet per line. That belongs to `receipt-ingestion.md` and it is why these two sheets stay single-product.
- **Serial-tracked take-out.** The detail screen handles serial tracking (below), but the sheets do not yet: a serial take-out picks a specific unit rather than an amount, so the amount buttons do not apply and the lot picker becomes a serial picker.

## Serial tracking (D28)

A product declares whether its units are fungible or individually identified, and the two are mutually exclusive **by nature rather than by policy**: partial consumption only means something for a quantity. Half a drill does not exist, so a product carrying both a content declaration and serials would describe something impossible. A test asserts a serial-tracked fixture has no lots, no content and no open unit.

What changes on the detail screen:

| Lot-tracked | Serial-tracked |
|---|---|
| "Partiler", with a quantity per row | "Seri numaraları", with a serial per row and no quantity |
| Row date is an expiry | Row date is a warranty end |
| Location holds a possibly-fractional amount | Location holds a whole count |
| Section is not collapsible | Section IS collapsible |

The section collapses because forty identical drills are forty rows a user reads only when hunting one specific unit, whereas a lot list is short by nature and is what the user came for.

**The warranty reuses the expiry machinery.** Same derived warning window, same badge, same place in the attention list. A warranty running out and a carton going off are the same shape of problem, a date after which the thing is worth less, and two mechanisms would be two things to keep in sync for no gain. A shop that misses a warranty expiry eats the repair.

**Units that have left stay in the list, faded**, like a depleted lot. A shop asked "did we ever have this serial" needs the answer to be yes rather than silence.

**The standing cost of shipping both models is real and already showing.** Twice now a lot-shaped assumption has quietly broken the serial path: once summing lots for a location total (which reported "0 konum" beside two drills on a shelf) and once hardcoding the identity card (which put a carton of milk's description and EAN-13 on a power drill). Both were invisible until a serial-tracked fixture and its own catalog preview existed. **Every screen that branches on tracking mode needs a fixture and a preview for both paths**, or the second path is the one nobody looks at.
