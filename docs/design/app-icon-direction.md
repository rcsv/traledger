# App icon direction: Activity Weaver

Last updated: 2026-07-21

## Status

The app icon is in **monochrome geometry validation**. No production icon asset has been
selected or added to Xcode yet.

`Activity Weaver` is the working name for the icon and brand concept. It describes the
product's central action — arranging independent Activities into one coherent trip — and
does not by itself rename the product. The product remains **TripMap** unless a separate
product-naming decision changes that.

## The decision so far

The leading icon concept is **Threaded Timeline** (also called **Threaded Itinerary**):

> Three independent Activity Cards are bound into one trip by a single chronological
> Thread.

The mark represents the *ordering and binding* of a trip's Activities, rather than a
literal route drawn on a map.

The current construction rules are:

- Use exactly three equal, horizontal Activity Cards.
- Keep the cards separate; do **not** overlap or fan them out.
- Use a single straight, vertical Thread positioned near the leading quarter of each card.
- Let the Thread pass in front of the top and bottom cards and disappear behind the middle
  card. The occlusion, not a curving line, communicates the weave.
- Do not add arrows, map pins, place glyphs, clocks, text, or card-internal details.
- Keep the middle card fully legible. The uninterrupted middle card can suggest the
  selected or current Activity without requiring a special color or label.

The design must work as a recognisable silhouette before color, Liquid Glass, or texture
are added.

## Why this direction

TripMap is not primarily a navigation replacement. Its value is that the same trip data
becomes a Planner before travel, a Guide during travel, and a Memory afterward. In every
phase, the durable unit is the Activity and the product's distinctive operation is placing
Activities in time and in relation to one another.

Threaded Timeline expresses that relationship directly:

| Element | Meaning |
| --- | --- |
| Three equal cards | Independent, equally valid Activities |
| Equal separation | Activities occupy distinct moments in a schedule |
| One vertical Thread | A continuous trip timeline |
| Front/back crossings | Activities are bound into an intentional sequence |

Removing card overlap was a deliberate improvement. A stack can imply simultaneity,
duplication, or an unorganised bundle; separation better expresses a planned itinerary.

## Alternatives considered and rejected

### Literal route

The earliest concept used a broad, curving route and an endpoint. It was distinctive but
too expressive: multiple curves introduced meanings such as wandering, turning back, or
drifting. The translucent base and coral endpoint also read as marine-themed artwork.

Simplifying a physical route tends to converge on an ascending Z, N, or S shape. Those
shapes carry an unwanted association with growth charts, optimisation, or generic forward
motion. Apple Maps and Google Maps avoid that ambiguity by providing a map field, road
context, and navigation marker; TripMap should not compete by imitating that category.

### Fold / hairpin silhouette

The first promising monochrome Fold shape had a strong silhouette but visibly encoded a
U-turn. A return journey is not a core promise of TripMap; the icon must also suit
multi-city and one-way travel. Keep the idea of a *fold* only as a relationship between
layers, not as a route that doubles back.

### Trip Spine

A straight timeline with three Activities is semantically clear. Showing all three cards
made it look like a signpost, a project plan, or a generic list. Cropping the outer cards
helped suggest continuity, but the concept remained close to timeline and Gantt-tool
iconography.

### Initial Trip Weave

The first Weave explorations used overlapping cards and a heavily curved thread. The
physical tag-and-string metaphor was promising, but overlap made the cards look bundled
instead of scheduled. The straight Thread and separated cards retain the useful binding
metaphor while removing the craft, price-tag, and route-line associations.

## Geometry under test

The favoured base geometry is **B**:

- Card aspect ratio: `2.6 : 1`
- Thread position: 25% from the leading edge of a card
- Three cards: equal size and equal width
- Thread depth order: front / behind / front

One geometry cannot serve every icon size. The Thread and the spaces between cards reach
subpixel dimensions when a single 1024px design is scaled to 24–32px. Optical-size variants
are therefore being tested:

| Variant | Use range | Card gap | Thread width | Corner radius |
| --- | --- | ---: | ---: | ---: |
| B-Large | 128px and above | 15% of card height | 18% | 9% |
| B-Medium | around 64px | 21% | 22% | 12% |
| B-Small | 32px and below | 28% | 28% | 16% |

The variants may change only gap, Thread width, radius, and pixel alignment. They must not
change the card count, card ratio, Thread position, or depth order; otherwise they become
different icons instead of optical corrections.

At 24px, a Thread may be only one physical pixel wide. The small variant prioritises a
two-pixel card gap so all three Activities remain distinct. Pixel-grid alignment must be
validated in the eventual PNG assets.

## Current evidence

The following artifacts are exploration tools, not production assets:

- [Initial six-variant monochrome study](threaded-timeline-monochrome-scale-study.svg)
  — useful for recording the route to B, but not a valid pixel-size test. Its 8–12% Thread
  widths scale below one pixel at 24–32px.
- [B optical-size comparison sheet](threaded-timeline-optical-sizes/threaded-timeline-b-optical-size-study.png)
  — compares B-Large, B-Medium, and B-Small at native raster sizes and with nearest-neighbor
  inspection.
- [Optical-size renderer](render_threaded_timeline_optical_study.py) — generates the sheet
  and the individual PNG files in `threaded-timeline-optical-sizes/`.

The comparison supports this allocation:

- B-Large holds the strongest compact mass at 128px and above.
- B-Medium is the most balanced form around 64px.
- B-Small is necessary at 32px and 24px, where B-Large and B-Medium allow the card gaps to
  collapse.

The primary unresolved monochrome issue is material continuity: the construction study uses
black outside the cards and white inside the outer cards to reveal Thread depth. At small
sizes this can read as a slit rather than a continuous thread. The color and appearance
phase must solve this without losing the depth order.

## Color and Liquid Glass: next phase

Do not choose a palette until the geometry is accepted. When color work begins, use roles,
not decoration:

- **Background:** the product's brand field.
- **Activity Cards:** a stable neutral layer; do not assign a different color to each card.
- **Thread:** one continuous accent material that is visible outside the cards, over the
  outer cards, and hidden only by the middle card.

The Thread must read as a single material. A color that flips between black and white should
be treated as a failed continuity test, not a final answer.

Liquid Glass should reinforce the existing depth relationship rather than add generic gloss.
The likely layer stack is:

1. Background
2. Rear Thread segment
3. Three Activity Cards
4. Front Thread segments over the top and bottom cards

Avoid making every card highly translucent or strongly refractive. The foreground silhouette
must survive Default, Dark, Clear, Tinted, and small-size appearances.

## Delivery decision pending

The choice of asset pipeline affects optical sizing:

- **Icon Composer** uses a single multi-layer design that the system renders across
  platforms, appearances, and sizes. It is the preferred Liquid Glass workflow, but it
  does not expose a documented per-size artwork substitution mechanism.
- **Asset Catalog, All Sizes** permits separate icon assets by size, making the B-Large /
  B-Medium / B-Small approach possible. It requires maintaining the variants and is less
  aligned with a single dynamic Icon Composer source.

Before production integration, decide whether the priority is:

1. A single Icon Composer source with a more conservative, size-robust Thread; or
2. Per-size optical correction in an Asset Catalog.

Do not mix an Icon Composer app icon with a separate asset-catalog app icon in the same
target without verifying the supported Xcode configuration.

## Current color and implementation baseline

The first buildable baseline uses the selected Dusty Blue / Signal Red palette:

- **Background:** Dusty Blue `#6E86A8`
- **Activity Cards:** Warm Ivory `#F4F1E8`
- **Thread:** Signal Red `#D92D20`

The repository now includes `TripMap/Assets.xcassets/AppIcon.appiconset/` with iOS and macOS
slots generated from the B geometry family. The renderer at
`docs/design/render_app_icon_assets.swift` applies optical correction: B-Large at 128px and
above, B-Medium around 80–128px, and B-Small at 64px and below. The iOS and macOS targets
reference the catalog through `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

This is an implementation baseline for device/build validation, not a final Liquid Glass
layer authoring decision. Appearance variants and Icon Composer migration remain follow-up
work after the raster silhouette is reviewed in actual system contexts.

## Liquid Glass structure study

The first layered source is now staged at `TripMap/AppIcon.icon/`. Its full-canvas layer
images live in the Icon Composer-managed `Assets/` subfolder. Four groups preserve the
weave in the actual layer structure: Thread Bed; Top Activity (Top Thread Front + Top Card);
Middle Activity; and Bottom Activity (Bottom Thread Front + Bottom Card). This keeps the
Thread's depth relationship explicit: the middle card occludes the rear Thread, while the
outer-card segments sit above their respective cards. Liquid Glass is enabled only on the
two front Thread crossings; the cards and Thread Bed remain solid.

`AppIcon.icon` is registered as a resource of both the iOS and macOS targets. The App Icon
build setting remains `AppIcon`, matching the Icon Composer filename. Xcode 27 therefore
selects the Icon Composer source over the legacy `AppIcon.appiconset`; the catalog remains
as a documented fallback/reference for the optical-size raster studies. A clean iOS
Simulator and macOS build confirmed that the compiled `Assets.car` contains the layered
`AppIcon.iconstack`, all four groups, and lighting effects on only the two front Thread
crossings. The next review should compare Default, Dark, Clear, and Tinted renditions and
check that refraction does not make the Thread look broken or overly glossy.

## Validation checklist before implementation

1. Inspect individual raster output at 128, 64, 32, and 24 pixels; do not infer this from a
   zoomed SVG alone.
2. Confirm the Thread is visible and that all three cards remain separate at 32px and 24px.
3. Compare the mark beside Calendar, Reminders, Apple Maps, and common list/server/project
   icons. It must not read first as a hamburger menu, server rack, signpost, or Gantt chart.
4. Run an unprompted recognition test: show the icon briefly, then ask what category and
   shape people remember. Do not lead with the phrase "travel app".
5. After color is selected, test Default, Dark, Clear, Tinted, and monochrome appearances on
   light and dark wallpapers.
6. Test in actual system contexts: Home Screen, Dock, Spotlight/Search, Settings, and
   notifications where applicable.
7. Import the final layers into Icon Composer or the Asset Catalog only after the preceding
   checks pass.

## Change log

- **2026-07-21:** Chose Activity Weaver as the working icon/brand concept; selected Threaded
  Timeline as the leading mark direction.
- **2026-07-21:** Rejected literal route, hairpin Fold, and overlapping-card Weave directions.
- **2026-07-21:** Chose the B geometry family and added B-Large / B-Medium / B-Small optical
  variants for validation.
- **2026-07-22:** Selected Dusty Blue background with Signal Red Thread and generated a
  buildable iOS/macOS AppIcon asset catalog with optical-size variants.
- **2026-07-22:** Added an Icon Composer layer study separating background, rear Thread,
  Activity Cards, and front Thread for constrained Liquid Glass treatment.
- **2026-07-22:** Registered `AppIcon.icon` with the iOS and macOS targets and verified the
  compiled layered icon stack in successful Xcode 27 builds.
