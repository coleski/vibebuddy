import ComposableArchitecture
import Foundation

@Reducer
struct PortManagementFeature {
  struct ProcessInfo: Identifiable, Equatable {
    let id = UUID()
    let pid: Int32
    let port: Int
    let processName: String
    let command: String
  }
  
  @ObservableState
  struct State: Equatable {
    var processes: [ProcessInfo] = []
    var isLoading = false
    var errorMessage: String?
    var lastRefreshDate: Date?
  }
  
  enum Action {
    case refresh
    case processesLoaded([ProcessInfo])
    case killProcess(ProcessInfo)
    case processKilled(ProcessInfo)
    case errorOccurred(String)
    case clearError
  }
  
  @Dependency(\.portManagementClient) var portManagementClient
  @Dependency(\.continuousClock) var clock
  
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .refresh:
        state.isLoading = true
        state.errorMessage = nil
        
        return .run { send in
          do {
            let processes = try await portManagementClient.getAllPortProcesses()
            await send(.processesLoaded(processes))
          } catch {
            await send(.errorOccurred(error.localizedDescription))
          }
        }
        
      case let .processesLoaded(processes):
        state.processes = processes
        state.isLoading = false
        state.lastRefreshDate = Date()
        return .none
        
      case let .killProcess(process):
        return .run { send in
          do {
            try await portManagementClient.killProcess(process.pid)
            await send(.processKilled(process))
            try await clock.sleep(for: .milliseconds(500))
            await send(.refresh)
          } catch {
            await send(.errorOccurred("Failed to kill process: \(error.localizedDescription)"))
          }
        }
        
      case let .processKilled(process):
        state.processes.removeAll { $0.id == process.id }
        return .none
        
      case let .errorOccurred(message):
        state.errorMessage = message
        state.isLoading = false
        return .none
        
      case .clearError:
        state.errorMessage = nil
        return .none
      }
    }
  }
}