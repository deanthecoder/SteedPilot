# Route geometry regression fixtures

These seven MapKit routes were captured on September 6, 2026, using source revision `50ad2e1324a24419fd5aebb2b93b395e38b267b2`. They preserve closely spaced roundabouts and unaffected turns for deterministic tests without network requests.

Each `.json.gz` file contains route and step geometry, reported distances, and the original navigation targets. Route points are `[localEastMeters, localNorthMeters, distanceAlongRouteMeters]`; step points contain only the first two values. Local coordinates use a Mercator scale at `origin`, stored as `[latitude, longitude]`. Along-route lengths use `MKMapPoint.distance`.

`tools/test_route_geometry` decompresses these inputs into a temporary directory and runs them through the production route builder. The tests verify three corrected roundabout targets, fourteen unchanged roundabouts, and twenty-three unchanged ordinary turns/arrivals. They also check that roundabout approach samples stay within their own steps.

The captures are overlapping planned routes, not GPS logs or verified road-entry positions. Expected corrections are recorded in `tools/steedpilot_route_geometry_tests.swift`.
