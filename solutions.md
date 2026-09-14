# Solutions

Branch: `fix/res-101-107-bug-tickets`. Each ticket/feature is one commit,
prefixed `[RES-10x]` / `[F-x]`, with its regression test(s) in the same
commit.

---

## Part A — Bug tickets

### RES-101 · Search shows results for the wrong query

**Root cause.** `SearchDealsController.onQueryChanged` fires a new search on
every keystroke with no guard against out-of-order responses.
`FakeApiService.searchDeals` deliberately makes **shorter (broader) queries
slower** than longer ones (`broadness = max(0, 1200 - length*280)`). So
typing "sushi" fires requests for "s", "su", "sus"... in that order, but
"s" — the slowest — can resolve *last*, and its `results.assignAll(...)`
overwrites the correct "sushi" results with stale ones for "s".

**Fix.** A monotonically increasing request id captured before each async
call; a response is only applied if `_requestId` hasn't moved on since.
Debouncing alone would reduce request volume but not fix this — two
in-flight requests can still resolve out of order under variable latency,
debounced or not. The id-guard is the actual invariant that needs to hold.

**Rejected alternative:** cancelling the previous HTTP call outright. The
fake backend has no cancellation API, and even with a real one, cancellation
races the response arriving anyway — you still need the guard.

**Edge cases:** clearing the box mid-flight (`query.trim().isEmpty`) still
bumps the request id and returns early, so a slow in-flight response for
the previous text can't repopulate results after the user cleared the box.

---

### RES-102 · Crash after leaving My orders

**Root cause.** `_PickupCountdownState.initState()` starts a
`Timer.periodic` and never stores a reference to it. There's no `dispose()`
override, so nothing ever cancels it. A couple of seconds after the widget
is disposed, the timer fires and calls `setState()` on a dead `State`.

**Fix.** Store the `Timer` and cancel it in `dispose()`. This is the
textbook fix for this exact bug class — nothing to weigh against.

**Edge cases:** the countdown's `build()` already treats a negative
remaining duration as "Pickup window is open", so no change was needed
there; the bug was purely about timer lifecycle, not display logic.

---

### RES-103 · Requests pile up the longer you browse

**Root cause.** `DealDetailsController.onInit()` calls
`ever(cartService.itemCount, (_) => _recheckAvailability())` to keep stock
info fresh, but never disposes the returned `Worker`. The controller itself
*is* torn down when the screen closes (`Get.lazyPut`, no `fenix`), but a
`Worker` from `ever()` is an independent subscription against
`cartService.itemCount` (a permanent, session-lived singleton) — it is not
tied to the controller's lifecycle just because the controller created it.
Every deal ever viewed leaves one more permanent listener behind; each
"Add to bag" fires all of them, each issuing a `GET /deals/:id`.

**Fix.** Store the `Worker` and call `.dispose()` in `onClose()`.

**Rejected alternative:** move the cart-watching logic into `CartService`
itself, keyed by deal id, so there's only ever one listener no matter how
many detail screens have been visited. This is arguably the more scalable
design, but it's a bigger structural change for a ticket whose actual bug
is "a per-screen resource was never released" — the minimal, correct fix is
disposing it, not restructuring who owns the subscription.

---

### RES-104 · Duplicate deals in the home feed

**Root cause.** `refreshDeals()` (`assignAll`) and `loadMore()` (`addAll`)
mutate the same `deals` list with no coordination. If `loadMore()`'s
request for page *N* is still in flight when the user pulls to refresh,
`refreshDeals()` resets the list to page 1, and the stale page-*N* response
is then appended on top once it arrives — duplicated cards, or more items
than the catalog has, depending on exact timing.

**Fix.** Same generation-token pattern as RES-101: `refreshDeals()` bumps a
counter; `loadMore()` captures it before its request and discards the
result if a refresh happened meanwhile. `loadMore()` also no longer mutates
`_page` until its request actually succeeds (previously it incremented
optimistically and decremented on error — the generation guard makes that
dance unnecessary).

**Rejected alternative:** de-duplicating the final list by deal id before
rendering. That hides the symptom (no visible duplicates) without fixing
the actual race, and doesn't address "more items than the catalog" (which
isn't necessarily a *duplicate* id — it can also be a legitimate item that
just doesn't belong in the list at that point).

**Edge cases:** two refreshes in a row (double pull) also race each other
under the same mechanism — the second refresh's generation bump makes the
first one's completion a no-op, which is the correct behavior (last refresh
wins).

---

### RES-105 · Home feed is janky and memory keeps climbing

Three independent contributing causes, matching the ticket's "more than
one" framing:

**1. A single `Obx` wrapped the entire `Scaffold`, keyed on `scrollOffset`.**
`scrollOffset` updates on every scroll pixel, so every scroll frame rebuilt
the app bar *and the entire feed, including every card and every image
widget* — regardless of whether anything they render actually changed.
Fixed by scoping reactivity to just the two things that legitimately depend
on scroll position (app bar elevation, the scroll-to-top FAB), each behind
its own small `Obx`. The feed itself now only rebuilds when its own state
changes (`isLoading`, `todayOnly`, `deals`, `flashDeals`).

**2. `ListView(children: [...])` instead of `ListView.builder`.** Every
card for every loaded page existed simultaneously — nothing was ever
lazily built or disposed as it scrolled off-screen. Switched to
`CustomScrollView` + `SliverList.builder`.

**3. Images decoded at full native resolution.** Deals are served at a
fixed 1600×1200 regardless of display size (a ~160px-tall card thumbnail).
`TheNetworkImage` never capped the decode size, so `cached_network_image`
decoded — and cached — every image at full resolution:
`1600 * 1200 * 4 bytes (RGBA) = 7,680,000 bytes per image`, confirmed
exactly by the measurement below. Fixed with `memCacheWidth`/`memCacheHeight`
derived from the widget's actual display size × `devicePixelRatio`.

**Measurement (before/after).** A resource-constrained emulator made
driving the DevTools UI by hand unreliable, so I measured with two small,
temporary (not committed) instrumentation points instead of the DevTools
Performance/Memory tabs: a `DealCard` build counter, and
`PaintingBinding.instance.imageCache` stats logged every 2s. Same repro
both times: cold start, then 15 identical `adb shell input swipe` gestures
scrolling down the feed.

| metric | before | after |
|---|---|---|
| `DealCard` builds (start → after scroll) | 3 → **289** | 3 → **74** |
| unique cards scrolled past | 13 | 59 |
| rebuilds per unique card | **~22.2×** | **~1.25×** |
| image cache, bytes/image (avg) | **7,680,000** (exact: 1600×1200×4) | **~1,760,510** |

The image-cache-per-image number is the clean, timing-independent proof:
before, every image was decoded at the full native size no matter what;
after, decode size tracks what's actually on screen. The build-count number
is noisier (different runs scroll past a different number of cards, and the
"after" run's lighter per-frame cost means the same swipe gesture travels
further — itself a symptom of the "before" jank), but the *ratio* — rebuilds
per unique card landing near 1× after the fix vs. ~22× before — is the
signal that matters: cards now build once when they appear and stay inert
until their data actually changes, instead of rebuilding on every scroll
tick regardless.

**Rejected alternative:** `RepaintBoundary` around each card. That avoids
re-*painting* unchanged pixels but does nothing about the underlying
`Obx`-triggered *rebuild* (`build()` still runs, `CachedNetworkImage` still
re-evaluates) or the eager `ListView`/oversized image cache — it would have
treated the symptom DevTools shows (dropped frames) without touching either
actual cause.

**Not done:** I did not add a disk-cache size cap or a custom
`ImageCacheManager` — `memCacheWidth/Height` alone fixes the ballooning
described in the ticket, and going further wasn't demonstrated to be
necessary by the measurements above.

---

### RES-106 · Wrong pickup times; "Pickup today" filter misses deals

**Root cause.** The API sends pickup instants as ISO-8601 UTC.
`PickupWindowModel.label` formatted the raw UTC `DateTime` directly with
`DateFormat`, which reads a `DateTime`'s own field values regardless of its
`isUtc` flag — it does not convert to any particular timezone on its own.
Bangkok is UTC+7, so a 06:00–09:30 opening displays as the UTC clock digits,
exactly 7 hours behind: **23:00–02:30**, matching the ticket's repro
exactly. `isToday` had the same root problem from the other direction: it
compared `start.day` (the raw UTC day-of-month) against
`DateTime.now().day` (the *device's local* day) — two different reference
frames — so a pickup starting just after midnight Bangkok time (which falls
on the *previous* UTC calendar day) was wrongly excluded from "today".

**Fix.** Both getters convert to the market's fixed UTC+7 offset (Bangkok
has no DST, so a constant offset is exact, not an approximation) before
formatting or comparing calendar fields. `isOpenNow` and `untilStart` did
**not** need changing — `DateTime` comparison and `difference()` operate on
the absolute instant regardless of the UTC/local flag, so they were already
timezone-correct.

**Rejected alternative:** `.toLocal()`. That converts to the *device's*
timezone, which is correct only by coincidence if the device happens to be
set to Bangkok time — wrong for a QA device set to UTC, wrong for a
traveler's phone, and the ticket is explicit that the market's local time
is what matters here (a pickup window is meaningless in any timezone other
than the store's own).

**Rejected alternative (heavier):** the `timezone` package with a real IANA
`Asia/Bangkok` location. More "correct-looking" for a timezone with DST,
but Bangkok has none — a plain `Duration(hours: 7)` offset is exact, and
pulling in a timezone database (plus its own data-freshness concerns) buys
nothing here.

---

### RES-107 · Deep link opens to a crash

**Root cause.** `DealDetailsController.onInit()` did
`deal = Get.arguments as DealModel` unconditionally. Navigating from the
feed passes the already-fetched `DealModel` as `arguments` (`Get.toNamed(
Routes.dealRoute(...), arguments: deal)`), so that path always had a real
object to cast. A deep link — real or the in-app simulator — only supplies
an `id` query parameter; nothing is in memory yet, so `Get.arguments` is
`null` and the cast throws exactly the reported
`type 'Null' is not a subtype of type 'DealModel'`.

**Fix.** `deal` became a nullable `Rxn<DealModel>`. `onInit` now falls back
to `dealRepo.fetchById(int.parse(Get.parameters['id']))` when no
`DealModel` was passed as arguments. Since that's async, the screen shows a
brief loading spinner while it resolves, then renders the *same* page
either way — an error state only appears if the id is missing/invalid or
the deal genuinely doesn't exist (per the ticket, deal 42 always exists, so
the real repro always lands on the working page, verified live via
`adb shell am start ... rescu://open/deal?id=42&source=push`).

**Rejected alternative:** keep `deal` as a required, non-null field and
block navigation to the route entirely until a fetch completes (e.g. do the
fetch in the middleware before entering the page). That pushes the loading
state to a place the user never sees feedback for (a dead tap on a
notification with no visual response until the page suddenly appears) —
worse UX than a spinner on the page they were already taken to.

**Edge case handled:** the "id exists but deal doesn't" and "id missing/
malformed" cases both show a `This deal could not be found.` state rather
than a second crash.

---

## Part B — Features

### F-1 · Live flash-sale countdowns

One shared `CountdownTickerService` (a `GetxService` with a single
`Timer.periodic(1s)`, cancelled in `onClose`) drives every countdown in the
app, instead of each of 100+ visible cards running its own timer.
`FlashCountdown` is a small widget whose `Obx` is scoped to just the
countdown `Text` — wrapping only a flash-sale badge, not the card around
it, so the RES-105 fix isn't undone: a plain (non-flash) `DealCard` never
subscribes to the tick at all.

`DealModel.isFlashSaleExpired` is the single source of truth for "this
countdown hit zero", used consistently by the card (dims + disables tap +
swaps badge to "Expired"), the details screen (disables "Add to bag",
relabels it), and `CartService` (see below).

**Underspecified-ish decision:** what "the deal can no longer be added to
the bag" means when the countdown ticks to zero *while the user is looking
at the button*, not just on the next screen load. Handled by making the
details-screen button itself reactive (its own small `Obx`, only for flash
deals) rather than only checking expiry at tap time — the button visibly
disables itself the instant the countdown crosses zero.

**Cart interaction:** `CartService` subscribes to the same shared tick to
sweep expired flash-sale lines out of the bag with a snackbar, independent
of whether any countdown widget for that deal happens to be on screen —
this is the same mechanism F-3 reuses for reservation expiry (see below),
so a user sitting on, say, the Orders screen still gets their bag corrected
in real time.

---

### F-2 · Impression tracking

`ImpressionTracker` wraps each card with `visibility_detector`: a `Timer`
starts the moment `visibleFraction >= 0.5` and is cancelled if visibility
drops below that before the timer fires, so a card only counts as
"impressed" after a full continuous second above threshold. Wired into the
flash rail, home feed, and search results, each with their own `source`
and `position`.

Dedup ("at most once per deal per session, across all screens") and
delivery live in `AnalyticsService`, not the widget — a `Set<int>` of
already-impressed deal ids is checked before anything else happens, and
because it's on the (permanent, singleton) service rather than per-widget
state, "across all screens" falls out for free: seeing the same deal in
search *and* the home feed only logs once, whichever happens first.

Batching: events queue up; a flush fires at 10 events or `batchInterval`
(15s in production) since the *first* unsent event, whichever comes first,
delivered via `FakeApiService.sendAnalyticsBatch`. `batchInterval` is a
constructor parameter defaulting to 15s purely so tests don't have to wait
15 real seconds to exercise that path — production behavior is unchanged.

**Rejected alternative:** computing visible-for-1s using
`RenderObject.paintBounds` + a per-frame callback instead of
`visibility_detector`. The package already solves the "throttle this so
scrolling doesn't regress" problem (it batches its own checks rather than
running one per frame); reimplementing that was not worth it for something
already in `pubspec.yaml`.

---

### F-3 · Stock reservations with optimistic UI

**The underspecified question — what happens when a reservation expires
while the user is still in the app, or mid-checkout — has two different
answers depending on *where* it happens, and I think that's actually the
right shape for the decision, not a cop-out:**

- **Sitting in the bag, off-checkout:** `CartService`'s existing tick-driven
  sweep (introduced for F-1's flash-sale expiry) also checks
  `reservation.isExpired`. An expired line is removed automatically, with a
  snackbar naming what was removed. Rationale: the hold is *already gone*
  server-side by definition of "expired" — there is no correct amount of
  stock this line represents anymore, so continuing to show it as "in your
  bag" would be actively misleading. This mirrors how the flash-sale-expiry
  sweep from F-1 already works, which made this a natural extension rather
  than a new mechanism.

- **Mid-checkout (the API's 410):** checkout fails **closed**, with a
  plain-language message ("review your bag and try again"), and does
  **not** try to silently drop just the offending line and resubmit.
  `POST /checkout` doesn't say *which* line's reservation was the problem,
  and a checkout is one atomic action from the user's point of view — an
  order confirmation for a request that silently became a *different*
  request than what they saw is a worse outcome than asking them to look
  again. The tick sweep (already running) independently removes the actual
  expired line within the next second, so "review your bag" leads
  somewhere — the bag will already show what's still valid.

**Rejected alternatives for the mid-checkout case:**
- *Auto-retry checkout with the expired line dropped.* Changes what the
  user is charged for without them seeing it happen — the "wrong" kind of
  behavior the ticket warns about.
- *Extend/renew the reservation silently on 410 and resubmit.* The 410
  means the *stock hold* is gone; re-requesting a hold at the moment of
  checkout can itself fail (contention), so this just relocates the same
  failure one step later while pretending nothing happened in between.
- *Do nothing special (fall through to the generic "Checkout failed"
  message).* Loses the chance to explain *why* — a raw "Unknown
  reservation"/"Reservation expired" string is not something a non-technical
  user should have to parse.

**Invariant used to keep the rest of the implementation simple:** a cart
line's `reservation`, whenever non-null, always covers **at least** its
current `quantity`. This means:
- `add()` (new line or increment) reserves for the *new total*, then
  releases whatever reservation existed before — there is a brief window
  where both are held, never a window with zero coverage.
- `decrement()` above zero releases the old reservation and reserves the
  *smaller* quantity, so a reduced bag doesn't keep blocking stock nobody
  in that bag needs anymore. If that shrink-reservation fails, the old
  (larger) reservation and quantity are kept rather than leaving the line
  uncovered — over-holding is harmless (`checkout` only validates that a
  reservation id is valid and unexpired, not that its quantity matches),
  losing an already-secured item to a failed "shrink" is not.
- Any `add()`/`decrement()` failure only ever rolls back the *quantity
  delta* that triggered it, never touches an already-confirmed reservation
  that covered the prior state.

All of `add`/`decrement`/`remove`/`clear` update the observable list
**before** awaiting the network call (optimistic), then reconcile in a
`try/catch/finally` — instant feedback, a `Get.snackbar` with the (already
non-technical) `ApiException.message` on failure, and `isReserving` cleared
in `finally` regardless of outcome.

**Not done / scope cut:** the UI does not offer a manual "extend my hold"
action before it expires — nothing in the ticket asks for it, and it would
need its own product decision about whether extending is always allowed
(re-contending for stock a second time) that felt out of scope for this
pass.

---

## AI usage log

Used Claude (via Claude Code) for the entire branch: reading the existing
code to find root causes, writing fixes, writing and iterating on tests,
running `flutter analyze`/`flutter test`/the Android emulator to verify,
and drafting this document. Two concrete places it was wrong, how that was
caught, and what happened instead:

1. **Assuming `testWidgets`' fake clock only affects `Timer`, not
   `Future.delayed`.** While writing the `FlashCountdown` "fires
   `onExpired` exactly once" test, the first version used a bare
   `await Future.delayed(const Duration(milliseconds: 700))` inside the
   `testWidgets` body to let real time pass a countdown's deadline. That
   hung indefinitely — `flutter test` visibly counted up past two real
   minutes with the test still "running". `Future.delayed` is implemented
   on top of `Timer`, and Flutter's test binding virtualizes *all* Timer
   creation inside `testWidgets`, so the delay was waiting on a virtual
   clock nothing was advancing, not real time. Caught by watching the
   test's own progress counter climb with no result; fixed by wrapping the
   real wait in `tester.runAsync(() => Future.delayed(...))`, which
   explicitly opts that block out of the virtual clock. The same fix was
   then needed in the F-2 impression test and the F-3 cart-expiry test,
   which hit the identical issue.

2. **Trusting `debugPrintRebuildDirtyWidgets` output as a rebuild count.**
   For RES-105's before/after evidence, the first attempt set
   `debugPrintRebuildDirtyWidgets = true` and counted `Building DealCard`
   lines in the console log across a scripted scroll gesture. The "before"
   count came back suspiciously low (a handful of rebuilds) given the bug
   report described continuous whole-feed rebuilding — a number that would
   have *understated* the bug and could have led to shipping a fix while
   believing the measurement showed only a minor issue. The actual cause:
   Flutter throttles/drops console print volume under heavy bursts (exactly
   what a whole-tree rebuild-per-scroll-frame produces), so most lines
   never made it to the log. Caught by sanity-checking the number against
   what the bug report implied it should look like, rather than taking the
   log at face value. Replaced with a plain in-memory counter incremented
   in `build()` and reported once every 2 seconds — a single low-volume
   print that can't be throttled away — which is what produced the
   3→289-vs-3→74 numbers actually used above.

Smaller ones not written up in full: an early coordinate-scaling mistake
driving the emulator via `adb shell input tap` (screenshots were returned
at a different logical size than the physical device, so raw pixel
coordinates from a screenshot needed a 1.2× correction) caused a couple of
"nothing happened" taps that looked like app bugs before the scaling issue
was noticed; and a cart-reservation test initially asserted
`releasedIds == [firstReservationId]` based on a wrong assumption about
*when* `add()` releases a superseded reservation — the failing assertion
(`['res_1', 'res_2']` instead of the expected single id) was the thing that
surfaced the wrong assumption, not a re-read of the implementation first.

---

## Design questions

**Q1. `GetxController` lifecycle vs. widget `State` lifecycle, and a bug
from confusing them.**

A widget `State` lives and dies with its position in the widget tree:
`initState`/`dispose` fire whenever *that element* is inserted or removed,
which can happen many times for what a user perceives as "the same screen"
(e.g. rebuilt under a different parent, or via `GlobalKey` reparenting). A
`GetxController` registered via `Get.put`/`lazyPut` lives in GetX's DI
container and is scoped to *route lifetime* (or explicitly `permanent`),
tracked independently of any particular widget instance — `onInit`/`onClose`
fire once per route push/pop (or once ever, for permanent services), not
once per rebuild. The two are easy to conflate because a screen's
`GetView`/`StatelessWidget` typically has no `State` of its own at all —
all the "does this need cleanup" thinking naturally lands on the
controller, which is exactly where RES-103 went wrong: the assumption "the
controller gets recreated every time the screen opens, so anything it sets
up gets cleaned up too" is true for the controller's *own* fields, but not
for a `Worker` handed back by `ever()` — that's a subscription against the
*target* Rx (`cartService.itemCount`, on a permanent singleton), which has
nothing to do with the controller's lifecycle unless something explicitly
ties them together by calling `.dispose()` in `onClose()`. RES-102 is the
mirror image on the `State` side: a `Timer` started in `initState` was
assumed to be implicitly scoped to the widget the same way the widget's own
memory is — but a `Timer` is just as untethered from `State` lifecycle as a
`Worker` is from controller lifecycle unless `dispose()` says otherwise.

**Q2. When does a single `Obx` around a large subtree hurt, and how do you
decide how tightly to scope reactivity?**

It hurts exactly when the subtree contains widgets that *don't* depend on
the observable(s) the `Obx` is reacting to, but get rebuilt anyway because
they're in its `build()` closure — RES-105's top-level `Obx` on
`scrollOffset` is the extreme version: nearly the entire screen was
unrelated to scroll position, but all of it re-ran on every scroll pixel.
The cost isn't just wasted CPU on the rebuild itself; anything expensive
inside that scope (network image `build()` calls re-evaluating,
`CachedNetworkImage` re-checking its cache) pays that cost too, every time,
even though nothing they'd render changed. The way I decide scope: find the
smallest widget whose *entire visible output* is a pure function of the
observable(s) in question, and put the `Obx` there — usually a `Text`, an
icon's color, a button's `onPressed`/label, not the `Card`/`ListTile`/
`Scaffold` around it. If that smallest widget would need to rebuild on
every tick of something high-frequency (a per-second countdown, a
per-pixel scroll offset) and there are many instances of it (100+ cards),
that's the signal to also share the underlying trigger (one
`CountdownTickerService` Timer, not one per widget) rather than just
narrowing each `Obx` individually — narrow scope reduces *rebuild size* per
tick, a shared trigger reduces *tick count* system-wide, and both were
needed for F-1 to hold up under "100+ visible countdowns" the way RES-105
demanded for scrolling.

**Q3. A test that would have caught RES-106 before release, and what
would need to change to make it possible.**

The `label`-formatting half is already straightforwardly testable exactly
as written — the actual regression test in this branch
(`pickup_window_model_test.dart`) constructs a UTC instant, asserts the
formatted string, and fails against the old code with the exact reported
symptom (`23:00 – 02:30` instead of `06:00 – 09:30`); nothing about the
model needed to change to make *that* possible, because `label` never reads
ambient time at all. `isToday` is the harder half: the old implementation
compared against `DateTime.now()` directly, which makes a test's
correctness depend on *what real time it happens to run at* — a naive test
written the same way the bug happened (`start.day == DateTime.now().day`)
would only fail during part of the day (I confirmed this directly while
building this branch's own `isToday` test: whether the old code coincidentally
"passes" a given repro depends on the current UTC hour, since the bug is a
mismatch between two different timezone references that only sometimes
land on the same calendar day by chance). A test that pins its own
fixture *relative to* `DateTime.now()` at run time (compute "today in
Bangkok", construct a UTC instant that's "just after midnight Bangkok" from
that, assert `isToday`) sidesteps this without changing the source at all —
that's what this branch's test does, and it's deterministic regardless of
when it runs. But it's still exercising the *real* clock, which means the
test is only as trustworthy as this reasoning about UTC-hour boundaries —
to make `isToday` straightforwardly testable the way `label` already is
(assert-a-fixed-input, get-a-fixed-output, no reasoning about the clock
required), the model would need a way to inject "now" — either an optional
`DateTime Function() now` field or depending on `package:clock`'s
zone-based `Clock.now()` instead of the bare static call — so a test can
pin *both* sides of the comparison to fixed values instead of pinning one
side and computing the other from the real clock.

---

## Time spent, and what's next with one more day

Roughly a full day's worth of focused work across this session: exploring
the codebase and reproducing each Part A ticket, fixing and testing all
seven, then designing and building all three Part B features with their
own tests, plus live verification on an Android emulator throughout
(including unrelated environment setup — Flutter/Java/Android SDK
install, an emulator keyboard-passthrough config bug, and a DNS
misconfiguration that blocked image loading — none of which turned out to
be app bugs, but all of which cost real time before being ruled out).

With one more day:
- **RES-105 evidence in DevTools proper**, not just console
  instrumentation — the numbers here are real and reproducible, but a
  screenshot of the actual Performance/Memory tabs is more convincing than
  a table, and I'd want that if this were going to a reviewer who wasn't
  already following the reasoning.
- **F-3's "extend a hold" question** — right now an about-to-expire
  reservation has no user-facing action besides "wait and get swept out";
  a "your hold is expiring, tap to keep it" affordance in the last ~30
  seconds feels like the obviously-missing next feature once you've built
  the countdown display.
- **A widget/golden test for RES-105's Obx scoping** specifically (this
  branch verified it with instrumentation + live device checking rather
  than an automated regression test, unlike every other ticket) — e.g.
  asserting a `DealCard`'s `Key`ed element doesn't get a new `build()` call
  when only `scrollOffset` changes.
- **Q3's clock-injection seam**, actually implemented rather than just
  described, plus the deterministic `isToday` test that would come with it.
