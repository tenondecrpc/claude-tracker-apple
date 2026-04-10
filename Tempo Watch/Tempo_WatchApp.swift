//
//  Tempo_WatchApp.swift
//  Tempo Watch App
//
//  Created by Cristian Paniagua on 27/03/2026.
//

import SwiftUI

@main
struct Tempo_WatchApp: App {
    @State private var store = TokenStore()
    @State private var receiver: WatchSessionReceiver?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear {
                    if receiver == nil {
                        receiver = WatchSessionReceiver(store: store)
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(TokenStore.self) private var store

    var body: some View {
        @Bindable var bindableStore = store
        TabView {
            ContentView()
                .tag(0)
            TrendView()
                .tag(1)
            SessionView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .sheet(item: $bindableStore.pendingCompletion) { (item: SessionInfo) in
            CompletionView(session: item)
        }
    }
}
