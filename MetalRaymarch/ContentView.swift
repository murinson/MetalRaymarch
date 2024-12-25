//
//  ContentView.swift
//  MetalProject
//
//  Created by MU on 18/11/24.
//

import SwiftUI
import RealityKit

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    
    @State private var speed: Float = 0

    var body: some View {
        VStack {
            ToggleImmersiveSpaceButton()
            
            if appModel.immersiveSpaceState == .open {
                Spacer()
                
                Text("Animation speed (caution: motion sickness!)")
                
                Slider(value: $speed, in: 0...2, onEditingChanged: { editing in
                    if !editing {
                        appModel.clock.speed = Double(speed)
                    }
                })
            }
        }
        .padding(40)
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
