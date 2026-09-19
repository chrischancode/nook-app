import Foundation
import Combine
import SwiftUI

enum PomodoroState {
    case idle
    case focus(secondsRemaining: Int)
    case breakTime(secondsRemaining: Int)
}

class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()
    
    @Published var state: PomodoroState = .idle
    
    private var timer: Timer?
    private let focusDuration = 25 * 60
    private let breakDuration = 5 * 60
    
    private init() {}
    
    func startFocus() {
        state = .focus(secondsRemaining: focusDuration)
        startTimer()
    }
    
    func startBreak() {
        state = .breakTime(secondsRemaining: breakDuration)
        startTimer()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.tick()
        }
    }
    
    private func tick() {
        switch state {
        case .idle:
            timer?.invalidate()
        case .focus(let secondsRemaining):
            if secondsRemaining > 1 {
                state = .focus(secondsRemaining: secondsRemaining - 1)
            } else {
                stop()
                // Optionally play a sound
            }
        case .breakTime(let secondsRemaining):
            if secondsRemaining > 1 {
                state = .breakTime(secondsRemaining: secondsRemaining - 1)
            } else {
                stop()
                // Optionally play a sound
            }
        }
    }
}
