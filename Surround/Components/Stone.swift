//
//  Stone.swift
//  Surround
//
//  Created by Anh Khoa Hong on 29/12/2020.
//

import SwiftUI

struct Stone: View {
    var color: StoneColor
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
                            Path(path).fill(Color.black).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
                            Path(path).fill(Color(UIColor.clear)).shadow(color: Color(red: 0.45, green: 0.45, blue: 0.45), radius: size / 4, x: -size / 4, y: -size / 4)
                                .clipShape(Circle())
                        }
                    } else {
                        Circle().fill(Color.black)
                    }
                case .white:
                    ZStack {
                        if shadowRadius > 0 {
                            Path(path).fill(Color(red: 0.75, green: 0.75, blue: 0.75)).shadow(radius: shadowRadius, x: shadowRadius, y: shadowRadius)
                            Path(path).fill(Color(UIColor.clear)).shadow(color: Color.white, radius: size / 4, x: -size / 4, y: -size / 4)
                                .clipShape(Circle())
                        } else {
                            Circle().fill(Color.white)
                        }
                        Circle().stroke(Color.gray, lineWidth: 0.5)
                    }
                }
            }.aspectRatio(1, contentMode: .fit)
            )
        }
    }
}

struct Stone_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Stone(color: .black, shadowRadius: 2)
                .frame(width: 25, height: 25)
                .previewLayout(.fixed(width: 100, height: 50))
            Stone(color: .white, shadowRadius: 2)
                .frame(width: 25, height: 25)
                .previewLayout(.fixed(width: 100, height: 50))
            ZStack {
                Rectangle().fill(Color(UIColor.systemGray5))
                Stone(color: .black, shadowRadius: 2)
                    .frame(width: 25, height: 25)
            }
            .previewLayout(.fixed(width: 100, height: 50))
            .colorScheme(.dark)
            ZStack {
                Rectangle().fill(Color(UIColor.systemGray5))
                Stone(color: .white, shadowRadius: 2)
                    .frame(width: 25, height: 25)
            }
            .previewLayout(.fixed(width: 100, height: 50))
            .colorScheme(.dark)
        }
    }
}
