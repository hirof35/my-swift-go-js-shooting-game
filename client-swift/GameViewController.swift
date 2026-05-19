import UIKit
import SpriteKit

class GameViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        if let view = self.view as? SKView {
            // 最初にタイトル画面をセット
            let scene = TitleScene(size: view.bounds.size)
            scene.scaleMode = .aspectFill
            
            view.presentScene(scene)
            view.ignoresSiblingOrder = true
            
            // デバッグ情報（開発が終わったらfalseにする）
            view.showsFPS = true
            view.showsNodeCount = true
        }
    }
    override var prefersStatusBarHidden: Bool { return true }
}