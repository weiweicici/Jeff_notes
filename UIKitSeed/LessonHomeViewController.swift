import UIKit

/// 第一册 第一课 主界面控制器 (LessonHomeViewController)
/// 专为老旧 iPad Mini 2 (iOS 12.5.7, A7 芯片, 1GB RAM) 优化设计。
/// 具备 60 FPS 极流畅运行、绝对不闪退、低内存占用及防重击保护等特性。
public final class LessonHomeViewController: UIViewController {
    
    // MARK: - 数据源
    /// 16 个核心汉字列表 (4x4 矩阵)
    private let words = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "百", "千", "个", "人", "小", "大"]
    
    // MARK: - 点击防重状态 (UICollectionView 级别)
    private var lastWordTapTime: TimeInterval = 0
    private let wordDebounceInterval: TimeInterval = 0.5
    
    // MARK: - UI 控件
    private let topBarView = UIView()
    private let titleLabel = UILabel()
    private let topButtonStack = UIStackView()
    
    private var collectionView: UICollectionView!
    private let collectionLayout = UICollectionViewFlowLayout()
    
    private let bottomBarView = UIView()
    private let bottomButtonStack = UIStackView()
    private let trophyButton = TrophyButton(type: .custom)
    
    // MARK: - 生命分类与初始化
    override public func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
    }
    
    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 动态计算 4x4 宫格的最佳尺寸，完美适配横屏与竖屏
        updateCollectionViewLayout()
    }
    
    // MARK: - UI 构建与极致性能配置
    private func setupUI() {
        // 1. 设置整体护眼淡黄色背景 (Hex: #F5F2E9) - 纯色背景极为高效，杜绝 GPU 渲染瓶颈
        view.backgroundColor = UIColor(hex: "#F5F2E9")
        view.isOpaque = true
        
        // 2. 顶部导航栏配置
        topBarView.backgroundColor = .clear
        topBarView.isOpaque = true
        view.addSubview(topBarView)
        
        // 左侧文本 "第一册 第一课" 大号加粗
        titleLabel.text = "第一册 第一课"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = UIColor(hex: "#333333") // 深灰色护眼字
        titleLabel.isOpaque = true
        titleLabel.backgroundColor = UIColor(hex: "#F5F2E9")
        topBarView.addSubview(titleLabel)
        
        // 右侧三个导航按钮水平排列
        topButtonStack.axis = .horizontal
        topButtonStack.spacing = 12
        topButtonStack.distribution = .fillEqually
        topButtonStack.isOpaque = true
        topButtonStack.backgroundColor = .clear
        
        let menuBtn = createCyanButton(title: "章节目录")
        let followBtn = createCyanButton(title: "全文跟读")
        let readBtn = createCyanButton(title: "全文朗读")
        
        // 绑定防重复的点击事件
        menuBtn.addTarget(self, action: #selector(topBarButtonTapped(_:)), for: .touchUpInside)
        followBtn.addTarget(self, action: #selector(topBarButtonTapped(_:)), for: .touchUpInside)
        readBtn.addTarget(self, action: #selector(topBarButtonTapped(_:)), for: .touchUpInside)
        
        topButtonStack.addArrangedSubview(menuBtn)
        topButtonStack.addArrangedSubview(followBtn)
        topButtonStack.addArrangedSubview(readBtn)
        topBarView.addSubview(topButtonStack)
        
        // 3. 中间 4x4 汉字网格 CollectionView 配置
        collectionLayout.minimumLineSpacing = 16
        collectionLayout.minimumInteritemSpacing = 16
        collectionLayout.scrollDirection = .vertical
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionLayout)
        // 极致优化点：设置 CollectionView 背景为与主背景一致的纯色并开启 Opaque，消除大面积透明图层混合 (Transparency Blending)
        collectionView.backgroundColor = UIColor(hex: "#F5F2E9")
        collectionView.isOpaque = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.isScrollEnabled = false // 16个字在 iPad 屏幕刚好完全铺满，关闭滑动性能更佳
        
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(WordCollectionViewCell.self, forCellWithReuseIdentifier: WordCollectionViewCell.reuseIdentifier)
        
        view.addSubview(collectionView)
        
        // 4. 底部游戏入口栏配置
        bottomBarView.backgroundColor = .clear
        bottomBarView.isOpaque = true
        view.addSubview(bottomBarView)
        
        bottomButtonStack.axis = .horizontal
        bottomButtonStack.spacing = 16
        bottomButtonStack.distribution = .fillEqually
        bottomButtonStack.isOpaque = true
        bottomButtonStack.backgroundColor = .clear
        
        let game1 = createCyanButton(title: "拼字游戏")
        let game2 = createCyanButton(title: "找字游戏")
        let game3 = createCyanButton(title: "跳字游戏")
        let game4 = createCyanButton(title: "认读游戏")
        
        game1.addTarget(self, action: #selector(gameButtonTapped(_:)), for: .touchUpInside)
        game2.addTarget(self, action: #selector(gameButtonTapped(_:)), for: .touchUpInside)
        game3.addTarget(self, action: #selector(gameButtonTapped(_:)), for: .touchUpInside)
        game4.addTarget(self, action: #selector(gameButtonTapped(_:)), for: .touchUpInside)
        
        bottomButtonStack.addArrangedSubview(game1)
        bottomButtonStack.addArrangedSubview(game2)
        bottomButtonStack.addArrangedSubview(game3)
        bottomButtonStack.addArrangedSubview(game4)
        bottomBarView.addSubview(bottomButtonStack)
        
        // 右下角矢量奖杯按钮 (Trophy Button)
        trophyButton.addTarget(self, action: #selector(trophyButtonTapped), for: .touchUpInside)
        bottomBarView.addSubview(trophyButton)
    }
    
    // MARK: - AutoLayout 精准网格铺满与边界控制
    private func setupConstraints() {
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topButtonStack.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        bottomBarView.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonStack.translatesAutoresizingMaskIntoConstraints = false
        trophyButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // 顶部导航栏约束
            topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            topBarView.heightAnchor.constraint(equalToConstant: 80),
            
            titleLabel.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor),
            
            topButtonStack.centerYAnchor.constraint(equalTo: topBarView.centerYAnchor),
            topButtonStack.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor),
            topButtonStack.heightAnchor.constraint(equalToConstant: 46),
            topButtonStack.widthAnchor.constraint(equalToConstant: 400),
            
            // 底部游戏入口栏约束
            bottomBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            bottomBarView.heightAnchor.constraint(equalToConstant: 80),
            
            bottomButtonStack.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            bottomButtonStack.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor),
            bottomButtonStack.trailingAnchor.constraint(equalTo: trophyButton.leadingAnchor, constant: -24),
            bottomButtonStack.heightAnchor.constraint(equalToConstant: 48),
            
            trophyButton.centerYAnchor.constraint(equalTo: bottomBarView.centerYAnchor),
            trophyButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor),
            trophyButton.widthAnchor.constraint(equalToConstant: 56),
            trophyButton.heightAnchor.constraint(equalToConstant: 56),
            
            // 中间 CollectionView 约束 (上下左右填充剩余空间)
            collectionView.topAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: 16),
            collectionView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: -16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }
    
    // MARK: - 动态计算 4x4 矩阵尺寸 (完美解决 subpixel 渲染带来的抖动与模糊)
    private func updateCollectionViewLayout() {
        guard collectionView.bounds.width > 0 && collectionView.bounds.height > 0 else { return }
        
        let cols: CGFloat = 4
        let rows: CGFloat = 4
        
        let totalSpacingW = collectionLayout.minimumInteritemSpacing * (cols - 1)
        let totalSpacingH = collectionLayout.minimumLineSpacing * (rows - 1)
        
        // 使用 floor 进行物理像素向下取整，规避 iOS 浮点坐标引起的锯齿和微调抖动
        let cellW = floor((collectionView.bounds.width - totalSpacingW) / cols)
        let cellH = floor((collectionView.bounds.height - totalSpacingH) / rows)
        
        let newSize = CGSize(width: cellW, height: cellH)
        if collectionLayout.itemSize != newSize {
            collectionLayout.itemSize = newSize
            collectionView.reloadData()
        }
    }
    
    // MARK: - 控件快捷工厂方法
    private func createCyanButton(title: String) -> DebouncedButton {
        let button = DebouncedButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        
        // 设定柔和的护眼浅青色底色 (Hex: #7BC5CD)
        button.backgroundColor = UIColor(hex: "#7BC5CD")
        button.layer.cornerRadius = 10
        
        // 极致优化点：设置 Opaque 避免透明混合
        button.isOpaque = true
        
        // 精细的按钮内边距控制
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return button
    }
    
    // MARK: - 业务交互动作响应
    
    @objc private func topBarButtonTapped(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }
        showAlert(title: "提示", message: "您点击了顶部导航：[\(title)]")
    }
    
    @objc private func gameButtonTapped(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }
        showAlert(title: "游戏模式", message: "正在为您载入：[\(title)] ...")
    }
    
    @objc private func trophyButtonTapped() {
        showAlert(title: "荣誉金牌", message: "恭喜你在本次认字课堂中表现卓越，获得一枚金牌奖杯！🏆")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

// MARK: - UICollectionView 数据源与代理协议实现
extension LessonHomeViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return words.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: WordCollectionViewCell.reuseIdentifier, for: indexPath) as? WordCollectionViewCell else {
            return UICollectionViewCell()
        }
        
        let word = words[indexPath.item]
        
        // 动态匹配汉字字号大小：使其约为 Cell 高度的 55%，完美平衡视觉美感与极佳的阅读舒适度
        let cellHeight = collectionLayout.itemSize.height
        let optimalFontSize = floor(cellHeight * 0.55)
        
        cell.configure(word: word, fontSize: optimalFontSize)
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let currentTime = CACurrentMediaTime()
        
        // 1. 实现 CollectionView 级别的点击防重复响应，杜绝对低内存多媒体的疯狂轰炸
        guard currentTime - lastWordTapTime >= wordDebounceInterval else {
            #if DEBUG
            print("[LessonHomeViewController] 拦截到高频点击网格字: \(words[indexPath.item])")
            #endif
            return
        }
        lastWordTapTime = currentTime
        
        let word = words[indexPath.item]
        
        // 2. 触发预留的高效、资源独占型音频播放
        LessonAudioManager.shared.playWordAudio(word: word)
        
        // 3. 执行轻量、极致流畅的原生缩放反馈动画 (UIView.animate scales)
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        
        // 先放大至 1.1 倍，随后平滑恢复。动画纯在 GPU 执行，不破坏原 UILabel 硬件字形缓存
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut], animations: {
            cell.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.10, delay: 0, options: [.curveEaseIn], animations: {
                cell.transform = .identity
            }, completion: nil)
        }
    }
}

// MARK: - 专为 A7 芯片定制的高效文字 Cell
public final class WordCollectionViewCell: UICollectionViewCell {
    
    public static let reuseIdentifier = "WordCollectionViewCell"
    
    private let wordLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    
    private func setupCell() {
        // 极致优化点：Cell 开启 Opaque，并设为纯白背景，杜绝图层重叠混合开销
        backgroundColor = .white
        isOpaque = true
        
        // 简约大气的高清实体边框，不使用任何 shadow，彻底消灭 Offscreen Rendering 离屏渲染
        layer.borderColor = UIColor(hex: "#E0DBCE").cgColor
        layer.borderWidth = 1.5
        layer.cornerRadius = 12
        
        // UILabel 初始化与极致渲染配置
        wordLabel.textAlignment = .center
        wordLabel.textColor = UIColor(hex: "#222222") // 偏深木炭灰，视觉对比强，护眼
        wordLabel.isOpaque = true
        wordLabel.backgroundColor = .white
        
        // 核心性能点：开启异步栅格化渲染，避免汉字极其复杂的矢量字形主线程绘制引起的系统卡顿或掉帧
        wordLabel.layer.drawsAsynchronously = true
        
        contentView.addSubview(wordLabel)
        wordLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            wordLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            wordLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            wordLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            wordLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }
    
    /// 动态配置文字与字体
    public func configure(word: String, fontSize: CGFloat) {
        wordLabel.text = word
        
        // 优先载入优美的楷体，iOS 12 原生支持 Kaiti SC (简体楷体) 与 STKaiti (华文楷体)
        wordLabel.font = UIFont(name: "STKaiti", size: fontSize) ??
                        UIFont(name: "Kaiti SC", size: fontSize) ??
                        UIFont.systemFont(ofSize: fontSize, weight: .bold)
    }
    
    override public func prepareForReuse() {
        super.prepareForReuse()
        // 重置状态，避免复用引起的变换紊乱
        transform = .identity
        wordLabel.text = nil
    }
}

// MARK: - 矢量小奖杯按钮自定义实现 (完美兼容 iOS 12, 无需 SFSymbols 资源)
public final class TrophyButton: DebouncedButton {
    
    private let trophyLayer = CAShapeLayer()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupTrophy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrophy()
    }
    
    private func setupTrophy() {
        backgroundColor = .clear
        isOpaque = false // 局部小面积自定义矢量绘图，对 GPU Blending 无可察觉影响
        
        // 设置奖杯金牌底色与高质感描边
        trophyLayer.fillColor = UIColor(hex: "#FFD700").cgColor  // 耀眼纯金色
        trophyLayer.strokeColor = UIColor(hex: "#D4AF37").cgColor // 暗金包边
        trophyLayer.lineWidth = 2.0
        
        layer.addSublayer(trophyLayer)
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        let path = UIBezierPath()
        let w = bounds.width
        let h = bounds.height
        
        // 手工绘制精美矢量奖杯：高复用、高精度、0 内存加载图片负荷
        // 1. 杯身
        path.move(to: CGPoint(x: w * 0.28, y: h * 0.22))
        path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.22))
        path.addQuadCurve(to: CGPoint(x: w * 0.64, y: h * 0.58), controlPoint: CGPoint(x: w * 0.68, y: h * 0.45))
        path.addLine(to: CGPoint(x: w * 0.36, y: h * 0.58))
        path.addQuadCurve(to: CGPoint(x: w * 0.28, y: h * 0.22), controlPoint: CGPoint(x: w * 0.32, y: h * 0.45))
        
        // 2. 支撑脚与底座
        path.move(to: CGPoint(x: w * 0.46, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.46, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.82))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.58))
        
        // 3. 奖杯侧面提手 (左右双耳)
        // 左耳
        path.move(to: CGPoint(x: w * 0.28, y: h * 0.30))
        path.addCurve(to: CGPoint(x: w * 0.28, y: h * 0.46), controlPoint1: CGPoint(x: w * 0.14, y: h * 0.26), controlPoint2: CGPoint(x: w * 0.14, y: h * 0.50))
        
        // 右耳
        path.move(to: CGPoint(x: w * 0.72, y: h * 0.30))
        path.addCurve(to: CGPoint(x: w * 0.72, y: h * 0.46), controlPoint1: CGPoint(x: w * 0.86, y: h * 0.26), controlPoint2: CGPoint(x: w * 0.86, y: h * 0.50))
        
        trophyLayer.path = path.cgPath
    }
}

// MARK: - 基础颜色工具扩展
extension UIColor {
    /// 通过 Hex 字符串生成高兼容性 UIColor (iOS 12 适用)
    convenience init(hex: String) {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }
        
        if cString.count != 6 {
            self.init(white: 1.0, alpha: 1.0)
            return
        }
        
        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)
        
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}
