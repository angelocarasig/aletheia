# Aletheia

@Metadata {
    @TechnologyRoot
}

An offline-first iOS reader for series, manhwa, and manhua - source-agnostic, built on GRDB.

## Overview

Minimum deployment target is **iOS 26** - the codebase always reaches for the newest API rather
than a fallback path (Liquid Glass, `WebPage`, `.sensoryFeedback`, symbol effects, and so on).
There's no earlier-OS branch to maintain.

Code is organized by type - database, network, reader, screens, and so on. Callers reach
persistence through ``aletheia/DatabaseClient`` directly.

## Topics

### Reference

- <doc:Architecture>
- <doc:Persistence>
- <doc:Framework>
- <doc:Providers>
- <doc:DetailsFeature>
- <doc:TrackerServices>
- <doc:ReaderFeature>
- <doc:BackgroundAndData>
- <doc:Home>

### Exploratory

- <doc:Ports>
- <doc:Research>
- <doc:Recommendations>
