import SwiftUI

struct CameraCardView: View {
    @ObservedObject var cameraManager = CameraManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let cgImage = cameraManager.frame {
                    Image(cgImage, scale: 1.0, label: Text("Camera Feed"))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "video.slash")
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera Mirror")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(cameraManager.permissionGranted ? (cameraManager.frame != nil ? "Live" : "Starting...") : "No Access")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(cameraManager.permissionGranted ? .green : .red)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            cameraManager.start()
        }
        .onDisappear {
            cameraManager.stop()
        }
    }
}
