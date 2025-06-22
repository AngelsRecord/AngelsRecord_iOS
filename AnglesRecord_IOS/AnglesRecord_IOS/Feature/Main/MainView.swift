import SwiftUI
import SwiftData
import AVFoundation

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    @Query(sort: \RecordListModel.addedDate, order: .reverse) private var records: [RecordListModel]
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var showingFilePicker = false
    @State private var selectedRecord: RecordListModel?
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("AngelsRecord")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    // Dark Mode Toggle
                    Button(action: {
                        isDarkMode.toggle()
                    }) {
                        Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding()
                
                // Record List
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(records) { record in
                            RecordCardView(record: record)
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        if selectedRecord?.id == record.id {
                                            selectedRecord = nil
                                            audioPlayer.stop()
                                        } else {
                                            selectedRecord = record
                                            audioPlayer.play(record)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, selectedRecord != nil ? 100 : 20)
                }
                
                Spacer()
                
                // Add Record Button
                if selectedRecord == nil {
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        Text("add Record File")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                    .padding()
                }
            }
            
            // Mini Player
            if let record = selectedRecord {
                MiniPlayerView(
                    record: record,
                    audioPlayer: audioPlayer,
                    onDelete: {
                        deleteRecord(record)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Copy file to app's documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(url.lastPathComponent)
            
            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: url, to: destinationURL)
                
                // Get audio duration
                let asset = AVURLAsset(url: destinationURL)
                let duration = CMTimeGetSeconds(asset.duration)
                
                // Create new record
                let newRecord = RecordListModel(
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: "Unknown Artist",
                    duration: duration,
                    fileURL: destinationURL
                )
                
                modelContext.insert(newRecord)
                try? modelContext.save()
                
            } catch {
                print("Error importing file: \(error)")
            }
            
        case .failure(let error):
            print("File import failed: \(error)")
        }
    }
    
    private func deleteRecord(_ record: RecordListModel) {
        if audioPlayer.currentRecord?.id == record.id {
            audioPlayer.stop()
        }
        
        selectedRecord = nil
        
        // Delete file
        if let fileURL = record.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from database
        modelContext.delete(record)
        try? modelContext.save()
    }
} 
