package main

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type ClientMessage struct {
	Level  string `json:"level,omitempty"`
	Action string `json:"action,omitempty"`
}

type GameState struct {
	Type          string  `json:"type"` // "enemy_spawn", "boss_spawn", "boss_update", "boss_exploding", "clear", "enemy_bullet", "boss_bullet"
	EnemyID       float64 `json:"enemy_id,omitempty"`
	X             float64 `json:"x,omitempty"`
	Y             float64 `json:"y,omitempty"` // 弾の発射位置用に追加
	Speed         float64 `json:"speed,omitempty"`
	MaxHP         int     `json:"max_hp,omitempty"`
	CurrentHP     int     `json:"current_hp,omitempty"`
	AttackPattern string  `json:"attack_pattern,omitempty"`
}

type GameManager struct {
	mu            sync.Mutex
	bossHP        int
	maxBossHP     int
	isBossSpawned bool
	isGameOver    bool
}

func handleGame(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	defer ws.Close()

	manager := &GameManager{
		maxBossHP: 30,
		bossHP:    30,
	}

	_, msgBytes, err := ws.ReadMessage()
	if err != nil {
		return
	}
	var initMsg ClientMessage
	json.Unmarshal(msgBytes, &initMsg)
	fmt.Printf("ゲーム開始 - 難易度: %s\n", initMsg.Level)

	var spawnInterval time.Duration
	var enemySpeed float64

	switch initMsg.Level {
	case "easy":
		spawnInterval = 1200 * time.Millisecond
		enemySpeed = 4.5
	case "hard":
		spawnInterval = 300 * time.Millisecond
		enemySpeed = 1.8
	default:
		spawnInterval = 600 * time.Millisecond
		enemySpeed = 2.8
	}

	// ザコ敵・および敵の攻撃ループ（15秒間）
	stopEnemySpawn := make(chan bool)
	go func() {
		ticker := time.NewTicker(spawnInterval)
		defer ticker.Stop()
		bossTimer := time.After(15 * time.Second)

		for {
			select {
			case <-ticker.C:
				manager.mu.Lock()
				if !manager.isBossSpawned && !manager.isGameOver {
					enemyID := float64(time.Now().UnixNano())
					enemyX := rand.Float64() * 350

					// 1. 敵の出現を通知
					ws.WriteJSON(GameState{
						Type:    "enemy_spawn",
						EnemyID: enemyID,
						X:       enemyX,
						Speed:   enemySpeed,
					})

					// 2. 敵が出現して0.5秒後に、その座標から弾を撃ち下ろす指示を出す（非同期待ち）
					go func(x float64) {
						time.Sleep(500 * time.Millisecond)
						manager.mu.Lock()
						if !manager.isBossSpawned && !manager.isGameOver {
							ws.WriteJSON(GameState{
								Type: "enemy_bullet",
								X:    x,
							})
						}
						manager.mu.Unlock()
					}(enemyX)
				}
				manager.mu.Unlock()

			case <-bossTimer:
				manager.mu.Lock()
				manager.isBossSpawned = true
				manager.mu.Unlock()

				ws.WriteJSON(GameState{
					Type:          "boss_spawn",
					MaxHP:         manager.maxBossHP,
					CurrentHP:     manager.bossHP,
					AttackPattern: "normal",
				})
				stopEnemySpawn <- true
				return
			}
		}
	}()

	// ボスの弾幕タイマーループ（ボス出現後にトリガー）
	go func() {
		<-stopEnemySpawn // ボスが出るまで待機
		
		// 0.8秒ごとにボスが攻撃行動を起こす
		bossAttackTicker := time.NewTicker(800 * time.Millisecond)
		defer bossAttackTicker.Stop()

		for {
			<-bossAttackTicker.C
			manager.mu.Lock()
			if manager.isGameOver || manager.bossHP <= 0 {
				manager.mu.Unlock()
				return
			}

			// クライアント側へ「ボスが弾を撃った」と通知
			// 怒り状態（HP半分以下）なら、クライアント側に激しい攻撃パターン（"rage"）を指示
			pattern := "normal"
			if manager.bossHP <= manager.maxBossHP/2 {
				pattern = "rage"
			}

			ws.WriteJSON(GameState{
				Type:          "boss_bullet",
				AttackPattern: pattern,
			})
			manager.mu.Unlock()
		}
	}()

	// 受信ループ（変更なし）
	for {
		_, message, err := ws.ReadMessage()
		if err != nil {
			manager.mu.Lock()
			manager.isGameOver = true
			manager.mu.Unlock()
			break
		}

		var clientMsg ClientMessage
		json.Unmarshal(message, &clientMsg)

		if clientMsg.Action == "damage" {
			manager.mu.Lock()
			if manager.isBossSpawned && manager.bossHP > 0 {
				manager.bossHP--
				if manager.bossHP <= 0 {
					ws.WriteJSON(GameState{Type: "boss_exploding"})
					go func(w *websocket.Conn) {
						time.Sleep(2 * time.Second)
						w.WriteJSON(GameState{Type: "clear"})
					}(ws)
				} else {
					pattern := "normal"
					if manager.bossHP <= manager.maxBossHP/2 {
						pattern = "rage"
					}
					ws.WriteJSON(GameState{
						Type:          "boss_update",
						MaxHP:         manager.maxBossHP,
						CurrentHP:     manager.bossHP,
						AttackPattern: pattern,
					})
				}
			}
			manager.mu.Unlock()
		}
	}
}

func main() {
	http.HandleFunc("/game", handleGame)
	fmt.Println("敵・ボス弾幕対応サーバーをポート 8080 で起動中...")
	http.ListenAndServe(":8080", nil)
}