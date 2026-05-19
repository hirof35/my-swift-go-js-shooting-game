import SpriteKit

// サーバーから届くデータの構造体
struct GameState: Decodable {
    let type: String
    let enemy_id: Double?
    let x: Double?
    let y: Double?
    let speed: Double?
    let max_hp: Int?
    let current_hp: Int?
    let attack_pattern: String?
}

class GameScene: SKScene, URLSessionWebSocketDelegate {
    
    var webSocketTask: URLSessionWebSocketTask?
    var difficulty: String = "normal"
    
    // ゲームオブジェクトの管理
    var player: SKSpriteNode!
    var boss: SKSpriteNode!
    var bossHPBarBackground: SKShapeNode?
    var bossHPBar: SKShapeNode?
    
    // 衝突判定のためのグループ（カテゴリビットマスク）
    let playerCategory: UInt32      = 0x1 << 0  // 0001
    let bulletCategory: UInt32      = 0x1 << 1  // 0010
    let enemyCategory: UInt32       = 0x1 << 2  // 0100
    let enemyBulletCategory: UInt32 = 0x1 << 3  // 1000 ★敵・ボスの弾（新規追加）

    override func didMove(to view: SKView) {
        backgroundColor = .black
        physicsWorld.contactDelegate = self // 当たり判定の窓口になる
        
        // 1. プレイヤー（自機）の作成
        player = SKSpriteNode(color: .cyan, size: CGSize(width: 40, height: 40))
        player.position = CGPoint(x: frame.midX, y: 150)
        player.physicsBody = SKPhysicsBody(rectangleOf: player.size)
        player.physicsBody?.isDynamic = true
        player.physicsBody?.categoryBitMask = playerCategory
        player.physicsBody?.contactTestBitMask = enemyCategory | enemyBulletCategory // ★敵本体と敵の弾の両方に当たる
        player.physicsBody?.collisionBitMask = 0
        addChild(player)
        
        // 2. 自機の自動連射スタート
        let fireAction = SKAction.run { [weak self] in self?.firePlayerBullet() }
        let waitAction = SKAction.wait(forDuration: 0.18)
        let sequence = SKAction.sequence([fireAction, waitAction])
        run(SKAction.repeatForever(sequence))
        
        // 3. サーバーへ接続
        connectToServer()
    }
    
    // プレイヤーの弾発射
    func firePlayerBullet() {
        let bullet = SKSpriteNode(color: .orange, size: CGSize(width: 6, height: 6))
        bullet.position = CGPoint(x: player.position.x, y: player.position.y + 20)
        bullet.physicsBody = SKPhysicsBody(rectangleOf: bullet.size)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = bulletCategory
        bullet.physicsBody?.contactTestBitMask = enemyCategory // 敵に当たる（ボス判定は座標で行う）
        bullet.physicsBody?.collisionBitMask = 0
        addChild(bullet)
        
        let moveAction = SKAction.moveBy(x: 0, y: 600, duration: 1.0)
        let removeAction = SKAction.removeFromParent()
        bullet.run(SKAction.sequence([moveAction, removeAction]))
    }
    
    // ★ 敵・ボスの弾を画面に生成する共通関数（新規追加）
    func spawnEnemyBullet(x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat, size: CGFloat, color: UIColor) {
        let bullet = SKSpriteNode(color: color, size: CGSize(width: size, height: size))
        bullet.position = CGPoint(x: x, y: y)
        
        bullet.physicsBody = SKPhysicsBody(rectangleOf: bullet.size)
        bullet.physicsBody?.isDynamic = true
        bullet.physicsBody?.categoryBitMask = enemyBulletCategory
        bullet.physicsBody?.contactTestBitMask = playerCategory // プレイヤーに当たる
        bullet.physicsBody?.collisionBitMask = 0
        addChild(bullet)
        
        // 1秒あたりの移動量（vx, vy）をもとに、画面外に出るまで動かす処理
        // 配ルプ（update）を使わず、SwiftではSKActionで綺麗に斜め移動を表現できます
        let moveBy = SKAction.moveBy(x: vx * 60, y: vy * 60, duration: 1.0)
        let repeatMove = SKAction.repeatForever(moveBy)
        
        // 画面外（下端・左右）に出たら自動削除するチェックコード
        let checkBounds = SKAction.run {
            if bullet.position.y < 0 || bullet.position.x < 0 || bullet.position.x > self.frame.width {
                bullet.removeFromParent()
            }
        }
        let sequence = SKAction.sequence([SKAction.wait(forDuration: 0.1), checkBounds])
        
        bullet.run(repeatMove)
        bullet.run(SKAction.repeatForever(sequence))
    }

    // 接続処理
    func connectToServer() {
        let url = URL(string: "ws://localhost:8080/game")! // WindowsのIPに変える場合はここを修正
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue.main)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // 最初に難易度を送信
        let initMsg = ["level": difficulty]
        if let jsonData = try? JSONSerialization.data(withJSONObject: initMsg),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { _ in }
        }
        
        receiveMessage()
    }
    
    // データ受信ループ
    func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let res = try? JSONDecoder().decode(GameState.self, from: data) {
                        self?.handleServerResponse(res)
                    }
                default: break
                }
                self?.receiveMessage() // 次のメッセージを待つループ
            case .failure: break
            }
        }
    }
    
    // ★ サーバーからのデータ処理（敵・ボス弾幕のパケット受信を追加）
    func handleServerResponse(_ res: GameState) {
        switch res.type {
        case "enemy_spawn":
            guard let rx = res.x, let rSpeed = res.speed else { return }
            let enemy = SKSpriteNode(color: .magenta, size: CGSize(width: 30, height: 30))
            // サーバーの基準横幅(350)から、iPhoneの画面幅(frame.width)に比率を合わせる
            let targetX = CGFloat(rx) / 350.0 * frame.width
            enemy.position = CGPoint(x: targetX, y: frame.height + 20)
            
            enemy.physicsBody = SKPhysicsBody(rectangleOf: enemy.size)
            enemy.physicsBody?.isDynamic = true
            enemy.physicsBody?.categoryBitMask = enemyCategory
            enemy.physicsBody?.contactTestBitMask = playerCategory | bulletCategory
            enemy.physicsBody?.collisionBitMask = 0
            addChild(enemy)
            
            let moveAction = SKAction.moveTo(y: -20, duration: rSpeed)
            let removeAction = SKAction.removeFromParent()
            enemy.run(SKAction.sequence([moveAction, removeAction]))
            
        case "enemy_bullet":
            // ★ 敵の位置（出現位置ベース）から下向きに弾を撃ち出す
            guard let rx = res.x else { return }
            let targetX = CGFloat(rx) / 350.0 * frame.width
            // 画面上部からまっすぐ下に移動（vx: 0, vy: -4）
            spawnEnemyBullet(x: targetX, y: frame.height - 100, vx: 0, vy: -4, size: 5, color: .red)
            
        case "boss_bullet":
            guard let bossNode = boss else { return }
            if res.attack_pattern == "normal" {
                // 通常攻撃：3方向（扇状）
                // JavaScript版の角度計算をSwiftのラジアンに変換して速度ベクトル（vx, vy）を作ります
                let angles: [CGFloat] = [-0.2, 0, 0.2]
                for angle in angles {
                    let vx = sin(angle) * 5
                    let vy = -cos(angle) * 5 // 下向きに進むのでマイナス
                    spawnEnemyBullet(x: bossNode.position.x, y: bossNode.position.y - 20, vx: vx, vy: vy, size: 7, color: .orange)
                }
            } else if res.attack_pattern == "rage" {
                // 発狂攻撃：全方位 8方向弾幕
                for i in 0..<8 {
                    let angle = (CGFloat.pi * 2 / 8) * CGFloat(i)
                    let vx = cos(angle) * 6
                    let vy = sin(angle) * 6
                    spawnEnemyBullet(x: bossNode.position.x, y: bossNode.position.y - 20, vx: vx, vy: vy, size: 6, color: .systemPink)
                }
            }
            
        case "boss_spawn":
            // ボス出現処理（前回と同様）
            boss = SKSpriteNode(color: .purple, size: CGSize(width: 90, height: 70))
            boss.position = CGPoint(x: frame.midX, y: frame.height - 150)
            addChild(boss)
            
            // 左右反復移動のアクション
            let moveLeft = SKAction.moveTo(x: 50, duration: 2.0)
            let moveRight = SKAction.moveTo(x: frame.width - 50, duration: 2.0)
            let bossSequence = SKAction.sequence([moveLeft, moveRight])
            boss.run(SKAction.repeatForever(bossSequence))
            
            createHPBar(maxHP: res.max_hp ?? 30)
            
        case "boss_update":
            if let current = res.current_hp, let max = res.max_hp {
                updateHPBar(current: current, max: max)
            }
            if res.attack_pattern == "rage" {
                boss?.color = .red // 発狂したら赤変化
            }
            
        case "boss_exploding":
            if let bossNode = boss {
                createExplosion(at: bossNode.position, isBig: true)
                boss?.removeFromParent()
                boss = nil
                shakeScreen()
            }
            
        case "clear":
            bossHPBarBackground?.removeFromParent()
            let label = SKLabelNode(text: "STAGE CLEAR ✨")
            label.fontName = "Helvetica-Bold"
            label.fontSize = 32
            label.fontColor = .green
            label.position = CGPoint(x: frame.midX, y: frame.midY)
            addChild(label)
            
        default: break
        }
    }
    
    // 自機移動（タッチ操作）
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            let location = touch.location(in: self)
            player.position.x = location.x
        }
    }
    
    // --- 以下、演出用ヘルパー関数（HPバー、爆発、画面シェイク） ---
    
    func createHPBar(maxHP: Int) {
        bossHPBarBackground = SKShapeNode(rectOf: CGSize(width: 240, height: 12))
        bossHPBarBackground?.position = CGPoint(x: frame.midX, y: frame.height - 60)
        bossHPBarBackground?.fillColor = .darkGray
        bossHPBarBackground?.strokeColor = .clear
        addChild(bossHPBarBackground!)
        
        bossHPBar = SKShapeNode(rectOf: CGSize(width: 240, height: 12))
        bossHPBar?.position = CGPoint(x: frame.midX, y: frame.height - 60)
        bossHPBar?.fillColor = .red
        bossHPBar?.strokeColor = .clear
        addChild(bossHPBar!)
    }
    
    func updateHPBar(current: Int, max: Int) {
        let ratio = CGFloat(current) / CGFloat(max)
        bossHPBar?.xScale = ratio
    }
    
    func createExplosion(at position: CGPoint, isBig: Bool) {
        let count = isBig ? 100 : 20
        for _ in 0..<count {
            let particle = SKSpriteNode(color: arc4random_uniform(2) == 0 ? .orange : .yellow, size: CGSize(width: 3, height: 3))
            particle.position = position
            addChild(particle)
            
            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let speed = CGFloat.random(in: 1...5) * (isBig ? 1.5 : 1.0)
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed
            
            let move = SKAction.moveBy(x: vx * 30, y: vy * 30, duration: 0.5)
            let fade = SKAction.fadeOut(withDuration: 0.5)
            let group = SKAction.group([move, fade])
            let remove = SKAction.removeFromParent()
            particle.run(SKAction.sequence([group, remove]))
        }
    }
    
    func shakeScreen() {
        let move1 = SKAction.moveBy(x: 5, y: -5, duration: 0.05)
        let move2 = SKAction.moveBy(x: -10, y: 10, duration: 0.05)
        let move3 = SKAction.moveBy(x: 5, y: -5, duration: 0.05)
        let seq = SKAction.sequence([move1, move2, move3])
        scene?.run(SKAction.repeat(seq, count: 10))
    }
}

// ★ 当たり判定（衝突）イベントの処理
extension GameScene: SKPhysicsContactDelegate {
    func didBegin(_ contact: SKPhysicsContact) {
        var firstBody: SKPhysicsBody
        var secondBody: SKPhysicsBody
        
        if contact.bodyA.categoryBitMask < contact.bodyB.categoryBitMask {
            firstBody = contact.bodyA
            secondBody = contact.bodyB
        } else {
            firstBody = contact.bodyB
            secondBody = contact.bodyA
        }
        
        // パターン1: プレイヤーの弾がザコ敵に当たった
        if firstBody.categoryBitMask == bulletCategory && secondBody.categoryBitMask == enemyCategory {
            if let enemyNode = secondBody.node as? SKSpriteNode, let bulletNode = firstBody.node {
                createExplosion(at: enemyNode.position, isBig: false)
                enemyNode.removeFromParent()
                bulletNode.removeFromParent()
            }
        }
        
        // パターン2: 自機（プレイヤー）が敵、または敵の弾に当たった（ゲームオーバー）
        if firstBody.categoryBitMask == playerCategory {
            if secondBody.categoryBitMask == enemyCategory || secondBody.categoryBitMask == enemyBulletCategory {
                if let playerNode = firstBody.node as? SKSpriteNode {
                    createExplosion(at: playerNode.position, isBig: false)
                    playerNode.removeFromParent() // 自機消滅
                    
                    // ゲームオーバー表示
                    let label = SKLabelNode(text: "GAME OVER")
                    label.fontName = "Helvetica-Bold"
                    label.fontSize = 32
                    label.fontColor = .red
                    label.position = CGPoint(x: frame.midX, y: frame.midY)
                    addChild(label)
                }
            }
        }
    }
    
    // ボスへのダメージ判定（SpriteKitの物理衝突の隙間を補うため、毎フレームの座標チェックで判定）
    override func update(_ currentTime: TimeInterval) {
        guard let bossNode = boss else { return }
        
        // 画面上の全ノードからプレイヤーの弾を探す
        enumerateChildNodes(withName: "//*") { node, _ in
            if node.physicsBody?.categoryBitMask == self.bulletCategory {
                // 弾がボスの当たり判定（サイズ）の中に入っているか計算
                if abs(node.position.x - bossNode.position.x) < 45 && abs(node.position.y - bossNode.position.y) < 35 {
                    node.removeFromParent() // 弾を消す
                    // サーバーへダメージ通知を送信
                    let damageMsg = ["action": "damage"]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: damageMsg),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        self.webSocketTask?.send(.string(jsonString)) { _ in }
                    }
                }
            }
        }
    }
}