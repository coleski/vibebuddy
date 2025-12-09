import AppKit
import Carbon
import Dependencies
import DependenciesMacros
import Foundation
import HexCore
import os
import Sauce

private let logger = Logger(subsystem: "com.kitlangton.Hex", category: "KeyEventMonitor")

/// A token that can be used to cancel input event monitoring
public final class InputEventCancellationToken {
  let id: UUID
  private let cancelHandler: (UUID) -> Void

  init(id: UUID, cancelHandler: @escaping (UUID) -> Void) {
    self.id = id
    self.cancelHandler = cancelHandler
  }

  public func cancel() {
    cancelHandler(id)
  }
}

public struct RawKeyEvent {
  let key: Key?
  let modifiers: Modifiers
  let eventType: CGEventType
  let keyCode: Int
}

public extension RawKeyEvent {
  init(cgEvent: CGEvent, type: CGEventType) {
    let keyCode = Int(cgEvent.getIntegerValueField(.keyboardEventKeycode))
    let key = cgEvent.type == .keyDown ? Sauce.shared.key(for: keyCode) : nil

    let modifiers = Modifiers.from(carbonFlags: cgEvent.flags)
    self.init(key: key, modifiers: modifiers, eventType: type, keyCode: keyCode)
  }
}

@DependencyClient
struct KeyEventMonitorClient {
  var listenForKeyPress: @Sendable () async -> AsyncThrowingStream<RawKeyEvent, Error> = { .never }
  var handleKeyEvent: @Sendable (@escaping (RawKeyEvent) -> Bool) -> InputEventCancellationToken = { _ in InputEventCancellationToken(id: UUID(), cancelHandler: { _ in }) }
  var handleInputEvent: @Sendable (@escaping (InputEvent) -> Bool) -> InputEventCancellationToken = { _ in InputEventCancellationToken(id: UUID(), cancelHandler: { _ in }) }
  var startMonitoring: @Sendable () async -> Void = {}
}

extension KeyEventMonitorClient: DependencyKey {
  static var liveValue: KeyEventMonitorClient {
    let live = KeyEventMonitorClientLive()
    return KeyEventMonitorClient(
      listenForKeyPress: {
        live.listenForKeyPress()
      },
      handleKeyEvent: { handler in
        return live.handleKeyEvent(handler)
      },
      handleInputEvent: { handler in
        return live.handleInputEvent(handler)
      },
      startMonitoring: {
        live.startMonitoring()
      }
    )
  }
}

extension DependencyValues {
  var keyEventMonitor: KeyEventMonitorClient {
    get { self[KeyEventMonitorClient.self] }
    set { self[KeyEventMonitorClient.self] = newValue }
  }
}

class KeyEventMonitorClientLive {
  private var eventTapPort: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var continuations: [UUID: (RawKeyEvent) -> Bool] = [:]
  private var inputEventHandlers: [UUID: (InputEvent) -> Bool] = [:]
  private let continuationsLock = NSLock()
  private var isMonitoring = false

  init() {
    logger.info("Initializing HotKeyClient with CGEvent tap.")
  }

  deinit {
    self.stopMonitoring()
  }

  /// Provide a stream of key events.
  func listenForKeyPress() -> AsyncThrowingStream<RawKeyEvent, Error> {
    AsyncThrowingStream { continuation in
      let uuid = UUID()
      
      continuationsLock.lock()
      continuations[uuid] = { event in
        continuation.yield(event)
        return false
      }
      let shouldStartMonitoring = continuations.count == 1
      continuationsLock.unlock()

      // Start monitoring if this is the first subscription
      if shouldStartMonitoring {
        startMonitoring()
      }

      // Cleanup on cancellation
      continuation.onTermination = { [weak self] _ in
        self?.removeContinuation(uuid: uuid)
      }
    }
  }

  private func removeContinuation(uuid: UUID) {
    continuationsLock.lock()
    continuations[uuid] = nil
    let shouldStopMonitoring = continuations.isEmpty
    continuationsLock.unlock()

    // Stop monitoring if no more listeners
    if shouldStopMonitoring {
      stopMonitoring()
    }
  }

  func startMonitoring() {
    guard !isMonitoring else {
      return
    }

    // Check accessibility permission first
    let trusted = AXIsProcessTrusted()
    if !trusted {
      logger.error("Not trusted! Cannot create event tap.")
      return
    }

    isMonitoring = true

    // Create an event tap at the HID level to capture keyDown, keyUp, flagsChanged, and mouse clicks
    let eventMask =
      ((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue))

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: { _, type, cgEvent, userInfo in
          guard
            let hotKeyClientLive = Unmanaged<KeyEventMonitorClientLive>
            .fromOpaque(userInfo!)
            .takeUnretainedValue() as KeyEventMonitorClientLive?
          else {
            return Unmanaged.passUnretained(cgEvent)
          }

          // Handle mouse click events
          if type == .leftMouseDown || type == .rightMouseDown {
            let handled = hotKeyClientLive.processMouseClick()
            // Never intercept mouse clicks - just notify handlers
            return Unmanaged.passUnretained(cgEvent)
          }

          let keyEvent = RawKeyEvent(cgEvent: cgEvent, type: type)
          let handled = hotKeyClientLive.processKeyEvent(keyEvent)

          if handled {
            return nil
          } else {
            return Unmanaged.passUnretained(cgEvent)
          }
        },
        userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
      )
    else {
      isMonitoring = false
      logger.error("Failed to create event tap.")
      return
    }

    eventTapPort = eventTap

    // Create a RunLoop source and add it to the current run loop
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    self.runLoopSource = runLoopSource

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    logger.info("Started monitoring key events via CGEvent tap.")
  }

  func handleKeyEvent(_ handler: @escaping (RawKeyEvent) -> Bool) -> InputEventCancellationToken {
    let uuid = UUID()

    continuationsLock.lock()
    continuations[uuid] = handler
    let shouldStartMonitoring = continuations.count == 1
    continuationsLock.unlock()

    if shouldStartMonitoring {
      startMonitoring()
    }

    return InputEventCancellationToken(id: uuid) { [weak self] id in
      self?.removeKeyEventHandler(id: id)
    }
  }

  private func removeKeyEventHandler(id: UUID) {
    continuationsLock.lock()
    continuations[id] = nil
    let shouldStopMonitoring = continuations.isEmpty && inputEventHandlers.isEmpty
    continuationsLock.unlock()

    if shouldStopMonitoring {
      stopMonitoring()
    }
  }

  private func stopMonitoring() {
    guard isMonitoring else { return }
    isMonitoring = false

    if let runLoopSource = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      self.runLoopSource = nil
    }

    if let eventTapPort = eventTapPort {
      CGEvent.tapEnable(tap: eventTapPort, enable: false)
      self.eventTapPort = nil
    }

    logger.info("Stopped monitoring key events via CGEvent tap.")
  }

  private func processKeyEvent(_ keyEvent: RawKeyEvent) -> Bool {
    var handled = false

    continuationsLock.lock()
    let handlers = Array(continuations.values)
    let inputHandlers = Array(inputEventHandlers.values)
    continuationsLock.unlock()

    for continuation in handlers {
      if continuation(keyEvent) {
        handled = true
      }
    }

    // Also dispatch to input event handlers (convert to HexCore KeyEvent)
    let hexKeyEvent = KeyEvent(key: keyEvent.key, modifiers: keyEvent.modifiers)
    for handler in inputHandlers {
      if handler(.keyboard(hexKeyEvent)) {
        handled = true
      }
    }

    return handled
  }

  func handleInputEvent(_ handler: @escaping (InputEvent) -> Bool) -> InputEventCancellationToken {
    let uuid = UUID()

    continuationsLock.lock()
    inputEventHandlers[uuid] = handler
    let shouldStartMonitoring = continuations.isEmpty && inputEventHandlers.count == 1
    continuationsLock.unlock()

    if shouldStartMonitoring {
      startMonitoring()
    }

    return InputEventCancellationToken(id: uuid) { [weak self] id in
      self?.removeInputEventHandler(id: id)
    }
  }

  private func removeInputEventHandler(id: UUID) {
    continuationsLock.lock()
    inputEventHandlers[id] = nil
    let shouldStopMonitoring = continuations.isEmpty && inputEventHandlers.isEmpty
    continuationsLock.unlock()

    if shouldStopMonitoring {
      stopMonitoring()
    }
  }

  private func processMouseClick() -> Bool {
    var handled = false

    continuationsLock.lock()
    let inputHandlers = Array(inputEventHandlers.values)
    continuationsLock.unlock()

    for handler in inputHandlers {
      if handler(.mouseClick) {
        handled = true
      }
    }

    return handled
  }
}
