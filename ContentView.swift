import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var bdInfoText: String = "请选择完整的蓝光原盘目录进行扫描...\n\n(已搭载「异步日志尾随架构」与原版 BDInfo 引擎，彻底告别管道死锁，提供 100% 纯正 PT 报告！)"
    @State private var fullReportForExport: String = ""
    @State private var isScanning: Bool = false
    
    @State private var scanStartTime: Date?
    @State private var elapsedTimeString: String = "00:00"
    @State private var etaString: String = "等待目标..."
    @State private var scanProgress: Double = 0.0
    @State private var timer: Timer?
    @State private var logTailTimer: Timer?
    @State private var isBlinking: Bool = false
    @State private var lastProgressUpdate: Date?
    @State private var lastLogOutputAt: Date?
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Mac 原生 BDInfo 扫描器 (极客解耦版)")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            ScrollView {
                Text(bdInfoText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            
            if isScanning {
                VStack(spacing: 8) {
                    ProgressView(value: scanProgress, total: 1.0).progressViewStyle(.linear).padding(.horizontal)
                    HStack {
                        Text("已耗时: \(elapsedTimeString)").monospacedDigit().foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(isBlinking ? Color.green : Color.clear).frame(width: 8, height: 8)
                            Text(String(format: "进度: %.2f%%", scanProgress * 100)).bold().foregroundColor(.accentColor)
                        }
                        Spacer()
                        Text("状态: \(etaString)").monospacedDigit().foregroundColor(.secondary)
                    }
                    .font(.callout).padding(.horizontal)
                }
                .frame(height: 50)
            }
            
            HStack(spacing: 30) {
                Button(action: selectAndScanFolder) {
                    if isScanning {
                        ProgressView().controlSize(.small).padding(.trailing, 5)
                        Text("引擎全速扒轨中...")
                    } else {
                        Image(systemName: "opticaldisc")
                        Text("选择 BDMV 目录并开始扫描")
                    }
                }
                .disabled(isScanning)
                .buttonStyle(.borderedProminent)
                
                Button(action: exportToFile) {
                    Image(systemName: "arrow.down.doc")
                    Text("导出标准报告")
                }
                .disabled(bdInfoText.isEmpty || isScanning)
                .buttonStyle(.bordered)
            }
            .padding(.bottom)
        }
        .padding().frame(minWidth: 800, minHeight: 650)
    }
    
    private func startTimers(logFileURL: URL) {
        scanStartTime = Date()
        elapsedTimeString = "00:00"
        etaString = "准备测算..."
        scanProgress = 0.0
        lastProgressUpdate = nil
        lastLogOutputAt = nil
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let startTime = self.scanStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self.elapsedTimeString = self.formatTimeInterval(elapsed)
                self.applyFallbackProgress(elapsed: elapsed)
                if let lastOutput = self.lastLogOutputAt {
                    let silentSeconds = Date().timeIntervalSince(lastOutput)
                    if silentSeconds > 3, self.scanProgress < 0.99 {
                        self.etaString = "扫描中（引擎输出缓冲）"
                    }
                }
            }
        }
        
        // 💥 解耦核心：每 0.5 秒读取一次底层日志文件，刷新 UI
        var lastReadOffset: UInt64 = 0
        logTailTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard let handle = try? FileHandle(forReadingFrom: logFileURL) else { return }
            defer { try? handle.close() }
            
            try? handle.seek(toOffset: lastReadOffset)
            let newData = handle.readDataToEndOfFile()
            if !newData.isEmpty {
                lastReadOffset = try! handle.offset()
                if let newString = String(data: newData, encoding: .utf8) {
                    let cleanString = newString.replacingOccurrences(of: "\r", with: "\n")
                    DispatchQueue.main.async {
                        self.lastLogOutputAt = Date()
                        self.isBlinking.toggle()
                        self.etaString = "扫描中（日志持续更新）"
                        self.bdInfoText += cleanString
                        if self.bdInfoText.count > 3000 { self.bdInfoText = "..." + String(self.bdInfoText.suffix(2000)) }
                        _ = self.parseProgress(from: cleanString)
                    }
                }
            }
        }
    }
    
    private func stopTimers() {
        timer?.invalidate(); timer = nil
        logTailTimer?.invalidate(); logTailTimer = nil
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 && interval.isFinite else { return "00:00" }
        let totalSeconds = Int(interval)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
    
    private func selectAndScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = "请选择蓝光原盘目录，或直接选择视频文件"
        if panel.runModal() == .OK, let selectedURL = panel.url { runStandardBDInfo(at: selectedURL) }
    }
    
    // MARK: - 🌟 底层净化与寻路
    private func cleanGhostFilesNatively(at url: URL) {
        guard url.hasDirectoryPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dot_clean")
        process.arguments = ["-m", url.path]
        try? process.run()
        process.waitUntilExit()
    }
    
    private func resolveFirstExistingDirectory(from candidates: [URL]) -> URL? {
        for dir in candidates where FileManager.default.fileExists(atPath: dir.path) { return dir }
        return nil
    }

    private func resolveStreamDirectory(from url: URL) -> URL? {
        let streamDirs = [
            url.appendingPathComponent("BDMV").appendingPathComponent("STREAM"),
            url.appendingPathComponent("STREAM"),
            url
        ]
        return resolveFirstExistingDirectory(from: streamDirs)
    }

    private func resolvePlaylistDirectory(from url: URL) -> URL? {
        let playlistDirs = [
            url.appendingPathComponent("BDMV").appendingPathComponent("PLAYLIST"),
            url.appendingPathComponent("PLAYLIST")
        ]
        return resolveFirstExistingDirectory(from: playlistDirs)
    }

    private func findLargestM2TSBaseName(in url: URL) -> String? {
        guard let targetDir = resolveStreamDirectory(from: url) else { return nil }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.fileSizeKey])
            let m2ts = files.filter { $0.pathExtension.lowercased() == "m2ts" && !$0.lastPathComponent.hasPrefix("._") }
            let largest = m2ts.max { a, b in
                let sizeA = (try? a.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let sizeB = (try? b.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return sizeA < sizeB
            }
            return largest?.deletingPathExtension().lastPathComponent
        } catch { return nil }
    }

    private func readUInt16BE(_ data: Data, at offset: Int) -> UInt16? {
        guard offset + 1 < data.count else { return nil }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset + 3 < data.count else { return nil }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    private func parsePlayItemClipIDs(from mplsData: Data) -> [String] {
        guard let playlistStart = readUInt32BE(mplsData, at: 8) else { return [] }
        let start = Int(playlistStart)
        guard start + 10 <= mplsData.count else { return [] }
        guard let playItemCount = readUInt16BE(mplsData, at: start + 6) else { return [] }

        var clipIDs: [String] = []
        var cursor = start + 10
        for _ in 0..<Int(playItemCount) {
            guard let itemLength = readUInt16BE(mplsData, at: cursor) else { break }
            let itemStart = cursor + 2
            let itemEnd = itemStart + Int(itemLength)
            guard itemEnd <= mplsData.count else { break }
            guard itemStart + 9 <= mplsData.count else { break }

            let clipNameData = mplsData[itemStart..<(itemStart + 5)]
            let codecData = mplsData[(itemStart + 5)..<(itemStart + 9)]
            let clipName = String(data: clipNameData, encoding: .ascii) ?? ""
            let codec = String(data: codecData, encoding: .ascii) ?? ""
            if codec == "M2TS", clipName.count == 5 {
                clipIDs.append(clipName)
            }
            cursor = itemEnd
        }
        return clipIDs
    }
    
    private func getTargetPlaylist(at url: URL, targetM2TSBase: String) -> String? {
        guard let playlistDir = resolvePlaylistDirectory(from: url) else { return nil }
        let normalizedTarget = String(targetM2TSBase.suffix(5))

        struct PlaylistCandidate {
            let fileName: String
            let clipIDs: [String]
            let fileSize: Int
            let target: String
            var hasTarget: Bool { clipIDs.contains(target) }
            var firstIsTarget: Bool { clipIDs.first == target }
            var fileNameMatchesTarget: Bool {
                (fileName as NSString).deletingPathExtension == target
            }
            var targetHitCount: Int {
                clipIDs.reduce(0) { $0 + ($1 == target ? 1 : 0) }
            }
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: playlistDir, includingPropertiesForKeys: [.fileSizeKey])
            let mplsFiles = files.filter { $0.pathExtension.lowercased() == "mpls" && !$0.lastPathComponent.hasPrefix("._") }

            var candidates: [PlaylistCandidate] = []
            for file in mplsFiles {
                guard let data = try? Data(contentsOf: file) else { continue }
                let clipIDs = parsePlayItemClipIDs(from: data)
                guard !clipIDs.isEmpty else { continue }
                let fileSize = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                candidates.append(
                    PlaylistCandidate(fileName: file.lastPathComponent, clipIDs: clipIDs, fileSize: fileSize, target: normalizedTarget)
                )
            }

            let matched = candidates
                .filter { $0.hasTarget }
                .sorted { lhs, rhs in
                    if lhs.fileNameMatchesTarget != rhs.fileNameMatchesTarget {
                        return lhs.fileNameMatchesTarget && !rhs.fileNameMatchesTarget
                    }
                    if lhs.firstIsTarget != rhs.firstIsTarget {
                        return lhs.firstIsTarget && !rhs.firstIsTarget
                    }
                    if lhs.targetHitCount != rhs.targetHitCount {
                        return lhs.targetHitCount > rhs.targetHitCount
                    }
                    if lhs.clipIDs.count != rhs.clipIDs.count {
                        return lhs.clipIDs.count < rhs.clipIDs.count
                    }
                    return lhs.fileSize > rhs.fileSize
                }

            if let best = matched.first {
                return best.fileName
            }
        } catch { return nil }
        return nil
    }
    
    // MARK: - 🚀 解耦引擎启动
    private func runStandardBDInfo(at url: URL) {
        isScanning = true
        bdInfoText = "▶ 准备启动纯血 BDInfo 引擎...\n"
        fullReportForExport = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async { self.bdInfoText += "▶ 正在调用 dot_clean 净化 ExFAT 磁盘幽灵文件...\n" }
            self.cleanGhostFilesNatively(at: url)
            
            guard let executableURL = Bundle.main.url(forResource: "bdinfo-cli", withExtension: nil) else {
                DispatchQueue.main.async { self.bdInfoText += "❌ 找不到 bdinfo-cli 组件。\n"; self.isScanning = false }
                return
            }
            
            let tempOutputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempOutputDir, withIntermediateDirectories: true)
            
            // 创建用于解耦的临时日志文件
            let logFileURL = tempOutputDir.appendingPathComponent("engine_output.log")
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
            
            DispatchQueue.main.async { self.startTimers(logFileURL: logFileURL) }
            
            let process = Process()
            process.executableURL = executableURL
            
            if url.hasDirectoryPath {
                if let baseName = self.findLargestM2TSBaseName(in: url) {
                    if let mpls = self.getTargetPlaylist(at: url, targetM2TSBase: baseName) {
                        DispatchQueue.main.async { self.bdInfoText += "▶ 完美锁定正片列表: [ \(mpls) ]\n" }
                        process.arguments = ["-m", mpls, url.path, tempOutputDir.path]
                    } else {
                        let streamDir = self.resolveStreamDirectory(from: url) ?? url
                        let m2tsFile = streamDir.appendingPathComponent("\(baseName).m2ts")
                        process.arguments = [m2tsFile.path, tempOutputDir.path]
                    }
                } else {
                    DispatchQueue.main.async { self.bdInfoText += "❌ 目录为空。\n"; self.stopTimers(); self.isScanning = false }
                    return
                }
            } else {
                process.arguments = [url.path, tempOutputDir.path]
            }
            
            // 💥 终极解耦：将引擎的标准输出和错误直接绑定到实体日志文件上！
            if let logFileHandle = try? FileHandle(forWritingTo: logFileURL) {
                process.standardOutput = logFileHandle
                process.standardError = logFileHandle
            }
            
            do {
                DispatchQueue.main.async { self.bdInfoText += "▶ 纯血引擎已剥离至后台全速运行。\n(日志实时尾随中，请静候 100% 准确的 PT 报告！)\n==============================\n" }
                try process.run()
                process.waitUntilExit()
                
                // 收集最终的 .txt 报告
                if let reportFiles = try? FileManager.default.contentsOfDirectory(atPath: tempOutputDir.path),
                   let txtFile = reportFiles.first(where: { $0.hasSuffix(".txt") }) {
                    let reportPath = tempOutputDir.appendingPathComponent(txtFile)
                    let reportContent = try String(contentsOf: reportPath, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.fullReportForExport = reportContent
                        self.bdInfoText = "✅ 扫描完美结束！报告如下：\n\n" + self.makeLightweightPreview(from: reportContent)
                        self.scanProgress = 1.0
                        self.etaString = "扫描完成"
                        self.isBlinking = true
                        self.stopTimers(); self.isScanning = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.bdInfoText += "\n\n⚠️ 扫描结束，未能生成报告。"
                        self.isBlinking = false
                        self.stopTimers(); self.isScanning = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.bdInfoText += "\n❌ 引擎崩溃: \(error.localizedDescription)"
                    self.isBlinking = false
                    self.stopTimers(); self.isScanning = false
                }
            }
        }
    }

    private func makeLightweightPreview(from report: String) -> String {
        let maxVisibleChars = 120_000
        guard report.count > maxVisibleChars else { return report }
        let head = String(report.prefix(80_000))
        let tail = String(report.suffix(30_000))
        return """
        [报告较长，为避免界面卡顿，此处仅显示节选。导出文件为完整报告。]

        \(head)

        ...

        \(tail)
        """
    }
    
    private func parseProgress(from output: String) -> Bool {
        let nsString = output as NSString

        // Pattern 1: explicit percent, e.g. "12.34%"
        if let percentRegex = try? NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s*%", options: []),
           let match = percentRegex.matches(in: output, options: [], range: NSRange(location: 0, length: nsString.length)).last {
            let value = nsString.substring(with: match.range(at: 1))
            if let percent = Double(value) {
                scanProgress = min(max(scanProgress, percent / 100.0), 0.999)
                lastProgressUpdate = Date()
                etaString = "扫描进度解析中"
                return true
            }
        }

        // Pattern 2: fraction style, e.g. "23/512" or "23 of 512"
        let fractionPatterns = [
            "([0-9]{1,6})\\s*/\\s*([0-9]{1,6})",
            "([0-9]{1,6})\\s+of\\s+([0-9]{1,6})"
        ]
        for pattern in fractionPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.matches(in: output, options: [], range: NSRange(location: 0, length: nsString.length)).last else { continue }
            let lhs = nsString.substring(with: match.range(at: 1))
            let rhs = nsString.substring(with: match.range(at: 2))
            if let current = Double(lhs), let total = Double(rhs), total > 0 {
                let ratio = min(max(current / total, 0.0), 0.999)
                scanProgress = max(scanProgress, ratio)
                lastProgressUpdate = Date()
                etaString = "扫描进度解析中"
                return true
            }
        }

        return false
    }

    private func applyFallbackProgress(elapsed: TimeInterval) {
        guard scanProgress < 0.97 else { return }

        // If no parsable progress appears for a while, use a smooth time-based fallback.
        if let last = lastProgressUpdate, Date().timeIntervalSince(last) < 4 {
            return
        }

        // Reach ~70% at 5 min, ~90% at 20 min; reserve tail for real completion.
        let t = max(elapsed, 0)
        let fallback = min(0.97, 1.0 - exp(-t / 360.0))
        if fallback > scanProgress {
            scanProgress = fallback
        }
    }
    
    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "导出 BDinfo"
        panel.nameFieldStringValue = "BDinfo_Report.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            let content = fullReportForExport.isEmpty ? bdInfoText : fullReportForExport
            do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { print("保存失败") }
        }
    }
}
