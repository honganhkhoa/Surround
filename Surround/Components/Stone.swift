//
//  Stone.swift
//  Surround
//
//  Created by Anh Khoa Hong on 29/12/2020.
//

import SwiftUI

struct Stone: View {
    var color: StoneColor?
    var shadowRadius: CGFloat = 0.0
    
    var body: some View {
        GeometryReader { geometry -> AnyView in
            let size = geometry.size.width
            let path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
            return AnyView(erasing: Group {
                switch color {
                case .black:
                    if shadowRadius > 0 {
                        ZStack {
                            Path(path).fill(
                                Color(red: 0.6, green: 0.6, blue: 0.6)
                                    .shadow(.inner(color: Color.black, radius: size / 4, x: -size / 2.5, y: -size / 2.5))
                            ).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
                        }
                    } else {
                        Circle().fill(Color.black)
                    }
                case .white:
                    ZStack {
                        if shadowRadius > 0 {
                            Path(path).fill(
                                Color.white
                                    .shadow(.inner(color: Color(red: 0.8, green: 0.8, blue: 0.8), radius: size / 4, x: -size / 2.5, y: -size / 2.5))
                            ).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
                        } else {
                            Circle().fill(Color.white)
                        }
                        Circle().stroke(Color.gray, lineWidth: 0.5)
                    }
                case .none:
                    ZStack {
                        if shadowRadius > 0 {
                            Path(path).fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black, Color.white]
                                    ),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
                        }
                        Text(verbatim: "?").font(Font.system(size: size / 1.5).bold()).foregroundColor(Color.white)
                        Circle().stroke(Color.gray, lineWidth: 0.5)
                    }
                }
            }.aspectRatio(1, contentMode: .fit)
            )
        }
    }
}

#if DEBUG
#Preview("Black with shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .black, shadowRadius: 2)
        .frame(width: 25, height: 25)
}

#Preview("White with shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .white, shadowRadius: 2)
        .frame(width: 25, height: 25)
}

#Preview("Empty intersection", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: nil, shadowRadius: 2)
        .frame(width: 25, height: 25)
}

#Preview("Black with shadow — Dark", traits: .fixedLayout(width: 100, height: 50)) {
    ZStack {
        Rectangle().fill(Color(UIColor.systemGray5))
        Stone(color: .black, shadowRadius: 2)
            .frame(width: 25, height: 25)
    }
    .colorScheme(.dark)
}

#Preview("White with shadow — Dark", traits: .fixedLayout(width: 100, height: 50)) {
    ZStack {
        Rectangle().fill(Color(UIColor.systemGray5))
        Stone(color: .white, shadowRadius: 2)
            .frame(width: 25, height: 25)
    }
    .colorScheme(.dark)
}

#Preview("Black without shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .black)
        .frame(width: 25, height: 25)
}

#Preview("White without shadow", traits: .fixedLayout(width: 100, height: 50)) {
    Stone(color: .white)
        .frame(width: 25, height: 25)
}
#endif
