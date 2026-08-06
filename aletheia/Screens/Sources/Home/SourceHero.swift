//
//  SourceHero.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Kingfisher

struct SourceHero: View {
    let source: Source
    let record: SourceRecord?
    let entries: [SeriesStub]
    let isLoading: Bool
    
    @Environment(\.dimensions) private var dimensions
    @State private var width: CGFloat = 0
    
    private enum Layout {
        static let heroHeight: CGFloat = 400
        static let coverWidthDivisor: CGFloat = 2.5
        static let cycleDurationPerEntry: Double = 5.0
        static let iconSize: CGFloat = 60
        static let iconScale: CGFloat = 1.0
        static let overlayDim: Double = 0.15
        static let shadowOpacity: Double = 0.5
        static let shadowRadius: CGFloat = 8
        static let shadowY: CGFloat = 4
    }
    
    private enum Motion {
        static let easing: Double = 0.3
        static let breatheRate: Double = 0.3
        static let breatheAmplitude: Double = 0.015
        static let linearFactor: Double = 0.7
    }
    
    private var coverWidth: CGFloat { max(width, 1) / Layout.coverWidthDivisor }
    private var cycleDuration: Double { Double(max(entries.count, 1)) * Layout.cycleDurationPerEntry }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Background
            
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .canvas.opacity(0.3), location: 0.4),
                    .init(color: .canvas.opacity(0.7), location: 0.8),
                    .init(color: .canvas, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            
            Overlay
        }
        .frame(height: Layout.heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
    
    @ViewBuilder
    private var Background: some View {
        if !entries.isEmpty, width > 0 {
            TimelineView(.animation) { timeline in
                let doubled = entries + entries
                let totalWidth = coverWidth * CGFloat(entries.count)
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let linear = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
                let eased = (1 - cos(linear * .pi * 2)) / 2 * Motion.easing
                let breathe = sin(elapsed * Motion.breatheRate) * Motion.breatheAmplitude
                let progress = linear * Motion.linearFactor + eased + breathe
                let offset = -totalWidth * progress
                
                Canvas { context, size in
                    for (index, entry) in doubled.enumerated() {
                        let x = CGFloat(index) * coverWidth + offset
                        let wrapped = x < -coverWidth ? x + totalWidth * 2 : x
                        guard wrapped > -coverWidth, wrapped < size.width + coverWidth else { continue }
                        if let symbol = context.resolveSymbol(id: entry.slug + String(index)) {
                            context.draw(symbol, at: CGPoint(x: wrapped + coverWidth / 2, y: size.height / 2))
                        }
                    }
                } symbols: {
                    ForEach(Array(doubled.enumerated()), id: \.offset) { index, entry in
                        KFImage(entry.cover)
                            .requestModifier(refererModifier)
                            .resizable()
                            .scaledToFill()
                            .frame(width: coverWidth, height: Layout.heroHeight)
                            .clipped()
                            .tag(entry.slug + String(index))
                    }
                }
                .overlay(Color.black.opacity(Layout.overlayDim))
            }
            .allowsHitTesting(false)
        } else if isLoading {
            Rectangle().fill(.surface).shimmer()
        } else {
            Rectangle().fill(Color.surface.opacity(0.3))
        }
    }
    
    private var Overlay: some View {
        HStack(alignment: .center, spacing: dimensions.spacing.space20) {
            Image(source.descriptor.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
                .overlay {
                    RoundedRectangle(cornerRadius: dimensions.radius.radius12)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                }
                .scaleEffect(Layout.iconScale)
                .shadow(color: .black.opacity(Layout.shadowOpacity), radius: Layout.shadowRadius, y: Layout.shadowY)
                .opacity(record?.disabled == true ? 0.5 : 1)
            
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(source.descriptor.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(source.descriptor.description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .truncationMode(.tail)
            }
            
            Spacer()
        }
        .padding(.horizontal, dimensions.screenMargin)
        .padding(.bottom, dimensions.screenMargin)
    }
    
    private var refererModifier: AnyModifier {
        let referer = source.descriptor.referer.absoluteString
        return AnyModifier { request in
            var request = request
            request.setValue(referer, forHTTPHeaderField: "Referer")
            return request
        }
    }
}
