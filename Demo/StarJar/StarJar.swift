import CoreMotion
import SpriteKit
import SwiftUI

/**
 * 星星弹跳物理模拟器
 *
 * 功能特点：
 * - 真实的重力物理效果
 * - 星星碰撞边界会弹跳
 * - 智能防震动机制
 * - 可调节星星数量和显示参数
 * - 使用star.png图片纹理
 */

// MARK: - SwiftUI 主界面容器
struct StarJar: View {
  // MARK: - 状态变量
  @State private var scene: StarScene  // SpriteKit场景实例
  @State private var starCount = 20  // 星星数量，默认5个
  @State private var showPhysics = false  // 是否显示物理调试边界

  // MARK: 常量
  let SceneWidth: CGFloat = UIScreen.main.bounds.width  // 场景宽度（屏幕宽度）
  let SceneHeight: CGFloat = UIScreen.main.bounds.height  //场景高度
  let StarSize = CGSize(width: 40, height: 40)  // 星星大小

  // MARK: - 初始化方法
  init() {
    // 创建游戏场景
    let gameScene = StarScene()
    gameScene.size = CGSize(width: SceneWidth, height: SceneHeight)  // 设置场景尺寸
    gameScene.scaleMode = .resizeFill  // 自适应填充模式
    _scene = State(initialValue: gameScene)
  }

  // MARK: - 界面布局
  var body: some View {
    VStack {
      // SpriteKit游戏视图
      SpriteView(
        scene: scene,
        debugOptions: showPhysics ? [.showsPhysics, .showsFPS] : []  // 根据开关决定是否显示物理调试信息
      )
      .frame(width: SceneWidth, height: SceneHeight)  // 固定尺寸
      .onTapGesture { location in
        // 将SwiftUI坐标转换为SpriteKit场景坐标
        let sceneLocation = scene.convertPoint(fromView: location)
        // 点击屏幕时在点击位置添加星星
        scene.addStar(
          at: sceneLocation,
          withVelocity: CGVector(
            dx: CGFloat.random(in: -10...10),  // 轻微随机水平速度
            dy: CGFloat.random(in: -10...10)  // 轻微随机垂直速度
          ))
      }
      .onAppear {
        // 视图出现时初始化场景
        scene.setupScene()
        // 添加初始的20个星星，从天而降
        for _ in 0..<starCount {
          scene.addRandomStar()
        }
      }
    }
    .padding(.bottom)  // 添加底部安全距离
  }
}

// MARK: - SpriteKit 物理场景
/// StarScene - 星星物理模拟场景
///
/// 主要功能：
/// 1. 设置重力和物理边界
/// 2. 创建和管理星星（使用star.png纹理）
/// 3. 智能防震动检测
/// 4. 物理参数优化
class StarScene: SKScene {

  // MARK: - 设备运动检测
  private let motionManager = CMMotionManager()  // 设备运动检测管理器
  private var lastGravity = CGVector.zero  // 上一次重力

  // MARK: - 场景生命周期

  // 执行时机：当SpriteKit场景被添加到SKView时调用
  override func didMove(to view: SKView) {
    setupScene()  // 设置场景
    startDeviceMotionDetection()  // 启动设备运动检测
  }

  // 执行时机：当SpriteKit场景被销毁时调用
  deinit {
    stopDeviceMotionDetection()
  }

  // MARK: - 场景初始化设置
  /**
   * 设置物理世界的基本参数
   */
  func setupScene() {
    // 设置背景
    backgroundColor = .white

    // 重力由设备姿态驱动（startDeviceMotionDetection 中实时更新）
    // physicsWorld.gravity = CGVector(dx: 0, dy: -6.0)

    // 物理世界速度倍数（0.7 = 慢速模式， 1 = 正常模式， 2 = 快速模式）
    physicsWorld.speed = 1

    // 创建屏幕边界物理体
    createBoundaries()

    // 启动星星状态监控循环（防震动机制）
    startStarStatusCheck()
  }

  // MARK: - 防震动机制
  /**
   * 启动定时检查，防止星星无休止微震动
   */
  func startStarStatusCheck() {
    let checkAction = SKAction.repeatForever(
      SKAction.sequence([
        SKAction.wait(forDuration: 0.1),  // 每0.1秒检查一次
        SKAction.run { [weak self] in
          self?.checkStarsStatus()  // 检查所有星星状态
        },
      ])
    )

    // 启动定时检查动作，防止星星无休止微震动
    run(checkAction, withKey: "starStatusCheck")
  }

  /**
   * 检查星星状态，对接近静止的星星进行处理
   */
  func checkStarsStatus() {
    // 获取所有星星
    let stars = children.filter { $0.name == "star" }

    for star in stars {
      guard let physicsBody = star.physicsBody else { continue }

      // 计算当前速度的大小（勾股定理）
      let velocity = physicsBody.velocity
      let speed = sqrt(
        velocity.dx * velocity.dx + velocity.dy * velocity.dy
      )

      // 如果星星速度很小且靠近底部，强制让它停止
      // 条件：速度 < 20 且 高度 < 50像素
      if speed < 20 && star.position.y < 50 {
        // 完全停止移动和旋转
        physicsBody.velocity = CGVector.zero  // 停止线性运动
        physicsBody.angularVelocity = 0  // 停止旋转

        // 将星星固定在底部位置，避免穿透
        if star.position.y > 25 {
          star.position.y = 25
        }
      }
    }
  }

  // MARK: - 物理边界设置
  /**
   * 创建屏幕四周的物理边界
   */
  func createBoundaries() {
    // 清理旧的边界（如果存在）
    children.filter { $0.name == "boundary" }.forEach {
      $0.removeFromParent()
    }

    // 创建屏幕边界的物理体（edgeLoopFrom创建空心边界）
    let border = SKPhysicsBody(edgeLoopFrom: frame)

    // 物理参数调优：
    border.friction = 0.5  // 摩擦系数：适中摩擦，帮助减速
    border.restitution = 0.4  // 弹性系数：适度弹跳，不会太高也不会完全不弹

    // 将边界物理体应用到场景
    physicsBody = border
  }

  /**
   * 添加从天而降的新星星
   */
  func addRandomStar() {
    // 默认从顶部随机位置开始
    let margin: CGFloat = 25
    let x = CGFloat.random(in: margin...(frame.width - margin))
    let y = frame.height - margin
    addStar(
      at: CGPoint(x: x, y: y),
      withVelocity: CGVector(
        dx: CGFloat.random(in: -20...20),
        dy: CGFloat.random(in: -30...0)
      ))
  }

  /**
   * 在指定位置添加星星
   * @param position: 位置
   * @param velocity: 速度
   */
  func addStar(at position: CGPoint, withVelocity velocity: CGVector = CGVector.zero) {
    // 1. 使用star图片资源创建精灵节点
    let star = SKSpriteNode(imageNamed: "star")

    // 2. 设置星星大小（与Star组件保持一致：40x40）
    star.size = CGSize(width: 40, height: 40)

    // 3. 设置初始位置
    star.position = position

    // 4. 创建物理体（使用圆形物理体，更适合星星形状）
    star.physicsBody = SKPhysicsBody(circleOfRadius: 20)

    // 5. 设置物理属性
    star.physicsBody?.restitution = CGFloat.random(in: 0.3...0.6)  // 随机弹性
    star.physicsBody?.friction = 0.4  // 表面摩擦力
    star.physicsBody?.mass = 0.1  // 质量（较轻）
    star.physicsBody?.allowsRotation = true  // 允许旋转

    star.physicsBody?.usesPreciseCollisionDetection = true
    star.physicsBody?.linearDamping = 0.2
    star.physicsBody?.angularDamping = 0.2

    // 7. 设置初始速度
    star.physicsBody?.velocity = velocity

    // 8. 设置名称标识并添加到场景
    star.name = "star"
    addChild(star)
  }

  /**
   * 重置所有星星
   * @param count: 新的星星数量
   */
  func resetStars(count: Int) {
    // 移除场景中所有现有星星
    children.filter { $0.name == "star" }.forEach { $0.removeFromParent() }

    // 重新添加指定数量的星星，从天而降
    for _ in 0..<count {
      addRandomStar()
    }
  }

  // MARK: - 设备运动检测方法
  /**
   * 启动设备运动检测（以“手机=瓶子”的直觉映射）
   * - 思路：直接使用 CMDeviceMotion.gravity（单位：g），并将其映射到当前屏幕方向上的 x/y
   *   让物理重力永远指向现实世界的“下方”。
   */
  private func startDeviceMotionDetection() {
    guard motionManager.isDeviceMotionAvailable else {
      print("设备运动检测不可用")
      return
    }

    motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60fps

    // 使用主队列更新，便于直接更新 SpriteKit 场景
    motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
      guard let self = self, let motion = motion else { return }

      // 1) 读取系统当前界面方向（与真实屏幕朝向一致）
      let orientation = self.currentInterfaceOrientation()

      // 2) 将重力向量映射到屏幕坐标（SpriteKit: 右为 +x， 上为 +y）
      let gVec = self.mapGravity(motion.gravity, to: orientation)

      // 3) 轻度平滑，避免抖动
      let smooth: CGFloat = 0.15
      let blended = CGVector(
        dx: self.lastGravity.dx * (1 - smooth) + gVec.dx * smooth,
        dy: self.lastGravity.dy * (1 - smooth) + gVec.dy * smooth
      )

      // 4) 设置物理世界重力（数值可按手感调整）
      let gScale: CGFloat = 9.0  // 接近地球重力手感；改小=更“黏”，改大=更“活”
      self.physicsWorld.gravity = CGVector(dx: blended.dx * gScale, dy: blended.dy * gScale)

      self.lastGravity = blended
    }
  }

  /// 获取当前界面方向；若不可得，默认为 .portrait
  private func currentInterfaceOrientation() -> UIInterfaceOrientation {
    if let view = self.view,
      let windowScene = view.window?.windowScene
    {
      return windowScene.interfaceOrientation
    }
    // 退化处理（例如在预览或极端情况下）
    return .portrait
  }

  /// 将 CoreMotion 的重力向量映射到屏幕坐标（SpriteKit 坐标系）
  /// - 参数 g: CMDeviceMotion.gravity（单位 g，x 向右、y 向上、z 向外）
  /// - 参数 orientation: 当前界面方向
  /// - 返回: 屏幕坐标系下的 2D 重力方向，已考虑横竖屏/倒置
  private func mapGravity(_ g: CMAcceleration, to orientation: UIInterfaceOrientation) -> CGVector {
    // 注意：CM 的 y 轴“向上”为正，SpriteKit 的 y 轴“向上”为正；
    //      因此在直立竖屏时，g.y ≈ -1 应该让重力向下（dy 为负）。
    switch orientation {
    case .portrait:  // 直立竖屏（听筒在上，Home 在下）
      return CGVector(dx: g.x, dy: g.y)
    case .portraitUpsideDown:  // 倒立竖屏（手机倒过来）
      return CGVector(dx: -g.x, dy: -g.y)
    case .landscapeLeft:  // 横屏：设备左边在下（Home/灵动岛在右）
      // 屏幕坐标下，“下方”应指向 +x 或 -x，取决于设备坐标；
      // 这里将设备的 g.y 映射到屏幕的 +x，将 -g.x 映射到屏幕的 +y
      return CGVector(dx: g.y, dy: -g.x)
    case .landscapeRight:  // 横屏：设备右边在下（Home/灵动岛在左）
      return CGVector(dx: -g.y, dy: g.x)
    default:
      // 其他未知情形，按竖屏处理
      return CGVector(dx: g.x, dy: g.y)
    }
  }

  /**
   * 停止设备运动检测
   */
  private func stopDeviceMotionDetection() {
    motionManager.stopDeviceMotionUpdates()
  }
}

// MARK: - SwiftUI 预览
#Preview {
  StarJar()
    .preferredColorScheme(.light)  // 浅色模式预览
}

/*
 * 物理参数说明：
 *
 * 重力 (gravity):
 * - CGVector(dx: 0, dy: -9.8)
 * - 模拟地球重力加速度
 *
 * 弹性系数 (restitution):
 * - 0.0 = 完全不弹跳（如泥土）
 * - 1.0 = 完美弹跳（如超级球）
 * - 0.6-0.9 = 适中弹跳（如篮球）
 *
 * 摩擦力 (friction):
 * - 0.0 = 无摩擦（如冰面）
 * - 1.0 = 高摩擦（如橡胶）
 * - 0.3-0.5 = 适中摩擦
 *
 * 阻尼 (damping):
 * - 0.0 = 无阻尼（永动机）
 * - 1.0 = 完全阻尼（立即停止）
 * - 0.1 = 轻微阻尼（逐渐减速）
 */
