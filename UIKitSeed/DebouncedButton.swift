import UIKit

/// 专为老旧 iPad 设备定制的高性能防重击按钮 (Debounced Button)
/// 在 UIKit 响应链的 sendAction 层拦截高频连击，防止音频重叠、界面锁死或多次跳转。
open class DebouncedButton: UIButton {
    
    /// 防重击时间间隔（秒），即在此时间内连续点击将被静默过滤。默认 0.5 秒。
    public var debounceInterval: TimeInterval = 0.5
    
    /// 上一次点击触发成功的绝对时间戳 (使用 CACurrentMediaTime 避免受系统时区或手动改时间影响)
    private var lastTapTime: TimeInterval = 0
    
    open override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        let currentTime = CACurrentMediaTime()
        
        // 判断当前时间与上一次触发时间的差值是否大于等于设定的阈值
        if currentTime - lastTapTime >= debounceInterval {
            lastTapTime = currentTime
            super.sendAction(action, to: target, for: event)
        } else {
            // 静默拦截学生的高频狂点，保护系统稳定性
            #if DEBUG
            print("[DebouncedButton] 拦截到高频重复点击！已自动过滤。时间差: \(currentTime - lastTapTime)s")
            #endif
        }
    }
}
