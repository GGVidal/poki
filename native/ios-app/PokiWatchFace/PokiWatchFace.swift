// Adapted from semantic-craft/iOS-vibebuddy (VibeBuddyApp/WatchWidget/FollowedTaskWidget.swift,
// commit 2c2972d7), MIT License, Copyright (c) 2026 Xianwei Zhang.
// Poki adapts the WidgetKit complication families and widgetURL routing to Paper W01 with
// Poki's bear artwork and pokiwatch://start automatic launch.

import SwiftUI
import WidgetKit

@main
struct PokiWatchFace: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PokiWatchFace", provider: PokiWatchFaceTimeline()) { _ in
            PokiWatchFaceEntry()
                .unredacted()
                .widgetURL(URL(string: "pokiwatch://start"))
        }
        .configurationDisplayName("Poki")
        .description("Open Poki to control live voice or send a task.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private enum WatchFacePalette {
    static let pokiBlueFill = Color(.sRGB, red: 0.0, green: 119.0 / 255.0, blue: 253.0 / 255.0, opacity: 0x38 / 255.0)
    static let skyBlue = Color(.sRGB, red: 90.0 / 255.0, green: 167.0 / 255.0, blue: 1.0, opacity: 1.0)
    static let skyBlueCornerFill = Color(.sRGB, red: 90.0 / 255.0, green: 167.0 / 255.0, blue: 1.0, opacity: 0x29 / 255.0)
    static let cardFill = Color(.sRGB, red: 26.0 / 255.0, green: 29.0 / 255.0, blue: 38.0 / 255.0, opacity: 1.0)
    static let subtitle = Color(.sRGB, red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0, opacity: 0xAD / 255.0)
    static let chevron = Color(.sRGB, red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0, opacity: 0.40)
}

private struct PokiWatchFaceEntry: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularComplication
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")

        case .accessoryCorner:
            cornerComplication
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")

        case .accessoryRectangular:
            rectangularComplication
                .containerBackground(WatchFacePalette.cardFill, for: .widget)
                .accessibilityLabel("Open Poki")

        case .accessoryInline:
            Label("Poki Voice", systemImage: "waveform")
                .foregroundStyle(WatchFacePalette.skyBlue)
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")

        default:
            circularComplication
                .containerBackground(.black, for: .widget)
                .accessibilityLabel("Open Poki")
        }
    }

    private var circularComplication: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let bearSize = side * (67.0 / 72.0)
            ZStack {
                Circle()
                    .fill(WatchFacePalette.pokiBlueFill)
                    .overlay {
                        Image("WatchBear-ready")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: bearSize, height: bearSize)
                            .offset(x: side * (1.0 / 72.0), y: side * (2.5 / 72.0))
                    }
                    .clipShape(Circle())

                Circle()
                    .strokeBorder(WatchFacePalette.skyBlue, lineWidth: max(1.5, side * (2.5 / 72.0)))
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private var cornerComplication: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let bearSize = side * (50.0 / 54.0)
            Circle()
                .fill(WatchFacePalette.skyBlueCornerFill)
                .overlay {
                    Image("WatchBear-ready")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: bearSize, height: bearSize)
                        .offset(x: side * (1.0 / 54.0), y: side * (2.0 / 54.0))
                }
                .clipShape(Circle())
                .frame(width: side, height: side)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .widgetLabel {
            Gauge(value: 0.65) {
                Text("Poki")
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(WatchFacePalette.skyBlue)
        }
    }

    private var rectangularComplication: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(WatchFacePalette.pokiBlueFill)
                    .overlay {
                        Image("WatchBear-ready")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 41, height: 41)
                            .offset(x: 0.5, y: 1.5)
                    }
                    .clipShape(Circle())
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Poki Voice")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Tap or Double Tap")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(WatchFacePalette.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WatchFacePalette.chevron)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PokiWatchFaceTimeline: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
