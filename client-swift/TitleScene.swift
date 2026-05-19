import SpriteKit

class TitleScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .black
        
        let titleLabel = SKLabelNode(text: "GO × SWIFT SHOOTING")
        titleLabel.fontName = "Helvetica-Bold"
        titleLabel.fontSize = 32
        titleLabel.fontColor = .cyan
        titleLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.7)
        addChild(titleLabel)
        
        createButton(text: "▶ EASY", yRatio: 0.45, name: "easy", color: .green)
        createButton(text: "▶ NORMAL", yRatio: 0.35, name: "normal", color: .yellow)
        createButton(text: "▶ HARD", yRatio: 0.25, name: "hard", color: .red)
    }
    
    func createButton(text: String, yRatio: CGFloat, name: String, color: UIColor) {
        let button = SKLabelNode(text: text)
        button.fontName = "Helvetica-Bold"
        button.fontSize = 26
        button.fontColor = color
        button.position = CGPoint(x: size.width / 2, y: size.height * yRatio)
        button.name = name
        addChild(button)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)
        
        if let buttonName = touchedNode.name {
            if ["easy", "normal", "hard"].contains(buttonName) {
                let gameScene = GameScene(size: self.size)
                gameScene.selectedDifficulty = buttonName
                gameScene.scaleMode = .aspectFill
                
                // ドアが縦に開くような本格的な画面遷移演出
                let transition = SKTransition.doorsOpenVertical(withDuration: 0.8)
                self.view?.presentScene(gameScene, transition: transition)
            }
        }
    }
}