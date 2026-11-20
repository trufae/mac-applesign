import SwiftUI

/// A crafting slot: a sunken well framed by Liquid Glass.
struct Slot<Content: View>: View {
    var size: CGFloat
    var isTargeted = false
    var tint: Color? = nil
    @ViewBuilder var content: Content

    private var radius: CGFloat { size * 0.17 }

    var body: some View {
        content
            .frame(width: size - 16, height: size - 16)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.black.opacity(0.07).shadow(.inner(color: .black.opacity(0.28), radius: 5, y: 2)))
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    }
            }
            .clipShape(.rect(cornerRadius: radius, style: .continuous))
            // Scale the well, not the glass: a GlassEffectContainer draws the
            // glass itself and ignores transforms applied after .glassEffect,
            // so scaling the whole slot drifts the well off center.
            .scaleEffect(isTargeted ? 1.06 : 1, anchor: .center)
            .animation(.bouncy(duration: 0.3), value: isTargeted)
            .padding(8)
            .contentShape(.rect(cornerRadius: radius + 8, style: .continuous))
            .glassEffect(glass, in: .rect(cornerRadius: radius + 8, style: .continuous))
    }

    private var glass: Glass {
        if isTargeted { return .regular.tint(.accentColor.opacity(0.45)).interactive() }
        if let tint { return .regular.tint(tint.opacity(0.25)).interactive() }
        return .regular.interactive()
    }
}

/// Title and detail below a slot, like the captions of a DMG background.
struct SlotCaption: View {
    var step: Int
    var title: String
    var detail: String?
    var width: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Text("\(step)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(.tint, in: .circle)
                Text(title).font(.callout.weight(.semibold))
            }
            Text(detail ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: width)
    }
}

/// The app icon extracted from an IPA, or a generic placeholder.
struct AppIconView: View {
    var preview: AppPreview?
    var size: CGFloat

    var body: some View {
        Group {
            if let data = preview?.iconData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    LinearGradient(colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// Placeholder shown in an empty slot.
struct EmptySlotLabel: View {
    var symbol: String
    var text: String?
    var size: CGFloat = 38

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .light))
                .symbolRenderingMode(.hierarchical)
            if let text {
                Text(text).font(.caption).multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
    }
}
