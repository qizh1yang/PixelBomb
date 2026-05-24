package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"bomberman-server/logic"

	"github.com/lonng/nano"
	"github.com/lonng/nano/component"
	"github.com/lonng/nano/serialize/json"
)

func printBanner() {
	banner, err := os.ReadFile("banner.txt")
	if err != nil {
		log.Println("PixelBomb Server starting...")
		return
	}
	fmt.Print(string(banner))
}

func main() {
	printBanner()

	// 1. 初始化 Nano 组件
	userComp := logic.NewUserComponent()
	roomComp := logic.NewRoomComponent(userComp)

	// 2. 准备组件集合，并显式指定组件名称以简化路由
	components := &component.Components{}
	components.Register(userComp, component.WithName("User"))
	components.Register(roomComp, component.WithName("Room"))

	// 3. 配置并启动 Nano
	log.Println("[Server] Nano engine starting on :8080...")
	
	// 并存健康检查 API (移至 8081 避免冲突)
	go func() {
		http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
			w.Write([]byte("OK"))
		})
		if err := http.ListenAndServe(":8081", nil); err != nil {
			log.Printf("Health check server error: %v", err)
		}
	}()

	// 启动 Nano
	nano.Listen(":8080", 
		nano.WithIsWebsocket(true),
		nano.WithWSPath("/ws"),
		nano.WithSerializer(json.NewSerializer()),
		nano.WithComponents(components),
		nano.WithDebugMode(),
	)
}
