# RELIO patch

This repository-local Android-capable source subset is based on
`nearby_connections` 4.3.0. It preserves Google Nearby connection resolution
codes/messages and correlates native callbacks with a RELIO trace ID. The
upstream BSD-2-Clause license is retained in `LICENSE`.

Changes are additive channel arguments/events and Dart callbacks. Existing
`Status` callbacks and Nearby file payload handling remain compatible. The
Android dependency remains `play-services-nearby:19.2.0`; this is not a
dependency upgrade. Revisit or remove this fork when upstream exposes
equivalent raw status and trace support.
