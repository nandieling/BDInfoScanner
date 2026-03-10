import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var bdInfoText: String = "请选择完整的蓝光原盘目录进行标准 BDinfo 扫描...\n\n(注意：标准物理扫描需要几分钟到十几分钟不等，具体取决于光盘体积和硬盘速度)"
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
            
            // 扫描结果展示区
            TextEditor(text: $bdInfoText)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            
            // 进度条与状态展示区
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
            
            // 操作按钮区
            HStack(spacing: 30) {
                Button(action: selectAndScanFolder) {
                    if isScanning {
                        ProgressView().controlSize(.small).padding(.trailing, 5)
                        Text("正在扫描正片数据...")
                    } else {
                        Image(systemName: "opticaldisc")
                        Text("选择 BDMV 并开始扫描")
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
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        guard interval > 0 && interval.isFinite else { return "00:00" }
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - 选择文件夹
    private func selectAndScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "请选择蓝光原盘的 BDMV 文件夹或其父目录"
        
        if panel.runModal() == .OK, let selectedURL = panel.url {
            runStandardBDInfo(at: selectedURL)
        }
    }
    
    // MARK: - 🌟 阶段1：读取播放列表，寻找正片
    private func getTopPlaylist(at url: URL, executableURL: URL) -> String? {
        let process = Process()
        process.executableURL = executableURL
        // -l 参数：只列出播放列表，不扫描
        process.arguments = ["-l", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            // 正则匹配第一个出现的 .MPLS 文件名 (BDInfo 默认将最长的主影片排在第一个)
            let pattern = "([0-9A-Za-z]+\\.[mM][pP][lL][sS])"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.utf16.count)) {
                return (output as NSString).substring(with: match.range)
            }
            return nil
        } catch {
            return nil
        }
    }
    
    // MARK: - 🌟 阶段2：定向启动扫描
    private func runStandardBDInfo(at url: URL) {
        isScanning = true
        bdInfoText = "▶ 正在启动 BDInfo 核心引擎...\n▶ 目标路径: \(url.path)\n\n正在提取播放列表树并侦测正片位置..."
        startTimer()
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let executableURL = Bundle.main.url(forResource: "bdinfo-cli", withExtension: nil) else {
                DispatchQueue.main.async {
                    self.bdInfoText = "❌ 错误：在应用包内未找到 bdinfo-cli 核心组件。"
                    self.stopTimer()
                    self.isScanning = false
                }
                return
            }
            
            // 执行阶段 1
            guard let topMpls = self.getTopPlaylist(at: url, executableURL: executableURL) else {
                DispatchQueue.main.async {
                    self.bdInfoText = "❌ 错误：未能从光盘中解析出有效的播放列表 (.mpls)。\n请确保这真的是一个合法的蓝光 BDMV 目录。"
                    self.stopTimer()
                    self.isScanning = false
                }
                return
            }
            
            DispatchQueue.main.async {
                self.bdInfoText += "\n\n▶ 已锁定最长正片列表: [ \(topMpls) ]\n▶ 正在强制分配定向扫描任务，彻底绕过互动拦截...\n▶ 开始深度物理测算，请观察下方进度条。"
            }
            
            // 执行阶段 2
            let tempOutputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempOutputDir, withIntermediateDirectories: true)
            
            let process = Process()
            process.executableURL = executableURL
            // 关键修改：使用 -m 指定播放列表，引擎就不会卡住等用户回车了！
            process.arguments = ["-m", topMpls, url.path, tempOutputDir.path]
            
            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe // 将错误输出也合并，防止进度流失
            
            let outHandle = outPipe.fileHandleForReading
            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                
                // 也可以把引擎真实的日志隐式打印到 Xcode 控制台方便调试
                print(output, terminator: "")
                
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
                        self.stopTimer()
                        self.isScanning = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.bdInfoText = "⚠️ 扫描完成，但未能找到生成的报告文件。"
                        self.stopTimer()
                        self.isScanning = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    outHandle.readabilityHandler = nil
                    self.bdInfoText = "❌ BDInfo 引擎执行崩溃: \(error.localizedDescription)"
                    self.stopTimer()
                    self.isScanning = false
                }
            }
        }
    }
    
    // MARK: - 正则表达式解析进度
    private func parseProgress(from output: String) {
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*%"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        
        let nsString = output as NSString
        let results = regex.matches(in: output, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let lastMatch = results.last {
            let matchRange = lastMatch.range(at: 1)
            let percentageStr = nsString.substring(with: matchRange)
            
            if let percentage = Double(percentageStr) {
                DispatchQueue.main.async {
                    self.scanProgress = min(percentage / 100.0, 0.999)
                }
            }
        }
    }
    
    // MARK: - 导出逻辑
    private func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "导出 BDinfo"
        panel.nameFieldStringValue = "BDinfo_Report.txt"
        panel.allowedContentTypes = [.plainText]
        
        if panel.runModal() == .OK, let url = panel.url {
            do { try bdInfoText.write(to: url, atomically: true, encoding: .utf8) }
            catch { print("保存失败: \(error)") }
        }
    }
}
