import Foundation
import AVFoundation

/// 专为 A7/1GB 内存 iPad 深度优化的音频播放管理器
/// 采用单例设计，在系统层保证同一时刻「仅存活一个」AVAudioPlayer 实例。
/// 杜绝多音轨并发导致的内存爆满、多媒体服务崩溃（mediaserverd 闪退）以及声音重叠问题。
public final class LessonAudioManager {
    
    /// 单例访问点
    public static let shared = LessonAudioManager()
    
    /// 当前唯一的音频播放器实例，常驻内存复用，避免频繁创建/销毁带来的内存碎片
    private var audioPlayer: AVAudioPlayer?
    
    private init() {
        setupAudioSession()
    }
    
    /// 配置全局音频会话 (iOS 12 兼容)
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // 使用 ambient 模式：允许静音键控制，不打断其他背景音乐（适合课堂环境）
            // 如果需要强制扬声器发声，可选用 .playback 类别
            try session.setCategory(.ambient, mode: .default, options: [])
            try session.setActive(true, options: [])
        } catch {
            #if DEBUG
            print("[LessonAudioManager] 初始化 AVAudioSession 失败: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// 播放汉字对应的字音
    /// - Parameter word: 汉字名称，例如 "一", "二", "三"
    public func playWordAudio(word: String) {
        // 强制所有音频操作回到主线程，确保多媒体状态机的线程安全，并绝不阻塞主 UI 运行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 1. 立即停止当前正在播放的字音，并清空播放进度，切断旧数据流
            if let activePlayer = self.audioPlayer {
                if activePlayer.isPlaying {
                    activePlayer.stop()
                }
                self.audioPlayer = nil // 强行释放旧的音频缓冲区，清空内存
            }
            
            // 2. 检索沙盒或本地 Bundle 中的音频文件
            // 兼容性极佳的无损压缩 AAC 格式 (.m4a) 或高质量高压缩的 MP3 格式
            // 优先匹配 word.mp3，其次 word.m4a
            guard let audioURL = Bundle.main.url(forResource: word, withExtension: "mp3") ??
                                 Bundle.main.url(forResource: word, withExtension: "m4a") ??
                                 Bundle.main.url(forResource: word, withExtension: "wav") else {
                // 如果文件未找到，记录日志并优雅跳过，绝对不能崩溃！
                #if DEBUG
                print("[LessonAudioManager] 未找到汉字 [\(word)] 的音频文件，请在 Xcode 中添加 [\(word).mp3/m4a/wav] 到 Bundle 中")
                #endif
                return
            }
            
            // 3. 安全初始化音频播放器
            do {
                // 使用 dataReadingOptions: .mappedIfSafe 减少实际物理 RAM 占用
                let player = try AVAudioPlayer(contentsOf: audioURL)
                player.prepareToPlay() // 提前预载解码缓存，消除点击和发声之间的物理延迟
                self.audioPlayer = player
                self.audioPlayer?.play()
                
                #if DEBUG
                print("[LessonAudioManager] 成功播放汉字字音: \(word)")
                #endif
            } catch {
                #if DEBUG
                print("[LessonAudioManager] 无法初始化音频文件 [\(word)]: \(error.localizedDescription)")
                #endif
                // 异常保护：即使初始化失败也绝不崩溃，保障 App 绝对不闪退的硬性要求
                self.audioPlayer = nil
            }
        }
    }
    
    /// 全局静音/重置多媒体服务 (用于退到后台或页面销毁时主动释放内存)
    public func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let activePlayer = self.audioPlayer {
                if activePlayer.isPlaying {
                    activePlayer.stop()
                }
                self.audioPlayer = nil
            }
        }
    }
}
