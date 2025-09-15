import ComposableArchitecture
import SwiftUI

struct PortManagementView: View {
  @Bindable var store: StoreOf<PortManagementFeature>
  
  var body: some View {
    Group {
      if !store.processes.isEmpty {
        ForEach(store.processes) { process in
          Button(action: { store.send(.killProcess(process)) }) {
            Text("\(process.port)  \(process.processName)")
              .font(.system(.body))
              .frame(minWidth: 200, alignment: .leading)
          }
          .buttonStyle(PortButtonStyle())
        }
      } else {
        Button(action: {}) {
          Text("No ports in use")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(true)
      }
      
      if let error = store.errorMessage {
        Button(action: { store.send(.clearError) }) {
          Text("Error: \(error)")
            .font(.caption)
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
      }
      
      Divider()
    }
    .onAppear {
      store.send(.startAutoRefresh)
    }
    .onDisappear {
      store.send(.stopAutoRefresh)
    }
  }
}

struct PortButtonStyle: ButtonStyle {
  @State private var isHovering = false
  
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundColor(isHovering ? Color.red.opacity(0.7) : Color.primary)
      .onHover { hovering in
        isHovering = hovering
      }
  }
}