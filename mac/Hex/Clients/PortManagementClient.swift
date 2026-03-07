import Dependencies
import Foundation

struct PortManagementClient {
  typealias ProcessInfo = PortManagementFeature.ProcessInfo
  
  var getProcessesOnPorts: @Sendable ([Int]) async throws -> [ProcessInfo]
  var getAllPortProcesses: @Sendable () async throws -> [ProcessInfo]
  var killProcess: @Sendable (Int32) async throws -> Void
  var isPortInUse: @Sendable (Int) async -> Bool
}

extension PortManagementClient: DependencyKey {
  static let liveValue = Self(
    getProcessesOnPorts: { ports in
      var allProcesses: [ProcessInfo] = []
      
      for port in ports {
        let processes = try await getProcessesOnPort(port)
        allProcesses.append(contentsOf: processes)
      }
      
      return allProcesses
    },
    getAllPortProcesses: {
      let process = Process()
      process.launchPath = "/usr/sbin/lsof"
      process.arguments = ["-iTCP", "-sTCP:LISTEN", "-n", "-P"]
      
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = Pipe()
      
      try process.run()
      process.waitUntilExit()
      
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: data, encoding: .utf8) else {
        return []
      }
      
      return parseSimpleLsofOutput(output)
    },
    killProcess: { pid in
      let process = Process()
      process.launchPath = "/bin/kill"
      process.arguments = ["-TERM", "\(pid)"]
      
      try process.run()
      process.waitUntilExit()
      
      if process.terminationStatus != 0 {
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let killProcess = Process()
        killProcess.launchPath = "/bin/kill"
        killProcess.arguments = ["-KILL", "\(pid)"]
        
        try killProcess.run()
        killProcess.waitUntilExit()
        
        if killProcess.terminationStatus != 0 {
          throw PortManagementError.failedToKillProcess(pid: pid)
        }
      }
    },
    isPortInUse: { port in
      do {
        let processes = try await getProcessesOnPort(port)
        return !processes.isEmpty
      } catch {
        return false
      }
    }
  )
  
  private static func getProcessesOnPort(_ port: Int) async throws -> [ProcessInfo] {
    let process = Process()
    process.launchPath = "/usr/sbin/lsof"
    process.arguments = ["-i", ":\(port)", "-n", "-P", "-F"]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    
    try process.run()
    process.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
      return []
    }
    
    return parseProcessOutput(output, port: port)
  }
  
  private static func parseSimpleLsofOutput(_ output: String) -> [ProcessInfo] {
    var processes: [ProcessInfo] = []
    let lines = output.split(separator: "\n").map(String.init)
    
    // Skip header line
    for (index, line) in lines.enumerated() {
      if index == 0 { continue } // Skip header
      
      let components = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
      if components.count < 9 { continue }
      
      // Format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
      let command = components[0]
      guard let pid = Int32(components[1]) else { continue }
      let name = components[8]
      
      // Parse port from NAME field (e.g., "*:3000" or "127.0.0.1:8080")
      if let colonIndex = name.lastIndex(of: ":"),
         let port = Int(name[name.index(after: colonIndex)...]) {
        
        let process = ProcessInfo(
          pid: pid,
          port: port,
          processName: command,
          command: command
        )
        
        // Avoid duplicates
        if !processes.contains(where: { $0.pid == process.pid && $0.port == process.port }) {
          processes.append(process)
        }
      }
    }
    
    // Sort by port number
    return processes.sorted { $0.port < $1.port }
  }
  
  private static func parseProcessOutput(_ output: String, port: Int) -> [ProcessInfo] {
    var processes: [ProcessInfo] = []
    let lines = output.split(separator: "\n").map(String.init)
    
    var currentPid: Int32?
    var currentCommand: String?
    
    for line in lines {
      if line.hasPrefix("p") {
        if let pidString = line.dropFirst().split(separator: "\0").first,
           let pid = Int32(pidString) {
          currentPid = pid
        }
      } else if line.hasPrefix("c") {
        currentCommand = String(line.dropFirst())
      } else if line.hasPrefix("n") && currentPid != nil {
        let nameInfo = String(line.dropFirst())
        
        if nameInfo.contains(":\(port)") {
          let processName = currentCommand ?? "Unknown"
          let fullCommand = getFullCommand(for: currentPid!) ?? processName
          
          let process = ProcessInfo(
            pid: currentPid!,
            port: port,
            processName: processName,
            command: fullCommand
          )
          
          if !processes.contains(where: { $0.pid == process.pid && $0.port == process.port }) {
            processes.append(process)
          }
        }
      }
    }
    
    return processes
  }
  
  private static func getFullCommand(for pid: Int32) -> String? {
    let process = Process()
    process.launchPath = "/bin/ps"
    process.arguments = ["-p", "\(pid)", "-o", "comm="]
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    
    do {
      try process.run()
      process.waitUntilExit()
      
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      guard let output = String(data: data, encoding: .utf8) else {
        return nil
      }
      
      return output.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      return nil
    }
  }
}

enum PortManagementError: LocalizedError {
  case failedToKillProcess(pid: Int32)
  case processNotFound
  
  var errorDescription: String? {
    switch self {
    case let .failedToKillProcess(pid):
      return "Failed to kill process with PID \(pid)"
    case .processNotFound:
      return "Process not found"
    }
  }
}

extension DependencyValues {
  var portManagementClient: PortManagementClient {
    get { self[PortManagementClient.self] }
    set { self[PortManagementClient.self] = newValue }
  }
}