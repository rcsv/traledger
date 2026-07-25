# Venue external information research gate

Status: Closed for the current product cycle

Date: 2026-07-25

## Question

Can a short Wikipedia overview, a third-party rating and vote count, or booking
inventory make Venue information meaningfully better without turning TripMap
into a place directory, weakening Activity/Venue ownership, requiring a
single-purpose application server, or making the core experience depend on an
external provider?

## Product boundary

The useful Venue surface remains deliberately small:

- the Activity owns time, day placement, notes, progress, category, and the
  user's reservation reference;
- the Venue snapshot owns the selected place identity, name, postal address,
  coordinate, optional MapKit category, and the route back to Maps;
- the image resolver owns user image, Look Around, Wikimedia image, and
  neutral placeholder precedence;
- Maps owns changing directory detail such as phone, website, opening hours,
  directions, and the broad place page.

A rating plus vote count would add useful decision confidence. It is not
rejected as a product idea. It is rejected for this cycle when the only
available sources require a commercial agreement, secret credentials, a new
server boundary, provider-specific place matching, or restrictive display and
cache behavior.

## Non-goals

- Scraping a consumer website or reproducing consumer review text.
- Adding an application server or reverse proxy solely to conceal a Venue
  enrichment key.
- Treating a provider search result as the selected MapKit Venue.
- Treating availability, a booking result, or an affiliate redirect as the
  user's `ReservationReference`.
- Generating summaries from reviews or sending user Trip/Venue data to a
  generative model.
- Shipping a provider SDK, API key, attribution treatment, or persisted
  provider payload during this gate.
- Changing the existing Wikimedia image fallback decision.

## Comparison matrix

| Source | Candidate value | Access and cost | Identity and coverage | Attribution and display | Freshness, cache, removal | Secret boundary | Current decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Apple MapKit and Maps | Selected place identity, address, category, Look Around, directions, richer system place detail | Native platform capability under the app's Apple platform use | Same source as Venue selection; coverage varies by place and region | System-provided presentation and Maps handoff | Live lookup plus the app's deliberate historical `PlaceSnapshot` | No new third-party secret | **Baseline adopted** |
| Wikipedia/Wikimedia overview | A short, locally meaningful description for landmarks | Public Wikimedia APIs; no product API key or per-request fee identified | Article availability and language vary. A title match alone cannot prove that an article and an `MKMapItem` identify the same place | Source link and Wikipedia/Wikimedia attribution are mandatory. Reused text remains subject to its content license; modifications must be identified | Rate limits and backoff apply. Cached or persisted text needs version/source/license/removal rules. Article redirects, renames, deletion, and edits must be handled | Client access is possible; a descriptive `User-Agent` is required | **Not adopted; isolated research spike is eligible** |
| Tripadvisor Content API | Rating, review count, limited review/photo context | Application and integration approval; production use is contractual. Published partner material describes quotas and Order-specific commercial terms | Provider location ID must be matched to the MapKit place. Partner guidance expects mapping and validation rather than assuming a name match | Exact rating, branding, link, and content rules apply; rating must not be rounded | Partner terms constrain caching and downstream use; quota and access can be changed or revoked. The legacy partner JSON API is in transition | Credentials must not be shipped in the app; a service boundary would be required | **Blocked** |
| Booking.com Demand API | Lodging inventory, price, availability, redirect or booking flow | Managed Affiliate Partner registration, signed agreement, affiliate ID, API token, and production approval | Strong for bookable accommodation, weak and biased for the general Venue concept | Booking.com display, pricing, availability, and redirect/booking requirements apply | Highly dynamic data; production readiness requires explicit cache, monitoring, and failure handling | Documentation says credentials must never be exposed client-side | **Rejected for Venue enrichment** |
| Trip.com developer platform | Potential accommodation or travel inventory and ratings | Public landing page exists, but detailed material inspected by this gate requires an assigned account login | Public evidence does not establish a general-place API or a supported MapKit-to-Trip.com identity contract | Terms, attribution, cache, rating precision, and removal requirements could not be verified without partner access | Cannot establish a safe freshness or deletion contract from public documentation | Assume credentials require protection until partner terms prove otherwise | **Blocked pending partner documentation; no scraping** |

## Official evidence reviewed

### Wikimedia

- [Wikimedia API usage guidelines](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_API_Usage_Guidelines)
- [Wikimedia User-Agent policy](https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy)
- [Wikimedia Terms of Use](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use)
- [MediaWiki TextExtracts documentation](https://www.mediawiki.org/wiki/Extension:TextExtracts)
- [MediaWiki page-content API guide](https://www.mediawiki.org/wiki/API:Get_the_contents_of_a_page)

The TextExtracts documentation says not to build new Wikimedia production
features on that API and points summary consumers toward the Page Content
Service. That makes a successful `prop=extracts` response evidence of current
technical reachability, not an acceptable production endpoint decision.

### Tripadvisor

- [Tripadvisor Content API](https://developer-tripadvisor.com/)
- [Content API FAQ](https://developer-tripadvisor.com/content-api/FAQ/)
- [Partner rating and review breakdown](https://developer-tripadvisor.com/partner/json-api/business-content/review-count-and-breakdowns/)
- [Partner FAQ](https://developer-tripadvisor.com/partner/faq/)
- [Master partnership terms](https://developer-tripadvisor.com/partner/master-partnerships-terms-and-conditions/)
- [Partner JSON API status](https://developer-tripadvisor.com/partner/json-api/)

### Booking.com

- [Demand API overview](https://developers.booking.com/demand/docs/getting-started/overview)
- [Prerequisites](https://developers.booking.com/demand/docs/getting-started/prerequisites)
- [Authentication](https://developers.booking.com/demand/docs/development-guide/authentication)
- [Production readiness](https://developers.booking.com/demand/docs/development-guide/production-readiness)
- [Sandbox](https://developers.booking.com/demand/docs/getting-started/sandbox)

### Trip.com

- [Trip.com developer platform](https://developers.trip.com/)
- [Trip.com developer sign-in](https://developers.trip.com/signIn/)

## Public-response observation

On 2026-07-25 the Japanese Wikipedia Action API returned a page ID, canonical
title, and plain-text introduction for each of the existing QA landmarks
`東京駅`, `那覇空港`, and `首里城`.

This observation proves only that known Japanese titles can currently resolve.
It does not close:

- MapKit-to-Wikipedia identity for same-name, nearby, renamed, or
  disambiguation pages;
- locale fallback when the preferred-language article is absent;
- a production-supported summary endpoint;
- attribution and license presentation;
- cache invalidation, article removal, or offline behavior.

No authenticated Tripadvisor, Booking.com, or Trip.com request was made.
Credentials, contractual access, and user data were neither available nor
required to reach the product decision.

## Test matrix for any future Wikipedia overview spike

| ID | Scenario | Required result |
| --- | --- | --- |
| W-01 | Exact landmark with a stable article and coordinate | Overview appears only after identity validation, with source and attribution |
| W-02 | Same title in multiple places | No overview until one candidate is proven to match |
| W-03 | Disambiguation, list, redirect, or administrative-area page | Redirect may be followed; disambiguation/list/wrong-scope content is omitted |
| W-04 | Preferred locale missing, another locale present | Deterministic documented fallback; language is exposed to presentation |
| W-05 | No matching article | Section is omitted without alert, empty card, or retry spinner |
| W-06 | Throttle, timeout, offline, malformed payload | Existing Venue Card remains complete and usable; Maps stays available |
| W-07 | Article renamed, removed, or suppressed after caching | Stale text is not presented indefinitely; removal wins on refresh |
| W-08 | Attribution and source interaction | VoiceOver reads source meaningfully and the source opens the exact article |
| W-09 | Long, changing, or newline-heavy introduction | Layout remains bounded without silently altering the author's meaning |
| W-10 | User image, Look Around, or Wikimedia image resolves concurrently | Overview work does not change image precedence or cancel image resolution |
| W-11 | Activity is moved, skipped, or its Venue is replaced | Request cancellation never commits content to a different Venue identity |
| W-12 | App relaunch with no network | No persisted overview is assumed until its cache/license policy is accepted |

## Gate decision

No external summary, rating, review count, or booking inventory will ship in
the current cycle.

MapKit remains the Venue authority and `Mapsで開く` remains the intentional
path to richer, changing place information. This is a complete fallback, not
an error state and not an invitation to add phone, website, hours, or review
content back into the Venue Card.

Wikipedia overview may proceed only as a separate, in-memory research spike
behind a provider protocol. The spike must:

1. accept an immutable Venue identity value rather than an Activity model;
2. validate article identity using more than an unqualified title;
3. use a currently supported Wikimedia endpoint;
4. return source URL, source language, attribution metadata, and content
   version alongside text;
5. omit the section on every failure;
6. avoid persistence until cache, license, update, and removal behavior are
   separately accepted;
7. remain independent from `VenueImageResolver`.

Ratings can be reconsidered only when either:

- a provider offers a documented client-safe API with an acceptable identity,
  attribution, cost, cache, deletion, and regional contract; or
- TripMap already has a justified general application service for broader
  product needs and a commercial provider agreement is approved.

An application server will not be introduced solely to make ratings possible.
