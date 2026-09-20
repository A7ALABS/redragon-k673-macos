// Renders AppIcon.icns. Run from this directory: swift make-icon.swift
import AppKit
import SwiftUI

struct Key: View {
    let hue: Double
    var label = ""
    var body: some View {
        let glow = Color(hue: hue, saturation: 0.95, brightness: 1)
        RoundedRectangle(cornerRadius: 34)
            .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(glow.opacity(0.9), lineWidth: 5))
            .overlay(Text(label).font(.system(size: 92, weight: .heavy, design: .rounded)).foregroundStyle(glow).shadow(color: glow, radius: 18))
            .shadow(color: glow.opacity(0.85), radius: 38)
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.16), Color(red: 0.03, green: 0.03, blue: 0.04)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 4))
            VStack(spacing: 40) {
                HStack(spacing: 40) {
                    Key(hue: 0.98, label: "K").frame(width: 190, height: 190)
                    Key(hue: 0.12).frame(width: 190, height: 190)
                    Circle()
                        .fill(RadialGradient(colors: [Color(white: 0.38), Color(white: 0.12)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 130))
                        .overlay(Circle().stroke(Color(hue: 0.78, saturation: 0.9, brightness: 1), lineWidth: 6))
                        .overlay(Capsule().fill(Color.white.opacity(0.85)).frame(width: 12, height: 50).offset(y: -52).rotationEffect(.degrees(35)))
                        .shadow(color: Color(hue: 0.78, saturation: 0.9, brightness: 1).opacity(0.85), radius: 38)
                        .frame(width: 190, height: 190)
                }
                HStack(spacing: 40) {
                    Key(hue: 0.33).frame(width: 190, height: 190)
                    Key(hue: 0.5).frame(width: 190, height: 190)
                    Key(hue: 0.62).frame(width: 190, height: 190)
                }
                Key(hue: 0.88).frame(width: 650, height: 120)
            }
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon-1024.png"))
}

let sizes = [16, 32, 128, 256, 512]
try? FileManager.default.removeItem(atPath: "AppIcon.iconset")
try! FileManager.default.createDirectory(atPath: "AppIcon.iconset", withIntermediateDirectories: true)
func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
}
for s in sizes {
    run("/usr/bin/sips", ["-z", "\(s)", "\(s)", "icon-1024.png", "--out", "AppIcon.iconset/icon_\(s)x\(s).png"])
    run("/usr/bin/sips", ["-z", "\(s * 2)", "\(s * 2)", "icon-1024.png", "--out", "AppIcon.iconset/icon_\(s)x\(s)@2x.png"])
}
run("/usr/bin/iconutil", ["-c", "icns", "AppIcon.iconset", "-o", "AppIcon.icns"])
try? FileManager.default.removeItem(atPath: "AppIcon.iconset")
