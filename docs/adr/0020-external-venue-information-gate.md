# ADR 0020: Keep external Venue information outside the product boundary

Status: Accepted

Date: 2026-07-25

## Context

Place Card and Activity Card previously repeated the same information. The
current design instead keeps Activity ownership distinct from a compact Venue
snapshot and lets Maps provide changing directory detail.

User ratings and vote counts could improve confidence when choosing a Venue.
A Wikipedia overview could add useful context for landmarks. The likely
providers, however, have materially different identities, licenses, freshness,
commercial incentives, and failure modes from MapKit.

TripMap must remain useful without any external provider, must not embed
secret credentials, and must not create an application server solely to
enrich a card. A booking inventory result must also never become a local
reservation without explicit user confirmation.

## Decision

MapKit remains the sole Venue selection authority. The shipped Venue surface
continues to show the persisted MapKit-derived snapshot, image precedence, and
Maps handoff. It does not show an external overview, rating, vote count, review
text, price, availability, website, phone number, or business hours.

Tripadvisor is blocked because place mapping, partner approval, credentials,
display rules, cache constraints, and the API transition cannot be justified
for one optional card metric.

Booking.com Demand API is rejected for Venue enrichment. It is a managed
affiliate inventory and booking surface rather than a neutral general-place
source, and its credentials require a protected service boundary.

Trip.com is blocked because publicly accessible documentation does not expose
enough of the relevant data, identity, attribution, cache, cost, and
credential contract to approve integration. Consumer pages will not be
scraped.

Wikipedia overview is not approved for production. It is eligible for a later
isolated, in-memory spike only after a supported endpoint and reliable
MapKit-to-article identity strategy are proven. Any provider result must carry
its source, language, attribution, version, and canonical article URL. Failure
omits the overview without degrading the existing Venue Card.

The detailed evidence, provider matrix, and future test cases live in
`docs/qa/venue-external-information-research-gate.md`.

## Consequences

- The product avoids a new server, secret, commercial dependency, and
  provider-specific stored identifier.
- Activity and Venue ownership remain clear.
- The user always has the native Maps path to live place detail.
- Desired rating and vote-count functionality remains an explicit deferred
  capability instead of being silently discarded.
- Existing user-image, Look Around, Wikimedia-image, and placeholder
  precedence does not acquire a second cancellation or caching pipeline.
- A future provider proposal must reopen this ADR with official terms,
  identity evidence, unavailable UI, deletion behavior, cache policy, key
  boundary, cost, and regional coverage.

## Verification

- The gate compares MapKit, Wikimedia/Wikipedia, Tripadvisor, Booking.com, and
  Trip.com using public official documentation.
- Known Japanese Wikipedia landmark titles were queried only as a reachability
  observation; that result was not treated as identity proof.
- No provider credential, SDK, endpoint, model field, UI dependency, or server
  was added.
