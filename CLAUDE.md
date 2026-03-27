# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipeline**: Claude Code Stop hook → iCloud JSON → iOS companion → WatchConnectivity (`transferUserInfo`) → watchOS haptic + UI

## Build

Open `claude-tracker-applewatch.xcodeproj` in Xcode. No CLI build system.

## Status

Blank watchOS template. Features not yet implemented. See `FUTURE_PLAN.md` for the 6-phase roadmap.

## Workflow

- **Design**: use `/openspec-propose` to draft changes before implementing
- **SwiftUI**: invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code
