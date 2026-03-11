import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var bdInfoText: String = "请选择完整的蓝光原盘目录进行标准 BDinfo 扫描...\n\n(已搭载「UNIX 物理强杀」引擎，无视 macOS 隐藏机制，专治 exFAT 幽灵文件)"
    @State private var isScanning: Bool = false
    
    // 进度与时间相关状态
    @State private var scanStartTime: Date?
    @State private var elapsedTimeString: String = "00:00"
    @State private var etaString: String = "计算中..."
    @State private var scanProgress: Double = 0.0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Mac 原生 BDInfo 扫描器")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top)
            
            TextEditor(text: $bdInfoText)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            
            if isScanning {
                VStack(spacing: 8) {
                    ProgressView(value: scanProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .padding(.horizontal)
                    
                    HStack {
                        Text("已耗时: \(elapsedTimeString)")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "进度: %.1f%%", scanProgress * 100))
                            .bold()
                            .foregroundColor(.accentColor)
                        Spacer()
                        Text("预计剩余: \(etaString)")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal)
                }
                .frame(height: 50)
            }
            
            HStack(spacing: 30) {
                Button(action: selectAndScanFolder) {
                    if isScanning {
                        ProgressView().controlSize(.small).padding(.trailing, 5)
                        Text("正在扫描正片数据...")
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
        .padding()
        .frame(minWidth: 800, minHeight: 650)
    }
    
    // MARK: - 计时器逻辑
    private func startTimer() {
        scanStartTime = Date()
        elapsedTimeString = "00:00"
        etaString = "计算中..."
        scanProgress = 0.0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard let startTime = self.scanStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self.elapsedTimeString = self.formatTimeInterval(elapsed)
                if self.scanProgress > 0.01 {
                    let totalEstimatedTime = elapsed / self.scanProgress
                    let remainingTime = totalEstimatedTime - elapsed
                    self.etaString = self.formatTimeInterval(remainingTime)
                } else {
                    self.etaString = "计算中..."
                }
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }
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
    
    // MARK: - 🛡️ 阶段 0：UNIX 底层物理强杀幽灵文件 (无视苹果隐藏机制)
    private func cleanGhostFilesPOSIX(at url: URL) {
        guard url.hasDirectoryPath else { return }
        
        let process = Process()
        // 直接调用最底层的 UNIX find 指令，暴力搜索并删除所有 ._ 开头的文件
        process.executableURL = URL(fileURLWithPath: "/usr/bin/find")
        process.arguments = [url.path, "-type", "f", "-name", "._*", "-delete"]
        
        do {
            try process.run()
            process.waitUntilExit()
            print("UNIX 底层查杀完毕，状态码: \(process.terminationStatus)")
        } catch {
            print("UNIX 查杀执行失败: \(error)")
        }
    }
    
    // MARK: - 🌟 智能寻找最大的 .m2ts 文件
    private func findLargestM2TS(in url: URL) -> String? {
        if !url.hasDirectoryPath { return url.pathExtension.lowercased() == "m2ts" ? url.path : nil }
        
        let streamURL1 = url.appendingPathComponent("BDMV").appendingPathComponent("STREAM")
        let streamURL2 = url.appendingPathComponent("STREAM")
        var targetDir = url
        if FileManager.default.fileExists(atPath: streamURL1.path) { targetDir = streamURL1 }
        else if FileManager.default.fileExists(atPath: streamURL2.path) { targetDir = streamURL2 }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: targetDir, includingPropertiesForKeys: [.fileSizeKey])
            let m2tsFiles = fileURLs.filter { $0.pathExtension.lowercased() == "m2ts" }
            var largestFile: URL?, maxSize: Int = 0
            for file in m2tsFiles {
                if let resources = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = resources.fileSize, size > maxSize {
                    maxSize = size; largestFile = file
                }
            }
            return largestFile?.path
        } catch { return nil }
    }
    
    // MARK: - 🌟 阶段 1：读取播放列表
    private func getTopPlaylist(at url: URL, executableURL: URL) -> String? {
        if !url.hasDirectoryPath { return nil }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-l", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let pattern = "([0-9A-Za-z]+\\.[mM][pP][lL][sS])"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.utf16.count)) {
                return (output as NSString).substring(with: match.range)
            }
            return nil
        } catch { return nil }
    }
    
    // MARK: - 🌟 阶段 2：定向启动扫描
    private func runStandardBDInfo(at url: URL) {
        isScanning = true
        bdInfoText = "▶ 正在启动 BDInfo 核心引擎...\n▶ 目标路径: \(url.path)\n"
        startTimer()
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 🛡️ 启动底层扫除
            DispatchQueue.main.async { self.bdInfoText += "▶ 正在调用底层 UNIX 指令，暴力抹除 exFAT 幽灵文件...\n" }
            self.cleanGhostFilesPOSIX(at: url)
            
            DispatchQueue.main.async { self.bdInfoText += "▶ 幽灵文件清扫完毕！开始提取播放列表树...\n" }
            
            guard let executableURL = Bundle.main.url(forResource: "bdinfo-cli", withExtension: nil) else {
                DispatchQueue.main.async {
                    self.bdInfoText += "❌ 错误：未找到 bdinfo-cli 组件。"
                    self.stopTimer(); self.isScanning = false
                }
                return
            }
            
            let tempOutputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempOutputDir, withIntermediateDirectories: true)
            
            let process = Process()
            process.executableURL = executableURL
            
            if let topMpls = self.getTopPlaylist(at: url, executableURL: executableURL) {
                DispatchQueue.main.async { self.bdInfoText += "▶ 已成功锁定正片: [ \(topMpls) ]\n▶ 开始深度测算，请观察下方进度条。" }
                process.arguments = ["-m", topMpls, url.path, tempOutputDir.path]
            } else if let largestM2TS = self.findLargestM2TS(in: url) {
                let fileName = (largestM2TS as NSString).lastPathComponent
                DispatchQueue.main.async { self.bdInfoText += "⚠️ 未检测到播放列表，已锁定最大视频流 [ \(fileName) ]，开始裸流测算..." }
                process.arguments = [largestM2TS, tempOutputDir.path]
            } else {
                DispatchQueue.main.async {
                    self.bdInfoText += "❌ 错误：未找到有效的 .mpls 或 .m2ts 文件。\n如果确认目录没选错，请务必前往 Mac 的 [系统设置] 授予 Xcode 完全磁盘访问权限！"
                    self.stopTimer(); self.isScanning = false
                }
                return
            }
            
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe
            let outHandle = outPipe.fileHandleForReading
            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                self.parseProgress(from: output)
            }
            
            do {
                try process.run()
                process.waitUntilExit()
                outHandle.readabilityHandler = nil
                
                if let reportFiles = try? FileManager.default.contentsOfDirectory(atPath: tempOutputDir.path),
                   let txtFile = reportFiles.first(where: { $0.hasSuffix(".txt") }) {
                    let reportPath = tempOutputDir.appendingPathComponent(txtFile)
                    let reportContent = try String(contentsOf: reportPath, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.bdInfoText = reportContent
                        self.scanProgress = 1.0
                        self.stopTimer(); self.isScanning = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.bdInfoText += "\n⚠️ 扫描结束，但引擎未能生成报告。"
                        self.stopTimer(); self.isScanning = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    outHandle.readabilityHandler = nil
                    self.bdInfoText += "\n❌ 引擎崩溃: \(error.localizedDescription)"
                    self.stopTimer(); self.isScanning = false
                }
            }
        }
    }
    
    private func parseProgress(from output: String) {
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*%"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsString = output as NSString
        let results = regex.matches(in: output, options: [], range: NSRange(location: 0, length: nsString.length))
        if let lastMatch = results.last {
            let matchRange = lastMatch.range(at: 1)
            let percentageStr = nsString.substring(with: matchRange)
            if let percentage = Double(percentageStr) {
                DispatchQueue.main.async { self.scanProgress = min(percentage / 100.0, 0.999) }
            }
        }
    }
    
    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "导出 BDinfo"
        panel.nameFieldStringValue = "BDinfo_Report.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do { try bdInfoText.write(to: url, atomically: true, encoding: .utf8) }
            catch { print("保存失败") }
        }
    }
}
