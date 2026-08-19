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

### Architecture

- <doc:Schema>
- <doc:Comments>
- <doc:Design>
- <doc:LiquidGlass>
- <doc:WebKit>
- <doc:FeedbackIteration>

### Persistence

- ``aletheia/DatabaseClient``
- ``aletheia/DatabaseRecord``
- ``aletheia/ViewRecord``
- ``aletheia/UniqueRecord``

### Code Reference

- ``aletheia``

### Source Framework

- <doc:BuildingASource>
- <doc:SourceProtocols>
- <doc:SourceAuth>

### Providers

- <doc:MangaFireSource>
- <doc:NHentaiSource>
- <doc:AtsumaruSource>
- <doc:ScansGGSource>
- <doc:ToonilySource>
- <doc:MangaBallSource>

### Details Screen

- <doc:Details>
- <doc:AdultContent>
- <doc:Errors>
- <doc:LoadingTransitions>
- <doc:SelectionLanguage>

### Tracking

- <doc:Trackers>
- <doc:TrackerMetadata>
- <doc:TrackerMangaBaka>
- <doc:TrackerRestore>

### Reader Engine

- <doc:ReaderGeometry>
- <doc:PageDimensions>

### Background & Data

- <doc:BackgroundActivity>
- <doc:ActivityHistory>
- <doc:Metrics>
- <doc:LibraryBackup>

### Home

- <doc:HomeScreen>
- <doc:ReleasePrediction>

### Ports

Kept for future debugging reference, not current-state documentation - see each page's own status.

- <doc:Reader>
- <doc:ReaderBacklog>
- <doc:Library>

### Research: Search & Filters

Proposals and findings-only research, not current-state reference - each page states its own
status.

- <doc:SectionControls>
- <doc:SourceSearch>
- <doc:HighCardinalityFilters>

### Research: Storage & Sync

- <doc:ChapterStorage>
- <doc:ChapterComments>
- <doc:DatabaseWrites>
- <doc:OfflineAvailability>

### Research: Other

- <doc:Deeplinks>
- <doc:Metal>

### Recommendations

- <doc:Integration>
- <doc:PortPlan>
- <doc:V01Artifact>
- <doc:V02Artifact>
