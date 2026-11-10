# Packaged Thailand basemap

The offline map uses the Protomaps Basemap 4.15.2 daily PMTiles build for
2026-11-01 (`https://build.protomaps.com/20261101.pmtiles`), whose OSM
replication timestamp is `2026-11-01T04:00:00Z`. The original regional overview
covers longitude 97..106 and latitude 5.5..21 through z10. A Natural Earth
public-domain Thailand boundary adds Thailand detail at z11..12, and the latest
extract adds z13..15 inside that same boundary. Border overview remains z0..10;
tiles intersecting the country polygon can include a narrow area outside it.
This is a basemap, not turn-by-turn navigation data.

Final archive `20261101-z15-v4` is PMTiles v3 / MVT, **601,215,311 bytes**,
with 506,404 addressed tiles and native tile maximum z15. The z13..15 addition
is **512,082,477 bytes**. Representative z15 vector tiles were read from
Bangkok (25531/15119, 140,631 bytes), Chiang Mai (25393/14642, 82,260 bytes),
Phuket (25339/15664, 47,479 bytes), Udon Thani (25739/14773, 10,648 bytes),
and Chiang Rai (25471/14534, 45,241 bytes). The combined archive passed
`pmtiles verify`.

The high-detail extraction uses the Natural Earth 1:10m country boundary
(`ADM0_A3=THA`), which is public domain under
[Natural Earth terms](https://www.naturalearthdata.com/about/terms-of-use/).
Tiles derive from OpenStreetMap data distributed in Protomaps' ODbL Produced
Work. Keep attribution accessible to users: the MapLibre attribution control
links to [OpenStreetMap copyright](https://www.openstreetmap.org/copyright) and
[Protomaps basemap terms](https://docs.protomaps.com/basemaps/downloads).

The z13..15 tiles were extracted with the official go-pmtiles v1.31.2 CLI from
the regional boundary, not from OSMF tile servers:

```text
pmtiles extract https://build.protomaps.com/20261101.pmtiles thailand-z13-15.pmtiles --region=thailand-boundary.geojson --minzoom=13 --maxzoom=15
pmtiles merge thailand-z0-12.pmtiles thailand-z13-15.pmtiles thailand.pmtiles
pmtiles verify thailand.pmtiles
```

The versioned Protomaps style, sprites, glyphs and licenses are bundled under
this directory and resolved to local file URLs. Noto Sans assets use SIL OFL
(`FONT-LICENSE.txt`); arbitrary international peer names may need glyph ranges
not currently packaged. The source `maxzoom` is 15. MapLibre Native reuses
z15 vector tiles when the camera is above the source maximum, so camera zooms
16..18 are overzoomed views rather than new native-detail tiles. Small roads
are available only where present in the underlying OSM data.

MapLibre Flutter 0.27.1 uses Android MapLibre Native 13.5.0. Direct reads from
the APK asset failed on physical phones with PMTiles metadata decompression
errors. `MainActivity` therefore copies resources on a dedicated native worker
in 64 KiB chunks into the versioned app-private directory
`relio_offline_map/20261101-z15-v4`, atomically replaces each file, and writes
the completion marker last. This adds about 601 MB app-private storage; the
first Map opening waits for preparation while Nearby/List remain usable. Old
map directories are preserved. The archive stays uncompressed in Android
assets for random reads, and essential map data/style/glyph/sprites do not
require an Internet connection.

The legacy opt-in offline-area adapter remains for compatibility tests only;
it has no consumer entry point. No user download is required.
