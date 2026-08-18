# ``aletheia``

An offline-first iOS reader for series, manhwa, and manhua - source-agnostic, built on GRDB.

## Overview

Minimum deployment target is **iOS 26** - the codebase always reaches for the newest API rather
than a fallback path (Liquid Glass, `WebPage`, `.sensoryFeedback`, symbol effects, and so on).
There's no earlier-OS branch to maintain.

Code is organized by type - database, network, reader, screens, and so on. Callers reach
persistence through ``DatabaseClient`` directly.

## Topics

### Architecture

- <doc:Schema>
- <doc:Comments>
- <doc:Design>
- <doc:LiquidGlass>
- <doc:WebKit>
- <doc:FeedbackIteration>

### Persistence

- ``DatabaseClient``
- ``DatabaseRecord``
- ``ViewRecord``
- ``UniqueRecord``

### Source Framework

- <doc:BuildingASource>
- <doc:SourceProtocols>
- <doc:SourceAuth>

### Features

- <doc:Details>
- <doc:Errors>
- <doc:LoadingTransitions>
- <doc:SelectionLanguage>
- <doc:AdultContent>
- <doc:ReaderGeometry>
- <doc:PageDimensions>
- <doc:TrackerRestore>
- <doc:LibraryBackup>
- <doc:Trackers>
- <doc:TrackerMetadata>
- <doc:TrackerMangaBaka>
- <doc:BackgroundActivity>
- <doc:ActivityHistory>
- <doc:Metrics>
- <doc:HomeScreen>
- <doc:ReleasePrediction>

### Providers

- <doc:MangaFireSource>
- <doc:NHentaiSource>
- <doc:AtsumaruSource>
- <doc:ScansGGSource>
- <doc:ToonilySource>
- <doc:MangaBallSource>

### Ports

Kept for future debugging reference, not current-state documentation - see each page's own status.

- <doc:Reader>
- <doc:ReaderBacklog>
- <doc:Library>

### Research

Proposals, findings-only research, and partially-implemented ideas - not current-state reference.
Each page states its own status.

- <doc:SectionControls>
- <doc:SourceSearch>
- <doc:HighCardinalityFilters>
- <doc:Deeplinks>
- <doc:OfflineAvailability>
- <doc:ChapterStorage>
- <doc:ChapterComments>
- <doc:DatabaseWrites>
- <doc:Metal>

### Recommendations

- <doc:Integration>
- <doc:PortPlan>
- <doc:V01Artifact>
- <doc:V02Artifact>
