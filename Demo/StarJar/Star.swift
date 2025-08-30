//
//  Star.swift
//  Demo
//
//  Created by hezeying on 2025/8/30.
//

import SwiftUI

struct Star: View {
    var body: some View {
        Image("star")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
    }
}

#Preview {
    Star()
}
