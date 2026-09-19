import SwiftUI

struct PomodoroCardView: View {
    @ObservedObject var pomodoroManager = PomodoroManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "timer")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(colorForState)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(timeString)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                if isRunning {
                    Button(action: {
                        pomodoroManager.stop()
                    }) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        pomodoroManager.startFocus()
                    }) {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        pomodoroManager.startBreak()
                    }) {
                        Image(systemName: "cup.and.saucer.fill")
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var colorForState: Color {
        switch pomodoroManager.state {
        case .idle: return .white.opacity(0.5)
        case .focus: return .orange
        case .breakTime: return .green
        }
    }
    
    private var titleText: String {
        switch pomodoroManager.state {
        case .idle: return "Pomodoro"
        case .focus: return "Focus Session"
        case .breakTime: return "Break Time"
        }
    }
    
    private var timeString: String {
        switch pomodoroManager.state {
        case .idle:
            return "25:00 / 05:00"
        case .focus(let seconds), .breakTime(let seconds):
            let min = seconds / 60
            let sec = seconds % 60
            return String(format: "%02d:%02d", min, sec)
        }
    }
    
    private var isRunning: Bool {
        if case .idle = pomodoroManager.state {
            return false
        }
        return true
    }
}
