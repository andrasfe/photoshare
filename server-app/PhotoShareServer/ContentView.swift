import SwiftUI
import Photos

struct ContentView: View {
    @EnvironmentObject var serverManager: ServerManager
    @State private var showingLogs = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    statusCard
                    photosAccessCard
                    configurationCard
                    statsCard
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer with logs toggle
            footerView
        }
        .frame(width: 480, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingLogs) {
            LogsView(logs: serverManager.logs)
        }
    }
    
    // MARK: - Header
    
    var headerView: some View {
        HStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            VStack(alignment: .leading, spacing: 4) {
                Text("PhotoShare Server")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(serverManager.isRunning ? "Running on port 8080" : "Stopped")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(serverManager.isRunning ? Color.green : Color.red)
                .frame(width: 12, height: 12)
                .shadow(color: serverManager.isRunning ? .green.opacity(0.5) : .red.opacity(0.5), radius: 4)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Status Card
    
    var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Server Status", systemImage: "server.rack")
                .font(.headline)
            
            HStack(spacing: 16) {
                Button(action: {
                    if serverManager.isRunning {
                        serverManager.stopServer()
                    } else {
                        serverManager.startServer()
                    }
                }) {
                    HStack {
                        Image(systemName: serverManager.isRunning ? "stop.fill" : "play.fill")
                        Text(serverManager.isRunning ? "Stop Server" : "Start Server")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(serverManager.isRunning ? .red : .green)
                
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "http://localhost:8080/health")!)
                }) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Open in Browser")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(!serverManager.isRunning)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Photos Access Card
    
    var photosAccessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Photos Access", systemImage: "photo.stack")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(photosAccessStatusText)
                        .font(.subheadline)
                    
                    Text(photosAccessDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if serverManager.photosAuthStatus != .authorized {
                    Button("Request Access") {
                        serverManager.requestPhotosAccess()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    var photosAccessStatusText: String {
        switch serverManager.photosAuthStatus {
        case .authorized:
            return "Access Granted"
        case .limited:
            return "Limited Access"
        case .denied:
            return "Access Denied"
        case .restricted:
            return "Access Restricted"
        case .notDetermined:
            return "Not Requested"
        @unknown default:
            return "Unknown"
        }
    }
    
    var photosAccessDescription: String {
        switch serverManager.photosAuthStatus {
        case .authorized:
            return "PhotoShare can access your entire Photos library"
        case .limited:
            return "PhotoShare can only access selected photos"
        case .denied:
            return "Open System Settings to grant access"
        case .restricted:
            return "Photos access is restricted on this device"
        case .notDetermined:
            return "Click 'Request Access' to enable photo sharing"
        @unknown default:
            return ""
        }
    }
    
    // MARK: - Configuration Card
    
    var configurationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Configuration", systemImage: "gearshape")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Port:")
                        .foregroundColor(.secondary)
                    Text("8080")
                        .fontWeight(.medium)
                        .monospaced()
                }
                
                GridRow {
                    Text("Host:")
                        .foregroundColor(.secondary)
                    Text("0.0.0.0 (all interfaces)")
                        .fontWeight(.medium)
                        .monospaced()
                }
                
                GridRow {
                    Text("Secret:")
                        .foregroundColor(.secondary)
                    Text(serverManager.hasCustomSecret ? "Custom (from env)" : "Default ⚠️")
                        .fontWeight(.medium)
                        .foregroundColor(serverManager.hasCustomSecret ? .primary : .orange)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Stats Card
    
    var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Statistics", systemImage: "chart.bar")
                .font(.headline)
            
            HStack(spacing: 24) {
                StatItem(title: "Requests", value: "\(serverManager.requestCount)", icon: "arrow.down.circle")
                StatItem(title: "Photos Served", value: "\(serverManager.photosServed)", icon: "photo")
                StatItem(title: "Uptime", value: serverManager.uptimeString, icon: "clock")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    // MARK: - Footer
    
    var footerView: some View {
        HStack {
            Button(action: { showingLogs = true }) {
                Label("View Logs", systemImage: "doc.text")
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            if let lastLog = serverManager.logs.last {
                Text(lastLog)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LogsView: View {
    let logs: [String]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Server Logs")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logs.indices, id: \.self) { index in
                        Text(logs[index])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 400)
    }
}

struct MenuBarView: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(serverManager.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serverManager.isRunning ? "Server Running" : "Server Stopped")
            }
            
            Divider()
            
            Button(serverManager.isRunning ? "Stop Server" : "Start Server") {
                if serverManager.isRunning {
                    serverManager.stopServer()
                } else {
                    serverManager.startServer()
                }
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(8)
    }
}

#Preview {
    ContentView()
        .environmentObject(ServerManager())
}

